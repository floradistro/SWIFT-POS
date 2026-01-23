//
//  InvoiceService.swift
//  Whale
//
//  Invoice creation and management.
//  Calls the send-invoice edge function to create invoices with payment links.
//

import Foundation
import Supabase
import os.log

// MARK: - Invoice Line Item

struct InvoiceLineItem: Codable, Identifiable, Sendable {
    var id: UUID
    var productId: UUID?
    var productName: String
    var quantity: Int
    var unitPrice: Decimal
    var subtotal: Decimal
    var taxAmount: Decimal
    var discountAmount: Decimal
    var total: Decimal

    enum CodingKeys: String, CodingKey {
        case id
        case productId = "product_id"
        case productName = "product_name"
        case quantity
        case unitPrice = "unit_price"
        case subtotal
        case taxAmount = "tax_amount"
        case discountAmount = "discount_amount"
        case total
    }

    // Custom decoder to handle missing id in JSON from database
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Generate id if not present (DB line_items don't have id)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.productId = try container.decodeIfPresent(UUID.self, forKey: .productId)
        self.productName = try container.decode(String.self, forKey: .productName)
        self.quantity = try container.decode(Int.self, forKey: .quantity)
        self.unitPrice = try container.decode(Decimal.self, forKey: .unitPrice)
        self.subtotal = try container.decode(Decimal.self, forKey: .subtotal)
        self.taxAmount = try container.decodeIfPresent(Decimal.self, forKey: .taxAmount) ?? 0
        self.discountAmount = try container.decodeIfPresent(Decimal.self, forKey: .discountAmount) ?? 0
        self.total = try container.decode(Decimal.self, forKey: .total)
    }

    /// Create line item with pre-calculated values from backend
    /// Use InvoiceLineItem.create() async factory method for proper backend calculation
    init(
        productId: UUID? = nil,
        productName: String,
        quantity: Int,
        unitPrice: Decimal,
        subtotal: Decimal,
        taxAmount: Decimal,
        total: Decimal
    ) {
        self.id = UUID()
        self.productId = productId
        self.productName = productName
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.subtotal = subtotal
        self.taxAmount = taxAmount
        self.discountAmount = 0
        self.total = total
    }

    /// Factory method - creates line item with backend-calculated values
    static func create(
        productId: UUID? = nil,
        productName: String,
        quantity: Int,
        unitPrice: Decimal,
        taxRate: Decimal = 0
    ) async throws -> InvoiceLineItem {
        // ALL calculation logic is server-side
        let result = try await PaymentCalculatorService.shared.calculateLineItem(
            unitPrice: unitPrice,
            quantity: quantity,
            taxRate: taxRate
        )
        return InvoiceLineItem(
            productId: productId,
            productName: productName,
            quantity: quantity,
            unitPrice: unitPrice,
            subtotal: result.subtotal,
            taxAmount: result.taxAmount,
            total: result.total
        )
    }

    /// Factory method for manual line items - backend-calculated
    static func createManual(
        description: String,
        quantity: Int,
        unitPrice: Decimal,
        taxRate: Decimal = 0
    ) async throws -> InvoiceLineItem {
        // ALL calculation logic is server-side
        let result = try await PaymentCalculatorService.shared.calculateLineItem(
            unitPrice: unitPrice,
            quantity: quantity,
            taxRate: taxRate
        )
        return InvoiceLineItem(
            productId: nil,
            productName: description,
            quantity: quantity,
            unitPrice: unitPrice,
            subtotal: result.subtotal,
            taxAmount: result.taxAmount,
            total: result.total
        )
    }
}

// MARK: - Invoice Request

struct SendInvoiceRequest: Codable {
    let storeId: UUID
    let customerId: UUID?
    let customerName: String
    let customerEmail: String
    let customerPhone: String?
    let description: String?
    let lineItems: [InvoiceLineItem]
    let subtotal: Decimal
    let taxAmount: Decimal
    let discountAmount: Decimal
    let totalAmount: Decimal
    let dueDate: String?  // ISO date string
    let notes: String?
    let locationId: UUID?
    let sendEmail: Bool

