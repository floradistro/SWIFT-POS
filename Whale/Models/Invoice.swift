//
//  Invoice.swift
//  Whale
//
//  Invoice, line item, and related types for invoice management.
//

import Foundation

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

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
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

    static func create(
        productId: UUID? = nil,
        productName: String,
        quantity: Int,
        unitPrice: Decimal,
        taxRate: Decimal = 0
    ) async throws -> InvoiceLineItem {
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

    static func createManual(
        description: String,
        quantity: Int,
        unitPrice: Decimal,
        taxRate: Decimal = 0
    ) async throws -> InvoiceLineItem {
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

// MARK: - Invoice Request/Response

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
    let dueDate: String?
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

struct SendInvoiceResponse: Codable {
    let success: Bool
    let invoice: InvoiceDetails?
    let emailSent: Bool?
    let emailError: String?
    let error: String?

    struct InvoiceDetails: Codable {
        let id: UUID
        let invoiceNumber: String
        let orderId: UUID
        let orderNumber: String
        let paymentToken: String
        let paymentUrl: String
    }
}

// MARK: - Invoice Model

struct Invoice: Identifiable, Codable, Sendable {
    let id: UUID
    let invoiceNumber: String
    let orderId: UUID?
    let storeId: UUID
    let customerId: UUID?
    let customerName: String?
    let customerEmail: String
    let customerPhone: String?
    let description: String?
    let lineItems: [InvoiceLineItem]?
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

    let sentAt: Date?
    let viewedAt: Date?
    let paidAt: Date?
    let reminderSentAt: Date?

    let paymentMethod: String?
    let transactionId: String?
    let cardLastFour: String?
    let cardType: String?

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

    var displayCustomerName: String {
        customerName ?? customerEmail
    }

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

        if let dueDateString = try container.decodeIfPresent(String.self, forKey: .dueDate) {
            let dateOnlyFormatter = DateFormatter()
            dateOnlyFormatter.dateFormat = "yyyy-MM-dd"
            dateOnlyFormatter.timeZone = TimeZone(identifier: "UTC")

            if let date = dateOnlyFormatter.date(from: dueDateString) {
                dueDate = date
            } else {
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

    init(
        id: UUID, invoiceNumber: String, orderId: UUID?, storeId: UUID,
        customerId: UUID?, customerName: String?, customerEmail: String, customerPhone: String?,
        description: String?, lineItems: [InvoiceLineItem]?,
        subtotal: Decimal, taxAmount: Decimal, discountAmount: Decimal, totalAmount: Decimal,
        status: InvoiceStatus, paymentStatus: String?, amountPaid: Decimal?, amountDue: Decimal?,
        dueDate: Date?, notes: String?, paymentToken: String?, paymentUrl: String?,
        sentAt: Date?, viewedAt: Date?, paidAt: Date?, reminderSentAt: Date?,
        paymentMethod: String?, transactionId: String?, cardLastFour: String?, cardType: String?,
        createdAt: Date, updatedAt: Date
    ) {
        self.id = id; self.invoiceNumber = invoiceNumber; self.orderId = orderId; self.storeId = storeId
        self.customerId = customerId; self.customerName = customerName; self.customerEmail = customerEmail
        self.customerPhone = customerPhone; self.description = description; self.lineItems = lineItems
        self.subtotal = subtotal; self.taxAmount = taxAmount; self.discountAmount = discountAmount
        self.totalAmount = totalAmount; self.status = status; self.paymentStatus = paymentStatus
        self.amountPaid = amountPaid; self.amountDue = amountDue; self.dueDate = dueDate
        self.notes = notes; self.paymentToken = paymentToken; self.paymentUrl = paymentUrl
        self.sentAt = sentAt; self.viewedAt = viewedAt; self.paidAt = paidAt
        self.reminderSentAt = reminderSentAt; self.paymentMethod = paymentMethod
        self.transactionId = transactionId; self.cardLastFour = cardLastFour; self.cardType = cardType
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }
}

// MARK: - Invoice Status

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

    var progressSteps: Int {
        var steps = 0
        if isSent { steps += 1 }
        if isViewed { steps += 1 }
        if isPaid { steps += 1 }
        return steps
    }
}

// MARK: - Invoice Errors

enum InvoiceError: LocalizedError {
    case invalidEmail
    case emptyLineItems
    case networkError(String)
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidEmail: return "Please enter a valid email address"
        case .emptyLineItems: return "Invoice must have at least one item"
        case .networkError(let message): return "Network error: \(message)"
        case .serverError(let message): return "Server error: \(message)"
        }
    }
}
