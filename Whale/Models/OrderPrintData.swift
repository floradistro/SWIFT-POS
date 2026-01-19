//
//  OrderPrintData.swift
//  Whale
//
//  Models for optimized order fetching for label printing.
//  Uses single RPC call to fetch order + full product details.
//

import Foundation

// MARK: - Order Print Data

/// Complete order data optimized for label printing
/// Fetched via `get_order_for_printing` RPC in a single query
struct OrderPrintData: Codable, Sendable {
    let orderId: UUID
    let orderNumber: String
    let storeId: UUID
    let locationId: UUID?  // Optional - orders may not have location_id set
    let pickupLocationId: UUID?
    let pickupLocation: PickupLocation?
    let createdAt: Date
    let items: [OrderPrintItem]

    /// Pickup location summary
    struct PickupLocation: Codable, Sendable {
        let id: UUID
        let name: String
    }

    enum CodingKeys: String, CodingKey {
        case orderId = "order_id"
        case orderNumber = "order_number"
        case storeId = "store_id"
        case locationId = "location_id"
        case pickupLocationId = "pickup_location_id"
        case pickupLocation = "pickup_location"
        case createdAt = "created_at"
        case items
    }
}

// MARK: - Order Print Item

/// Order item with embedded full product details
struct OrderPrintItem: Codable, Sendable, Identifiable {
    let id: UUID
    let productId: UUID
    let quantity: Int
    let tierLabel: String?
    let variantName: String?
    let product: ProductPrintData

    enum CodingKeys: String, CodingKey {
        case id, quantity, product
        case productId = "product_id"
        case tierLabel = "tier_label"
        case variantName = "variant_name"
    }
}

// MARK: - Product Print Data

/// Complete product data for printing labels
/// Includes all fields needed for QR codes, images, and label rendering
struct ProductPrintData: Codable, Sendable, Identifiable {
    let id: UUID
    let name: String
    let description: String?
    let sku: String?
    let featuredImage: String?
    let customFields: [String: AnyCodable]?
    let pricingData: [String: AnyCodable]?
    let storeId: UUID
    let primaryCategoryId: UUID?
    let status: String
    let coa: ProductCOA?

    enum CodingKeys: String, CodingKey {
        case id, name, description, sku, status, coa
        case featuredImage = "featured_image"
        case customFields = "custom_fields"
        case pricingData = "pricing_data"
        case storeId = "store_id"
        case primaryCategoryId = "primary_category_id"
    }

    // MARK: - Computed Properties

    /// Product image URL
    var iconUrl: URL? {
        guard let featuredImage = featuredImage, !featuredImage.isEmpty else {
            return nil
        }

        // If already a full URL, use it
        if featuredImage.hasPrefix("http://") || featuredImage.hasPrefix("https://") {
            return URL(string: featuredImage)
        }

        // Construct Supabase storage URL
        let baseURL = "https://uaednwpxursknmwdeejn.supabase.co/storage/v1/object/public"
        return URL(string: "\(baseURL)/\(featuredImage)")
    }

    /// Strain type from custom fields
    var strainType: String? {
        customFields?["strain_type"]?.value as? String
    }

    /// THCA percentage from custom fields
    var thcaPercentage: Double? {
        if let value = customFields?["thca_percentage"]?.value {
            if let double = value as? Double {
                return double
            }
            if let string = value as? String, let double = Double(string) {
                return double
            }
        }
        return nil
    }

    /// THC percentage from custom fields
    var thcPercentage: Double? {
        if let value = customFields?["thc_percentage"]?.value {
            if let double = value as? Double {
                return double
            }
            if let string = value as? String, let double = Double(string) {
                return double
            }
        }
        return nil
    }

    /// Brand name from custom fields
    var brandName: String? {
        customFields?["brand"]?.value as? String
    }

    // MARK: - Conversion

    /// Convert to full Product model
    func toProduct() -> Product {
        var product = Product(
            id: id,
            name: name,
            description: description,
            sku: sku,
            featuredImage: featuredImage,
            customFields: customFields,
            pricingData: pricingData,
            storeId: storeId,
            primaryCategoryId: primaryCategoryId
        )
        // Set coa property after initialization (Product init doesn't accept it as parameter)
        product.coa = coa
        return product
    }
}
