//
//  ProductServiceDTOs.swift
//  Whale
//
//  Product service DTOs: variant inventory, view row decoding,
//  and product update errors.
//

import Foundation

// MARK: - Product Update Errors

enum ProductUpdateError: LocalizedError {
    case updateFailed(String)

    var errorDescription: String? {
        switch self {
        case .updateFailed(let message):
            return "Update failed: \(message)"
        }
    }
}

// MARK: - Variant Inventory Data With Product

/// Extended variant inventory record including product ID (for batch fetch)
struct VariantInventoryDataWithProduct: Codable {
    let id: UUID
    let productId: UUID
    let variantTemplateId: UUID
    let quantity: Double
    let heldQuantity: Double?
    let categoryVariantTemplates: CategoryVariantTemplateData?

    enum CodingKeys: String, CodingKey {
        case id
        case productId = "product_id"
        case variantTemplateId = "variant_template_id"
        case quantity
        case heldQuantity = "held_quantity"
        case categoryVariantTemplates = "category_variant_templates"
    }
}

// MARK: - Variant Inventory Data

/// Variant inventory record from database
struct VariantInventoryData: Codable {
    let id: UUID
    let variantTemplateId: UUID
    let quantity: Double
    let heldQuantity: Double?
    let categoryVariantTemplates: CategoryVariantTemplateData?

    var variantName: String {
        categoryVariantTemplates?.variantName ?? "Unknown"
    }

    var conversionRatio: Double {
        categoryVariantTemplates?.conversionRatio ?? 1.0
    }

    var availableQuantity: Double {
        quantity - (heldQuantity ?? 0)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case variantTemplateId = "variant_template_id"
        case quantity
        case heldQuantity = "held_quantity"
        case categoryVariantTemplates = "category_variant_templates"
    }

    init(id: UUID, variantTemplateId: UUID, quantity: Double, heldQuantity: Double?, categoryVariantTemplates: CategoryVariantTemplateData?) {
        self.id = id
        self.variantTemplateId = variantTemplateId
        self.quantity = quantity
        self.heldQuantity = heldQuantity
        self.categoryVariantTemplates = categoryVariantTemplates
    }
}

// MARK: - Category Variant Template Data

struct CategoryVariantTemplateData: Codable {
    let variantName: String
    let conversionRatio: Double

    enum CodingKeys: String, CodingKey {
        case variantName = "variant_name"
        case conversionRatio = "conversion_ratio"
    }
}

// MARK: - View Row Decoding

/// Row from v_products_with_inventory view
/// Combines product data with inventory, category, and pricing template
struct ProductWithInventoryRow: Codable {
    let id: UUID
    let name: String
    let description: String?
    let sku: String?
    let featuredImage: String?
    let customFields: [String: AnyCodable]?
    let pricingData: [AnyCodable]?  // Array of pricing tiers from database
    let storeId: UUID
    let primaryCategoryId: UUID?
    let pricingSchemaId: UUID?
    let status: String?

    // Inventory fields (from LEFT JOIN)
    let inventoryId: UUID?
    let locationId: UUID?
    let totalQuantity: Double?
    let heldQuantity: Double?
    let availableQuantity: Double?

    // Nested JSONB objects
    let primaryCategory: CategoryJSON?
    let pricingSchema: PricingSchemaJSON?

    enum CodingKeys: String, CodingKey {
        case id, name, description, sku, status
        case featuredImage = "featured_image"
        case customFields = "custom_fields"
        case pricingData = "pricing_data"
        case storeId = "store_id"
        case primaryCategoryId = "primary_category_id"
        case pricingSchemaId = "pricing_schema_id"
        case inventoryId = "inventory_id"
        case locationId = "location_id"
        case totalQuantity = "total_quantity"
        case heldQuantity = "held_quantity"
        case availableQuantity = "available_quantity"
        case primaryCategory = "primary_category"
        case pricingSchema = "pricing_schema"
    }
}

/// Category from JSONB column in view
struct CategoryJSON: Codable {
    let id: UUID
    let name: String
}

/// Pricing schema from JSONB column in view
struct PricingSchemaJSON: Codable {
    let id: UUID
    let name: String
    let defaultTiers: [PricingTier]?

    enum CodingKeys: String, CodingKey {
        case id, name
        case defaultTiers = "tiers"
    }
}