    enum CodingKeys: String, CodingKey {
        case storeId
        case customerId
        case customerName
        case customerEmail
        case customerPhone
        case description
        case lineItems
        case subtotal
        case taxAmount
        case discountAmount
        case totalAmount
        case dueDate
        case notes
        case locationId
        case sendEmail
    }
}

// MARK: - Invoice Response

struct SendInvoiceResponse: Codable {
    let success: Bool
    let invoice: InvoiceDetails?
    let emailSent: Bool?
    let emailError: String?
    let error: String?

    struct InvoiceDetails: Codable {
        let id: UUID           // Edge function returns "id" not "invoiceId"
        let invoiceNumber: String
        let orderId: UUID
        let orderNumber: String
        let paymentToken: String
        let paymentUrl: String

        // No CodingKeys needed - edge function returns camelCase which Swift auto-decodes
    }

    // No CodingKeys needed - edge function returns camelCase
}

// MARK: - Invoice Model (for fetching from database)

struct Invoice: Identifiable, Codable, Sendable {
    let id: UUID
    let invoiceNumber: String
    let orderId: UUID?
    let storeId: UUID
    let customerId: UUID?
    let customerName: String?
    let customerEmail: String
    let customerPhone: String?
    let description: String?      // Invoice description
    let lineItems: [InvoiceLineItem]?  // Line items (JSONB in DB)
    let subtotal: Decimal
    let taxAmount: Decimal
    let discountAmount: Decimal
    let totalAmount: Decimal
    let status: InvoiceStatus
    let paymentStatus: String?
    let amountPaid: Decimal?
    let amountDue: Decimal?
    let dueDate: Date?
    let notes: String?
    let paymentToken: String?
    let paymentUrl: String?

    // Tracking fields (actual DB columns)
    let sentAt: Date?           // When invoice email was sent
    let viewedAt: Date?         // When customer viewed the invoice
    let paidAt: Date?           // When payment was completed
    let reminderSentAt: Date?   // When reminder email was sent

    // Payment details
    let paymentMethod: String?
    let transactionId: String?
    let cardLastFour: String?
    let cardType: String?

    // Timestamps
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case invoiceNumber = "invoice_number"
        case orderId = "order_id"
        case storeId = "store_id"
        case customerId = "customer_id"
        case customerName = "customer_name"
        case customerEmail = "customer_email"
        case customerPhone = "customer_phone"
        case description
        case lineItems = "line_items"
        case subtotal
        case taxAmount = "tax_amount"
        case discountAmount = "discount_amount"
        case totalAmount = "total_amount"
        case status
        case paymentStatus = "payment_status"
        case amountPaid = "amount_paid"
        case amountDue = "amount_due"
        case dueDate = "due_date"
        case notes
        case paymentToken = "payment_token"
        case paymentUrl = "payment_url"
        case sentAt = "sent_at"
        case viewedAt = "viewed_at"
        case paidAt = "paid_at"
        case reminderSentAt = "reminder_sent_at"
        case paymentMethod = "payment_method"
        case transactionId = "transaction_id"
        case cardLastFour = "card_last_four"
        case cardType = "card_type"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /// Display name for customer (falls back to email if no name)
    var displayCustomerName: String {
        customerName ?? customerEmail
    }

