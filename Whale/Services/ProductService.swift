//
//  ProductService.swift
//  Whale
//
//  Product fetching from Supabase.
//  Queries products table with inventory join.
//

import Foundation
import Supabase
import os.log

// MARK: - Product Service

enum ProductService {

    /// Fetch products for a store at a specific location
    /// Uses v_products_with_inventory view for single-query efficiency
    static func fetchProducts(storeId: UUID, locationId: UUID) async throws -> [Product] {
        Log.network.info("🔍 Fetching products for store: \(storeId.uuidString), location: \(locationId.uuidString)")

        // Single query using PostgREST embedded resources
        // Joins products + inventory_with_holds + categories + pricing_schemas in one request
        let response = try await supabase
            .from("products")
            .select("""
                id,
                name,
                description,
                sku,
                featured_image,
                custom_fields,
                pricing_data,
                store_id,
                primary_category_id,
                pricing_schema_id,
                status,
                primary_category:categories!primary_category_id(id, name),
                pricing_schema:pricing_schemas(id, name, tiers),
                inventory:inventory_with_holds!inner(id, product_id, location_id, total_quantity, held_quantity, available_quantity)
            """)
            .eq("store_id", value: storeId.uuidString)
            .eq("inventory.location_id", value: locationId.uuidString)
            .gt("inventory.available_quantity", value: 0)
            .order("name")
            .execute()

        Log.network.info("📦 Received response with \(response.data.count) bytes of data")

        // Decode off main thread to avoid blocking UI
        let productData = response.data
        var products: [Product]
        do {
            products = try await Task.detached {
                let decoder = JSONDecoder()
                return try decoder.decode([Product].self, from: productData)
            }.value
        } catch let decodingError as DecodingError {
            // Log detailed decoding error for debugging
            if let jsonString = String(data: productData, encoding: .utf8) {
                Log.network.debug("🔍 Raw JSON (first 2000 chars): \(String(jsonString.prefix(2000)))")
            }
            switch decodingError {
            case .keyNotFound(let key, let context):
                Log.network.error("❌ Key not found: \(key.stringValue) at \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
            case .typeMismatch(let type, let context):
                Log.network.error("❌ Type mismatch: expected \(type) at \(context.codingPath.map { $0.stringValue }.joined(separator: ".")): \(context.debugDescription)")
            case .valueNotFound(let type, let context):
                Log.network.error("❌ Value not found: \(type) at \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
            case .dataCorrupted(let context):
                Log.network.error("❌ Data corrupted at \(context.codingPath.map { $0.stringValue }.joined(separator: ".")): \(context.debugDescription)")
            @unknown default:
                Log.network.error("❌ Decoding error: \(decodingError.localizedDescription)")
            }
            throw decodingError
        }

        // FAIL-SAFE: Filter out any products with 0 or negative stock
        // This ensures 0-stock products NEVER appear on POS even if DB filter fails
        let inStockProducts = products.filter { $0.availableStock > 0 }

        if inStockProducts.count != products.count {
            Log.network.warning("⚠️ Filtered out \(products.count - inStockProducts.count) zero-stock products (DB filter may have failed)")
        }

        Log.network.info("✅ Fetched \(inStockProducts.count) in-stock products at location \(locationId.uuidString)")
        return inStockProducts
    }

    /// Fetch specific products by their IDs (for label printing, etc.)
    /// Returns products with COA data for proper label rendering
    static func fetchProductsByIds(_ productIds: [UUID]) async throws -> [Product] {
        guard !productIds.isEmpty else { return [] }

        Log.network.info("🔍 Fetching \(productIds.count) products by ID")

        let response = try await supabase
            .from("products")
            .select("""
                id,
                name,
                description,
                sku,
                featured_image,
                custom_fields,
                pricing_data,
                store_id,
                primary_category_id,
                pricing_schema_id,
                status,
                primary_category:categories!primary_category_id(id, name),
                pricing_schema:pricing_schemas(id, name, tiers)
            """)
            .in("id", values: productIds.map { $0.uuidString.lowercased() })
            .execute()

        var products = try JSONDecoder().decode([Product].self, from: response.data)

        // Batch fetch COAs
        do {
            let coasByProduct = try await fetchCOAs(for: productIds)
            for i in products.indices {
                products[i].coa = coasByProduct[products[i].id]
            }
            let productsWithCOA = products.filter { $0.hasCOA }.count
            Log.network.info("✅ Attached COAs to \(productsWithCOA)/\(products.count) products")
        } catch {
            Log.network.warning("⚠️ Failed to fetch COAs for label products: \(error.localizedDescription)")
        }

        Log.network.info("✅ Fetched \(products.count) products by ID")
        return products
    }

    /// Fetch all categories for a store
    static func fetchCategories(storeId: UUID) async throws -> [ProductCategory] {
        let categories: [ProductCategory] = try await supabase
            .from("categories")
            .select("id, name")
            .eq("store_id", value: storeId.uuidString)
            .order("name")
            .execute()
            .value

        Log.network.info("Fetched \(categories.count) categories")
        return categories
    }


    // MARK: - COA Fetching

    /// Fetch COAs for multiple products (batch)
    static func fetchCOAs(for productIds: [UUID]) async throws -> [UUID: ProductCOA] {
        guard !productIds.isEmpty else { return [:] }

        Log.network.info("🔬 Fetching COAs for \(productIds.count) products")

        let response = try await supabase
            .from("store_coas")
            .select("""
                id,
                product_id,
                file_url,
                file_name,
                lab_name,
                test_date,
                expiry_date,
                batch_number,
                test_results,
                is_active
            """)
            .in("product_id", values: productIds.map { $0.uuidString })
            .eq("is_active", value: true)
            .order("created_at", ascending: false)
            .execute()

        // Log raw response to help debug test_results structure
        if let responseString = String(data: response.data, encoding: .utf8) {
            Log.network.debug("🔬 Raw COA response (first 2000 chars): \(responseString.prefix(2000))")
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let coas = try decoder.decode([ProductCOA].self, from: response.data)
        Log.network.info("✅ Fetched \(coas.count) COAs")

        // Log parsed test_results for debugging
        for coa in coas.prefix(3) {
            if let results = coa.testResults {
                Log.network.debug("🔬 COA \(coa.id): thca=\(results.thca ?? -1), d9=\(results.d9Thc ?? -1), thcTotal=\(results.thcTotal ?? -1), cbd=\(results.cbdTotal ?? -1)")
            } else {
                Log.network.debug("🔬 COA \(coa.id): testResults is nil")
            }
        }

        // Group by product_id, taking most recent (first due to order)
        var coasByProduct: [UUID: ProductCOA] = [:]
        for coa in coas {
            guard let productId = coa.productId else { continue }
            if coasByProduct[productId] == nil {
                coasByProduct[productId] = coa
            }
        }

        return coasByProduct
    }

    /// Fetch single COA for a product
    static func fetchCOA(for productId: UUID) async throws -> ProductCOA? {
        Log.network.info("🔬 Fetching COA for product: \(productId.uuidString)")

        let response = try await supabase
            .from("store_coas")
            .select("""
                id,
                product_id,
                file_url,
                file_name,
                lab_name,
                test_date,
                expiry_date,
                batch_number,
                test_results,
                is_active
            """)
            .eq("product_id", value: productId.uuidString)
            .eq("is_active", value: true)
            .order("created_at", ascending: false)
            .limit(1)
            .execute()

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let coas = try decoder.decode([ProductCOA].self, from: response.data)
        return coas.first
    }

    /// Fetch products with COAs attached
    static func fetchProductsWithCOAs(storeId: UUID, locationId: UUID) async throws -> [Product] {
        // First fetch products normally
        var products = try await fetchProducts(storeId: storeId, locationId: locationId)

        // Then batch fetch COAs
        let productIds = products.map { $0.id }

        do {
            let coasByProduct = try await fetchCOAs(for: productIds)

            // Attach COAs to products
            for i in products.indices {
                products[i].coa = coasByProduct[products[i].id]
            }

            let productsWithCOA = products.filter { $0.hasCOA }.count
            Log.network.info("✅ Attached COAs to \(productsWithCOA)/\(products.count) products")
        } catch {
            Log.network.error("⚠️ Failed to fetch COAs: \(error.localizedDescription)")
            // Continue without COAs - non-critical failure
        }

        return products
    }

    // MARK: - Variant Fetching

    /// Fetch variants for multiple products (batch)
    static func fetchVariants(for productIds: [UUID]) async throws -> [UUID: [ProductVariant]] {
        guard !productIds.isEmpty else { return [:] }

        Log.network.info("🔀 Fetching variants for \(productIds.count) products")

        // Note: v_product_variants is a VIEW - can't use FK joins
        // Fetch variants without pricing schema join
        let response = try await supabase
            .from("v_product_variants")
            .select("""
                product_id,
                variant_template_id,
                variant_name,
                conversion_ratio,
                conversion_unit,
                pricing_schema_id,
                share_parent_inventory,
                display_order,
                is_enabled
            """)
            .in("product_id", values: productIds.map { $0.uuidString })
            .eq("is_enabled", value: true)
            .order("display_order", ascending: true)
            .execute()

        let decoder = JSONDecoder()
        var variants = try decoder.decode([ProductVariant].self, from: response.data)

        Log.network.info("✅ Fetched \(variants.count) variants")

        // Batch fetch pricing schemas for variants that have them
        let pricingSchemaIds = Set(variants.compactMap { $0.pricingSchemaId })
        if !pricingSchemaIds.isEmpty {
            let schemasResponse = try await supabase
                .from("pricing_schemas")
                .select("id, name, tiers")
                .in("id", values: pricingSchemaIds.map { $0.uuidString })
                .execute()

            let schemas = try decoder.decode([PricingSchema].self, from: schemasResponse.data)
            let schemasById = Dictionary(uniqueKeysWithValues: schemas.map { ($0.id, $0) })

            // Attach schemas to variants
            for i in variants.indices {
                if let schemaId = variants[i].pricingSchemaId {
                    variants[i].pricingSchema = schemasById[schemaId]
                }
            }
        }

        // Group by product_id
        var variantsByProduct: [UUID: [ProductVariant]] = [:]
        for variant in variants {
            variantsByProduct[variant.productId, default: []].append(variant)
        }

        return variantsByProduct
    }

    /// Fetch variants for a single product
    static func fetchVariants(for productId: UUID) async throws -> [ProductVariant] {
        Log.network.info("🔀 Fetching variants for product: \(productId.uuidString)")

        // Note: v_product_variants is a VIEW - can't use FK joins
        let response = try await supabase
            .from("v_product_variants")
            .select("""
                product_id,
                variant_template_id,
                variant_name,
                conversion_ratio,
                conversion_unit,
                pricing_schema_id,
                share_parent_inventory,
                display_order,
                is_enabled
            """)
            .eq("product_id", value: productId.uuidString)
            .eq("is_enabled", value: true)
            .order("display_order", ascending: true)
            .execute()

        let decoder = JSONDecoder()
        var variants = try decoder.decode([ProductVariant].self, from: response.data)

        // Fetch pricing schemas for variants that have them
        let pricingSchemaIds = Set(variants.compactMap { $0.pricingSchemaId })
        if !pricingSchemaIds.isEmpty {
            let schemasResponse = try await supabase
                .from("pricing_schemas")
                .select("id, name, tiers")
                .in("id", values: pricingSchemaIds.map { $0.uuidString })
                .execute()

            let schemas = try decoder.decode([PricingSchema].self, from: schemasResponse.data)
            let schemasById = Dictionary(uniqueKeysWithValues: schemas.map { ($0.id, $0) })

            for i in variants.indices {
                if let schemaId = variants[i].pricingSchemaId {
                    variants[i].pricingSchema = schemasById[schemaId]
                }
            }
        }

        Log.network.info("✅ Fetched \(variants.count) variants for product")
        return variants
    }

    /// Fetch products with variants attached - OPTIMIZED with parallel fetching
    static func fetchProductsWithVariants(storeId: UUID, locationId: UUID) async throws -> [Product] {
        // First fetch products normally
        var products = try await fetchProducts(storeId: storeId, locationId: locationId)
        let productIds = products.map { $0.id }

        guard !productIds.isEmpty else { return products }

        // Fetch variants, variant inventory, and COAs IN PARALLEL (3x faster)
        async let variantsTask = fetchVariantsSafe(for: productIds)
        async let variantInventoryTask = fetchVariantInventoryBatchSafe(productIds: productIds, locationId: locationId)
        async let coasTask = fetchCOAsSafe(for: productIds)

        let (variantsByProduct, variantInventoryByProduct, coasByProduct) = await (variantsTask, variantInventoryTask, coasTask)

        // Attach variants to products with their inventory
        for i in products.indices {
            if var variants = variantsByProduct[products[i].id] {
                // Attach inventory to each variant if available
                let productInventory = variantInventoryByProduct[products[i].id] ?? []
                for j in variants.indices {
                    if let inv = productInventory.first(where: { $0.variantTemplateId == variants[j].variantTemplateId }) {
                        variants[j].inventory = VariantInventory(
                            id: inv.id,
                            productId: products[i].id,
                            variantTemplateId: inv.variantTemplateId,
                            locationId: locationId,
                            quantity: Decimal(inv.quantity),
                            heldQuantity: Decimal(inv.heldQuantity ?? 0)
                        )
                    }
                }
                products[i].variants = variants
            }

            // Attach COA
            products[i].coa = coasByProduct[products[i].id]
        }

        let productsWithVariants = products.filter { $0.hasVariants }.count
        let productsWithCOA = products.filter { $0.coa != nil }.count
        Log.network.info("✅ Loaded \(products.count) products (\(productsWithVariants) with variants, \(productsWithCOA) with COAs)")

        return products
    }

    // MARK: - Safe Parallel Fetchers (don't throw - return empty on error)

    private static func fetchVariantsSafe(for productIds: [UUID]) async -> [UUID: [ProductVariant]] {
        do {
            return try await fetchVariants(for: productIds)
        } catch {
            Log.network.error("⚠️ Failed to fetch variants: \(error.localizedDescription)")
            return [:]
        }
    }

    private static func fetchVariantInventoryBatchSafe(productIds: [UUID], locationId: UUID) async -> [UUID: [VariantInventoryData]] {
        do {
            return try await fetchVariantInventoryBatch(productIds: productIds, locationId: locationId)
        } catch {
            Log.network.error("⚠️ Failed to fetch variant inventory: \(error.localizedDescription)")
            return [:]
        }
    }

    private static func fetchCOAsSafe(for productIds: [UUID]) async -> [UUID: ProductCOA] {
        do {
            return try await fetchCOAs(for: productIds)
        } catch {
            Log.network.error("⚠️ Failed to fetch COAs: \(error.localizedDescription)")
            return [:]
        }
    }

    // MARK: - Pricing Schema Fetching

    /// Fetch a pricing schema by ID
    static func fetchPricingSchema(id: UUID) async throws -> PricingSchema? {
        Log.network.info("💰 Fetching pricing schema: \(id.uuidString)")

        let response = try await supabase
            .from("pricing_schemas")
            .select("id, name, tiers")
            .eq("id", value: id.uuidString)
            .limit(1)
            .execute()

        let decoder = JSONDecoder()
        let schemas = try decoder.decode([PricingSchema].self, from: response.data)
        return schemas.first
    }

    // MARK: - Store Product Fields

    /// Fetch store product field definitions (for custom field labels)
    /// These define the display labels and types for product custom_fields
    static func fetchStoreProductFields(storeId: UUID, categoryId: UUID? = nil) async throws -> [StoreProductField] {
        Log.network.info("🏷️ Fetching store product fields for store: \(storeId.uuidString)")

        let response: Data
        if let categoryId = categoryId {
            // Fetch fields for specific category
            response = try await supabase
                .from("store_product_fields")
                .select("""
                    id,
                    store_id,
                    category_id,
                    field_id,
                    field_definition,
                    sort_order
                """)
                .eq("store_id", value: storeId.uuidString)
                .eq("category_id", value: categoryId.uuidString)
                .order("sort_order", ascending: true)
                .execute()
                .data
        } else {
            // Fetch all fields for store
            response = try await supabase
                .from("store_product_fields")
                .select("""
                    id,
                    store_id,
                    category_id,
                    field_id,
                    field_definition,
                    sort_order
                """)
                .eq("store_id", value: storeId.uuidString)
                .order("sort_order", ascending: true)
                .execute()
                .data
        }

        let decoder = JSONDecoder()
        let fields = try decoder.decode([StoreProductField].self, from: response)

        Log.network.info("✅ Fetched \(fields.count) store product fields")
        return fields
    }

    /// Fetch field definitions for a specific category (or all if no category)
    /// Returns a dictionary mapping field_id to StoreProductField for quick lookup
    static func fetchFieldDefinitions(storeId: UUID, categoryId: UUID? = nil) async throws -> [String: StoreProductField] {
        let fields = try await fetchStoreProductFields(storeId: storeId, categoryId: categoryId)
        return Dictionary(uniqueKeysWithValues: fields.map { ($0.fieldId, $0) })
    }

    // MARK: - Product Updates

    /// Update a single product field
    static func updateProductField(
        productId: UUID,
        storeId: UUID,
        field: String,
        value: Any?
    ) async throws {
        Log.network.info("✏️ Updating product \(productId.uuidString) field: \(field)")

        let session = try await supabase.auth.session

        // Build update payload
        var updates: [String: Any] = [
            field: value as Any,
            "updated_at": ISO8601DateFormatter().string(from: Date())
        ]

        let rpcUrl = SupabaseConfig.url.appendingPathComponent("rest/v1/products")
            .appending(queryItems: [
                URLQueryItem(name: "id", value: "eq.\(productId.uuidString)"),
                URLQueryItem(name: "store_id", value: "eq.\(storeId.uuidString)")
            ])

        var request = URLRequest(url: rpcUrl)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: updates)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            Log.network.error("❌ Update failed: \(errorMessage)")
            throw ProductUpdateError.updateFailed(errorMessage)
        }

        Log.network.info("✅ Product field updated: \(field)")
    }

    /// Update product custom_fields (merges with existing)
    static func updateCustomField(
        productId: UUID,
        storeId: UUID,
        fieldKey: String,
        value: String
    ) async throws {
        Log.network.info("✏️ Updating custom field '\(fieldKey)' for product \(productId.uuidString)")

        // First fetch current custom_fields
        let response = try await supabase
            .from("products")
            .select("custom_fields")
            .eq("id", value: productId.uuidString)
            .limit(1)
            .execute()

        struct CustomFieldsRow: Decodable {
            let customFields: [String: AnyCodable]?

            enum CodingKeys: String, CodingKey {
                case customFields = "custom_fields"
            }
        }

        let decoder = JSONDecoder()
        let rows = try decoder.decode([CustomFieldsRow].self, from: response.data)
        var currentFields = rows.first?.customFields ?? [:]

        // Update the specific field
        currentFields[fieldKey] = AnyCodable(value)

        // Convert back to [String: Any] for update
        var fieldsDict: [String: Any] = [:]
        for (key, val) in currentFields {
            fieldsDict[key] = val.value
        }

        try await updateProductField(
            productId: productId,
            storeId: storeId,
            field: "custom_fields",
            value: fieldsDict
        )

        Log.network.info("✅ Custom field updated: \(fieldKey)")
    }

}

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

// MARK: - ProductService Extension (continued)

extension ProductService {

