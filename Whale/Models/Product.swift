//
//  Product.swift
//  Whale
//
//  Product model for POS.
//  Matches Supabase products table structure.
//

import Foundation
import os.log

struct Product: Identifiable, Hashable, Sendable {
    let id: UUID
    let storeId: UUID?
    let name: String
    let description: String?
    let sku: String?
    let type: String?  // simple, variable, service, bundle, subscription

    // Images
    let imageUrl: String?
    let featuredImage: String?

    // Category
    let primaryCategoryId: UUID?

    // Pricing Schema
    let pricingSchemaId: UUID?

    // Stock
    let stockQuantity: Int?

    // Custom fields (JSONB - decoded as raw)
    let customFields: [String: AnyCodable]?

    // Joined data (set after fetch)
    var inventory: ProductInventory?
    var inventoryArray: [ProductInventory]?  // For PostgREST embedded array decoding
    var primaryCategory: ProductCategory?
    var pricingSchema: PricingSchema?
    var coa: ProductCOA?  // Certificate of Analysis

    // Variants (loaded separately from v_product_variants)
    var variants: [ProductVariant]?
}

// MARK: - Codable

extension Product: Codable {
    enum CodingKeys: String, CodingKey {
        case id
        case storeId = "store_id"
        case name
        case description
        case sku
        case type
        case imageUrl = "image_url"
        case featuredImage = "featured_image"
        case primaryCategoryId = "primary_category_id"
        case pricingSchemaId = "pricing_schema_id"
        case stockQuantity = "stock_quantity"
        case customFields = "custom_fields"
        case primaryCategory = "primary_category"
        case pricingSchema = "pricing_schema"
        case inventory = "inventory"
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        storeId = try container.decodeIfPresent(UUID.self, forKey: .storeId)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        sku = try container.decodeIfPresent(String.self, forKey: .sku)
        type = try container.decodeIfPresent(String.self, forKey: .type)

        imageUrl = try? container.decodeIfPresent(String.self, forKey: .imageUrl)
        featuredImage = try? container.decodeIfPresent(String.self, forKey: .featuredImage)
        primaryCategoryId = try? container.decodeIfPresent(UUID.self, forKey: .primaryCategoryId)
        pricingSchemaId = try? container.decodeIfPresent(UUID.self, forKey: .pricingSchemaId)
        stockQuantity = Self.decodeInt(from: container, forKey: .stockQuantity)
        customFields = try? container.decodeIfPresent([String: AnyCodable].self, forKey: .customFields)

        // Nested objects from joins
        primaryCategory = try? container.decodeIfPresent(ProductCategory.self, forKey: .primaryCategory)

        // Decode pricing schema (silent - no per-product logging)
        pricingSchema = try? container.decodeIfPresent(PricingSchema.self, forKey: .pricingSchema)

        // Decode inventory array from embedded PostgREST join
        // PostgREST returns to-many relations as arrays
        inventoryArray = try? container.decodeIfPresent([ProductInventory].self, forKey: .inventory)
        inventory = inventoryArray?.first
    }

    private static func decodeInt(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> Int? {
        // Try Int first
        if let int = try? container.decodeIfPresent(Int.self, forKey: key) {
            return int
        }
        // Try Double
        if let double = try? container.decodeIfPresent(Double.self, forKey: key) {
            return Int(double)
        }
        // Try String
        if let string = try? container.decodeIfPresent(String.self, forKey: key) {
            return Int(string)
        }
        return nil
    }


    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(storeId, forKey: .storeId)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(sku, forKey: .sku)
        try container.encodeIfPresent(imageUrl, forKey: .imageUrl)
        try container.encodeIfPresent(featuredImage, forKey: .featuredImage)
        try container.encodeIfPresent(primaryCategoryId, forKey: .primaryCategoryId)
        try container.encodeIfPresent(pricingSchemaId, forKey: .pricingSchemaId)
        try container.encodeIfPresent(stockQuantity, forKey: .stockQuantity)
        try container.encodeIfPresent(customFields, forKey: .customFields)
    }

    /// Minimal init for creating placeholder products (e.g., for label printing)
    init(id: UUID, name: String, storeId: UUID?) {
        self.id = id
        self.storeId = storeId
        self.name = name
        self.description = nil
        self.sku = nil
        self.type = nil
        self.imageUrl = nil
        self.featuredImage = nil
        self.primaryCategoryId = nil
        self.pricingSchemaId = nil
        self.stockQuantity = nil
        self.customFields = nil
        self.primaryCategory = nil
        self.pricingSchema = nil
        self.coa = nil
        self.variants = nil
        self.inventory = nil
        self.inventoryArray = nil
    }

