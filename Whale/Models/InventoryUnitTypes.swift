//
//  InventoryUnitTypes.swift
//  Whale
//
//  Supporting types for InventoryUnit: status, scan records,
//  conversion tiers, and tier templates.
//

import Foundation

// MARK: - Unit Status

enum UnitStatus: String, Codable, Sendable {
    case available
    case reserved
    case inTransit = "in_transit"
    case consumed
    case sold
    case damaged
    case expired
    case sample
    case adjustment

    var displayName: String {
        switch self {
        case .available: return "Available"
        case .reserved: return "Reserved"
        case .inTransit: return "In Transit"
        case .consumed: return "Consumed"
        case .sold: return "Sold"
        case .damaged: return "Damaged"
        case .expired: return "Expired"
        case .sample: return "Sample"
        case .adjustment: return "Adjustment"
        }
    }

    var color: String {
        switch self {
        case .available: return "green"
        case .reserved: return "orange"
        case .inTransit: return "blue"
        case .consumed, .sold: return "gray"
        case .damaged, .expired: return "red"
        case .sample, .adjustment: return "purple"
        }
    }
}

// MARK: - Scan Record

struct ScanRecord: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let scannedAt: Date
    let operation: String
    let operationStatus: String
    let locationName: String?
    let scannedByName: String?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case id
        case scannedAt = "scanned_at"
        case operation
        case operationStatus = "operation_status"
        case locationName = "location_name"
        case scannedByName = "scanned_by_name"
        case notes
    }
}

// MARK: - Conversion Tier

struct ConversionTier: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let label: String
    let quantity: Double
    let baseUnit: String
    let tierLevel: Int
    let locationTypes: [String]
    let qrPrefix: String
    let canConvertTo: [String]
    let labelTemplate: String
    let icon: String?

    var quantityFormatted: String {
        if quantity >= 453.6 {
            return String(format: "%.1f lb", quantity / 453.6)
        } else if quantity >= 28 {
            return String(format: "%.0fg", quantity)
        } else {
            return String(format: "%.1fg", quantity)
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case label
        case quantity
        case baseUnit = "base_unit"
        case tierLevel = "tier_level"
        case locationTypes = "location_types"
        case qrPrefix = "qr_prefix"
        case canConvertTo = "can_convert_to"
        case labelTemplate = "label_template"
        case icon
    }
}

// MARK: - Unit Conversion Tier Template

struct UnitConversionTierTemplate: Identifiable, Codable, Sendable {
    let id: UUID
    let categoryId: UUID
    let storeId: UUID
    let name: String
    let slug: String
    let description: String?
    let conversionTiers: [ConversionTier]
    let baseUnit: String
    let trackIndividualUnits: Bool
    let requireScanOnReceive: Bool
    let requireScanOnTransfer: Bool
    let allowPartialConversion: Bool
    let isActive: Bool
    let displayOrder: Int
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case categoryId = "category_id"
        case storeId = "store_id"
        case name
        case slug
        case description
        case conversionTiers = "conversion_tiers"
        case baseUnit = "base_unit"
        case trackIndividualUnits = "track_individual_units"
        case requireScanOnReceive = "require_scan_on_receive"
        case requireScanOnTransfer = "require_scan_on_transfer"
        case allowPartialConversion = "allow_partial_conversion"
        case isActive = "is_active"
        case displayOrder = "display_order"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
