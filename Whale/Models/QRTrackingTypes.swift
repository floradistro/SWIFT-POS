//
//  QRTrackingTypes.swift
//  Whale
//
//  QR code tracking types: code types, print sources, sale context,
//  registration requests, and responses.
//

import Foundation

// MARK: - QR Code Type

enum QRCodeType: String, Sendable {
    case product = "product"
    case sale = "sale"       // Sale-level tracking (unique per unit sold)
    case order = "order"
    case location = "location"
    case campaign = "campaign"
    case custom = "custom"
}

// MARK: - Print Source

/// Print source for analytics
enum PrintSource: String, Sendable {
    case posCheckout = "pos_checkout"      // Auto-print at POS checkout
    case fulfillment = "fulfillment"       // Manual print during order fulfillment
    case reprint = "reprint"               // Reprint of existing label
}

// MARK: - Sale Context

/// Sale context for per-unit QR tracking
struct SaleContext: Sendable {
    let orderId: UUID
    let customerId: UUID?
    let staffId: UUID?
    let locationId: UUID?
    let locationName: String?
    let soldAt: Date
    let unitPrice: Decimal?

    // Analytics fields
    let orderType: String?      // walk_in, pickup, shipping, delivery, direct
    let printSource: PrintSource?
}

// MARK: - QR Code Registration

/// QR registration request payload
struct QRCodeRegistration: Codable, Sendable {
    let storeId: String
    let code: String
    let name: String
    let type: String
    let destinationUrl: String
    let landingPageTitle: String?
    let landingPageDescription: String?
    let landingPageImageUrl: String?
    let landingPageCtaText: String?
    let landingPageCtaUrl: String?
    let productId: String?
    let orderId: String?
    let locationId: String?
    let campaignName: String?
    let logoUrl: String?
    let brandColor: String?
    let tags: [String]?

    // Sale-level tracking fields
    let customerId: String?
    let staffId: String?
    let soldAt: String?
    let unitPrice: String?
    let quantityIndex: Int?
    let locationName: String?

    // Analytics fields
    let orderType: String?       // walk_in, pickup, shipping, delivery, direct
    let printSource: String?     // pos_checkout, fulfillment, reprint
    let tierLabel: String?       // "1/8 oz", "Quarter Pound", etc.

    enum CodingKeys: String, CodingKey {
        case storeId = "store_id"
        case code
        case name
        case type
        case destinationUrl = "destination_url"
        case landingPageTitle = "landing_page_title"
        case landingPageDescription = "landing_page_description"
        case landingPageImageUrl = "landing_page_image_url"
        case landingPageCtaText = "landing_page_cta_text"
        case landingPageCtaUrl = "landing_page_cta_url"
        case productId = "product_id"
        case orderId = "order_id"
        case locationId = "location_id"
        case campaignName = "campaign_name"
        case logoUrl = "logo_url"
        case brandColor = "brand_color"
        case tags
        case customerId = "customer_id"
        case staffId = "staff_id"
        case soldAt = "sold_at"
        case unitPrice = "unit_price"
        case quantityIndex = "quantity_index"
        case locationName = "location_name"
        case orderType = "order_type"
        case printSource = "print_source"
        case tierLabel = "tier_label"
    }
}

// MARK: - QR Registration Response

struct QRRegistrationResponse: Codable, Sendable {
    let success: Bool
    let qrCode: QRCodeData?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case success
        case qrCode = "qr_code"
        case error
    }
}

// MARK: - QR Code Data

struct QRCodeData: Codable, Sendable {
    let id: String
    let code: String
    let name: String
    let type: String
    let destinationUrl: String?
    let trackingUrl: String?

    enum CodingKeys: String, CodingKey {
        case id
        case code
        case name
        case type
        case destinationUrl = "destination_url"
        case trackingUrl = "tracking_url"
    }
}
