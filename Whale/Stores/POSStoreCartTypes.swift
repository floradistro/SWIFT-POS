//
//  POSStoreCartTypes.swift
//  Whale
//
//  Cart compatibility types: ManualDiscountType and CartItem wrapper
//  for backward compatibility with existing views.
//

import Foundation

// MARK: - Manual Discount Type

enum ManualDiscountType: String, Sendable, Codable {
    case percentage
    case fixed
}

// MARK: - CartItem (Compatibility Layer)

/// CartItem struct for backward compatibility with existing views
/// Wraps ServerCartItem data - uses server-calculated values for pricing
struct CartItem: Identifiable, Sendable, Equatable {
    let id: UUID
    let productId: UUID
    let productName: String
    let unitPrice: Decimal
    var quantity: Int
    let tierQuantity: Double
    let sku: String?
    let tierLabel: String?
    let inventoryId: UUID?
    let variantId: UUID?
    let variantName: String?
    let conversionRatio: Double?
    var manualDiscountType: ManualDiscountType?
    var manualDiscountValue: Decimal?

    // Server-calculated values (no client-side pricing logic)
    let lineTotal: Decimal
    let discountAmount: Decimal

    /// Create from server cart item
    init(from server: ServerCartItem) {
        self.id = server.id
        self.productId = server.productId
        self.productName = server.productName
        self.unitPrice = server.unitPrice
        self.quantity = server.quantity
        self.tierQuantity = server.tierQuantity
        self.sku = server.sku
        self.tierLabel = server.tierLabel
        self.inventoryId = server.inventoryId
        self.variantId = server.variantId
        self.variantName = server.variantName
        self.conversionRatio = nil  // Not in server response
        if let type = server.manualDiscountType {
            self.manualDiscountType = ManualDiscountType(rawValue: type)
        }
        self.manualDiscountValue = server.manualDiscountValue

        // Use server-calculated values - no client-side pricing logic
        self.lineTotal = server.lineTotal
        self.discountAmount = server.discountAmount
    }

    /// Original line total before any discounts (for display only)
    var originalLineTotal: Decimal {
        unitPrice * Decimal(quantity)
    }

    /// Effective unit price (derived from server lineTotal for accuracy)
    var effectiveUnitPrice: Decimal {
        guard quantity > 0 else { return unitPrice }
        return lineTotal / Decimal(quantity)
    }

    /// Whether this item has a manual discount applied
    var hasManualDiscount: Bool {
        discountAmount > 0
    }

    /// Display string for the discount (e.g., "10% off" or "$5 off")
    var discountDisplayText: String? {
        guard let discountType = manualDiscountType,
              let discountValue = manualDiscountValue,
              discountValue > 0 else {
            return nil
        }

        switch discountType {
        case .percentage:
            return "\(NSDecimalNumber(decimal: discountValue).intValue)% off"
        case .fixed:
            return "\(CurrencyFormatter.format(discountValue)) off"
        }
    }

    var inventoryDeduction: Double {
        tierQuantity * Double(quantity)
    }

    /// Whether this is a variant sale (e.g., Pre-Roll instead of Flower)
    var isVariantSale: Bool {
        variantId != nil
    }

    /// Display name including variant (e.g., "OG Kush (Pre-Roll)")
    var displayName: String {
        if let variantName = variantName {
            return "\(productName) (\(variantName))"
        }
        return productName
    }
}