    // MARK: - Variant Inventory Fetching

    /// Fetch variant inventory for a product at a location
    static func fetchVariantInventory(productId: UUID, locationId: UUID) async throws -> [VariantInventoryData] {
        Log.network.info("📦 Fetching variant inventory for product: \(productId.uuidString)")

        let response = try await supabase
            .from("variant_inventory")
            .select("""
                id,
                variant_template_id,
                quantity,
                category_variant_templates (
                    variant_name,
                    conversion_ratio
                )
            """)
            .eq("product_id", value: productId.uuidString)
            .eq("location_id", value: locationId.uuidString)
            .execute()

        let decoder = JSONDecoder()
        let inventories = try decoder.decode([VariantInventoryData].self, from: response.data)

        Log.network.info("✅ Fetched \(inventories.count) variant inventory records")
        return inventories
    }

    /// Fetch variant inventory for multiple products at a location (batch)
    static func fetchVariantInventoryBatch(productIds: [UUID], locationId: UUID) async throws -> [UUID: [VariantInventoryData]] {
        guard !productIds.isEmpty else { return [:] }

        Log.network.info("📦 Fetching variant inventory for \(productIds.count) products")

        let productIdStrings = productIds.map { $0.uuidString }

        let response = try await supabase
            .from("variant_inventory")
            .select("""
                id,
                product_id,
                variant_template_id,
                quantity,
                category_variant_templates (
                    variant_name,
                    conversion_ratio
                )
            """)
            .in("product_id", values: productIdStrings)
            .eq("location_id", value: locationId.uuidString)
            .execute()

        let decoder = JSONDecoder()
        let inventories = try decoder.decode([VariantInventoryDataWithProduct].self, from: response.data)

        // Group by product_id
        var inventoryByProduct: [UUID: [VariantInventoryData]] = [:]
        for inv in inventories {
            let data = VariantInventoryData(
                id: inv.id,
                variantTemplateId: inv.variantTemplateId,
                quantity: inv.quantity,
                heldQuantity: inv.heldQuantity,
                categoryVariantTemplates: inv.categoryVariantTemplates
            )
            inventoryByProduct[inv.productId, default: []].append(data)
        }

        Log.network.info("✅ Fetched variant inventory for \(inventoryByProduct.count) products")
        return inventoryByProduct
    }
}

// MARK: - Variant Inventory Data With Product (for batch fetch)

private struct VariantInventoryDataWithProduct: Codable {
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

// MARK: - Variant Inventory Data (raw from DB)

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

    // Manual initializer for batch fetch
    init(id: UUID, variantTemplateId: UUID, quantity: Double, heldQuantity: Double?, categoryVariantTemplates: CategoryVariantTemplateData?) {
        self.id = id
        self.variantTemplateId = variantTemplateId
        self.quantity = quantity
        self.heldQuantity = heldQuantity
        self.categoryVariantTemplates = categoryVariantTemplates
    }
}

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
    // Note: created_at/updated_at excluded - not needed and date format issues

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
