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
        // Service products are always available (no inventory tracking)
        if isService { return 999 }
        return inventory?.quantity ?? stockQuantity ?? 0
    }

    /// Is in stock
    var inStock: Bool {
        availableStock > 0
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

// MARK: - Product Category

struct ProductCategory: Codable, Sendable {
    let id: UUID
    let name: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
    }
}

// MARK: - Pricing Schema

struct PricingSchema: Sendable {
    let id: UUID
    let name: String
    let defaultTiers: [PricingTier]?
}

extension PricingSchema: Codable {
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case defaultTiers = "tiers"
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // ID can be UUID or String
        if let uuid = try? container.decode(UUID.self, forKey: .id) {
            id = uuid
        } else if let str = try? container.decode(String.self, forKey: .id), let uuid = UUID(uuidString: str) {
            id = uuid
        } else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: container, debugDescription: "Invalid UUID")
        }

        name = try container.decode(String.self, forKey: .name)
        defaultTiers = try container.decodeIfPresent([PricingTier].self, forKey: .defaultTiers)
    }
}

struct PricingTier: Sendable, Identifiable {
    let id: String
    let label: String
    let quantity: Double
    let unit: String
    let defaultPrice: Decimal
    let sortOrder: Int?
}

extension PricingTier: Codable {
    enum CodingKeys: String, CodingKey {
        case id
        case label
        case quantity
        case unit
        case defaultPrice = "default_price"
        case sortOrder = "sort_order"
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)

        // Quantity can be Int or Double
        if let intVal = try? container.decode(Int.self, forKey: .quantity) {
            quantity = Double(intVal)
        } else {
            quantity = try container.decode(Double.self, forKey: .quantity)
        }

        unit = try container.decode(String.self, forKey: .unit)

        // Price can be Decimal, Double, Int, or String
        if let decimal = try? container.decode(Decimal.self, forKey: .defaultPrice) {
            defaultPrice = decimal
        } else if let double = try? container.decode(Double.self, forKey: .defaultPrice) {
            defaultPrice = Decimal(double)
        } else if let int = try? container.decode(Int.self, forKey: .defaultPrice) {
            defaultPrice = Decimal(int)
        } else if let str = try? container.decode(String.self, forKey: .defaultPrice), let decimal = Decimal(string: str) {
            defaultPrice = decimal
        } else {
            defaultPrice = 0
        }

        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder)
    }
}

// MARK: - Certificate of Analysis (COA)

struct ProductCOA: Codable, Sendable, Identifiable {
    let id: UUID
    let productId: UUID?  // Optional - not included in RPC responses
    let fileUrl: String?
    let fileName: String?
    let labName: String?      // mapped from source_name in store_documents
    let testDate: Date?       // mapped from document_date in store_documents
    let expiryDate: Date?
    let batchNumber: String?  // mapped from reference_number in store_documents
    let testResults: COATestResults?  // mapped from data in store_documents
    let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case productId = "product_id"
        case fileUrl = "file_url"
        case fileName = "file_name"
        case labName = "source_name"        // was lab_name in store_coas
        case testDate = "document_date"     // was test_date in store_coas
        case expiryDate = "expiry_date"
        case batchNumber = "reference_number"  // was batch_number in store_coas
        case testResults = "data"           // was test_results in store_coas
        case isActive = "is_active"
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        productId = try container.decodeIfPresent(UUID.self, forKey: .productId)
        fileUrl = try container.decodeIfPresent(String.self, forKey: .fileUrl)
        fileName = try container.decodeIfPresent(String.self, forKey: .fileName)
        labName = try container.decodeIfPresent(String.self, forKey: .labName)
        batchNumber = try container.decodeIfPresent(String.self, forKey: .batchNumber)
        isActive = (try? container.decodeIfPresent(Bool.self, forKey: .isActive)) ?? true

        // Parse dates with flexible handling
        if let dateString = try? container.decodeIfPresent(String.self, forKey: .testDate) {
            testDate = Self.parseDate(dateString)
        } else {
            testDate = try? container.decodeIfPresent(Date.self, forKey: .testDate)
        }

        if let dateString = try? container.decodeIfPresent(String.self, forKey: .expiryDate) {
            expiryDate = Self.parseDate(dateString)
        } else {
            expiryDate = try? container.decodeIfPresent(Date.self, forKey: .expiryDate)
        }

