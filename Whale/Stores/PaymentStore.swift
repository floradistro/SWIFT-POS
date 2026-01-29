//
//  PaymentStore.swift
//  Whale
//
//  Simplified payment store - renders backend state via Realtime.
//  All payment logic is now in the backend (payment-intent Edge Function).
//
//  Flow:
//    1. Client calls createPaymentIntent() → POST /payment-intent
//    2. Backend creates intent, starts processing, manages state machine
//    3. Client subscribes to payment_intents table via Realtime
//    4. UI renders status updates as they arrive
//

import Foundation
import SwiftUI
import Combine
import Supabase
import os.log

// MARK: - Payment Store

@MainActor
final class PaymentStore: ObservableObject {

    @Published private(set) var uiState: UIPaymentState = .idle
    @Published private(set) var currentIntentId: UUID?

    private let logger = Logger(subsystem: "com.whale.pos", category: "Payment")
    private var realtimeChannel: RealtimeChannelV2?

    // Store context for terminal callback
    private var pendingSessionInfo: SessionInfo?
    private var pendingAmount: Decimal?

    // MARK: - Computed Properties

    var isProcessing: Bool {
        if case .processing = uiState { return true }
        return false
    }

    var canStartPayment: Bool {
        switch uiState {
        case .idle, .failed: return true
        default: return false
        }
    }

    var errorMessage: String? {
        if case .failed(let message) = uiState { return message }
        return nil
    }

    var completion: SaleCompletion? {
        if case .success(let completion) = uiState { return completion }
        return nil
    }

    var progressMessage: String {
        if case .processing(let message, _, _) = uiState { return message }
        return ""
    }

    // MARK: - Actions

    func reset() {
        unsubscribeFromIntent()
        currentIntentId = nil
        pendingSessionInfo = nil
        pendingAmount = nil
        uiState = .idle
    }

    func cancel() {
        guard let intentId = currentIntentId else { return }
        logger.warning("Cancelling payment intent: \(intentId)")

        Task {
            do {
                try await cancelPaymentIntent(intentId)
            } catch {
                logger.error("Failed to cancel: \(error.localizedDescription)")
            }
        }

        reset()
    }

    // MARK: - Payment Methods

    func processCashPayment(
        cart: [CartItem], totals: CheckoutTotals, cashTendered: Decimal,
        sessionInfo: SessionInfo, customer: Customer?,
        loyaltyPointsRedeemed: Int = 0, loyaltyDiscountAmount: Decimal = 0,
        campaignDiscountAmount: Decimal = 0, campaignId: UUID? = nil
    ) async throws -> SaleCompletion {

        // Calculate adjusted total after loyalty discount
        let adjustedTotal = totals.total - loyaltyDiscountAmount
        guard let change = CheckoutCalculator.calculateChange(tendered: cashTendered, total: adjustedTotal) else {
            throw PaymentError.insufficientCash
        }

        return try await createAndProcessIntent(
            cart: cart,
            totals: totals,
            paymentMethod: .cash,
            sessionInfo: sessionInfo,
            customer: customer,
            cashTendered: cashTendered,
            changeGiven: change,
            loyaltyPointsRedeemed: loyaltyPointsRedeemed,
            loyaltyDiscountAmount: loyaltyDiscountAmount,
            campaignDiscountAmount: campaignDiscountAmount,
            campaignId: campaignId
        )
    }

    func processCardPayment(
        cart: [CartItem], totals: CheckoutTotals,
        sessionInfo: SessionInfo, customer: Customer?,
        loyaltyPointsRedeemed: Int = 0, loyaltyDiscountAmount: Decimal = 0,
        campaignDiscountAmount: Decimal = 0, campaignId: UUID? = nil
    ) async throws -> SaleCompletion {

        return try await createAndProcessIntent(
            cart: cart,
            totals: totals,
            paymentMethod: .card,
            sessionInfo: sessionInfo,
            customer: customer,
            loyaltyPointsRedeemed: loyaltyPointsRedeemed,
            loyaltyDiscountAmount: loyaltyDiscountAmount,
            campaignDiscountAmount: campaignDiscountAmount,
            campaignId: campaignId
        )
    }