    // Custom decoder to handle date-only format for dueDate
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        invoiceNumber = try container.decode(String.self, forKey: .invoiceNumber)
        orderId = try container.decodeIfPresent(UUID.self, forKey: .orderId)
        storeId = try container.decode(UUID.self, forKey: .storeId)
        customerId = try container.decodeIfPresent(UUID.self, forKey: .customerId)
        customerName = try container.decodeIfPresent(String.self, forKey: .customerName)
        customerEmail = try container.decode(String.self, forKey: .customerEmail)
        customerPhone = try container.decodeIfPresent(String.self, forKey: .customerPhone)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        lineItems = try container.decodeIfPresent([InvoiceLineItem].self, forKey: .lineItems)
        subtotal = try container.decode(Decimal.self, forKey: .subtotal)
        taxAmount = try container.decode(Decimal.self, forKey: .taxAmount)
        discountAmount = try container.decode(Decimal.self, forKey: .discountAmount)
        totalAmount = try container.decode(Decimal.self, forKey: .totalAmount)
        status = try container.decode(InvoiceStatus.self, forKey: .status)
        paymentStatus = try container.decodeIfPresent(String.self, forKey: .paymentStatus)
        amountPaid = try container.decodeIfPresent(Decimal.self, forKey: .amountPaid)
        amountDue = try container.decodeIfPresent(Decimal.self, forKey: .amountDue)

