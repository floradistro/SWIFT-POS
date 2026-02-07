//
//  InventoryUnitResponses.swift
//  Whale
//
//  API response types for inventory unit operations:
//  registration, conversion, lookup, and scanning.
//

import Foundation
import UIKit

// MARK: - Register Unit Response

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

// MARK: - QR Code Record

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

// MARK: - Conversion Result

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

// MARK: - Lookup Result

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

// MARK: - Supporting Info Types

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

// MARK: - Scan Result

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

// MARK: - Sale From Portion Result

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

struct InventoryLabelData {
    let productName: String
    let qrCode: String
    let trackingURL: String
    let tierLabel: String
    let quantity: String
    let batchNumber: String?
    let storeLogo: UIImage?
}