    func processSplitPayment(
        cart: [CartItem], totals: CheckoutTotals,
        cashAmount: Decimal, cardAmount: Decimal,
        sessionInfo: SessionInfo, customer: Customer?,
        loyaltyPointsRedeemed: Int = 0, loyaltyDiscountAmount: Decimal = 0,
        campaignDiscountAmount: Decimal = 0, campaignId: UUID? = nil
    ) async throws -> SaleCompletion {

        // Calculate adjusted total after loyalty discount
        let adjustedTotal = totals.total - loyaltyDiscountAmount
        guard (cashAmount + cardAmount) == adjustedTotal else {
            throw PaymentError.invalidAmount
        }

        let splitPayments = [
            SplitPaymentPayload(method: "cash", amount: cashAmount),
            SplitPaymentPayload(method: "card", amount: cardAmount)
        ]

        return try await createAndProcessIntent(
            cart: cart,
            totals: totals,
            paymentMethod: .split,
            sessionInfo: sessionInfo,
            customer: customer,
            cashAmount: cashAmount,
            cardAmount: cardAmount,
            splitPayments: splitPayments,
            loyaltyPointsRedeemed: loyaltyPointsRedeemed,
            loyaltyDiscountAmount: loyaltyDiscountAmount,
            campaignDiscountAmount: campaignDiscountAmount,
            campaignId: campaignId
        )
    }

    func processMultiCardPayment(
        cart: [CartItem], totals: CheckoutTotals,
        card1Amount: Decimal, card2Amount: Decimal,
        sessionInfo: SessionInfo, customer: Customer?,
        loyaltyPointsRedeemed: Int = 0, loyaltyDiscountAmount: Decimal = 0,
        campaignDiscountAmount: Decimal = 0, campaignId: UUID? = nil
    ) async throws -> MultiCardResult {

        // Calculate adjusted total after loyalty discount
        let adjustedTotal = totals.total - loyaltyDiscountAmount
        guard (card1Amount + card2Amount) == adjustedTotal else {
            throw PaymentError.invalidAmount
        }

        let splitPayments = [
            SplitPaymentPayload(method: "card", amount: card1Amount, cardNumber: 1),
            SplitPaymentPayload(method: "card", amount: card2Amount, cardNumber: 2)
        ]

        do {
            let completion = try await createAndProcessIntent(
                cart: cart,
                totals: totals,
                paymentMethod: .multiCard,
                sessionInfo: sessionInfo,
                customer: customer,
                splitPayments: splitPayments,
                loyaltyPointsRedeemed: loyaltyPointsRedeemed,
                loyaltyDiscountAmount: loyaltyDiscountAmount,
                campaignDiscountAmount: campaignDiscountAmount,
                campaignId: campaignId
            )

            return MultiCardResult(
                success: true,
                orderId: completion.orderId,
                orderNumber: completion.orderNumber,
                card1Success: true,
                card2Success: true,
                card1ErrorMessage: nil,
                card2ErrorMessage: nil
            )
        } catch {
            return MultiCardResult(
                success: false,
                orderId: nil,
                orderNumber: nil,
                card1Success: false,
                card2Success: false,
                card1ErrorMessage: error.localizedDescription,
                card2ErrorMessage: nil
            )
        }
    }

    // MARK: - Backend-Driven Payment API (Cart ID Based)

