//
//  Deal.swift
//  Whale
//
//  Discount/promotion campaigns that can be applied at checkout.
//  Supports percentage, fixed amount, and BOGO discount types.
//

import Foundation

// MARK: - Discount Types

enum DiscountType: String, Codable, CaseIterable, Sendable {
    case percentage
    case fixed
    case bogo

    var displayName: String {
        switch self {
        case .percentage: return "Percentage"
        case .fixed: return "Fixed Amount"
        case .bogo: return "Buy One Get One"
        }
    }
}

enum DealApplyTo: String, Codable, CaseIterable, Sendable {
    case all
    case categories
    case products
}

enum DealLocationScope: String, Codable, CaseIterable, Sendable {
    case all
    case specific
}

enum DealScheduleType: String, Codable, CaseIterable, Sendable {
    case always
    case dateRange = "date_range"
    case recurring
}

enum DealApplicationMethod: String, Codable, CaseIterable, Sendable {
    case auto
    case manual
    case code
}

enum DealSalesChannel: String, Codable, CaseIterable, Sendable {
    case both
    case inStore = "in_store"
    case online
}

// MARK: - Recurring Pattern

struct RecurringPattern: Codable, Sendable, Equatable {
    let days: [Int]?       // 0-6 for Sunday-Saturday
    let startTime: String? // "HH:MM" format
    let endTime: String?   // "HH:MM" format

    enum CodingKeys: String, CodingKey {
        case days
        case startTime = "start_time"
        case endTime = "end_time"
    }
}

// MARK: - Deal Model

struct Deal: Identifiable, Codable, Sendable, Equatable, Hashable {
    let id: UUID
    let storeId: UUID
    let name: String

    // Discount configuration
    let discountType: DiscountType
    let discountValue: Decimal  // 20 for 20%, 5 for $5, etc.

    // Targeting
    let applyTo: DealApplyTo
    let applyToIds: [String]

    // Location scope
    let locationScope: DealLocationScope
    let locationIds: [String]

    // Scheduling
    let scheduleType: DealScheduleType
    let startDate: Date?
    let endDate: Date?
    let recurringPattern: RecurringPattern?

    // Application method
    let applicationMethod: DealApplicationMethod
    let couponCode: String?
    let salesChannel: DealSalesChannel

    // Usage limits
    let maxUsesPerCustomer: Int?
    let maxTotalUses: Int?
    let currentUses: Int

    // Status
    let isActive: Bool
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case storeId = "store_id"
        case name
        case discountType = "discount_type"
        case discountValue = "discount_value"
        case applyTo = "apply_to"
        case applyToIds = "apply_to_ids"
        case locationScope = "location_scope"
        case locationIds = "location_ids"
        case scheduleType = "schedule_type"
        case startDate = "start_date"
        case endDate = "end_date"
        case recurringPattern = "recurring_pattern"
        case applicationMethod = "application_method"
        case couponCode = "coupon_code"
        case salesChannel = "sales_channel"
        case maxUsesPerCustomer = "max_uses_per_customer"
        case maxTotalUses = "max_total_uses"
        case currentUses = "current_uses"
        case isActive = "is_active"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    // MARK: - Computed Properties

    /// Display string for the discount value
    var discountDisplayValue: String {
        switch discountType {
        case .percentage:
            return "\(NSDecimalNumber(decimal: discountValue).intValue)% off"
        case .fixed:
            return CurrencyFormatter.format(discountValue) + " off"
        case .bogo:
            return "BOGO"
        }
    }

    /// Short badge text for pills
    var badgeText: String {
        switch discountType {
        case .percentage:
            return "\(NSDecimalNumber(decimal: discountValue).intValue)%"
        case .fixed:
            return CurrencyFormatter.format(discountValue)
        case .bogo:
            return "BOGO"
        }
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Deal, rhs: Deal) -> Bool {
        lhs.id == rhs.id
    }
}
