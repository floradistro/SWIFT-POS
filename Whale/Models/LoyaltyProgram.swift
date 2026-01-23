//
//  LoyaltyProgram.swift
//  Whale
//
//  Loyalty program model. Matches Supabase loyalty_programs table.
//

import Foundation

struct LoyaltyProgram: Codable, Identifiable, Sendable {
    let id: UUID
    let storeId: UUID
    let name: String
    let description: String?
    let pointsPerDollar: Decimal
    let pointValue: Decimal  // Dollar value per point (e.g., 0.05 = 5 cents per point)
    let minRedemptionPoints: Int
    let pointsExpiryDays: Int?
    let allowPointsOnDiscountedItems: Bool
    let pointsOnTax: Bool
    let isActive: Bool
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case storeId = "store_id"
        case name
        case description
        case pointsPerDollar = "points_per_dollar"
        case pointValue = "point_value"
        case minRedemptionPoints = "min_redemption_points"
        case pointsExpiryDays = "points_expiry_days"
        case allowPointsOnDiscountedItems = "allow_points_on_discounted_items"
        case pointsOnTax = "points_on_tax"
        case isActive = "is_active"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /// Calculate the dollar discount for a given number of points
    func discountAmount(for points: Int) -> Decimal {
        Decimal(points) * pointValue
    }

    /// Calculate max points that can be redeemed for a given order total
    /// Never allow redeeming more than the order total
    func maxRedeemablePoints(forTotal total: Decimal, availablePoints: Int) -> Int {
        // Max points based on order total: total / pointValue
        let maxByTotal = Int(truncating: (total / pointValue) as NSDecimalNumber)
        // Never exceed available points or order total
        return min(availablePoints, maxByTotal)
    }

    /// Default loyalty program (fallback)
    static let `default` = LoyaltyProgram(
        id: UUID(),
        storeId: UUID(),
        name: "Rewards",
        description: nil,
        pointsPerDollar: 1,
        pointValue: Decimal(string: "0.05")!, // $0.05 per point default
        minRedemptionPoints: 100,
        pointsExpiryDays: nil,
        allowPointsOnDiscountedItems: true,
        pointsOnTax: false,
        isActive: true,
        createdAt: Date(),
        updatedAt: Date()
    )
}