    /// Unified payment method - offloads ALL logic to backend
    /// Backend loads cart, calculates totals, validates, processes
    func processPayment(
        method: PaymentMethod,
        cartId: UUID,
        sessionInfo: SessionInfo,
        cashReceived: Decimal? = nil,
        splitAmounts: SplitAmounts? = nil,
        cardPercentages: CardPercentages? = nil,
        loyaltyDiscount: Decimal? = nil,
        pointsRedeemed: Int? = nil
    ) async {
        guard canStartPayment else {
            uiState = .failed(message: "Payment already in progress")
            return
        }

        uiState = .processing(message: "Processing payment...", amount: nil, label: nil)
        pendingSessionInfo = sessionInfo

        do {
            let session = try await supabase.auth.session
            let accessToken = session.accessToken

            let url = SupabaseConfig.url.appendingPathComponent("functions/v1/payment-intent")

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
            request.timeoutInterval = 30

            // Build simplified payload - backend handles everything
            var payload: [String: Any] = [
                "cartId": cartId.uuidString.lowercased(),
                "paymentMethod": method.rawValue,
                "storeId": sessionInfo.storeId.uuidString.lowercased(),
                "locationId": sessionInfo.locationId.uuidString.lowercased(),
                "registerId": sessionInfo.registerId.uuidString.lowercased(),
                "sessionId": sessionInfo.sessionId.uuidString.lowercased()
            ]

            if let userId = sessionInfo.userId {
                payload["userId"] = userId.uuidString.lowercased()
            }

            if let cash = cashReceived {
                payload["cashReceived"] = NSDecimalNumber(decimal: cash).doubleValue
            }

            if let split = splitAmounts {
                payload["splitAmounts"] = [
                    "cash": NSDecimalNumber(decimal: split.cash).doubleValue,
                    "card": NSDecimalNumber(decimal: split.card).doubleValue
                ]
            }

            if let cards = cardPercentages {
                payload["cardPercentages"] = [
                    "card1Percent": cards.card1Percent,
                    "card2Percent": cards.card2Percent
                ]
            }

            if let discount = loyaltyDiscount {
                payload["loyaltyDiscount"] = NSDecimalNumber(decimal: discount).doubleValue
            }

            if let points = pointsRedeemed {
                payload["pointsRedeemed"] = points
            }

            request.httpBody = try JSONSerialization.data(withJSONObject: payload)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
                let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw PaymentError.networkError("HTTP error: \(errorText)")
            }

            let decoder = JSONDecoder()
            let intentResponse = try decoder.decode(CreateIntentResponse.self, from: data)
            let intentId = intentResponse.intentId

            currentIntentId = UUID(uuidString: intentId)

            // Subscribe to realtime updates
            await subscribeToIntent(intentId)

            // Check if already awaiting_terminal
            if intentResponse.status == "awaiting_terminal" {
                let intent = try await fetchIntent(intentId)
                let terminalAmount = intent.terminalAmount.map { Decimal($0) } ?? Decimal(intent.amount)
                pendingAmount = terminalAmount
                let cardNumber = intent.currentCardNumber
                Task {
                    await handleAwaitingTerminal(
                        intentId: intentId,
                        amount: terminalAmount,
                        sessionInfo: sessionInfo,
                        cardNumber: cardNumber
                    )
                }
            }

            // Wait for completion
            let completion = try await waitForCompletion(intentId: intentId, timeout: 300)

            Haptics.success()
            uiState = .success(completion)

        } catch {
            Haptics.error()
            let errorMessage = mapError(error)
            uiState = .failed(message: errorMessage)
        }
    }

    /// Send invoice - backend handles email, payment link generation
    func sendInvoice(
        cartId: UUID,
        sessionInfo: SessionInfo,
        email: String,
        dueDate: Date,
        notes: String? = nil
    ) async {
        guard canStartPayment else {
            uiState = .failed(message: "Payment already in progress")
            return
        }

        uiState = .processing(message: "Sending invoice...", amount: nil, label: nil)

        do {
            let session = try await supabase.auth.session
            let accessToken = session.accessToken

            let url = SupabaseConfig.url.appendingPathComponent("functions/v1/payment-intent")

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
            request.timeoutInterval = 30

            let dateFormatter = ISO8601DateFormatter()

            var payload: [String: Any] = [
                "cartId": cartId.uuidString.lowercased(),
                "paymentMethod": "invoice",
                "storeId": sessionInfo.storeId.uuidString.lowercased(),
                "locationId": sessionInfo.locationId.uuidString.lowercased(),
                "registerId": sessionInfo.registerId.uuidString.lowercased(),
                "sessionId": sessionInfo.sessionId.uuidString.lowercased(),
                "invoiceEmail": email,
                "invoiceDueDate": dateFormatter.string(from: dueDate)
            ]

            if let userId = sessionInfo.userId {
                payload["userId"] = userId.uuidString.lowercased()
            }

            if let notes = notes, !notes.isEmpty {
                payload["invoiceNotes"] = notes
            }

            request.httpBody = try JSONSerialization.data(withJSONObject: payload)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
                let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw PaymentError.networkError("HTTP error: \(errorText)")
            }

            let decoder = JSONDecoder()
            let intentResponse = try decoder.decode(CreateIntentResponse.self, from: data)
            let intentId = intentResponse.intentId

            currentIntentId = UUID(uuidString: intentId)

            // Subscribe and wait for completion
            await subscribeToIntent(intentId)
            let completion = try await waitForCompletion(intentId: intentId, timeout: 60)

            Haptics.success()
            uiState = .success(completion)

        } catch {
            Haptics.error()
            let errorMessage = mapError(error)
            uiState = .failed(message: errorMessage)
        }
    }

    // MARK: - Core Intent Flow

    private func createAndProcessIntent(
        cart: [CartItem],
        totals: CheckoutTotals,
        paymentMethod: PaymentMethod,
        sessionInfo: SessionInfo,
        customer: Customer?,
        cashTendered: Decimal? = nil,
        changeGiven: Decimal? = nil,
        cashAmount: Decimal? = nil,
        cardAmount: Decimal? = nil,
        splitPayments: [SplitPaymentPayload]? = nil,
        loyaltyPointsRedeemed: Int = 0,
        loyaltyDiscountAmount: Decimal = 0,
        campaignDiscountAmount: Decimal = 0,
        campaignId: UUID? = nil
    ) async throws -> SaleCompletion {

        guard canStartPayment else { throw PaymentError.paymentInProgress }
        guard !cart.isEmpty else { throw PaymentError.emptyCart }

        // Show processing state
        uiState = .processing(message: "Creating payment...", amount: totals.total, label: nil)

        // Generate idempotency key
        let cartHash = cart.map { "\($0.productId)-\($0.quantity)" }.joined(separator: ",")
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let idempotencyKey = "\(sessionInfo.sessionId)-\(timestamp)-\(cartHash.hashValue)"

        // Build request payload
        let payload = CreateIntentPayload(
            storeId: sessionInfo.storeId.uuidString.lowercased(),
            locationId: sessionInfo.locationId.uuidString.lowercased(),
            registerId: sessionInfo.registerId.uuidString.lowercased(),
            sessionId: sessionInfo.sessionId.uuidString.lowercased(),
            paymentMethod: paymentMethod.rawValue,
            amount: NSDecimalNumber(decimal: totals.total).doubleValue,
            cartItems: cart.map { $0.toPayload(locationId: sessionInfo.locationId) },
            totals: TotalsPayload(
                subtotal: NSDecimalNumber(decimal: totals.subtotal).doubleValue,
                taxAmount: NSDecimalNumber(decimal: totals.taxAmount).doubleValue,
                discountAmount: NSDecimalNumber(decimal: totals.discountAmount).doubleValue,
                total: NSDecimalNumber(decimal: totals.total).doubleValue
            ),
            customerId: customer?.id.uuidString.lowercased(),
            customerName: customer?.fullName ?? "Walk-In",
            userId: sessionInfo.userId?.uuidString.lowercased(),
            cashTendered: cashTendered.map { NSDecimalNumber(decimal: $0).doubleValue },
            changeGiven: changeGiven.map { NSDecimalNumber(decimal: $0).doubleValue },
            cashAmount: cashAmount.map { NSDecimalNumber(decimal: $0).doubleValue },
            cardAmount: cardAmount.map { NSDecimalNumber(decimal: $0).doubleValue },
            splitPayments: splitPayments,
            loyaltyPointsRedeemed: loyaltyPointsRedeemed,
            loyaltyDiscountAmount: NSDecimalNumber(decimal: loyaltyDiscountAmount).doubleValue,
            campaignDiscountAmount: NSDecimalNumber(decimal: campaignDiscountAmount).doubleValue,
            campaignId: campaignId?.uuidString.lowercased(),
            idempotencyKey: idempotencyKey
        )

        // Store context for potential terminal callback
        pendingSessionInfo = sessionInfo
        pendingAmount = totals.total

        do {
            // Create the payment intent
            let response = try await createPaymentIntent(payload)
            let intentId = response.intentId

            currentIntentId = UUID(uuidString: intentId)

            // Subscribe to realtime updates
            await subscribeToIntent(intentId)

            // IMPORTANT: Check if we're already awaiting_terminal (race condition fix)
            // The backend may have already transitioned before we subscribed
            if response.status == "awaiting_terminal" {
                logger.info("Intent already awaiting_terminal on creation response - handling immediately")
                // Fetch full record to get terminal_amount
                let intent = try await fetchIntent(intentId)
                // Use terminal_amount if set, otherwise fall back to full amount
                let terminalAmount = intent.terminalAmount.map { Decimal($0) } ?? Decimal(intent.amount)
                let cardNumber = intent.currentCardNumber
                logger.info("Terminal amount from backend: $\(terminalAmount), card number: \(cardNumber ?? 0)")
                if let sessionInfo = pendingSessionInfo {
                    Task {
                        await handleAwaitingTerminal(
                            intentId: intentId,
                            amount: terminalAmount,
                            sessionInfo: sessionInfo,
                            cardNumber: cardNumber
                        )
                    }
                }
            }

            // Wait for completion
            let completion = try await waitForCompletion(intentId: intentId, timeout: 300)

            Haptics.success()
            uiState = .success(completion)

            return completion

        } catch {
            Haptics.error()
            let errorMessage = mapError(error)
            uiState = .failed(message: errorMessage)
            throw error
        }
    }

    // MARK: - API Calls

    private func createPaymentIntent(_ payload: CreateIntentPayload) async throws -> CreateIntentResponse {
        let session = try await supabase.auth.session
        let accessToken = session.accessToken

        let url = SupabaseConfig.url.appendingPathComponent("functions/v1/payment-intent")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.timeoutInterval = 30

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PaymentError.networkError("Invalid response")
        }

        guard httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw PaymentError.networkError("HTTP \(httpResponse.statusCode): \(errorText)")
        }

        let decoder = JSONDecoder()
        return try decoder.decode(CreateIntentResponse.self, from: data)
    }

    private func cancelPaymentIntent(_ intentId: UUID) async throws {
        let session = try await supabase.auth.session
        let accessToken = session.accessToken

        let url = SupabaseConfig.url
            .appendingPathComponent("functions/v1/payment-intent")
            .appendingPathComponent(intentId.uuidString.lowercased())
            .appendingPathComponent("cancel")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
            throw PaymentError.networkError("Failed to cancel")
        }
    }

    // MARK: - Realtime Subscription

    private func subscribeToIntent(_ intentId: String) async {
        unsubscribeFromIntent()

        let channel = await supabase.realtimeV2.channel("payment-intent-\(intentId)")

        let changes = await channel.postgresChange(
            UpdateAction.self,
            schema: "public",
            table: "payment_intents",
            filter: "id=eq.\(intentId)"
        )

        await channel.subscribe()

        Task {
            for await change in changes {
                await handleIntentUpdate(change.record)
            }
        }

        realtimeChannel = channel
    }

    private func unsubscribeFromIntent() {
        if let channel = realtimeChannel {
            Task {
                await channel.unsubscribe()
            }
        }
        realtimeChannel = nil
    }

    private func handleIntentUpdate(_ record: [String: AnyJSON]) async {
        guard let statusValue = record["status"]?.stringValue else { return }
        guard let intentIdString = record["id"]?.stringValue else { return }

        let statusMessage = record["status_message"]?.stringValue ?? ""
        let errorMessage = record["error_message"]?.stringValue

        switch statusValue {
        case "validating":
            uiState = .processing(message: statusMessage.isEmpty ? "Validating..." : statusMessage)
        case "processing":
            uiState = .processing(message: statusMessage.isEmpty ? "Processing..." : statusMessage)
        case "awaiting_terminal":
            // Terminal required! Call Dejavoo and report result
            // Get the terminal_amount from the record - this is the specific amount to charge
            // For split payments: card_amount. For multi-card: individual card amounts
            let terminalAmount: Decimal
            if let terminalAmountValue = record["terminal_amount"]?.doubleValue {
                terminalAmount = Decimal(terminalAmountValue)
            } else if let amountValue = record["card_amount"]?.doubleValue {
                // Fallback to card_amount for split payments
                terminalAmount = Decimal(amountValue)
            } else if let amount = pendingAmount {
                // Last fallback to full amount (single card payment)
                terminalAmount = amount
            } else {
                logger.error("Missing terminal amount in awaiting_terminal")
                uiState = .failed(message: "Configuration error - missing terminal amount")
                return
            }

            let cardNumber = record["current_card_number"]?.intValue

            if let sessionInfo = pendingSessionInfo {
                Task {
                    await handleAwaitingTerminal(
                        intentId: intentIdString,
                        amount: terminalAmount,
                        sessionInfo: sessionInfo,
                        cardNumber: cardNumber
                    )
                }
            } else {
                logger.error("Missing session info for terminal callback")
                uiState = .failed(message: "Configuration error - missing terminal context")
            }
        case "approved":
            uiState = .processing(message: statusMessage.isEmpty ? "Approved!" : statusMessage)
        case "saving":
            uiState = .processing(message: statusMessage.isEmpty ? "Saving order..." : statusMessage)
        case "completed":
            // Completion is handled by waitForCompletion
            break
        case "failed", "cancelled", "expired":
            uiState = .failed(message: errorMessage ?? statusMessage)
        default:
            break
        }
    }

    // MARK: - Wait for Completion

    private func waitForCompletion(intentId: String, timeout: TimeInterval) async throws -> SaleCompletion {
        let startTime = Date()

        while Date().timeIntervalSince(startTime) < timeout {
            // Poll for status
            let intent = try await fetchIntent(intentId)

            switch intent.status {
            case "completed":
                return SaleCompletion(
                    orderId: UUID(uuidString: intent.orderId ?? "") ?? UUID(),
                    orderNumber: intent.orderNumber ?? "",
                    transactionNumber: "TXN-\(intent.orderNumber ?? "")",
                    total: Decimal(intent.amount),
                    paymentMethod: PaymentMethod(rawValue: intent.paymentMethod) ?? .cash,
                    completedAt: Date(),
                    authorizationCode: intent.authorizationCode,
                    cardType: intent.cardType,
                    cardLast4: intent.cardLast4
                )

            case "failed":
                throw PaymentError.unknown(intent.errorMessage ?? "Payment failed")

            case "cancelled":
                throw PaymentError.unknown("Payment cancelled")

            case "expired":
                throw PaymentError.terminalTimeout

            default:
                // Still processing - wait and retry
                try await Task.sleep(for: .milliseconds(500))
            }
        }

        throw PaymentError.terminalTimeout
    }

    private func fetchIntent(_ intentId: String) async throws -> IntentStatus {
        let session = try await supabase.auth.session
        let accessToken = session.accessToken

        let url = SupabaseConfig.url
            .appendingPathComponent("functions/v1/payment-intent")
            .appendingPathComponent(intentId)

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")

        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(IntentStatus.self, from: data)
    }

    // MARK: - Helpers

    private func mapError(_ error: Error) -> String {
        if let pe = error as? PaymentError { return pe.localizedDescription }
        return error.localizedDescription
    }

    // MARK: - Terminal Integration

    /// Called when status changes to awaiting_terminal - process card through Dejavoo
    /// iOS is a dumb terminal proxy - backend tells us exactly what amount to charge
    /// We just execute and report back. No decisions made here.
    private func handleAwaitingTerminal(intentId: String, amount: Decimal, sessionInfo: SessionInfo, cardNumber: Int? = nil) async {
        let cardLabel = cardNumber.map { "Card \($0): " } ?? ""
        logger.info("💳 Terminal required - \(cardLabel)$\(amount) for intent \(intentId)")

        // For card 2+, add longer delay to let the terminal fully reset from previous transaction
        // Dejavoo terminals return "Service Busy" if called too quickly after a transaction
        // IMPORTANT: 5 seconds is the minimum safe delay - 3 seconds caused Service Busy errors
        if let num = cardNumber, num > 1 {
            logger.info("⏳ Waiting 5 seconds before card \(num) to let terminal reset...")
            uiState = .processing(message: "Card 1 approved! Preparing for card 2...", amount: amount, label: "Card \(num)")
            try? await Task.sleep(for: .seconds(5))
        }

        let message = cardNumber == 2 ? "Present second card..." : "Present card to terminal..."
        uiState = .processing(message: message, amount: amount, label: cardNumber.map { "Card \($0)" })

        // Get terminal config from session/location settings
        guard let terminal = await getTerminalClient(for: sessionInfo) else {
            // No terminal configured - report failure
            try? await reportTerminalResult(
                intentId: intentId,
                approved: false,
                errorMessage: "No payment terminal configured"
            )
            return
        }

        // Retry logic for transient errors (Service Busy, timeout, network issues)
        // These errors can occur even after a successful charge, so we retry before failing
        let maxRetries = 2
        var lastError: Error?

        for attempt in 1...(maxRetries + 1) {
            do {
                // Generate reference ID for this transaction
                let referenceId = DejavooReferenceGenerator.generate(prefix: "TXN")

                // Call the terminal
                let response = try await terminal.sale(
                    amount: amount,
                    referenceId: referenceId
                )

                // Report success to backend
                try await reportTerminalResult(
                    intentId: intentId,
                    approved: true,
                    authorizationCode: response.authCode,
                    cardType: response.cardType,
                    cardLast4: response.cardLast4,
                    referenceId: response.referenceId
                )

                logger.info("✅ Terminal approved - auth: \(response.authCode ?? "N/A")")
                return  // Success - exit the function

            } catch let error as DejavooError {
                lastError = error

                // Check if this is a retryable error (Service Busy, timeout, network)
                if error.isRetryable && attempt <= maxRetries {
                    let waitTime = attempt * 3  // 3s, then 6s
                    logger.warning("⚠️ Retryable error on attempt \(attempt): \(error.localizedDescription). Waiting \(waitTime)s before retry...")
                    uiState = .processing(message: "Terminal busy, retrying...", amount: amount, label: cardNumber.map { "Card \($0)" })
                    try? await Task.sleep(for: .seconds(waitTime))
                    continue  // Retry
                }

                // Non-retryable error or max retries exceeded
                logger.error("❌ Terminal error (attempt \(attempt)/\(maxRetries + 1)): \(error.localizedDescription)")
                break

            } catch {
                lastError = error
                logger.error("❌ Unexpected terminal error: \(error.localizedDescription)")
                break
            }
        }

        // All retries failed - report failure to backend
        let errorMessage = (lastError as? DejavooError)?.localizedDescription ?? lastError?.localizedDescription ?? "Unknown error"
        try? await reportTerminalResult(
            intentId: intentId,
            approved: false,
            errorMessage: errorMessage
        )
    }

    /// Terminal config response from vault RPC
    private struct TerminalConfig: Decodable {
        let processorName: String?
        let authkey: String?
        let tpn: String?
        let environment: String?
        let isActive: Bool?

        enum CodingKeys: String, CodingKey {
            case processorName = "processor_name"
            case authkey
            case tpn
            case environment
            case isActive = "is_active"
        }
    }

    /// Get terminal client for the current session (reads credentials from vault)
    private func getTerminalClient(for sessionInfo: SessionInfo) async -> (any PaymentTerminal)? {
        do {
            let registerId = sessionInfo.registerId.uuidString.lowercased()
            logger.info("🔍 Looking up terminal for register: \(registerId)")

            // Call RPC function that reads from vault
            let configs: [TerminalConfig] = try await supabase
                .rpc("get_terminal_config", params: ["p_register_id": registerId])
                .execute()
                .value

            guard let config = configs.first else {
                logger.warning("⚠️ No terminal config found for register: \(registerId)")
                return nil
            }

            logger.info("📋 Processor: \(config.processorName ?? "unnamed"), active: \(config.isActive ?? false)")

            guard config.isActive == true else {
                logger.warning("⚠️ Payment processor is not active")
                return nil
            }

            guard let authKey = config.authkey, let tpn = config.tpn else {
                logger.warning("⚠️ Missing Dejavoo credentials (authKey: \(config.authkey != nil), tpn: \(config.tpn != nil))")
                return nil
            }

            let environment: DejavooEnvironment = config.environment == "sandbox" ? .sandbox : .production
            let dejavooConfig = DejavooConfig(authKey: authKey, tpn: tpn, environment: environment)

            logger.info("💳 Using Dejavoo terminal: \(config.processorName ?? "Unknown") (TPN: \(tpn))")
            return DejavooClient(config: dejavooConfig)

        } catch {
            logger.error("❌ Failed to fetch terminal config: \(error.localizedDescription)")
            return nil
        }
    }

    /// Report terminal result back to Edge Function
    private func reportTerminalResult(
        intentId: String,
        approved: Bool,
        authorizationCode: String? = nil,
        cardType: String? = nil,
        cardLast4: String? = nil,
        referenceId: String? = nil,
        errorMessage: String? = nil
    ) async throws {
        let session = try await supabase.auth.session
        let accessToken = session.accessToken

        let url = SupabaseConfig.url
            .appendingPathComponent("functions/v1/payment-intent")
            .appendingPathComponent(intentId)
            .appendingPathComponent("terminal-result")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.timeoutInterval = 30

        let payload: [String: Any?] = [
            "approved": approved,
            "authorizationCode": authorizationCode,
            "cardType": cardType,
            "cardLast4": cardLast4,
            "referenceId": referenceId,
            "errorMessage": errorMessage
        ]

        request.httpBody = try JSONSerialization.data(
            withJSONObject: payload.compactMapValues { $0 }
        )

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw PaymentError.networkError("Failed to report terminal result: \(errorText)")
        }

        logger.debug("📤 Terminal result reported: approved=\(approved)")
    }
}

