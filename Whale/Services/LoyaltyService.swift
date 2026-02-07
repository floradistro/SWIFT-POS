//
//  LoyaltyService.swift
//  Whale
//
//  Service for loyalty points operations.
//  Uses bulletproof v2 RPC functions with:
//  - Atomic operations (FOR UPDATE NOWAIT locking)
//  - Idempotency (safe to retry)
//  - Anomaly detection
//  - Automatic balance sync
//

import Foundation
import Supabase
import os.log

// MARK: - Loyalty Response Types

struct LoyaltyAwardResult: Codable, Sendable {
    let success: Bool
    let idempotent: Bool?
    let message: String?
    let error: String?
    let retryable: Bool?
    let transactionId: UUID?
    let pointsAwarded: Int?
    let basePoints: Int?
    let bonusPoints: Int?
    let tierMultiplier: Decimal?
    let balanceBefore: Int?
    let balanceAfter: Int?

    enum CodingKeys: String, CodingKey {
        case success
        case idempotent
        case message
        case error
        case retryable
        case transactionId = "transaction_id"
        case pointsAwarded = "points_awarded"
        case basePoints = "base_points"
        case bonusPoints = "bonus_points"
        case tierMultiplier = "tier_multiplier"
        case balanceBefore = "balance_before"
        case balanceAfter = "balance_after"
    }
}

struct LoyaltyDeductResult: Codable, Sendable {
    let success: Bool
    let idempotent: Bool?
    let message: String?
    let error: String?
    let retryable: Bool?
    let transactionId: UUID?
    let pointsDeducted: Int?
    let balanceBefore: Int?
    let balanceAfter: Int?
    let available: Int?
    let requested: Int?

    enum CodingKeys: String, CodingKey {
        case success
        case idempotent
        case message
        case error
        case retryable
        case transactionId = "transaction_id"
        case pointsDeducted = "points_deducted"
        case balanceBefore = "balance_before"
        case balanceAfter = "balance_after"
        case available
        case requested
    }
}

struct LoyaltySetResult: Codable, Sendable {
    let success: Bool
    let message: String?
    let error: String?
    let balanceBefore: Int?
    let balanceAfter: Int?
    let adjustment: Int?
    let transactionType: String?

    enum CodingKeys: String, CodingKey {
        case success
        case message
        case error
        case balanceBefore = "balance_before"
        case balanceAfter = "balance_after"
        case adjustment
        case transactionType = "transaction_type"
    }
}

struct LoyaltyTransaction: Codable, Identifiable, Sendable {
    let id: UUID
    let customerId: UUID
    let transactionType: String
    let points: Int
    let balanceBefore: Int?
    let balanceAfter: Int?
    let referenceType: String?
    let referenceId: String?
    let description: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case customerId = "customer_id"
        case transactionType = "transaction_type"
        case points
        case balanceBefore = "balance_before"
        case balanceAfter = "balance_after"
        case referenceType = "reference_type"
        case referenceId = "reference_id"
        case description
        case createdAt = "created_at"
    }
}

extension LoyaltyTransaction {
    var formattedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: createdAt, relativeTo: Date())
    }
}

// MARK: - Loyalty Service

