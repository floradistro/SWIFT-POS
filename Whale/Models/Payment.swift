//
//  Payment.swift
//  Whale
//
//  Payment domain models.
//  State machine logic has been moved to backend (payment-intent Edge Function).
//  This file now contains only data types for rendering.
//

import Foundation

// MARK: - Payment Method

enum PaymentMethod: String, CaseIterable, Codable, Sendable {
    case cash
    case card
    case split          // Cash + Card combination
    case multiCard = "multi-card"  // Two card transactions
    case invoice        // Pay later via payment link

    var displayName: String {
        switch self {
        case .cash: return "Cash"
        case .card: return "Card"
        case .split: return "Split"
        case .multiCard: return "Multi-Card"
        case .invoice: return "Invoice"
        }
    }

    var icon: String {
        switch self {
        case .cash: return "banknote"
        case .card: return "creditcard"
        case .split: return "rectangle.stack"
        case .multiCard: return "creditcard.and.123"
        case .invoice: return "paperplane"
        }
    }

    /// All payment methods available in the checkout UI
    static var checkoutMethods: [PaymentMethod] {
        [.card, .cash, .split, .multiCard, .invoice]
    }
}

// NOTE: CheckoutTotals is defined in CartService.swift (server-side cart)

// MARK: - Sale Completion

/// Result of a successful sale (from backend)
struct SaleCompletion: Sendable, Equatable {
    let orderId: UUID
    let orderNumber: String
    let transactionNumber: String
    let total: Decimal
    let paymentMethod: PaymentMethod
    let completedAt: Date

    // Card details (if applicable)
    var authorizationCode: String?
    var cardType: String?
    var cardLast4: String?

    // Cash details (if applicable)
    var cashTendered: Decimal?
    var changeGiven: Decimal?

    // Loyalty
    var loyaltyPointsEarned: Int?
    var loyaltyPointsRedeemed: Int?

    // Invoice details (if applicable)
    var paymentUrl: String?
    var invoiceNumber: String?

    // Receipt
    var receiptData: String?
}

// MARK: - Payment Errors

enum PaymentError: LocalizedError, Sendable {
    case paymentInProgress
    case emptyCart
    case invalidAmount
    case terminalUnavailable
    case terminalTimeout
    case transactionDeclined(reason: String)
    case networkError(String)
    case saveFailed(String)
    case insufficientCash
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .paymentInProgress:
            return "Payment already in progress"
        case .emptyCart:
            return "Cart is empty"
        case .invalidAmount:
            return "Invalid payment amount"
        case .terminalUnavailable:
            return "Payment terminal unavailable"
        case .terminalTimeout:
            return "Terminal did not respond"
        case .transactionDeclined(let reason):
            return "Transaction declined: \(reason)"
        case .networkError(let message):
            return "Network error: \(message)"
        case .saveFailed(let message):
            return "Failed to save: \(message)"
        case .insufficientCash:
            return "Insufficient cash tendered"
        case .unknown(let message):
            return message
        }
    }
}

// MARK: - Decimal Extension

extension Decimal {
    /// Round to specified decimal places
    func rounded(scale: Int = 2) -> Decimal {
        var value = self
        var result = Decimal()
        NSDecimalRound(&result, &value, scale, .bankers)
        return result
    }
}