// MARK: - Payload Types

private struct CreateIntentPayload: Encodable {
    let storeId: String
    let locationId: String
    let registerId: String
    let sessionId: String
    let paymentMethod: String
    let amount: Double
    let cartItems: [CartItemPayload]
    let totals: TotalsPayload
    let customerId: String?
    let customerName: String
    let userId: String?
    let cashTendered: Double?
    let changeGiven: Double?
    let cashAmount: Double?
    let cardAmount: Double?
    let splitPayments: [SplitPaymentPayload]?
    let loyaltyPointsRedeemed: Int
    let loyaltyDiscountAmount: Double
    let campaignDiscountAmount: Double
    let campaignId: String?
    let idempotencyKey: String
}

private struct CartItemPayload: Encodable {
    let productId: String
    let productName: String
    let productSku: String?
    let quantity: Int
    let tierQty: Double
    let tierName: String?
    let unitPrice: Double
    let lineTotal: Double
    let discountAmount: Double
    let inventoryId: String?
    let gramsToDeduct: Double
    let locationId: String?
    let variantTemplateId: String?
    let variantName: String?
    let conversionRatio: Double?
}

private struct TotalsPayload: Encodable {
    let subtotal: Double
    let taxAmount: Double
    let discountAmount: Double
    let total: Double
}

