//
//  CartModels.swift
//  Whale
//
//  Server-side cart models: cart, items, totals, and tax breakdown.
//

import Foundation

// MARK: - Server Cart

struct ServerCart: Codable, Identifiable, Sendable {
    let id: UUID
    let storeId: UUID
    let locationId: UUID
    let customerId: UUID?
    let status: String
    let items: [ServerCartItem]
    let totals: CheckoutTotals

    var subtotal: Decimal { totals.subtotal }
    var discountAmount: Decimal { totals.discountAmount }
    var taxRate: Decimal { totals.taxRate }
    var taxAmount: Decimal { totals.taxAmount }
    var total: Decimal { totals.total }
    var itemCount: Int { totals.itemCount }

    enum CodingKeys: String, CodingKey {
        case id
        case storeId = "store_id"
        case locationId = "location_id"
        case customerId = "customer_id"
        case status
        case items
        case totals
    }
}

// MARK: - Server Cart Item

struct ServerCartItem: Codable, Identifiable, Sendable {
    let id: UUID
    let productId: UUID
    let productName: String
    let sku: String?
    let unitPrice: Decimal
    let quantity: Int
    let tierLabel: String?
    let tierQuantity: Double
    let variantId: UUID?
    let variantName: String?
    let inventoryId: UUID?
    let lineTotal: Decimal
    let discountAmount: Decimal
    let manualDiscountType: String?
    let manualDiscountValue: Decimal?

    enum CodingKeys: String, CodingKey {
        case id
        case productId = "product_id"
        case productName = "product_name"
        case sku
        case unitPrice = "unit_price"
        case quantity
        case tierLabel = "tier_label"
        case tierQuantity = "tier_quantity"
        case variantId = "variant_id"
        case variantName = "variant_name"
        case inventoryId = "inventory_id"
        case lineTotal = "line_total"
        case discountAmount = "discount_amount"
        case manualDiscountType = "manual_discount_type"
        case manualDiscountValue = "manual_discount_value"
    }

    var displayName: String {
        if let variantName = variantName {
            return "\(productName) (\(variantName))"
        }
        return productName
    }

    var hasDiscount: Bool {
        manualDiscountType != nil && (manualDiscountValue ?? 0) > 0
    }
}

// MARK: - Tax Breakdown Item

struct TaxBreakdownItem: Codable, Sendable {
    let name: String?
    let rate: Decimal?
    let amount: Decimal?

    enum CodingKeys: String, CodingKey {
        case name
        case rate
        case amount
        case taxName = "tax_name"
        case taxRate = "tax_rate"
        case taxAmount = "tax_amount"
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
            ?? container.decodeIfPresent(String.self, forKey: .taxName)
        rate = try container.decodeIfPresent(Decimal.self, forKey: .rate)
            ?? container.decodeIfPresent(Decimal.self, forKey: .taxRate)
        amount = try container.decodeIfPresent(Decimal.self, forKey: .amount)
            ?? container.decodeIfPresent(Decimal.self, forKey: .taxAmount)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(rate, forKey: .rate)
        try container.encodeIfPresent(amount, forKey: .amount)
    }
}

// MARK: - Checkout Totals

struct CheckoutTotals: Codable, Sendable {
    let subtotal: Decimal
    let discountAmount: Decimal
    let taxableAmount: Decimal
    let taxRate: Decimal
    let taxAmount: Decimal
    let taxBreakdown: [TaxBreakdownItem]?
    let total: Decimal
    let itemCount: Int
    let cashSuggestions: [Decimal]?
    let errors: [String]
    let isValid: Bool

    enum CodingKeys: String, CodingKey {
        case subtotal
        case discountAmount = "discount_amount"
        case taxableAmount = "taxable_amount"
        case taxRate = "tax_rate"
        case taxAmount = "tax_amount"
        case taxBreakdown = "tax_breakdown"
        case total
        case itemCount = "item_count"
        case cashSuggestions = "cash_suggestions"
        case errors
        case isValid = "is_valid"
    }
}

// MARK: - Cart Errors

enum CartError: LocalizedError {
    case serverError(String)
    case networkError
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .serverError(let message): return message
        case .networkError: return "Network error"
        case .httpError(let code): return "HTTP error: \(code)"
        }
    }
}
