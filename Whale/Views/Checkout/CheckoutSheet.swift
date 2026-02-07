//
//  CheckoutSheet.swift
//  Whale
//
//  Checkout sheet using unified modal system.
//  Uses existing ModalHeader, ModalSection, ModalActionButton components.
//

import SwiftUI
import os.log

struct CheckoutSheet: View {
    @Environment(\.posWindowSession) private var windowSession: POSWindowSession?
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var posStore: POSStore
    @ObservedObject var paymentStore: PaymentStore
    @ObservedObject var dealStore: DealStore
    let initialTotals: CheckoutTotals  // Initial totals (used as fallback)
    let sessionInfo: SessionInfo
    let loyaltyProgram: LoyaltyProgram?  // Store's loyalty program settings

    var onScanID: () -> Void
    var onComplete: (SaleCompletion?) -> Void

    // State
    @State private var checkoutPhase: CheckoutPhase = .checkout
    @State private var selectedPaymentMethod: DockPaymentMethod = .card
    @State private var cashAmount: String = ""
    @State private var splitCashAmount: String = ""
    @State private var card1Percentage: Double = 50

    // Invoice
    @State private var invoiceNotes: String = ""
    @State private var invoiceEmail: String = ""
    @State private var invoiceDueDate: Date = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var showDueDatePicker = false

    // Loyalty
    @State private var pointsToRedeem: Int = 0

    // Success
    @State private var completedOrder: SaleCompletion?
    @State private var copiedLink = false
    @State private var autoPrintFailed = false

    // Error
    @State private var showErrorAlert = false
    @State private var errorMessage = ""

    // Line Item Discount
    @State private var selectedItemForDiscount: CartItem?
    @State private var showDiscountSheet = false

    enum CheckoutPhase { case checkout, processing, success }

    // MARK: - Accessors

    private var isMultiWindowSession: Bool { windowSession?.location != nil }
    private var cartItems: [CartItem] { isMultiWindowSession ? (windowSession?.cartItems ?? []) : posStore.cartItems }
    private var selectedCustomer: Customer? { isMultiWindowSession ? windowSession?.selectedCustomer : posStore.selectedCustomer }

    /// Live totals from current cart state (updates when discounts are applied)
    private var totals: CheckoutTotals {
        if isMultiWindowSession {
            return windowSession?.activeCart?.totals ?? initialTotals
        } else {
            return posStore.activeCart?.totals ?? initialTotals
        }
    }

    private var hasLoyaltyPoints: Bool { (selectedCustomer?.loyaltyPoints ?? 0) > 0 }

    /// Point value from loyalty program (defaults to $0.05 per point)
    private var pointValue: Decimal { loyaltyProgram?.pointValue ?? Decimal(sign: .plus, exponent: -2, significand: 5) }

    /// Calculate loyalty discount based on actual point value from settings
    private var calculatedLoyaltyDiscount: Decimal { Decimal(pointsToRedeem) * pointValue }

    /// Max points that can be redeemed (capped at order total)
    private var maxRedeemablePoints: Int {
        let availablePoints = selectedCustomer?.loyaltyPoints ?? 0
        guard pointValue > 0 else { return 0 }
        // Max points = order total / point value (e.g., $5.33 / $0.05 = 106 points max)
        let maxByTotal = Int(truncating: (totals.total / pointValue) as NSDecimalNumber)
        return min(availablePoints, maxByTotal)
    }

    private var displayTotal: Decimal { totals.total - calculatedLoyaltyDiscount }
    private var hasLoyaltyDiscount: Bool { pointsToRedeem > 0 }