        // Handle dueDate which can be date-only (2025-12-25) or full timestamp
        if let dueDateString = try container.decodeIfPresent(String.self, forKey: .dueDate) {
            // Try date-only format first
            let dateOnlyFormatter = DateFormatter()
            dateOnlyFormatter.dateFormat = "yyyy-MM-dd"
            dateOnlyFormatter.timeZone = TimeZone(identifier: "UTC")

            if let date = dateOnlyFormatter.date(from: dueDateString) {
                dueDate = date
            } else {
                // Try ISO8601 format
                let isoFormatter = ISO8601DateFormatter()
                isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                dueDate = isoFormatter.date(from: dueDateString)
            }
        } else {
            dueDate = nil
        }

        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        paymentToken = try container.decodeIfPresent(String.self, forKey: .paymentToken)
        paymentUrl = try container.decodeIfPresent(String.self, forKey: .paymentUrl)
        sentAt = try container.decodeIfPresent(Date.self, forKey: .sentAt)
        viewedAt = try container.decodeIfPresent(Date.self, forKey: .viewedAt)
        paidAt = try container.decodeIfPresent(Date.self, forKey: .paidAt)
        reminderSentAt = try container.decodeIfPresent(Date.self, forKey: .reminderSentAt)
        paymentMethod = try container.decodeIfPresent(String.self, forKey: .paymentMethod)
        transactionId = try container.decodeIfPresent(String.self, forKey: .transactionId)
        cardLastFour = try container.decodeIfPresent(String.self, forKey: .cardLastFour)
        cardType = try container.decodeIfPresent(String.self, forKey: .cardType)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    // Memberwise initializer for programmatic creation
    init(
        id: UUID,
        invoiceNumber: String,
        orderId: UUID?,
        storeId: UUID,
        customerId: UUID?,
        customerName: String?,
        customerEmail: String,
        customerPhone: String?,
        description: String?,
        lineItems: [InvoiceLineItem]?,
        subtotal: Decimal,
        taxAmount: Decimal,
        discountAmount: Decimal,
        totalAmount: Decimal,
        status: InvoiceStatus,
        paymentStatus: String?,
        amountPaid: Decimal?,
        amountDue: Decimal?,
        dueDate: Date?,
        notes: String?,
        paymentToken: String?,
        paymentUrl: String?,
        sentAt: Date?,
        viewedAt: Date?,
        paidAt: Date?,
        reminderSentAt: Date?,
        paymentMethod: String?,
        transactionId: String?,
        cardLastFour: String?,
        cardType: String?,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.invoiceNumber = invoiceNumber
        self.orderId = orderId
        self.storeId = storeId
        self.customerId = customerId
        self.customerName = customerName
        self.customerEmail = customerEmail
        self.customerPhone = customerPhone
        self.description = description
        self.lineItems = lineItems
        self.subtotal = subtotal
        self.taxAmount = taxAmount
        self.discountAmount = discountAmount
        self.totalAmount = totalAmount
        self.status = status
        self.paymentStatus = paymentStatus
        self.amountPaid = amountPaid
        self.amountDue = amountDue
        self.dueDate = dueDate
        self.notes = notes
        self.paymentToken = paymentToken
        self.paymentUrl = paymentUrl
        self.sentAt = sentAt
        self.viewedAt = viewedAt
        self.paidAt = paidAt
        self.reminderSentAt = reminderSentAt
        self.paymentMethod = paymentMethod
        self.transactionId = transactionId
        self.cardLastFour = cardLastFour
        self.cardType = cardType
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

enum InvoiceStatus: String, Codable, Sendable {
    case draft
    case sent
    case viewed
    case paid
    case partiallyPaid = "partially_paid"
    case overdue
    case cancelled
    case refunded

    var displayName: String {
        switch self {
        case .draft: return "Draft"
        case .sent: return "Sent"
        case .viewed: return "Viewed"
        case .paid: return "Paid"
        case .partiallyPaid: return "Partial"
        case .overdue: return "Overdue"
        case .cancelled: return "Cancelled"
        case .refunded: return "Refunded"
        }
    }

    var color: String {
        switch self {
        case .draft: return "gray"
        case .sent: return "blue"
        case .viewed: return "amber"
        case .paid: return "green"
        case .partiallyPaid: return "orange"
        case .overdue: return "red"
        case .cancelled: return "gray"
        case .refunded: return "gray"
        }
    }
}

// MARK: - Invoice Tracking Info

struct InvoiceTrackingInfo: Sendable {
    let isSent: Bool
    let isViewed: Bool
    let isPaid: Bool
    let reminderSent: Bool

    let sentAt: Date?
    let viewedAt: Date?
    let paidAt: Date?
    let reminderSentAt: Date?

    init(invoice: Invoice) {
        self.isSent = invoice.sentAt != nil
        self.isViewed = invoice.viewedAt != nil
        self.isPaid = invoice.paidAt != nil
        self.reminderSent = invoice.reminderSentAt != nil

        self.sentAt = invoice.sentAt
        self.viewedAt = invoice.viewedAt
        self.paidAt = invoice.paidAt
        self.reminderSentAt = invoice.reminderSentAt
    }

    /// Progress through the invoice funnel (0-3)
    var progressSteps: Int {
        var steps = 0
        if isSent { steps += 1 }
        if isViewed { steps += 1 }
        if isPaid { steps += 1 }
        return steps
    }
}

// MARK: - Invoice Service

enum InvoiceService {

    private static let logger = Logger(subsystem: "com.whale.pos", category: "InvoiceService")
    private static var edgeFunctionURL: URL { URL(string: "\(SupabaseConfig.baseURL)/functions/v1/send-invoice")! }

    /// Create and send an invoice
    /// - Parameters:
    ///   - storeId: The store ID
    ///   - customer: Optional customer (can send to non-customer email)
    ///   - customerName: Customer name for invoice
    ///   - customerEmail: Email to send invoice to
    ///   - customerPhone: Optional phone number
    ///   - lineItems: Invoice line items
    ///   - taxRate: Tax rate to apply (e.g., 0.08 for 8%)
    ///   - description: Optional invoice description
    ///   - notes: Optional notes to include
    ///   - dueDate: Optional due date
    ///   - locationId: Optional location ID
    ///   - sendEmail: Whether to send email (default true)
    /// - Returns: Invoice response with payment URL
    static func sendInvoice(
        storeId: UUID,
        customer: Customer? = nil,
        customerName: String,
        customerEmail: String,
        customerPhone: String? = nil,
        lineItems: [InvoiceLineItem],
        taxRate: Decimal = 0,
        description: String? = nil,
        notes: String? = nil,
        dueDate: Date? = nil,
        locationId: UUID? = nil,
        sendEmail: Bool = true
    ) async throws -> SendInvoiceResponse {

        // Calculate totals
        let subtotal = lineItems.reduce(Decimal(0)) { $0 + $1.subtotal }
        let taxAmount = lineItems.reduce(Decimal(0)) { $0 + $1.taxAmount }
        let discountAmount = lineItems.reduce(Decimal(0)) { $0 + $1.discountAmount }
        let totalAmount = subtotal + taxAmount - discountAmount

        // Format due date if provided
        var dueDateString: String? = nil
        if let dueDate = dueDate {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate]
            dueDateString = formatter.string(from: dueDate)
        }

        let request = SendInvoiceRequest(
            storeId: storeId,
            customerId: customer?.id,
            customerName: customerName,
            customerEmail: customerEmail,
            customerPhone: customerPhone ?? customer?.phone,
            description: description,
            lineItems: lineItems,
            subtotal: subtotal,
            taxAmount: taxAmount,
            discountAmount: discountAmount,
            totalAmount: totalAmount,
            dueDate: dueDateString,
            notes: notes,
            locationId: locationId,
            sendEmail: sendEmail
        )

        logger.info("📧 Sending invoice to \(customerEmail) for \(totalAmount)")

        // Get auth token for authenticated request
        let session = try await supabase.auth.session
        let accessToken = session.accessToken

        // Make request with auth headers
        var urlRequest = URLRequest(url: edgeFunctionURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let encoder = JSONEncoder()
        urlRequest.httpBody = try encoder.encode(request)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw InvoiceError.networkError("Invalid response")
        }

        if httpResponse.statusCode != 200 {
            // Try to parse error message
            if let errorResponse = try? JSONDecoder().decode(SendInvoiceResponse.self, from: data) {
                throw InvoiceError.serverError(errorResponse.error ?? "Unknown error")
            }
            throw InvoiceError.serverError("HTTP \(httpResponse.statusCode)")
        }

        let decoder = JSONDecoder()

        do {
            let invoiceResponse = try decoder.decode(SendInvoiceResponse.self, from: data)

            if invoiceResponse.success {
                logger.info("✅ Invoice created: \(invoiceResponse.invoice?.invoiceNumber ?? "unknown")")
            } else {
                logger.error("❌ Invoice failed: \(invoiceResponse.error ?? "unknown")")
            }

            return invoiceResponse
        } catch {
            // Log raw response for debugging
            if let rawString = String(data: data, encoding: .utf8) {
                logger.error("❌ Failed to decode response: \(rawString.prefix(500))")
            }
            logger.error("❌ Decode error: \(error)")
            throw InvoiceError.serverError("Failed to parse response: \(error.localizedDescription)")
        }
    }

    /// Create an invoice from cart items - ALL calculations are backend-driven
    static func createFromCart(
        storeId: UUID,
        customer: Customer?,
        customerName: String,
        customerEmail: String,
        cartItems: [CartItem],
        taxRate: Decimal,
        locationId: UUID?,
        notes: String? = nil
    ) async throws -> SendInvoiceResponse {
        // Create line items with backend-calculated values
        var lineItems: [InvoiceLineItem] = []
        for item in cartItems {
            let productName = item.tierLabel != nil ? "\(item.productName) (\(item.tierLabel!))" : item.productName
            let lineItem = try await InvoiceLineItem.create(
                productId: item.productId,
                productName: productName,
                quantity: item.quantity,
                unitPrice: item.unitPrice,
                taxRate: taxRate
            )
            lineItems.append(lineItem)
        }

        return try await sendInvoice(
            storeId: storeId,
            customer: customer,
            customerName: customerName,
            customerEmail: customerEmail,
            lineItems: lineItems,
            taxRate: taxRate,
            notes: notes,
            locationId: locationId
        )
    }

    // MARK: - Fetch Invoice

    /// Fetch an invoice by ID
    static func fetchInvoice(id: UUID) async throws -> Invoice {
        logger.info("📄 Fetching invoice \(id)")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let invoice: Invoice = try await supabase
            .from("invoices")
            .select()
            .eq("id", value: id.uuidString)
            .single()
            .execute()
            .value

        return invoice
    }

    /// Fetch invoice by order ID
    static func fetchInvoiceByOrder(orderId: UUID) async throws -> Invoice? {
        // Use lowercase UUID for PostgreSQL compatibility
        let orderIdString = orderId.uuidString.lowercased()
        logger.info("📄 Fetching invoice for order \(orderIdString)")

        do {
            let invoices: [Invoice] = try await supabase
                .from("invoices")
                .select()
                .eq("order_id", value: orderIdString)
                .limit(1)
                .execute()
                .value

            logger.info("📄 Decoded \(invoices.count) invoices for order \(orderIdString)")

            if let invoice = invoices.first {
                logger.info("📄 Found invoice: \(invoice.invoiceNumber), status: \(invoice.status.rawValue)")
            } else {
                logger.info("📄 No invoice found for order \(orderIdString)")
            }

            return invoices.first
        } catch {
            logger.error("📄 Failed to fetch/decode invoice: \(error)")
            throw error
        }
    }

    /// Fetch all invoices for a store
    static func fetchInvoices(storeId: UUID, limit: Int = 50) async throws -> [Invoice] {
        logger.info("📄 Fetching invoices for store \(storeId)")

        let invoices: [Invoice] = try await supabase
            .from("invoices")
            .select()
            .eq("store_id", value: storeId.uuidString)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value

        logger.info("📄 Fetched \(invoices.count) invoices")
        return invoices
    }

    // MARK: - Resend Invoice

    private static var resendFunctionURL: URL { URL(string: "\(SupabaseConfig.baseURL)/functions/v1/resend-invoice")! }

    /// Resend an invoice email
    static func resendInvoice(invoiceId: UUID) async throws -> Bool {
        logger.info("📧 Resending invoice \(invoiceId)")

        // Get auth token
        let session = try await supabase.auth.session
        let accessToken = session.accessToken

        // Make request
        var urlRequest = URLRequest(url: resendFunctionURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let body = ["invoiceId": invoiceId.uuidString]
        urlRequest.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw InvoiceError.networkError("Invalid response")
        }

        if httpResponse.statusCode != 200 {
            if let errorJson = try? JSONDecoder().decode([String: String].self, from: data),
               let errorMessage = errorJson["error"] {
                throw InvoiceError.serverError(errorMessage)
            }
            throw InvoiceError.serverError("HTTP \(httpResponse.statusCode)")
        }

        // Parse response
        if let json = try? JSONDecoder().decode([String: Bool].self, from: data),
           let success = json["success"] {
            logger.info("✅ Invoice resent: \(success)")
            return success
        }

        return true
    }

    // MARK: - Send Reminder

    private static var reminderFunctionURL: URL { URL(string: "\(SupabaseConfig.baseURL)/functions/v1/send-invoice-reminder")! }

    /// Send a payment reminder for an unpaid invoice
    static func sendReminder(invoiceId: UUID) async throws -> Bool {
        logger.info("🔔 Sending reminder for invoice \(invoiceId)")

        // Get auth token
        let session = try await supabase.auth.session
        let accessToken = session.accessToken

        // Make request
        var urlRequest = URLRequest(url: reminderFunctionURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let body = ["invoiceId": invoiceId.uuidString]
        urlRequest.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw InvoiceError.networkError("Invalid response")
        }

        if httpResponse.statusCode != 200 {
            if let errorJson = try? JSONDecoder().decode([String: String].self, from: data),
               let errorMessage = errorJson["error"] {
                throw InvoiceError.serverError(errorMessage)
            }
            throw InvoiceError.serverError("HTTP \(httpResponse.statusCode)")
        }

        // Parse response
        if let json = try? JSONDecoder().decode([String: Bool].self, from: data),
           let success = json["success"] {
            logger.info("✅ Reminder sent: \(success)")
            return success
        }

        return true
    }

    // MARK: - Real-time Subscription

    /// Subscribe to real-time updates for invoices on a specific order
    /// This allows subscribing before knowing the invoice ID
    /// Returns an AsyncStream that emits Invoice updates
    static func subscribeToInvoiceByOrder(orderId: UUID) -> AsyncStream<Invoice> {
        AsyncStream { continuation in
            let channelName = "invoice-order-\(orderId.uuidString.prefix(8))-\(UInt64(Date().timeIntervalSince1970 * 1000))"
            logger.info("📄 Subscribing to invoice updates for order: \(channelName)")

            let channel = supabase.channel(channelName)

            // Listen for changes on invoices for this order
            let changes = channel.postgresChange(
                UpdateAction.self,
                schema: "public",
                table: "invoices",
                filter: "order_id=eq.\(orderId.uuidString.lowercased())"
            )

            Task {
                await channel.subscribe()
                logger.info("📄 Invoice subscription active for order \(orderId.uuidString.prefix(8))")

                for await change in changes {
                    logger.info("📄 Invoice update received for order")

                    // Decode the updated invoice
                    do {
                        let record = change.record
                        let data = try JSONSerialization.data(withJSONObject: sanitizeForJSON(record))
                        let decoder = JSONDecoder()
                        let invoice = try decoder.decode(Invoice.self, from: data)
                        continuation.yield(invoice)
                    } catch {
                        logger.error("📄 Failed to decode invoice update: \(error)")
                    }
                }
            }

            continuation.onTermination = { _ in
                logger.info("📄 Invoice subscription terminated")
                Task {
                    await channel.unsubscribe()
                    await supabase.removeChannel(channel)
                }
            }
        }
    }

    /// Subscribe to real-time updates for a specific invoice by ID
    /// Returns an AsyncStream that emits Invoice updates
    static func subscribeToInvoice(invoiceId: UUID) -> AsyncStream<Invoice> {
        AsyncStream { continuation in
            let channelName = "invoice-\(invoiceId.uuidString.prefix(8))-\(UInt64(Date().timeIntervalSince1970 * 1000))"
            logger.info("📄 Subscribing to invoice updates: \(channelName)")

            let channel = supabase.channel(channelName)

            // Listen for changes on this specific invoice
            let changes = channel.postgresChange(
                UpdateAction.self,
                schema: "public",
                table: "invoices",
                filter: "id=eq.\(invoiceId.uuidString.lowercased())"
            )

            Task {
                await channel.subscribe()
                logger.info("📄 Invoice subscription active")

                for await change in changes {
                    logger.info("📄 Invoice update received")

                    // Decode the updated invoice
                    do {
                        let record = change.record
                        let data = try JSONSerialization.data(withJSONObject: sanitizeForJSON(record))
                        let decoder = JSONDecoder()
                        let invoice = try decoder.decode(Invoice.self, from: data)
                        continuation.yield(invoice)
                    } catch {
                        logger.error("📄 Failed to decode invoice update: \(error)")
                    }
                }
            }

            continuation.onTermination = { _ in
                logger.info("📄 Invoice subscription terminated")
                Task {
                    await channel.unsubscribe()
                    await supabase.removeChannel(channel)
                }
            }
        }
    }

    /// Sanitize record for JSON serialization (handle AnyJSON types)
    private static func sanitizeForJSON(_ record: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in record {
            if let dict = value as? [String: Any] {
                result[key] = sanitizeForJSON(dict)
            } else if let array = value as? [Any] {
                result[key] = array.map { item -> Any in
                    if let dictItem = item as? [String: Any] {
                        return sanitizeForJSON(dictItem) as Any
                    }
                    return convertToJSONSafe(item)
                }
            } else {
                result[key] = convertToJSONSafe(value)
            }
        }
        return result
    }

    private static func convertToJSONSafe(_ value: Any) -> Any {
        // Handle AnyJSON and other Swift-bridged types
        if let stringValue = value as? String { return stringValue }
        if let intValue = value as? Int { return intValue }
        if let doubleValue = value as? Double { return doubleValue }
        if let boolValue = value as? Bool { return boolValue }
        if value is NSNull { return NSNull() }
        // Convert unknown types to string representation
        return String(describing: value)
    }
}

// MARK: - Errors

enum InvoiceError: LocalizedError {
    case invalidEmail
    case emptyLineItems
    case networkError(String)
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidEmail:
            return "Please enter a valid email address"
        case .emptyLineItems:
            return "Invoice must have at least one item"
        case .networkError(let message):
            return "Network error: \(message)"
        case .serverError(let message):
            return "Server error: \(message)"
        }
    }
}