        testResults = try? container.decodeIfPresent(COATestResults.self, forKey: .testResults)
    }

    private static func parseDate(_ string: String) -> Date? {
        let formatters: [DateFormatter] = {
            let iso = DateFormatter()
            iso.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"

            let simple = DateFormatter()
            simple.dateFormat = "yyyy-MM-dd"

            return [iso, simple]
        }()

        for formatter in formatters {
            if let date = formatter.date(from: string) {
                return date
            }
        }
        return nil
    }

    /// URL for QR code generation
    var coaUrl: URL? {
        guard let fileUrl else { return nil }
        return URL(string: fileUrl)
    }
}

// MARK: - COA Test Results (parsed from JSONB)
// Flexible decoding to handle various database key formats

struct COATestResults: Codable, Sendable {
    let thcTotal: Double?         // Total THC %
    let thca: Double?             // THCA % (pre-decarb)
    let d9Thc: Double?            // Delta-9 THC % (active)
    let cbdTotal: Double?         // Total CBD %
    let cbda: Double?             // CBDA %
    let strainType: String?       // "indica", "sativa", "hybrid"
    let terpenes: [String: Double]?
    let contaminants: ContaminantResults?

    // Custom decoding to handle multiple possible key formats from database
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: FlexibleCodingKeys.self)

        // THC Total - try multiple key variations
        thcTotal = Self.decodeDouble(from: container, keys: ["thc_total", "thcTotal", "total_thc", "totalThc", "THC", "thc"])

        // THCA - try multiple key variations
        thca = Self.decodeDouble(from: container, keys: ["thca", "THCA", "thca_percent", "thcaPercent"])

        // Delta-9 THC - try multiple key variations
        d9Thc = Self.decodeDouble(from: container, keys: ["d9_thc", "d9Thc", "delta9_thc", "delta9Thc", "d9", "delta9"])

        // CBD Total - try multiple key variations
        cbdTotal = Self.decodeDouble(from: container, keys: ["cbd_total", "cbdTotal", "total_cbd", "totalCbd", "CBD", "cbd"])

        // CBDA - try multiple key variations
        cbda = Self.decodeDouble(from: container, keys: ["cbda", "CBDA", "cbda_percent", "cbdaPercent"])

        // Strain type - try multiple key variations
        strainType = Self.decodeString(from: container, keys: ["strain_type", "strainType", "strain", "type"])

        // Terpenes
        if let key = FlexibleCodingKeys(stringValue: "terpenes") {
            terpenes = try? container.decodeIfPresent([String: Double].self, forKey: key)
        } else {
            terpenes = nil
        }

        // Contaminants
        if let key = FlexibleCodingKeys(stringValue: "contaminants") {
            contaminants = try? container.decodeIfPresent(ContaminantResults.self, forKey: key)
        } else {
            contaminants = nil
        }
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: FlexibleCodingKeys.self)
        if let key = FlexibleCodingKeys(stringValue: "thc_total") { try container.encodeIfPresent(thcTotal, forKey: key) }
        if let key = FlexibleCodingKeys(stringValue: "thca") { try container.encodeIfPresent(thca, forKey: key) }
        if let key = FlexibleCodingKeys(stringValue: "d9_thc") { try container.encodeIfPresent(d9Thc, forKey: key) }
        if let key = FlexibleCodingKeys(stringValue: "cbd_total") { try container.encodeIfPresent(cbdTotal, forKey: key) }
        if let key = FlexibleCodingKeys(stringValue: "cbda") { try container.encodeIfPresent(cbda, forKey: key) }
        if let key = FlexibleCodingKeys(stringValue: "strain_type") { try container.encodeIfPresent(strainType, forKey: key) }
        if let key = FlexibleCodingKeys(stringValue: "terpenes") { try container.encodeIfPresent(terpenes, forKey: key) }
        if let key = FlexibleCodingKeys(stringValue: "contaminants") { try container.encodeIfPresent(contaminants, forKey: key) }
    }

    // Helper to decode Double from multiple possible keys
    private static func decodeDouble(from container: KeyedDecodingContainer<FlexibleCodingKeys>, keys: [String]) -> Double? {
        for keyString in keys {
            guard let key = FlexibleCodingKeys(stringValue: keyString) else { continue }

            // Try Double directly
            if let value = try? container.decodeIfPresent(Double.self, forKey: key) {
                return value
            }
            // Try Int and convert
            if let intValue = try? container.decodeIfPresent(Int.self, forKey: key) {
                return Double(intValue)
            }
            // Try String and convert
            if let stringValue = try? container.decodeIfPresent(String.self, forKey: key),
               let doubleValue = Double(stringValue.replacingOccurrences(of: "%", with: "")) {
                return doubleValue
            }
        }
        return nil
    }

    // Helper to decode String from multiple possible keys
    private static func decodeString(from container: KeyedDecodingContainer<FlexibleCodingKeys>, keys: [String]) -> String? {
        for keyString in keys {
            guard let key = FlexibleCodingKeys(stringValue: keyString) else { continue }
            if let value = try? container.decodeIfPresent(String.self, forKey: key) {
                return value
            }
        }
        return nil
    }
}

