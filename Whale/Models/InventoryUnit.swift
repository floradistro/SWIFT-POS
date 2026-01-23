//
//  InventoryUnit.swift
//  Whale
//
//  Individual tracked inventory unit with QR code and lineage.
//  Supports bulk (B), distribution (D), and sale (S) tracking.
//

import Foundation
import UIKit

// MARK: - Inventory Unit

struct InventoryUnit: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let storeId: UUID
    let productId: UUID
    let batchId: UUID?
    let batchNumber: String?

    // Unit specification
    let tierId: String              // "lb", "qp", "oz", "3.5g"
    let tierLabel: String?          // "Quarter Pound (112g)"
    let quantity: Double            // Amount in base unit
    let baseUnit: String            // "g", "ml", "unit"

    // Location
    let currentLocationId: UUID
    let binLocation: String?

    // QR tracking
    let qrCode: String              // B{uuid}, D{uuid}, S{uuid}
    let qrCodeId: UUID?

    // Lineage
    let parentUnitId: UUID?
    let parentUnitIndex: Int?
    let conversionId: UUID?
    let generation: Int

    // Status
    let status: UnitStatus
    let statusChangedAt: Date?

    // Source
    let sourceType: String?
    let sourceId: UUID?
    let receivedAt: Date?
    let receivedByUserId: UUID?

    // Consumption
    let consumedAt: Date?
    let consumedByUserId: UUID?
    let consumedReason: String?
    let consumptionReferenceId: UUID?

    // Sale tracking
    let orderId: UUID?
    let customerId: UUID?

    let notes: String?
    let createdAt: Date
    let updatedAt: Date

    // MARK: - Joined Data (populated after fetch)

    var productName: String?
    var productSKU: String?
    var productImageURL: URL?
    var locationName: String?
    var parentQRCode: String?
    var siblingCount: Int?
    var scanHistory: [ScanRecord]?
    var canConvertTo: [String]?

    // MARK: - Computed

    var qrPrefix: String {
        String(qrCode.prefix(1))
    }

    var trackingURL: String {
        "https://floradistro.com/qr/\(qrCode)"
    }

    var quantityFormatted: String {
        if quantity >= 453.6 {
            return String(format: "%.1f lb", quantity / 453.6)
        } else if quantity >= 28 {
            return String(format: "%.0fg", quantity)
        } else {
            return String(format: "%.1fg", quantity)
        }
    }

    var tierIcon: String {
        switch qrPrefix {
        case "B": return "cube.box.fill"
        case "D": return "shippingbox"
        case "S": return "bag.fill"
        case "I": return "tag.fill"
        default: return "qrcode"
        }
    }

    // MARK: - Coding Keys

    enum CodingKeys: String, CodingKey {
        case id
        case storeId = "store_id"
        case productId = "product_id"
        case batchId = "batch_id"
        case batchNumber = "batch_number"
        case tierId = "tier_id"
        case tierLabel = "tier_label"
        case quantity
        case baseUnit = "base_unit"
        case currentLocationId = "current_location_id"
        case binLocation = "bin_location"
        case qrCode = "qr_code"
        case qrCodeId = "qr_code_id"
        case parentUnitId = "parent_unit_id"
        case parentUnitIndex = "parent_unit_index"
        case conversionId = "conversion_id"
        case generation
        case status
        case statusChangedAt = "status_changed_at"
        case sourceType = "source_type"
        case sourceId = "source_id"
        case receivedAt = "received_at"
        case receivedByUserId = "received_by_user_id"
        case consumedAt = "consumed_at"
        case consumedByUserId = "consumed_by_user_id"
        case consumedReason = "consumed_reason"
        case consumptionReferenceId = "consumption_reference_id"
        case orderId = "order_id"
        case customerId = "customer_id"
        case notes
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        // Joined data - not in database
        case productName = "product_name"
        case productSKU = "product_sku"
        case productImageURL = "product_image_url"
        case locationName = "location_name"
        case parentQRCode = "parent_qr_code"
        case siblingCount = "sibling_count"
        case scanHistory = "scan_history"
        case canConvertTo = "can_convert_to"
    }

    // Custom decoder to handle optional joined data
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        storeId = try container.decode(UUID.self, forKey: .storeId)
        productId = try container.decode(UUID.self, forKey: .productId)
        batchId = try container.decodeIfPresent(UUID.self, forKey: .batchId)
        batchNumber = try container.decodeIfPresent(String.self, forKey: .batchNumber)
        tierId = try container.decode(String.self, forKey: .tierId)
        tierLabel = try container.decodeIfPresent(String.self, forKey: .tierLabel)
        quantity = try container.decode(Double.self, forKey: .quantity)
        baseUnit = try container.decode(String.self, forKey: .baseUnit)
        currentLocationId = try container.decode(UUID.self, forKey: .currentLocationId)
        binLocation = try container.decodeIfPresent(String.self, forKey: .binLocation)
        qrCode = try container.decode(String.self, forKey: .qrCode)
        qrCodeId = try container.decodeIfPresent(UUID.self, forKey: .qrCodeId)
        parentUnitId = try container.decodeIfPresent(UUID.self, forKey: .parentUnitId)
        parentUnitIndex = try container.decodeIfPresent(Int.self, forKey: .parentUnitIndex)
        conversionId = try container.decodeIfPresent(UUID.self, forKey: .conversionId)
        generation = try container.decode(Int.self, forKey: .generation)
        status = try container.decode(UnitStatus.self, forKey: .status)
        statusChangedAt = try container.decodeIfPresent(Date.self, forKey: .statusChangedAt)
        sourceType = try container.decodeIfPresent(String.self, forKey: .sourceType)
        sourceId = try container.decodeIfPresent(UUID.self, forKey: .sourceId)
        receivedAt = try container.decodeIfPresent(Date.self, forKey: .receivedAt)
        receivedByUserId = try container.decodeIfPresent(UUID.self, forKey: .receivedByUserId)
        consumedAt = try container.decodeIfPresent(Date.self, forKey: .consumedAt)
        consumedByUserId = try container.decodeIfPresent(UUID.self, forKey: .consumedByUserId)
        consumedReason = try container.decodeIfPresent(String.self, forKey: .consumedReason)
        consumptionReferenceId = try container.decodeIfPresent(UUID.self, forKey: .consumptionReferenceId)
        orderId = try container.decodeIfPresent(UUID.self, forKey: .orderId)
        customerId = try container.decodeIfPresent(UUID.self, forKey: .customerId)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)

        // Optional joined data
        productName = try container.decodeIfPresent(String.self, forKey: .productName)
        productSKU = try container.decodeIfPresent(String.self, forKey: .productSKU)
        if let urlString = try container.decodeIfPresent(String.self, forKey: .productImageURL) {
            productImageURL = URL(string: urlString)
        }
        locationName = try container.decodeIfPresent(String.self, forKey: .locationName)
        parentQRCode = try container.decodeIfPresent(String.self, forKey: .parentQRCode)
        siblingCount = try container.decodeIfPresent(Int.self, forKey: .siblingCount)
        scanHistory = try container.decodeIfPresent([ScanRecord].self, forKey: .scanHistory)
        canConvertTo = try container.decodeIfPresent([String].self, forKey: .canConvertTo)
    }
}

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
    let id: String              // "lb", "qp", "oz"
    let label: String           // "Quarter Pound (112g)"
    let quantity: Double        // 112
    let baseUnit: String        // "g"
    let tierLevel: Int          // 1, 2, 3, 4
    let locationTypes: [String] // ["warehouse", "distribution"]
    let qrPrefix: String        // "B", "D", "S"
    let canConvertTo: [String]  // ["oz", "retail"]
    let labelTemplate: String   // "bulk", "distribution"
    let icon: String?           // SF Symbol name

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

