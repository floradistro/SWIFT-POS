//
//  PaymentPayloads.swift
//  Whale
//
//  Payment intent payloads and response types for the payment-intent Edge Function.
//  Extracted from PaymentStore for Apple engineering standards compliance.
//

import Foundation

// MARK: - Request Payloads

struct CreateIntentPayload: Encodable {
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
    let affiliateId: String?
    let affiliateCode: String?
    let affiliateDiscountAmount: Double
    let idempotencyKey: String
}

struct CartItemPayload: Encodable {
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
    let tierQuantity: Double
    let locationId: String?
    let variantTemplateId: String?
    let variantName: String?
    let conversionRatio: Double?
}

struct TotalsPayload: Encodable {
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

// MARK: - Response Types

struct CreateIntentResponse: Decodable {
    let success: Bool
    let intentId: String
    let status: String
    let orderId: String?
    let orderNumber: String?
    let idempotent: Bool?
}

struct IntentStatus: Decodable {
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
struct RegisterWithProcessor: Codable {
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
struct PaymentProcessorDetails: Codable {
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

// MARK: - CartItem Extension

extension CartItem {
    func toPayload(locationId: UUID) -> CartItemPayload {
        CartItemPayload(
            productId: productId.uuidString,
            productName: productName,
            productSku: sku,
            quantity: quantity,
            tierQty: tierQuantity,
            tierName: tierLabel,
            unitPrice: NSDecimalNumber(decimal: effectiveUnitPrice).doubleValue,
            lineTotal: NSDecimalNumber(decimal: lineTotal).doubleValue,
            discountAmount: NSDecimalNumber(decimal: discountAmount).doubleValue,
            inventoryId: inventoryId?.uuidString,
            tierQuantity: tierQuantity,
            locationId: locationId.uuidString,
            variantTemplateId: variantId?.uuidString,
            variantName: variantName,
            conversionRatio: conversionRatio
        )
    }
}