// Flexible coding keys for dynamic JSONB parsing
struct FlexibleCodingKeys: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

struct ContaminantResults: Codable, Sendable {
    let pesticides: String?       // "pass", "fail", "not_tested"
    let heavyMetals: String?
    let microbials: String?
    let residualSolvents: String?

    enum CodingKeys: String, CodingKey {
        case pesticides
        case heavyMetals = "heavy_metals"
        case microbials
        case residualSolvents = "residual_solvents"
    }
}

// MARK: - Product Inventory

struct ProductInventory: Codable, Sendable {
    let id: UUID
    let productId: UUID
    let locationId: UUID
    let totalQuantity: Decimal?
    let heldQuantity: Decimal?
    let availableQuantity: Decimal?

    enum CodingKeys: String, CodingKey {
        case id
        case productId = "product_id"
        case locationId = "location_id"
        case totalQuantity = "total_quantity"
        case heldQuantity = "held_quantity"
        case availableQuantity = "available_quantity"
    }

    var quantity: Int {
        let decimal = availableQuantity ?? totalQuantity ?? 0
        return NSDecimalNumber(decimal: decimal).intValue
    }

    /// Explicit initializer for creating updated inventory records
    init(id: UUID, productId: UUID, locationId: UUID, totalQuantity: Decimal?, heldQuantity: Decimal?, availableQuantity: Decimal?) {
        self.id = id
        self.productId = productId
        self.locationId = locationId
        self.totalQuantity = totalQuantity
        self.heldQuantity = heldQuantity
        self.availableQuantity = availableQuantity
    }
}

// MARK: - Store Product Field (field definitions from store_product_fields table)

struct StoreProductField: Codable, Sendable, Identifiable {
    let id: UUID
    let storeId: UUID
    let categoryId: UUID?
    let fieldId: String
    let fieldDefinition: FieldDefinition
    let sortOrder: Int

    var displayLabel: String {
        fieldDefinition.label ?? formatFieldId(fieldId)
    }

    private func formatFieldId(_ id: String) -> String {
        id.replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }

    enum CodingKeys: String, CodingKey {
        case id
        case storeId = "store_id"
        case categoryId = "category_id"
        case fieldId = "field_id"
        case fieldDefinition = "field_definition"
        case sortOrder = "sort_order"
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        storeId = try container.decode(UUID.self, forKey: .storeId)
        categoryId = try container.decodeIfPresent(UUID.self, forKey: .categoryId)
        fieldId = try container.decode(String.self, forKey: .fieldId)
        fieldDefinition = try container.decode(FieldDefinition.self, forKey: .fieldDefinition)
        sortOrder = (try? container.decodeIfPresent(Int.self, forKey: .sortOrder)) ?? 0
    }
}


struct FieldDefinition: Codable, Sendable {
    let type: String?
    let label: String?
    let options: [String]?

    enum CodingKeys: String, CodingKey {
        case type
        case label
        case options
    }
}

// MARK: - AnyCodable Helper

/// Type-erased Codable for JSONB custom_fields
struct AnyCodable: Codable, Sendable, Hashable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case let string as String:
            try container.encode(string)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let bool as Bool:
            try container.encode(bool)
        default:
            try container.encodeNil()
        }
    }

    func hash(into hasher: inout Hasher) {
        // Simple hash based on description
        hasher.combine(String(describing: value))
    }

    static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        String(describing: lhs.value) == String(describing: rhs.value)
    }
}