// MARK: - API Response Types

struct RegisterUnitResponse: Codable {
    let success: Bool
    let unit: InventoryUnit?
    let qrCode: String?
    let qrRecord: QRCodeRecord?
    let trackingUrl: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case success
        case unit
        case qrCode = "qr_code"
        case qrRecord = "qr_record"
        case trackingUrl = "tracking_url"
        case error
    }
}

struct QRCodeRecord: Codable {
    let id: UUID
    let code: String
    let name: String?
    let type: String

    init(id: UUID, code: String, name: String?, type: String) {
        self.id = id
        self.code = code
        self.name = name
        self.type = type
    }
}

struct ConversionResult: Codable {
    let success: Bool
    let conversion: ConversionRecord?
    let sourceUnit: SourceUnitInfo?
    let childUnits: [InventoryUnit]?
    let summary: ConversionSummary?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case success
        case conversion
        case sourceUnit = "source_unit"
        case childUnits = "child_units"
        case summary
        case error
    }
}

struct ConversionRecord: Codable {
    let id: UUID
}

struct SourceUnitInfo: Codable {
    let id: UUID
    let qrCode: String
    let originalQuantity: Double
    let quantitySold: Double?
    let consumed: Double?
    let remainingQuantity: Double
    let newStatus: String

    enum CodingKeys: String, CodingKey {
        case id
        case qrCode = "qr_code"
        case originalQuantity = "original_quantity"
        case quantitySold = "quantity_sold"
        case consumed
        case remainingQuantity = "remaining_quantity"
        case newStatus = "new_status"
    }
}