struct SplitPaymentPayload: Encodable {
    let method: String
    let amount: Double
    let cardNumber: Int?

    init(method: String, amount: Decimal, cardNumber: Int? = nil) {
        self.method = method
        self.amount = NSDecimalNumber(decimal: amount).doubleValue
        self.cardNumber = cardNumber
    }
}

private struct CreateIntentResponse: Decodable {
    let success: Bool
    let intentId: String
    let status: String
    let orderId: String?
    let orderNumber: String?
    let idempotent: Bool?
}

private struct IntentStatus: Decodable {
    let id: String
    let status: String
    let statusMessage: String?
    let errorMessage: String?
    let paymentMethod: String
    let amount: Double
    let orderId: String?
    let orderNumber: String?
    let authorizationCode: String?
    let cardType: String?
    let cardLast4: String?
    let terminalAmount: Double?
    let currentCardNumber: Int?
}

// MARK: - CartItem Extension

extension CartItem {
    fileprivate func toPayload(locationId: UUID) -> CartItemPayload {
        CartItemPayload(
            productId: productId.uuidString.lowercased(),
            productName: productName,
            productSku: sku,
            quantity: quantity,
            tierQty: tierQuantity,
            tierName: tierLabel,
            unitPrice: NSDecimalNumber(decimal: effectiveUnitPrice).doubleValue,
            lineTotal: NSDecimalNumber(decimal: lineTotal).doubleValue,
            discountAmount: NSDecimalNumber(decimal: discountAmount).doubleValue,
            inventoryId: inventoryId?.uuidString.lowercased(),
            gramsToDeduct: inventoryDeduction,
            locationId: locationId.uuidString.lowercased(),
            variantTemplateId: variantId?.uuidString.lowercased(),
            variantName: variantName,
            conversionRatio: conversionRatio
        )
    }
}