actor LoyaltyService {
    static let shared = LoyaltyService()

    private init() {}

    // MARK: - Award Points

    /// Award loyalty points for a purchase.
    /// Uses atomic v2 function with row locking and anomaly detection.
    /// Safe to retry - idempotent on order_id.
    func awardPoints(
        customerId: UUID,
        orderId: UUID,
        subtotal: Decimal,
        storeId: UUID
    ) async throws -> LoyaltyAwardResult {
        let result: LoyaltyAwardResult = try await supabase
            .rpc("award_loyalty_points_v2", params: [
                "p_customer_id": customerId.uuidString,
                "p_order_id": orderId.uuidString,
                "p_subtotal": "\(NSDecimalNumber(decimal: subtotal).doubleValue)",
                "p_store_id": storeId.uuidString
            ])
            .execute()
            .value

        return result
    }

    // MARK: - Deduct Points

    /// Deduct loyalty points for a redemption.
    /// Uses atomic v2 function with row locking.
    /// Safe to retry - idempotent on order_id.
    func deductPoints(
        customerId: UUID,
        points: Int,
        orderId: UUID? = nil,
        reason: String = "redemption"
    ) async throws -> LoyaltyDeductResult {
        var params: [String: String] = [
            "p_customer_id": customerId.uuidString,
            "p_points_to_deduct": "\(points)",
            "p_reason": reason
        ]

        if let orderId = orderId {
            params["p_order_id"] = orderId.uuidString
        }

        let result: LoyaltyDeductResult = try await supabase
            .rpc("deduct_loyalty_points_v2", params: params)
            .execute()
            .value

        return result
    }

    // MARK: - Get Balance

    /// Get current loyalty points balance for a customer.
    func getBalance(customerId: UUID) async throws -> Int {
        struct BalanceResult: Decodable {
            let loyaltyPoints: Int?

            enum CodingKeys: String, CodingKey {
                case loyaltyPoints = "loyalty_points"
            }
        }

        let result: [BalanceResult] = try await supabase
            .from("store_customer_profiles")
            .select("loyalty_points")
            .eq("relationship_id", value: customerId.uuidString)
            .execute()
            .value

        return result.first?.loyaltyPoints ?? 0
    }

    // MARK: - Get Transaction History

    /// Get loyalty transaction history for a customer.
    func getTransactionHistory(
        customerId: UUID,
        limit: Int = 50
    ) async throws -> [LoyaltyTransaction] {
        let transactions: [LoyaltyTransaction] = try await supabase
            .from("loyalty_transactions")
            .select()
            .eq("customer_id", value: customerId.uuidString)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value

        return transactions
    }

    // MARK: - Set Points (Admin Override)

    /// Directly set loyalty points balance for a customer.
    /// Uses RPC function to bypass RLS and properly update store_customer_profiles.
    /// Used for manual adjustments by staff.
    func setPoints(customerId: UUID, points: Int, reason: String = "manual_adjustment") async throws -> LoyaltySetResult {
        Log.network.debug("LoyaltyService.setPoints: customerId=\(customerId), points=\(points)")

        let result: LoyaltySetResult = try await supabase
            .rpc("set_loyalty_points", params: [
                "p_relationship_id": customerId.uuidString,
                "p_loyalty_points": "\(points)",
                "p_reason": reason
            ])
            .execute()
            .value

        if result.success {
            Log.network.info("LoyaltyService.setPoints: Success - \(result.balanceBefore ?? 0) -> \(result.balanceAfter ?? 0)")
        } else {
            Log.network.error("LoyaltyService.setPoints: Failed - \(result.error ?? "Unknown error")")
            throw LoyaltyError.unknown(result.error ?? "Failed to update points")
        }

        return result
    }

    // MARK: - Calculate Redemption Value

    /// Calculate the dollar value for a given number of points.
    /// Default: 20 points = $1 (5 cents per point)
    func calculateRedemptionValue(points: Int, pointValue: Decimal = 0.05) -> Decimal {
        Decimal(points) * pointValue
    }

    /// Calculate max redeemable points for a given order total.
    /// Never allow redeeming more than the order total.
    func maxRedeemablePoints(
        forTotal total: Decimal,
        availablePoints: Int,
        pointValue: Decimal = 0.05
    ) -> Int {
        guard pointValue > 0 else { return 0 }
        let maxByTotal = Int(truncating: (total / pointValue) as NSDecimalNumber)
        return min(availablePoints, maxByTotal)
    }
}

// MARK: - Loyalty Error

enum LoyaltyError: LocalizedError {
    case insufficientBalance(available: Int, requested: Int)
    case concurrentModification
    case networkError(String)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .insufficientBalance(let available, let requested):
            return "Insufficient points. Available: \(available), Requested: \(requested)"
        case .concurrentModification:
            return "Another transaction is in progress. Please try again."
        case .networkError(let message):
            return "Network error: \(message)"
        case .unknown(let message):
            return message
        }
    }

    var isRetryable: Bool {
        switch self {
        case .concurrentModification:
            return true
        default:
            return false
        }
    }
}