    /// Full memberwise init for creating products programmatically
    init(
        id: UUID,
        name: String,
        description: String? = nil,
        sku: String? = nil,
        featuredImage: String? = nil,
        customFields: [String: AnyCodable]? = nil,
        storeId: UUID,
        primaryCategoryId: UUID? = nil,
        pricingSchemaId: UUID? = nil,
        pricingSchema: PricingSchema? = nil,
        status: String? = nil
    ) {
        self.id = id
        self.storeId = storeId
        self.name = name
        self.description = description
        self.sku = sku
        self.type = nil
        self.imageUrl = nil
        self.featuredImage = featuredImage
        self.primaryCategoryId = primaryCategoryId
        self.pricingSchemaId = pricingSchemaId
        self.stockQuantity = nil
        self.customFields = customFields
        self.primaryCategory = nil
        self.pricingSchema = pricingSchema
        self.coa = nil
        self.variants = nil
        self.inventory = nil
        self.inventoryArray = nil
    }
}

// MARK: - Computed Properties

extension Product {
    /// Display price - derived from first tier of pricing schema
    /// All pricing is now tier-based - this returns the smallest/first tier price for display
    var displayPrice: Decimal {
        // Get first tier price from pricing schema (sorted by sort_order)
        if let tiers = pricingSchema?.defaultTiers,
           let firstTier = tiers.sorted(by: { ($0.sortOrder ?? 0) < ($1.sortOrder ?? 0) }).first {
            return firstTier.defaultPrice
        }
        return 0
    }

    /// Check if product uses tiered pricing
    var hasTieredPricing: Bool {
        guard let tiers = pricingSchema?.defaultTiers else { return false }
        return !tiers.isEmpty
    }

    /// Check if product has variants available
    var hasVariants: Bool {
        guard let variants = variants else { return false }
        return !variants.isEmpty
    }

    /// Get enabled variants sorted by display order
    var enabledVariants: [ProductVariant] {
        (variants ?? [])
            .filter { $0.isEnabled }
            .sorted { $0.displayOrder < $1.displayOrder }
    }

    /// All pricing tiers from pricing_schema
    /// Products MUST have pricing_schema_id set - no legacy fallback
    var allTiers: [PricingTier] {
        pricingSchema?.defaultTiers ?? []
    }

    /// Icon image URL (500x500) for product grid - HQ optimized
    var iconUrl: URL? {
        optimizedImageUrl(width: 500, height: 500)
    }

    /// Thumbnail image URL (100x100) for detail headers
    var thumbnailUrl: URL? {
        optimizedImageUrl(width: 100, height: 100)
    }

    /// Medium image URL (300x300) for modals
    var mediumImageUrl: URL? {
        optimizedImageUrl(width: 300, height: 300)
    }

    /// Full image URL from Supabase storage
    var fullImageUrl: URL? {
        let image = featuredImage ?? imageUrl
        guard let image, !image.isEmpty else { return nil }
        return URL(string: image)
    }

    /// Build optimized image URL using Supabase transforms
    private func optimizedImageUrl(width: Int, height: Int) -> URL? {
        let image = featuredImage ?? imageUrl
        guard let image, !image.isEmpty else { return nil }

        // Must be a Supabase storage URL to transform
        guard image.contains("supabase.co/storage/v1/object/public/") else {
            return URL(string: image)
        }

        // Transform: /object/public/ -> /render/image/public/
        let transformedUrl = image.replacingOccurrences(
            of: "/storage/v1/object/public/",
            with: "/storage/v1/render/image/public/"
        )

        return URL(string: "\(transformedUrl)?width=\(width)&height=\(height)&resize=cover")
    }

    /// Category name for display
    var categoryName: String? {
        primaryCategory?.name
    }

    /// Current stock at location (from inventory or denormalized field)
    /// Is this a service product (non-inventory)
    var isService: Bool {
        type == "service"
    }

    var availableStock: Int {
        // Service products don't have inventory tracking
        if isService { return 0 }
        return inventory?.quantity ?? stockQuantity ?? 0
    }

    /// Is in stock (service products are always available)
    var inStock: Bool {
        if isService { return true }
        return availableStock > 0
    }

    // MARK: - COA & Cannabinoid Properties