// MARK: - Multi-Card Result

struct MultiCardResult: Sendable {
    let success: Bool
    let orderId: UUID?
    let orderNumber: String?
    let card1Success: Bool
    let card2Success: Bool
    let card1ErrorMessage: String?
    let card2ErrorMessage: String?
}

// MARK: - Backend-Driven Payment Types

/// Split payment amounts (cash + card)
struct SplitAmounts: Sendable {
    let cash: Decimal
    let card: Decimal
}

/// Multi-card payment percentages
struct CardPercentages: Sendable {
    let card1Percent: Double
    let card2Percent: Double
}

// MARK: - Payment Processor Models

/// Register with nested payment processor (from Supabase join query)
private struct RegisterWithProcessor: Codable {
    let id: UUID
    let paymentProcessorId: UUID?
    let paymentProcessor: PaymentProcessorDetails?

    enum CodingKeys: String, CodingKey {
        case id
        case paymentProcessorId = "payment_processor_id"
        case paymentProcessor = "payment_processors"
    }
}

/// Payment processor details from nested query
private struct PaymentProcessorDetails: Codable {
    let id: UUID
    let processorName: String?
    let dejavooAuthkey: String?
    let dejavooTpn: String?
    let environment: String?
    let isActive: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case processorName = "processor_name"
        case dejavooAuthkey = "dejavoo_authkey"
        case dejavooTpn = "dejavoo_tpn"
        case environment
        case isActive = "is_active"
    }
}
