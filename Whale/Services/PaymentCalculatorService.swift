//
//  PaymentCalculatorService.swift
//  Whale
//
//  Backend-driven payment calculations.
//  ALL split logic, cash suggestions, and validation happens server-side.
//  iOS is a dumb terminal - we just display what the backend tells us.
//

import Foundation
import os.log

// MARK: - Payment Calculator Service

actor PaymentCalculatorService {
    static let shared = PaymentCalculatorService()

    private let logger = Logger(subsystem: "com.whale.pos", category: "PaymentCalc")
    private let baseURL = SupabaseConfig.url.appendingPathComponent("functions/v1/payment-calculator")

    // Cache for cash suggestions (they don't change often)
    private var cashSuggestionsCache: [Decimal: [Decimal]] = [:]

    // MARK: - Split Calculation

    /// Calculate split payment amounts - ALL logic is server-side
    func calculateSplit(
        total: Decimal,
        splitType: SplitType,
        preset: SplitPreset? = nil,
        editedField: EditedField? = nil,
        editedValue: Decimal? = nil
    ) async throws -> SplitResult {
        var payload: [String: Any] = [
            "total": NSDecimalNumber(decimal: total).doubleValue,
            "splitType": splitType.rawValue
        ]

        if let preset = preset {
            payload["preset"] = preset.rawValue
        }
        if let field = editedField, let value = editedValue {
            payload["editedField"] = field.rawValue
            payload["editedValue"] = NSDecimalNumber(decimal: value).doubleValue
        }

        let response: SplitResponse = try await post(endpoint: "split", payload: payload)

        return SplitResult(
            isValid: response.isValid,
            amount1: Decimal(response.amount1),
            amount2: Decimal(response.amount2),
            remaining: Decimal(response.remaining),
            errors: response.errors,
            label1: response.label1,
            label2: response.label2
        )
    }

    // MARK: - Cash Suggestions

    /// Get smart cash amount suggestions for a total
    func getCashSuggestions(for total: Decimal) async throws -> CashSuggestionsResult {
        // Check cache first
        if let cached = cashSuggestionsCache[total] {
            return CashSuggestionsResult(suggestions: cached, exactAmount: total)
        }

        let payload: [String: Any] = [
            "total": NSDecimalNumber(decimal: total).doubleValue
        ]

        let response: CashSuggestionsResponse = try await post(endpoint: "cash-suggestions", payload: payload)

        let suggestions = response.suggestions.map { Decimal($0) }
        cashSuggestionsCache[total] = suggestions

        return CashSuggestionsResult(
            suggestions: suggestions,
            exactAmount: Decimal(response.exactAmount)
        )
    }

    // MARK: - Loyalty Calculation

    /// Calculate loyalty points redemption - ALL logic is server-side
    func calculateLoyalty(
        total: Decimal,
        availablePoints: Int,
        pointValue: Decimal,
        pointsToRedeem: Int? = nil
    ) async throws -> LoyaltyResult {
        let payload: [String: Any] = [
            "total": NSDecimalNumber(decimal: total).doubleValue,
            "availablePoints": availablePoints,
            "pointValue": NSDecimalNumber(decimal: pointValue).doubleValue,
            "pointsToRedeem": pointsToRedeem ?? 0
        ]

        let response: LoyaltyResponse = try await post(endpoint: "loyalty", payload: payload)

        return LoyaltyResult(
            maxRedeemablePoints: response.maxRedeemablePoints,
            redemptionValue: Decimal(response.redemptionValue),
            newTotal: Decimal(response.newTotal),
            isValid: response.isValid,
            errors: response.errors
        )
    }

    // MARK: - Split by Percentage

    /// Calculate split amounts from percentage - for multi-card slider
    func calculateSplitPercentage(
        total: Decimal,
        percentage: Double
    ) async throws -> SplitPercentageResult {
        let payload: [String: Any] = [
            "total": NSDecimalNumber(decimal: total).doubleValue,
            "percentage": percentage
        ]

        let response: SplitPercentageResponse = try await post(endpoint: "split-percentage", payload: payload)

        return SplitPercentageResult(
            amount1: Decimal(response.amount1),
            amount2: Decimal(response.amount2),
            percentage: response.percentage,
            isValid: response.isValid
        )
    }

    // MARK: - Percentage from Amount (Reverse Calc)

    /// Calculate percentage from amount - for updating slider from text input
    func calculatePercentageFromAmount(
        total: Decimal,
        amount: Decimal
    ) async throws -> PercentageFromAmountResult {
        let payload: [String: Any] = [
            "total": NSDecimalNumber(decimal: total).doubleValue,
            "amount": NSDecimalNumber(decimal: amount).doubleValue
        ]

        let response: PercentageFromAmountResponse = try await post(endpoint: "percentage-from-amount", payload: payload)

        return PercentageFromAmountResult(
            percentage: response.percentage,
            amount1: Decimal(response.amount1),
            amount2: Decimal(response.amount2)
        )
    }

    // MARK: - Line Item Calculation

    /// Calculate line item subtotal, tax, and total - ALL logic is server-side
    func calculateLineItem(
        unitPrice: Decimal,
        quantity: Int,
        taxRate: Decimal = 0
    ) async throws -> LineItemResult {
        let payload: [String: Any] = [
            "unitPrice": NSDecimalNumber(decimal: unitPrice).doubleValue,
            "quantity": quantity,
            "taxRate": NSDecimalNumber(decimal: taxRate).doubleValue
        ]

        let response: LineItemResponse = try await post(endpoint: "line-item", payload: payload)

        return LineItemResult(
            subtotal: Decimal(response.subtotal),
            taxAmount: Decimal(response.taxAmount),
            total: Decimal(response.total)
        )
    }

    // MARK: - Discount Calculation

    /// Calculate discount amount - ALL logic is server-side
    func calculateDiscount(
        subtotal: Decimal,
        discountType: DiscountType,
        discountValue: Decimal
    ) async throws -> Decimal {
        let payload: [String: Any] = [
            "subtotal": NSDecimalNumber(decimal: subtotal).doubleValue,
            "discountType": discountType.rawValue,
            "discountValue": NSDecimalNumber(decimal: discountValue).doubleValue
        ]

        let response: DiscountResponse = try await post(endpoint: "discount", payload: payload)

        return Decimal(response.discountAmount)
    }

    // MARK: - Validation

    /// Validate a payment configuration
    func validate(
        total: Decimal,
        paymentMethod: PaymentMethod,
        cashAmount: Decimal? = nil,
        cardAmount: Decimal? = nil,
        card1Amount: Decimal? = nil,
        card2Amount: Decimal? = nil,
        cashTendered: Decimal? = nil
    ) async throws -> ValidationResult {
        var payload: [String: Any] = [
            "total": NSDecimalNumber(decimal: total).doubleValue,
            "paymentMethod": paymentMethod.rawValue
        ]

        if let cash = cashAmount {
            payload["cashAmount"] = NSDecimalNumber(decimal: cash).doubleValue
        }
        if let card = cardAmount {
            payload["cardAmount"] = NSDecimalNumber(decimal: card).doubleValue
        }
        if let c1 = card1Amount {
            payload["card1Amount"] = NSDecimalNumber(decimal: c1).doubleValue
        }
        if let c2 = card2Amount {
            payload["card2Amount"] = NSDecimalNumber(decimal: c2).doubleValue
        }
        if let tendered = cashTendered {
            payload["cashTendered"] = NSDecimalNumber(decimal: tendered).doubleValue
        }

        let response: ValidateResponse = try await post(endpoint: "validate", payload: payload)

        return ValidationResult(
            isValid: response.isValid,
            errors: response.errors,
            change: response.change.map { Decimal($0) },
            calculatedCardAmount: response.calculatedCardAmount.map { Decimal($0) },
            calculatedCard2Amount: response.calculatedCard2Amount.map { Decimal($0) }
        )
    }

    // MARK: - Private

    private func post<T: Decodable>(endpoint: String, payload: [String: Any]) async throws -> T {
        let url = baseURL.appendingPathComponent(endpoint)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.timeoutInterval = 10
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw PaymentCalculatorError.serverError(errorText)
        }

        return try JSONDecoder().decode(T.self, from: data)
    }

    func clearCache() {
        cashSuggestionsCache.removeAll()
    }
}