    /// Strain type - check customFields first, then COA
    var strainType: String? {
        // Check customFields for strain type (matches website: strain_type)
        if let strain = customFieldString(keys: ["strain_type", "strainType", "strain"]) {
            return strain.capitalized
        }
        return coa?.testResults?.strainType?.capitalized
    }

    /// COA file URL for QR code
    var coaUrl: URL? {
        coa?.coaUrl
    }

    /// THC percentage - check customFields first, then COA
    var thcPercentage: Double? {
        // Check customFields first (matches website: thca_percentage is the main THC field)
        if let thc = customFieldDouble(keys: ["thca_percentage", "thc_total", "thcTotal", "total_thc", "thc", "THC"]) {
            return thc
        }
        return coa?.testResults?.thcTotal
    }

    /// THCA percentage - check customFields first, then COA
    /// Website uses "thca_percentage" as the primary field
    var thcaPercentage: Double? {
        // Check customFields first - thca_percentage is the key used by Flora website
        if let thca = customFieldDouble(keys: ["thca_percentage", "thca", "THCA", "thca_percent", "THCa"]) {
            return thca
        }
        return coa?.testResults?.thca
    }

    /// Delta-9 THC percentage - check customFields first, then COA
    var d9ThcPercentage: Double? {
        // Check customFields first
        if let d9 = customFieldDouble(keys: ["d9_thc", "d9Thc", "delta9_thc", "delta9", "d9", "d9_percentage"]) {
            return d9
        }
        return coa?.testResults?.d9Thc
    }

    /// CBD percentage - check customFields first, then COA
    var cbdPercentage: Double? {
        // Check customFields first
        if let cbd = customFieldDouble(keys: ["cbd_total", "cbdTotal", "total_cbd", "cbd", "CBD", "cbd_percentage"]) {
            return cbd
        }
        return coa?.testResults?.cbdTotal
    }

    /// Total MG per package (for edibles)
    var totalMgPerPackage: Double? {
        customFieldDouble(keys: ["total_mg_per_package", "totalMgPerPackage"])
    }

    /// Total MG per piece (for edibles)
    var totalMgPerPiece: Double? {
        customFieldDouble(keys: ["total_mg_per_piece", "totalMgPerPiece"])
    }

    /// Product tagline
    var tagline: String? {
        customFieldString(keys: ["tagline"])
    }

    /// Has valid COA attached
    var hasCOA: Bool {
        coa != nil && coa?.fileUrl != nil
    }

    /// Test date - check COA first, then customFields
    var testDate: Date? {
        // Check COA first
        if let testDate = coa?.testDate {
            return testDate
        }
        // Fall back to customFields for backend-provided test date
        if let dateString = customFieldString(keys: ["test_date", "testDate"]) {
            // Try ISO8601 format first
            if let date = ISO8601DateFormatter().date(from: dateString) {
                return date
            }
            // Try simple date format
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            if let date = formatter.date(from: dateString) {
                return date
            }
        }
        return nil
    }

    // MARK: - Custom Fields Helpers

    /// Debug: Log all custom field keys for this product
    func logCustomFields() {
        guard let fields = customFields else {
            Log.network.debug("🏷️ Product '\(name)': No customFields")
            return
        }
        let keys = fields.keys.sorted()
        Log.network.debug("🏷️ Product '\(name)' customFields keys: \(keys.joined(separator: ", "))")
        for (key, value) in fields {
            Log.network.debug("  - \(key): \(String(describing: value.value))")
        }
    }

    /// Get a Double value from customFields, trying multiple key names
    private func customFieldDouble(keys: [String]) -> Double? {
        guard let fields = customFields else { return nil }
        for key in keys {
            if let anyCodable = fields[key] {
                // Try to extract Double from AnyCodable
                if let doubleVal = anyCodable.value as? Double {
                    return doubleVal
                }
                if let intVal = anyCodable.value as? Int {
                    return Double(intVal)
                }
                if let stringVal = anyCodable.value as? String,
                   let doubleVal = Double(stringVal.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)) {
                    return doubleVal
                }
            }
        }
        return nil
    }

    /// Get a String value from customFields, trying multiple key names
    private func customFieldString(keys: [String]) -> String? {
        guard let fields = customFields else { return nil }
        for key in keys {
            if let anyCodable = fields[key], let stringVal = anyCodable.value as? String {
                return stringVal
            }
        }
        return nil
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Product, rhs: Product) -> Bool {
        lhs.id == rhs.id
    }
}


