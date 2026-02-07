//
//  InventoryUnit.swift
//  Whale
//
//  Individual tracked inventory unit with QR code and lineage.
//  Supports bulk (B), distribution (D), and sale (S) tracking.
//

import Foundation

// MARK: - Inventory Unit

struct InventoryUnit: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let storeId: UUID
    let productId: UUID
    let batchId: UUID?
    let batchNumber: String?

    // Unit specification
    let tierId: String
    let tierLabel: String?
    let quantity: Double
    let baseUnit: String

    // Location
    let currentLocationId: UUID
    let binLocation: String?

    // QR tracking
    let qrCode: String
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
        case productName = "product_name"
        case productSKU = "product_sku"
        case productImageURL = "product_image_url"
        case locationName = "location_name"
        case parentQRCode = "parent_qr_code"
        case siblingCount = "sibling_count"
        case scanHistory = "scan_history"
        case canConvertTo = "can_convert_to"
    }

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