    private var canSendInvoice: Bool {
        guard selectedCustomer != nil else { return false }
        let hasEmail = selectedCustomer?.email?.isEmpty == false
        let emailRegex = #"^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        let hasValidManual = !invoiceEmail.isEmpty && invoiceEmail.range(of: emailRegex, options: .regularExpression) != nil
        return !cartItems.isEmpty && (hasEmail || hasValidManual)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            switch checkoutPhase {
            case .checkout: checkoutContent
            case .processing: processingContent
            case .success: successContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
        .onChange(of: paymentStore.uiState) { _, state in
            handlePaymentStateChange(state)
        }
        .alert("Payment Failed", isPresented: $showErrorAlert) {
            Button("Retry") { paymentStore.reset() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .overlay {
            if showDiscountSheet {
                LineItemDiscountOverlay(
                    item: selectedItemForDiscount,
                    isPresented: $showDiscountSheet,
                    isMultiWindowSession: isMultiWindowSession,
                    windowSession: windowSession,
                    posStore: posStore,
                    onRemoveItem: removeItemFromCart
                )
            }
        }
    }

    // MARK: - Checkout Content

    private var checkoutContent: some View {
        VStack(spacing: 0) {
            // Header
            sheetHeader

            // Scrollable content
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    // Items
                    itemsSection

                    // Totals
                    totalsSection

                    // Loyalty
                    if hasLoyaltyPoints {
                        loyaltySection
                    }

                    // Payment methods
                    paymentMethodSection

                    // Payment input
                    paymentInputSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)

            // Action button pinned at bottom
            actionButton
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
        }
    }

    // MARK: - Sheet Header

    private var sheetHeader: some View {
        VStack(spacing: 16) {
            HStack(alignment: .center) {
                ModalCloseButton { dismiss() }

                Spacer()

                // Total and customer
                VStack(spacing: 8) {
                    // Customer chip
                    if let customer = selectedCustomer {
                        HStack(spacing: 6) {
                            Text(customer.initials)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(Color.accentColor))

                            Text(customer.firstName ?? "Customer")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .glassEffect(.regular, in: .capsule)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Customer: \(customer.displayName)")
                    }

                    // Total
                    Text(CurrencyFormatter.format(displayTotal))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())

                    // Item count
                    Text("\(cartItems.count) item\(cartItems.count == 1 ? "" : "s")")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                }

                Spacer()

                // Placeholder for symmetry
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Items Section

    private var itemsSection: some View {
        VStack(spacing: 0) {
            ForEach(Array(cartItems.prefix(5).enumerated()), id: \.element.id) { index, item in
                CheckoutCartItemRow(
                    item: item,
                    index: index,
                    isMultiWindowSession: isMultiWindowSession,
                    windowSession: windowSession,
                    posStore: posStore,
                    onLongPress: { selectedItem in
                        selectedItemForDiscount = selectedItem
                        withAnimation(.spring(response: 0.3)) {
                            showDiscountSheet = true
                        }
                    },
                    onRemoveItem: removeItemFromCart
                )
            }

            if cartItems.count > 5 {
                Text("+\(cartItems.count - 5) more items")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.3))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
            }
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }

    private func removeItemFromCart(_ item: CartItem) async {
        if isMultiWindowSession {
            // POSWindowSession expects ServerCartItem, so we need to find it
            if let serverItem = windowSession?.activeCart?.items.first(where: { $0.id == item.id }) {
                await windowSession?.removeFromCart(serverItem)
            }
        } else {
            posStore.removeFromCart(item.id)
        }
    }

    // MARK: - Totals Section

    private var totalsSection: some View {
        VStack(spacing: 0) {
            totalsRow(label: "Subtotal", value: CurrencyFormatter.format(totals.subtotal))

            if totals.taxAmount > 0 {
                totalsRow(label: "Tax", value: CurrencyFormatter.format(totals.taxAmount))
            }

            if totals.discountAmount > 0 {
                totalsRow(label: "Discount", value: "-\(CurrencyFormatter.format(totals.discountAmount))", valueColor: .green)
            }

            if hasLoyaltyDiscount {
                totalsRow(label: "Points Redeemed", value: "-\(CurrencyFormatter.format(calculatedLoyaltyDiscount))", valueColor: .green)
            }

            // Divider
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 1)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)

            // Total row
            HStack {
                Text("Total")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text(CurrencyFormatter.format(displayTotal))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }

    private func totalsRow(label: String, value: String, valueColor: Color = .white.opacity(0.6)) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.5))
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(valueColor)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Loyalty Section

    private var loyaltySection: some View {
        VStack(spacing: 12) {
            // Header row
            HStack(alignment: .center) {
                // Star icon
                Image(systemName: "star.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.yellow)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Loyalty Points")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)

                    Text("\(selectedCustomer?.loyaltyPoints ?? 0) available • \(CurrencyFormatter.format(pointValue)) each")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                }

                Spacer()

                // Discount badge - only shown when redeeming
                if hasLoyaltyDiscount {
                    Text("-\(CurrencyFormatter.format(calculatedLoyaltyDiscount))")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.green)
                }
            }