struct ConversionSummary: Codable {
    let portionsCreated: Int
    let portionSize: Double
    let totalConsumed: Double
    let variance: Double

    enum CodingKeys: String, CodingKey {
        case portionsCreated = "portions_created"
        case portionSize = "portion_size"
        case totalConsumed = "total_consumed"
        case variance
    }
}

struct LookupResult: Codable {
    let success: Bool
    let found: Bool
    let qrCode: QRCodeRecord?
    let unit: InventoryUnit?
    let product: ProductInfo?
    let location: LocationInfo?
    let lineage: [InventoryUnit]?
    let children: [InventoryUnit]?
    let scanHistory: [ScanRecord]?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case success
        case found
        case qrCode = "qr_code"
        case unit
        case product
        case location
        case lineage
        case children
        case scanHistory = "scan_history"
        case error
    }

    init(success: Bool, found: Bool, qrCode: QRCodeRecord?, unit: InventoryUnit?, product: ProductInfo?, location: LocationInfo?, lineage: [InventoryUnit]?, children: [InventoryUnit]?, scanHistory: [ScanRecord]?, error: String?) {
        self.success = success
        self.found = found
        self.qrCode = qrCode
        self.unit = unit
        self.product = product
        self.location = location
        self.lineage = lineage
        self.children = children
        self.scanHistory = scanHistory
        self.error = error
    }
}

struct ProductInfo: Codable {
    let id: UUID
    let name: String
    let sku: String?
    let featuredImage: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case sku
        case featuredImage = "featured_image"
    }
}

struct LocationInfo: Codable {
    let id: UUID
    let name: String
    let type: String?
}

struct ScanResult: Codable {
    let success: Bool
    let scan: ScanRecord?
    let unit: InventoryUnit?
    let found: Bool
    let error: String?

    init(success: Bool, scan: ScanRecord?, unit: InventoryUnit?, found: Bool, error: String?) {
        self.success = success
        self.scan = scan
        self.unit = unit
        self.found = found
        self.error = error
    }
}

struct SaleFromPortionResult: Codable {
    let success: Bool
    let saleUnit: InventoryUnit?
    let saleQRCode: String?
    let sourceUnit: SourceUnitInfo?
    let trackingUrl: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case success
        case saleUnit = "sale_unit"
        case saleQRCode = "sale_qr_code"
        case sourceUnit = "source_unit"
        case trackingUrl = "tracking_url"
        case error
    }
}

// MARK: - Inventory Label Data

/// Data for printing inventory unit labels
struct InventoryLabelData {
    let productName: String
    let qrCode: String
    let trackingURL: String
    let tierLabel: String
    let quantity: String
    let batchNumber: String?
    let storeLogo: UIImage?
}
