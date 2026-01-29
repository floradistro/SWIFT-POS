//
//  CheckoutCalculator.swift
//  Whale
//
//  FULLY MIGRATED: ALL calculation logic now lives server-side in Edge Functions.
//  This file is kept for backwards compatibility only.
//
//  Server-side calculation happens in:
//  - /payment-calculator Edge Function (split amounts, cash suggestions, validation)
//  - /cart Edge Function (item totals via DB triggers)
//  - /checkout-calculate Edge Function (validation)
//
//  iOS is a "dumb terminal" - it sends user input and displays backend responses.
//  Use PaymentCalculatorService for all payment calculations.
//

import Foundation

// MARK: - Checkout Calculator (DEPRECATED - Use PaymentCalculatorService)

enum CheckoutCalculator {

    /// Default tax rate (8.25%) - actual rate comes from server
    static let defaultTaxRate: Decimal = 0.0825

    /// Calculate change for cash payment - simple local calculation is acceptable
    /// - Parameters:
    ///   - tendered: Amount given by customer
    ///   - total: Total amount due
    /// - Returns: Change amount (nil if insufficient)
    static func calculateChange(tendered: Decimal, total: Decimal) -> Decimal? {
        let change = tendered - total
        return change >= 0 ? change.rounded() : nil
    }

    /// @deprecated Use PaymentCalculatorService.getCashSuggestions() instead
    /// This method is kept for backwards compatibility but is no longer used.
    /// All cash suggestions are now fetched from the backend.
    @available(*, deprecated, message: "Use PaymentCalculatorService.getCashSuggestions() for backend-driven suggestions")
    static func suggestedCashAmounts(for total: Decimal) -> [Decimal] {
        let amount = NSDecimalNumber(decimal: total).doubleValue
        var suggestions: [Decimal] = []

        // Always start with exact amount
        suggestions.append(total.rounded())

        // Smart rounding based on total amount
        if amount <= 5 {
            // Small amounts: $5, $10, $20
            if 5 > amount { suggestions.append(5) }
            if 10 > amount { suggestions.append(10) }
            suggestions.append(20)
        } else if amount <= 10 {
            // $5-10: next $5, $20, $50
            let nextFive = ceil(amount / 5) * 5
            if nextFive > amount { suggestions.append(Decimal(nextFive)) }
            suggestions.append(20)
            suggestions.append(50)
        } else if amount <= 20 {
            // $10-20: next $5, $20, $50
            let nextFive = ceil(amount / 5) * 5
            if nextFive > amount && nextFive <= 20 { suggestions.append(Decimal(nextFive)) }
            if 20 > amount { suggestions.append(20) }
            suggestions.append(50)
            suggestions.append(100)
        } else if amount <= 50 {
            // $20-50: next $10, $50, $100
            let nextTen = ceil(amount / 10) * 10
            if nextTen > amount && nextTen < 50 { suggestions.append(Decimal(nextTen)) }
            if 50 > amount { suggestions.append(50) }
            suggestions.append(100)
        } else if amount <= 100 {
            // $50-100: next $10, next $20, $100
            let nextTen = ceil(amount / 10) * 10
            if nextTen > amount { suggestions.append(Decimal(nextTen)) }
            let nextTwenty = ceil(amount / 20) * 20
            if nextTwenty > amount && !suggestions.contains(Decimal(nextTwenty)) {
                suggestions.append(Decimal(nextTwenty))
            }
            if 100 > amount { suggestions.append(100) }
            suggestions.append(150)
        } else {
            // Over $100: next $20, next $50, next $100
            let nextTwenty = ceil(amount / 20) * 20
            if nextTwenty > amount { suggestions.append(Decimal(nextTwenty)) }
            let nextFifty = ceil(amount / 50) * 50
            if nextFifty > amount && !suggestions.contains(Decimal(nextFifty)) {
                suggestions.append(Decimal(nextFifty))
            }
            let nextHundred = ceil(amount / 100) * 100
            if nextHundred > amount && !suggestions.contains(Decimal(nextHundred)) {
                suggestions.append(Decimal(nextHundred))
            }
        }

        // Remove duplicates and limit to 4 suggestions
        var unique: [Decimal] = []
        for s in suggestions {
            if !unique.contains(s) { unique.append(s) }
        }

        return Array(unique.prefix(4))
    }
}

// MARK: - Tax Rate Provider

/// Protocol for location-based tax rates
protocol TaxRateProvider {
    func taxRate(for locationId: UUID) async throws -> Decimal
}

/// Default implementation using hardcoded rate
struct DefaultTaxRateProvider: TaxRateProvider {
    func taxRate(for locationId: UUID) async throws -> Decimal {
        // TODO: Fetch from Supabase locations table
        return CheckoutCalculator.defaultTaxRate
    }
}