            // Slider with labels
            VStack(spacing: 6) {
                Slider(
                    value: Binding(
                        get: { Double(pointsToRedeem) },
                        set: { newValue in
                            withAnimation(.interactiveSpring(response: 0.2, dampingFraction: 0.8)) {
                                pointsToRedeem = Int(newValue)
                            }
                        }
                    ),
                    in: 0...Double(max(maxRedeemablePoints, 1)),
                    step: 10
                )
                .tint(.yellow)

                // Labels under slider
                HStack {
                    Text("0")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.3))

                    Spacer()

                    // Current value - centered and prominent
                    if pointsToRedeem > 0 {
                        Text("\(pointsToRedeem) pts")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.yellow)
                    } else {
                        Text("Slide to redeem")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.35))
                    }

                    Spacer()

                    Text("\(maxRedeemablePoints)")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }

    // MARK: - Payment Method Section

    private var paymentMethodSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach([DockPaymentMethod.card, .cash, .split, .multiCard, .invoice], id: \.self) { method in
                    paymentMethodButton(method)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func paymentMethodButton(_ method: DockPaymentMethod) -> some View {
        let isSelected = selectedPaymentMethod == method

        return Button {
            Haptics.light()
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                selectedPaymentMethod = method
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: method.icon)
                    .font(.system(size: 18, weight: .medium))
                Text(method.label)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(isSelected ? .white : .white.opacity(0.6))
            .frame(width: 72, height: 56)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white.opacity(0.15))
                }
            }
            .glassEffect(.regular, in: .rect(cornerRadius: 14))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
                }
            }
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityLabel(method.label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Payment Input

    @ViewBuilder
    private var paymentInputSection: some View {
        switch selectedPaymentMethod {
        case .card:
            CardPaymentInput()
        case .cash:
            CashPaymentInput(cashAmount: $cashAmount, total: displayTotal)
        case .split:
            SplitPaymentInput(splitCashAmount: $splitCashAmount, total: displayTotal)
        case .multiCard:
            MultiCardPaymentInput(card1Percentage: $card1Percentage, total: displayTotal)
        case .invoice:
            InvoicePaymentInput(
                customer: selectedCustomer,
                invoiceEmail: $invoiceEmail,
                invoiceDueDate: $invoiceDueDate,
                invoiceNotes: $invoiceNotes,
                showDueDatePicker: $showDueDatePicker,
                onAddCustomer: { dismiss(); onScanID() }
            )
        }
    }

    // MARK: - Action Button

    private var actionButton: some View {
        SlideToPayButton(
            text: actionButtonText,
            icon: selectedPaymentMethod.icon,
            isEnabled: selectedPaymentMethod == .invoice ? canSendInvoice : true,
            onComplete: {
                Task {
                    if selectedPaymentMethod == .invoice {
                        await sendInvoice()
                    } else {
                        await processPayment()
                    }
                }
            }
        )
    }

    private var actionButtonText: String {
        switch selectedPaymentMethod {
        case .card: return "Pay \(CurrencyFormatter.format(displayTotal))"
        case .cash: return "Cash \(CurrencyFormatter.format(displayTotal))"
        case .split: return "Split \(CurrencyFormatter.format(displayTotal))"
        case .multiCard: return "2 Cards \(CurrencyFormatter.format(displayTotal))"
        case .invoice: return "Send Invoice"
        }
    }

    // MARK: - Processing Content

    private var processingContent: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 28) {
                // Animated spinner
                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.1), lineWidth: 4)
                        .frame(width: 80, height: 80)

                    ProgressView()
                        .scaleEffect(1.8)
                        .tint(.accentColor)
                }

                VStack(spacing: 6) {
                    Text("Processing...")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(selectedPaymentMethod.label)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }

                Text(CurrencyFormatter.format(displayTotal))
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Success Content

    private var successContent: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .center) {
                ModalCloseButton {
                    onComplete(completedOrder)
                    dismiss()
                }

                Spacer()

                VStack(spacing: 4) {
                    Text(isInvoice ? "Invoice Sent" : "Payment Complete")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    if let orderNumber = completedOrder?.orderNumber {
                        Text(orderNumber)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }

                Spacer()

                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            // Main content - fills space
            Spacer()

            VStack(spacing: 24) {
                if autoPrintFailed {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .accessibilityHidden(true)
                        Text("Labels failed to print")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.orange.opacity(0.15), in: Capsule())
                    .accessibilityElement(children: .combine)
                }

                Image(systemName: isInvoice ? "paperplane.circle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(isInvoice ? .blue : .green)
                    .symbolEffect(.bounce, value: checkoutPhase)
                    .accessibilityLabel(isInvoice ? "Invoice sent" : "Payment complete")

                Text(CurrencyFormatter.format(completedOrder?.total ?? displayTotal))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(isInvoice ? .blue : .green)

                if isInvoice, let paymentUrl = completedOrder?.paymentUrl {
                    Button {
                        UIPasteboard.general.string = paymentUrl
                        copiedLink = true
                        Haptics.success()
                        Task { @MainActor in try? await Task.sleep(for: .seconds(2)); copiedLink = false }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: copiedLink ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 14, weight: .medium))
                            Text(copiedLink ? "Copied!" : "Copy Payment Link")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                    }
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
                    .padding(.horizontal, 40)
                }
            }

            Spacer()
            Spacer()

            // Done button pinned at bottom
            Button {
                onComplete(completedOrder)
                dismiss()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Done")
                        .font(.system(size: 17, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(isInvoice ? Color.blue : Color.green, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(ScaleButtonStyle())
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var isInvoice: Bool {
        completedOrder?.paymentMethod == .invoice
    }

    // MARK: - Handlers

    private func handlePaymentStateChange(_ state: UIPaymentState) {
        switch state {
        case .idle: break
        case .processing:
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                checkoutPhase = .processing
            }
        case .success(let completion):
            completedOrder = completion
            ScanFeedback.shared.paymentSuccess()
            triggerAutoPrintIfEnabled(with: completion)
            LabelPrinterSettings.shared.stopPrewarming()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                checkoutPhase = .success
            }
        case .failed(let message):
            errorMessage = message
            showErrorAlert = true
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                checkoutPhase = .checkout
            }
            Haptics.error()
        }
    }

    private func processPayment() async {
        LabelPrinterSettings.shared.startPrewarming()
        let loyaltyDiscount = calculatedLoyaltyDiscount
        let effectiveTotal = displayTotal

        do {
            switch selectedPaymentMethod {
            case .card:
                _ = try await paymentStore.processCardPayment(
                    cart: cartItems, totals: totals, sessionInfo: sessionInfo, customer: selectedCustomer,
                    loyaltyPointsRedeemed: pointsToRedeem, loyaltyDiscountAmount: loyaltyDiscount
                )
            case .cash:
                let cashValue = Decimal(string: cashAmount) ?? effectiveTotal
                guard cashValue >= effectiveTotal else {
                    errorMessage = "Cash must be at least \(CurrencyFormatter.format(effectiveTotal))"
                    showErrorAlert = true
                    return
                }
                _ = try await paymentStore.processCashPayment(
                    cart: cartItems, totals: totals, cashTendered: cashValue, sessionInfo: sessionInfo, customer: selectedCustomer,
                    loyaltyPointsRedeemed: pointsToRedeem, loyaltyDiscountAmount: loyaltyDiscount
                )
            case .split:
                guard let cashValue = Decimal(string: splitCashAmount), cashValue > 0 else {
                    errorMessage = "Enter cash amount"
                    showErrorAlert = true
                    return
                }
                let cardAmount = effectiveTotal - cashValue
                guard cardAmount > 0 else {
                    errorMessage = "Card amount must be > $0"
                    showErrorAlert = true
                    return
                }
                _ = try await paymentStore.processSplitPayment(
                    cart: cartItems, totals: totals, cashAmount: cashValue, cardAmount: cardAmount, sessionInfo: sessionInfo, customer: selectedCustomer,
                    loyaltyPointsRedeemed: pointsToRedeem, loyaltyDiscountAmount: loyaltyDiscount
                )
            case .multiCard:
                let splitResult = try await PaymentCalculatorService.shared.calculateSplitPercentage(total: effectiveTotal, percentage: card1Percentage)
                _ = try await paymentStore.processMultiCardPayment(
                    cart: cartItems, totals: totals, card1Amount: splitResult.amount1, card2Amount: splitResult.amount2, sessionInfo: sessionInfo, customer: selectedCustomer,
                    loyaltyPointsRedeemed: pointsToRedeem, loyaltyDiscountAmount: loyaltyDiscount
                )
            case .invoice:
                break
            }
        } catch {
            errorMessage = error.localizedDescription
            showErrorAlert = true
        }
    }

    private func sendInvoice() async {
        guard let customer = selectedCustomer else {
            errorMessage = "Customer required"
            showErrorAlert = true
            return
        }

        let emailRegex = #"^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        let emailToUse: String
        if let customerEmail = customer.email, !customerEmail.isEmpty {
            emailToUse = customerEmail
        } else if !invoiceEmail.isEmpty && invoiceEmail.range(of: emailRegex, options: .regularExpression) != nil {
            emailToUse = invoiceEmail
        } else {
            errorMessage = "Valid email required"
            showErrorAlert = true
            return
        }

        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            checkoutPhase = .processing
        }

        do {
            var invoiceItems: [InvoiceLineItem] = []
            for item in cartItems {
                let lineItem = try await InvoiceLineItem.create(
                    productId: item.productId, productName: item.productName,
                    quantity: item.quantity, unitPrice: item.unitPrice, taxRate: totals.taxRate
                )
                invoiceItems.append(lineItem)
            }

            let response = try await InvoiceService.sendInvoice(
                storeId: sessionInfo.storeId, customer: customer, customerName: customer.displayName, customerEmail: emailToUse,
                customerPhone: customer.phone, lineItems: invoiceItems, taxRate: totals.taxRate,
                notes: invoiceNotes.isEmpty ? nil : invoiceNotes, dueDate: invoiceDueDate, locationId: sessionInfo.locationId
            )

            if response.success, let invoice = response.invoice {
                var completion = SaleCompletion(
                    orderId: invoice.orderId, orderNumber: invoice.invoiceNumber, transactionNumber: invoice.invoiceNumber,
                    total: totals.total, paymentMethod: .invoice, completedAt: Date()
                )
                completion.paymentUrl = invoice.paymentUrl
                completion.invoiceNumber = invoice.invoiceNumber
                completedOrder = completion
                triggerAutoPrintIfEnabled(with: completion)
                LabelPrinterSettings.shared.stopPrewarming()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    checkoutPhase = .success
                }
                Haptics.success()
            } else {
                throw InvoiceError.serverError(response.error ?? "Unknown error")
            }
        } catch {
            errorMessage = error.localizedDescription
            showErrorAlert = true
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                checkoutPhase = .checkout
            }
        }
    }

    private func triggerAutoPrintIfEnabled(with completion: SaleCompletion?) {
        let settings = LabelPrinterSettings.shared
        Log.label.debug("triggerAutoPrintIfEnabled called")
        Log.label.debug("autoPrintEnabled: \(settings.autoPrintEnabled)")
        Log.label.debug("isPrinterConfigured: \(settings.isPrinterConfigured)")
        Log.label.debug("printerUrl: \(settings.printerUrl?.absoluteString ?? "nil")")
        Log.label.debug("orderId: \(completion?.orderId.uuidString ?? "nil")")

        guard settings.autoPrintEnabled else {
            Log.label.debug("Auto-print disabled, skipping")
            return
        }
        guard let completion = completion else {
            Log.label.debug("No completion, skipping")
            return
        }
        let orderId = completion.orderId

        Task {
            do {
                guard let order = try await OrderService.fetchOrder(orderId: orderId) else {
                    await MainActor.run {
                        autoPrintFailed = true
                        errorMessage = "Print failed: Order not found in database"
                        showErrorAlert = true
                    }
                    return
                }

                try await LabelPrinterManager.shared.printOrder(order)
            } catch {
                await MainActor.run {
                    autoPrintFailed = true
                    errorMessage = "Print failed: \(error.localizedDescription)"
                    showErrorAlert = true
                }
            }
        }
    }
}
