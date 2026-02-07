//
//  PrintTypes.swift
//  Whale
//
//  Print-related DTOs: printable items, config, payload, results, and errors.
//

import Foundation

// MARK: - Printable Item

/// Single printable item with all data unified (no parallel arrays)
struct PrintableItem: Codable, Sendable {
    let product: PrintableProduct
    let saleCode: String
    let qrUrl: String
    let tierLabel: String?
    let quantityIndex: Int

    enum CodingKeys: String, CodingKey {
        case product
        case saleCode = "sale_code"
        case qrUrl = "qr_url"
        case tierLabel = "tier_label"
        case quantityIndex = "quantity_index"
    }
}

// MARK: - Printable Product

/// Product data for printing (subset of full Product)
struct PrintableProduct: Codable, Sendable {
    let id: String
    let name: String
    let description: String?
    let strainType: String?
    let thcaPercentage: Double?
    let d9ThcPercentage: Double?
    let featuredImage: String?
    let coaUrl: String?
    let testDate: String?
    let batchNumber: String?
    let primaryCategory: PrintableCategory?

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case strainType = "strain_type"
        case thcaPercentage = "thca_percentage"
        case d9ThcPercentage = "d9_thc_percentage"
        case featuredImage = "featured_image"
        case coaUrl = "coa_url"
        case testDate = "test_date"
        case batchNumber = "batch_number"
        case primaryCategory = "primary_category"
    }
}

// MARK: - Printable Category

struct PrintableCategory: Codable, Sendable {
    let name: String
}

// MARK: - Print Config

/// Configuration for label rendering
struct PrintConfig: Codable, Sendable {
    let storeId: String
    let storeLogoUrl: String?
    let locationName: String?
    let brandColor: String
    let distributorLicense: String?

    enum CodingKeys: String, CodingKey {
        case storeId = "store_id"
        case storeLogoUrl = "store_logo_url"
        case locationName = "location_name"
        case brandColor = "brand_color"
        case distributorLicense = "distributor_license"
    }
}

// MARK: - Print Payload

/// Complete print payload from backend (all QR codes pre-registered)
struct PrintPayload: Codable, Sendable {
    let items: [PrintableItem]
    let config: PrintConfig
    let sealedDate: String
    let saleContext: PrintSaleContext

    enum CodingKeys: String, CodingKey {
        case items, config
        case sealedDate = "sealed_date"
        case saleContext = "sale_context"
    }
}

// MARK: - Print Sale Context

/// Sale context for QR tracking
struct PrintSaleContext: Codable, Sendable {
    let orderId: String
    let customerId: String?
    let staffId: String?
    let locationId: String?
    let locationName: String?
    let soldAt: String?
    let orderType: String?
    let printSource: String?

    enum CodingKeys: String, CodingKey {
        case orderId = "order_id"
        case customerId = "customer_id"
        case staffId = "staff_id"
        case locationId = "location_id"
        case locationName = "location_name"
        case soldAt = "sold_at"
        case orderType = "order_type"
        case printSource = "print_source"
    }
}

// MARK: - Prepare Labels Response

/// Backend response for prepare-print-labels
struct PrepareLabelsResponse: Codable, Sendable {
    let success: Bool
    let payload: PrintPayload?
    let itemsCount: Int?
    let qrCodesRegistered: Int?
    let skippedProducts: [String]?  // Product IDs that were skipped (deleted/not found)
    let error: String?

    enum CodingKeys: String, CodingKey {
        case success, payload, error
        case itemsCount = "items_count"
        case qrCodesRegistered = "qr_codes_registered"
        case skippedProducts = "skipped_products"
    }
}

// MARK: - Print Result

/// Explicit result type for print operations
enum PrintResult: Sendable {
    case success(itemsPrinted: Int, qrCodesRegistered: Int)
    case partialSuccess(printed: Int, failed: [String])
    case failure(PrintError)

    var isSuccess: Bool {
        switch self {
        case .success: return true
        case .partialSuccess: return true
        case .failure: return false
        }
    }
}

// MARK: - Print Error

/// Print error types with context
enum PrintError: Error, Sendable {
    case notConfigured(String)
    case backendError(String)
    case networkError(String)
    case printerUnavailable(String)
    case renderError(String)
    case noItems
    case cancelled

    var localizedDescription: String {
        switch self {
        case .notConfigured(let msg): return "Print not configured: \(msg)"
        case .backendError(let msg): return "Backend error: \(msg)"
        case .networkError(let msg): return "Network error: \(msg)"
        case .printerUnavailable(let msg): return "Printer unavailable: \(msg)"
        case .renderError(let msg): return "Render error: \(msg)"
        case .noItems: return "No items to print"
        case .cancelled: return "Print cancelled"
        }
    }
}

// MARK: - Print Job Status

/// Status updates for print operations
enum PrintJobStatus: Sendable {
    case preparing
    case registeringQRCodes(count: Int)
    case qrCodesRegistered(count: Int)
    case rendering(pages: Int)
    case sending
    case completed(PrintResult)
    case failed(PrintError)
}

// MARK: - Print Cart Item

/// Cart item format for backend request
struct PrintCartItem: Codable, Sendable {
    let productId: String
    let quantity: Int
    let tierLabel: String?
    let unitPrice: Decimal?

    enum CodingKeys: String, CodingKey {
        case productId = "product_id"
        case quantity
        case tierLabel = "tier_label"
        case unitPrice = "unit_price"
    }
}
