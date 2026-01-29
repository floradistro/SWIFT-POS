//
//  ProductVariant.swift
//  Whale
//
//  Product variant support for category-level variants (e.g., Pre-Roll for Flower).
//  Variants are defined at the category level and products opt-in.
//

import Foundation

// MARK: - Category Variant Template

/// Defines a variant type at the category level (e.g., "Pre-Roll" for Flower category)
struct CategoryVariantTemplate: Identifiable, Codable, Sendable {
    let id: UUID
    let categoryId: UUID
    let storeId: UUID
    let variantName: String
    let variantSlug: String
    let conversionRatio: Double?       // e.g., 0.7 (1 pre-roll = 0.7g flower)
    let conversionUnit: String?        // e.g., "g"
    let pricingSchemaId: UUID?       // Separate pricing for this variant
    let shareParentInventory: Bool
    let trackSeparateInventory: Bool
    let allowOnDemandConversion: Bool
    let displayOrder: Int
    let isActive: Bool

    // Images
    let featuredImageUrl: String?
    let thumbnailUrl: String?
    let indicatorIconUrl: String?

    enum CodingKeys: String, CodingKey {
        case id
        case categoryId = "category_id"
        case storeId = "store_id"
        case variantName = "variant_name"
        case variantSlug = "variant_slug"
        case conversionRatio = "conversion_ratio"
        case conversionUnit = "conversion_unit"
        case pricingSchemaId = "pricing_schema_id"
        case shareParentInventory = "share_parent_inventory"
        case trackSeparateInventory = "track_separate_inventory"
        case allowOnDemandConversion = "allow_on_demand_conversion"
        case displayOrder = "display_order"
        case isActive = "is_active"
        case featuredImageUrl = "featured_image_url"
        case thumbnailUrl = "thumbnail_url"
        case indicatorIconUrl = "indicator_icon_url"
    }
}

// MARK: - Product Variant (Resolved View)

/// A fully resolved variant for a specific product (from v_product_variants view)
/// Combines category template defaults with product-level overrides
struct ProductVariant: Identifiable, Codable, Sendable, Hashable {
    let productId: UUID
    let variantTemplateId: UUID
    let variantName: String
    let conversionRatio: Double?
    let conversionUnit: String?
    let pricingSchemaId: UUID?
    let shareParentInventory: Bool
    let displayOrder: Int
    let isEnabled: Bool

    // Loaded separately or joined
    var pricingSchema: PricingSchema?
    var inventory: VariantInventory?

    // Identifiable conformance - use variantTemplateId as id
    var id: UUID { variantTemplateId }

    enum CodingKeys: String, CodingKey {
        case productId = "product_id"
        case variantTemplateId = "variant_template_id"
        case variantName = "variant_name"
        case conversionRatio = "conversion_ratio"
        case conversionUnit = "conversion_unit"
        case pricingSchemaId = "pricing_schema_id"
        case shareParentInventory = "share_parent_inventory"
        case displayOrder = "display_order"
        case isEnabled = "is_enabled"
        case pricingSchema = "pricing_schema"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        productId = try container.decode(UUID.self, forKey: .productId)
        variantTemplateId = try container.decode(UUID.self, forKey: .variantTemplateId)
        variantName = try container.decode(String.self, forKey: .variantName)
        conversionRatio = try container.decodeIfPresent(Double.self, forKey: .conversionRatio)
        conversionUnit = try container.decodeIfPresent(String.self, forKey: .conversionUnit)
        pricingSchemaId = try container.decodeIfPresent(UUID.self, forKey: .pricingSchemaId)
        shareParentInventory = (try? container.decode(Bool.self, forKey: .shareParentInventory)) ?? true
        displayOrder = (try? container.decode(Int.self, forKey: .displayOrder)) ?? 0
        isEnabled = (try? container.decode(Bool.self, forKey: .isEnabled)) ?? true
        pricingSchema = try? container.decodeIfPresent(PricingSchema.self, forKey: .pricingSchema)
        inventory = nil
    }

    // Manual initializer for testing/previews
    init(
        productId: UUID,
        variantTemplateId: UUID,
        variantName: String,
        conversionRatio: Double?,
        conversionUnit: String?,
        pricingSchemaId: UUID?,
        shareParentInventory: Bool = true,
        displayOrder: Int = 0,
        isEnabled: Bool = true,
        pricingSchema: PricingSchema? = nil,
        inventory: VariantInventory? = nil
    ) {
        self.productId = productId
        self.variantTemplateId = variantTemplateId
        self.variantName = variantName
        self.conversionRatio = conversionRatio
        self.conversionUnit = conversionUnit
        self.pricingSchemaId = pricingSchemaId
        self.shareParentInventory = shareParentInventory
        self.displayOrder = displayOrder
        self.isEnabled = isEnabled
        self.pricingSchema = pricingSchema
        self.inventory = inventory
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(productId)
    }

    static func == (lhs: ProductVariant, rhs: ProductVariant) -> Bool {
        lhs.id == rhs.id && lhs.productId == rhs.productId
    }
}

// MARK: - Variant Inventory

/// Tracks separate inventory for a variant at a specific location
struct VariantInventory: Codable, Sendable {
    let id: UUID
    let productId: UUID
    let variantTemplateId: UUID
    let locationId: UUID
    let quantity: Decimal
    let heldQuantity: Decimal

    var availableQuantity: Decimal {
        quantity - heldQuantity
    }

    enum CodingKeys: String, CodingKey {
        case id
        case productId = "product_id"
        case variantTemplateId = "variant_template_id"
        case locationId = "location_id"
        case quantity
        case heldQuantity = "held_quantity"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        productId = try container.decode(UUID.self, forKey: .productId)
        variantTemplateId = try container.decode(UUID.self, forKey: .variantTemplateId)
        locationId = try container.decode(UUID.self, forKey: .locationId)

        // Handle various number formats
        if let decimal = try? container.decode(Decimal.self, forKey: .quantity) {
            quantity = decimal
        } else if let double = try? container.decode(Double.self, forKey: .quantity) {
            quantity = Decimal(double)
        } else {
            quantity = 0
        }

        if let decimal = try? container.decode(Decimal.self, forKey: .heldQuantity) {
            heldQuantity = decimal
        } else if let double = try? container.decode(Double.self, forKey: .heldQuantity) {
            heldQuantity = Decimal(double)
        } else {
            heldQuantity = 0
        }
    }

    // Manual initializer for programmatic creation
    init(id: UUID, productId: UUID, variantTemplateId: UUID, locationId: UUID, quantity: Decimal, heldQuantity: Decimal) {
        self.id = id
        self.productId = productId
        self.variantTemplateId = variantTemplateId
        self.locationId = locationId
        self.quantity = quantity
        self.heldQuantity = heldQuantity
    }
}

// MARK: - Extensions

extension ProductVariant {
    /// Display label for the variant (e.g., "Pre-Roll")
    var displayName: String {
        variantName
    }

    /// Whether this variant has its own pricing schema
    var hasCustomPricing: Bool {
        pricingSchemaId != nil
    }

    /// Get pricing tiers for this variant
    var pricingTiers: [PricingTier] {
        pricingSchema?.defaultTiers ?? []
    }
}