// MARK: - Types

enum SplitType: String {
    case cashCard = "cash-card"
    case multiCard = "multi-card"
}

enum SplitPreset: String {
    case fiftyFifty = "50-50"
    case sixtyForty = "60-40"
    case seventyThirty = "70-30"
    case eightyTwenty = "80-20"
    case twenty = "$20"
    case fifty = "$50"
    case hundred = "$100"
}

enum EditedField: String {
    case amount1
    case amount2
}

struct SplitResult {
    let isValid: Bool
    let amount1: Decimal
    let amount2: Decimal
    let remaining: Decimal
    let errors: [String]
    let label1: String
    let label2: String
}

struct CashSuggestionsResult {
    let suggestions: [Decimal]
    let exactAmount: Decimal
}

struct ValidationResult {
    let isValid: Bool
    let errors: [String]
    let change: Decimal?
    let calculatedCardAmount: Decimal?
    let calculatedCard2Amount: Decimal?
}

struct LoyaltyResult {
    let maxRedeemablePoints: Int
    let redemptionValue: Decimal
    let newTotal: Decimal
    let isValid: Bool
    let errors: [String]
}

struct SplitPercentageResult {
    let amount1: Decimal
    let amount2: Decimal
    let percentage: Double
    let isValid: Bool
}

struct PercentageFromAmountResult {
    let percentage: Double
    let amount1: Decimal
    let amount2: Decimal
}

struct LineItemResult {
    let subtotal: Decimal
    let taxAmount: Decimal
    let total: Decimal
}

// DiscountType is defined in Deal.swift

// MARK: - API Response Types

private struct SplitResponse: Decodable {
    let isValid: Bool
    let amount1: Double
    let amount2: Double
    let remaining: Double
    let errors: [String]
    let label1: String
    let label2: String
}

private struct CashSuggestionsResponse: Decodable {
    let suggestions: [Double]
    let exactAmount: Double
}

private struct ValidateResponse: Decodable {
    let isValid: Bool
    let errors: [String]
    let change: Double?
    let calculatedCardAmount: Double?
    let calculatedCard2Amount: Double?
}

private struct LoyaltyResponse: Decodable {
    let maxRedeemablePoints: Int
    let redemptionValue: Double
    let newTotal: Double
    let isValid: Bool
    let errors: [String]
}

private struct SplitPercentageResponse: Decodable {
    let amount1: Double
    let amount2: Double
    let percentage: Double
    let isValid: Bool
}

private struct PercentageFromAmountResponse: Decodable {
    let percentage: Double
    let amount1: Double
    let amount2: Double
}

struct LineItemResponse: Decodable {
    let subtotal: Double
    let taxAmount: Double
    let total: Double
}

struct DiscountResponse: Decodable {
    let discountAmount: Double
}

// MARK: - Errors

enum PaymentCalculatorError: LocalizedError {
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .serverError(let message):
            return "Payment calculation error: \(message)"
        }
    }
}
