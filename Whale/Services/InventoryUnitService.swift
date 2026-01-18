//
//  InventoryUnitService.swift
//  Whale
//
//  Service for managing inventory units with QR tracking.
//  Handles bulk registration, conversions, scans, and lookups.
//
//  ## Architecture Note: Direct DB Access for Scans
//
//  This service intentionally uses DIRECT Supabase queries for scan operations
//  instead of Edge Functions. This is a deliberate performance trade-off:
//
//  - **Edge Functions** (used for: register, convert): ~200-400ms latency
//  - **Direct DB** (used for: scan, lookup): ~50-100ms latency
//
//  For warehouse workflows with rapid barcode scanning, the 150-300ms savings
//  per scan compounds significantly (e.g., scanning 100 units = 15-30 sec saved).
//
//  The business logic remains minimal in these direct queries:
//  - Scan: Insert audit record + update location (no calculations)
//  - Lookup: Simple SELECT with filters (no transformations)
//
//  Complex operations (registration, conversion) still use Edge Functions
//  where the latency trade-off is acceptable for the validation benefits.
//

import Foundation
import Supabase
import os.log

// MARK: - Inventory Unit Service

@MainActor
final class InventoryUnitService {
    static let shared = InventoryUnitService()

    private let logger = Logger(subsystem: "com.whale", category: "InventoryUnitService")

    // Edge function URL
    private var functionURL: String {
        "\(SupabaseConfig.baseURL)/functions/v1/inventory-units"
    }

    private init() {}

    // MARK: - Register Bulk Units

    /// Register new inventory units with QR codes (bulk/distribution)
    func registerBulkUnits(
        product: Product,
        tier: ConversionTier,
        quantity: Int,
        batchNumber: String?,
        binLocation: String?,
        storeId: UUID,
        locationId: UUID,
        userId: UUID?
    ) async throws -> [InventoryUnit] {
        logger.info("Registering \(quantity) bulk units for product \(product.name)")

        var units: [InventoryUnit] = []

        for i in 0..<quantity {
            let body: [String: Any] = [
                "action": "register",
                "store_id": storeId.uuidString,
                "product_id": product.id.uuidString,
                "location_id": locationId.uuidString,
                "tier_id": tier.id,
                "tier_label": tier.label,
                "quantity": tier.quantity,
                "base_unit": tier.baseUnit,
                "batch_number": batchNumber ?? "",
                "bin_location": binLocation ?? "",
                "qr_prefix": tier.qrPrefix,
                "label_template": tier.labelTemplate,
                "product_name": product.name,
                "product_image_url": product.featuredImage ?? "",
                "user_id": userId?.uuidString ?? ""
            ]

            let result: RegisterUnitResponse = try await callFunction(body: body)

            if result.success, let unit = result.unit {
                var mutableUnit = unit
                mutableUnit.productName = product.name
                mutableUnit.productSKU = product.sku
                if let imageUrl = product.featuredImage {
                    mutableUnit.productImageURL = URL(string: imageUrl)
                }
                units.append(mutableUnit)
                logger.debug("Registered unit \(i + 1)/\(quantity): \(unit.qrCode)")
            } else {
                logger.error("Failed to register unit \(i + 1): \(result.error ?? "Unknown error")")
            }
        }

        logger.info("Successfully registered \(units.count)/\(quantity) units")
        return units
    }

    // MARK: - Convert Unit

    /// Convert a bulk unit into smaller portions
    func convert(
        sourceQRCode: String,
        targetTierId: String,
        targetTierLabel: String,
        targetQuantity: Int,
        storeId: UUID,
        locationId: UUID,
        userId: UUID?,
        binLocations: [String] = [],
        notes: String? = nil
    ) async throws -> ConversionResult {
        logger.info("Converting \(sourceQRCode) to \(targetQuantity)x \(targetTierId)")

        let body: [String: Any] = [
            "action": "convert",
            "store_id": storeId.uuidString,
            "source_qr_code": sourceQRCode,
            "target_tier_id": targetTierId,
            "target_tier_label": targetTierLabel,
            "target_quantity": targetQuantity,
            "location_id": locationId.uuidString,
            "user_id": userId?.uuidString ?? "",
            "bin_locations": binLocations,
            "notes": notes ?? ""
        ]

        let result: ConversionResult = try await callFunction(body: body)

        if result.success {
            logger.info("Conversion complete: \(result.summary?.portionsCreated ?? 0) portions created")
        } else {
            logger.error("Conversion failed: \(result.error ?? "Unknown error")")
        }

        return result
    }

    // MARK: - Scan Unit

    /// Record a scan operation on an inventory unit (direct DB insert for speed)
    /// Automatically handles transfers when scanned at a different location
    func scan(
        qrCode: String,
        operation: ScanOperation,
        storeId: UUID,
        locationId: UUID,
        userId: UUID?,
        transferId: UUID? = nil,
        orderId: UUID? = nil,
        newStatus: String? = nil,
        newBinLocation: String? = nil,
        notes: String? = nil
    ) async throws -> ScanResult {
        logger.info("Scanning \(qrCode) for operation: \(operation.rawValue)")
        print("📱 Direct scan: \(operation.rawValue) for \(qrCode)")

        // First, find the inventory unit
        let unitResponse = try await supabase
            .from("inventory_units")
            .select()
            .eq("qr_code", value: qrCode)
            .eq("store_id", value: storeId.uuidString)
            .limit(1)
            .execute()

        guard let rawJSON = String(data: unitResponse.data, encoding: .utf8),
              rawJSON != "[]" else {
            print("❌ Unit not found: \(qrCode)")
            return ScanResult(success: false, scan: nil, unit: nil, found: false, error: "Unit not found")
        }

        // Parse unit to get ID and current status
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: dateString) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: dateString) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date")
        }

        let units = try decoder.decode([InventoryUnit].self, from: unitResponse.data)
        guard let unit = units.first else {
            return ScanResult(success: false, scan: nil, unit: nil, found: false, error: "Unit not found")
        }

        // Check if this is a transfer (scanned at different location)
        let isTransfer = unit.currentLocationId != locationId
        let actualOperation: ScanOperation = isTransfer && operation == .receiving ? .transferIn : operation

        // Get location names
        var fromLocationName: String?
        var toLocationName: String?

        if let locResponse = try? await supabase
            .from("locations")
            .select("id, name")
            .in("id", values: [unit.currentLocationId.uuidString, locationId.uuidString])
            .execute() {
            if let locs = try? JSONDecoder().decode([[String: String]].self, from: locResponse.data) {
                for loc in locs {
                    if loc["id"] == unit.currentLocationId.uuidString {
                        fromLocationName = loc["name"]
                    }
                    if loc["id"] == locationId.uuidString {
                        toLocationName = loc["name"]
                    }
                }
            }
        }

        // Build notes with transfer info
        var scanNotes = notes ?? ""
        if isTransfer && actualOperation == .transferIn {
            let transferNote = "Auto-transfer from \(fromLocationName ?? "Unknown") to \(toLocationName ?? "Unknown")"
            scanNotes = scanNotes.isEmpty ? transferNote : "\(transferNote) | \(scanNotes)"
            print("🚚 Auto-transfer detected: \(fromLocationName ?? "?") → \(toLocationName ?? "?")")
        }

        // Insert scan record
        let scanId = UUID()

        struct ScanInsert: Encodable {
            let id: String
            let store_id: String
            let inventory_unit_id: String
            let qr_code: String
            let operation: String
            let operation_status: String
            let location_id: String
            let location_name: String
            let scanned_by_user_id: String
            let previous_status: String
            let new_status: String
            let previous_location_id: String
            let new_location_id: String
            let quantity_affected: Double
            let notes: String
        }

        let scanRecord = ScanInsert(
            id: scanId.uuidString,
            store_id: storeId.uuidString,
            inventory_unit_id: unit.id.uuidString,
            qr_code: qrCode,
            operation: actualOperation.rawValue,
            operation_status: "success",
            location_id: locationId.uuidString,
            location_name: toLocationName ?? "",
            scanned_by_user_id: userId?.uuidString ?? "",
            previous_status: unit.status.rawValue,
            new_status: newStatus ?? unit.status.rawValue,
            previous_location_id: unit.currentLocationId.uuidString,
            new_location_id: locationId.uuidString,
            quantity_affected: unit.quantity,
            notes: scanNotes
        )

        try await supabase
            .from("inventory_unit_scans")
            .insert(scanRecord)
            .execute()

        print("✅ Scan recorded: \(scanId) (\(actualOperation.rawValue))")

        // Update unit location and optionally status/bin
        let now = ISO8601DateFormatter().string(from: Date())

        struct UnitUpdate: Encodable {
            var current_location_id: String
            var updated_at: String
            var bin_location: String?
            var status: String?
            var status_changed_at: String?
        }

        var unitUpdate = UnitUpdate(
            current_location_id: locationId.uuidString,
            updated_at: now,
            bin_location: nil,
            status: nil,
            status_changed_at: nil
        )

        if let bin = newBinLocation, !bin.isEmpty {
            unitUpdate.bin_location = bin
        }

        if let newStatus = newStatus {
            unitUpdate.status = newStatus
            unitUpdate.status_changed_at = now
        }

        try await supabase
            .from("inventory_units")
            .update(unitUpdate)
            .eq("id", value: unit.id.uuidString)
            .execute()

        print("✅ Unit location updated to: \(toLocationName ?? locationId.uuidString)")

        // TODO: Update inventory counts (deduct from source, add to destination)
        // This would update a separate inventory_levels table if you have one

        return ScanResult(success: true, scan: nil, unit: unit, found: true, error: nil)
    }

    // MARK: - Lookup

    /// Get full details for a QR code
    func lookup(qrCode: String, storeId: UUID? = nil) async throws -> LookupResult {
        logger.info("Looking up QR code: \(qrCode)")
        print("🔍 InventoryUnitService.lookup called with qrCode: \(qrCode)")

        // First try direct database lookup (faster and more reliable)
        do {
            let directResult = try await lookupDirect(qrCode: qrCode, storeId: storeId)
            if directResult.found {
                print("✅ Direct lookup found unit")
                return directResult
            }
        } catch {
            print("⚠️ Direct lookup failed, trying edge function: \(error)")
        }

        // Fallback to edge function
        var body: [String: Any] = [
            "action": "lookup",
            "qr_code": qrCode
        ]

        if let storeId = storeId {
            body["store_id"] = storeId.uuidString
        }

        print("🔍 Request body: \(body)")

        do {
            let result: LookupResult = try await callFunction(body: body)
            print("✅ Lookup response - success: \(result.success), found: \(result.found), error: \(result.error ?? "none")")
            return result
        } catch {
            print("❌ Lookup failed with error: \(error)")
            throw error
        }
    }

    /// Direct database lookup for inventory unit
    private func lookupDirect(qrCode: String, storeId: UUID?) async throws -> LookupResult {
        print("🔍 Direct DB lookup for: \(qrCode)")

        // Query the inventory_units table directly
        var query = supabase
            .from("inventory_units")
            .select()
            .eq("qr_code", value: qrCode)

        if let storeId = storeId {
            query = query.eq("store_id", value: storeId.uuidString)
        }

        let response = try await query.limit(1).execute()

        // Log raw response for debugging
        if let rawJSON = String(data: response.data, encoding: .utf8) {
            print("📦 Raw DB response: \(rawJSON.prefix(1000))")
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            // Try ISO8601 with fractional seconds
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: dateString) {
                return date
            }

            // Try without fractional seconds
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: dateString) {
                return date
            }

            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date format: \(dateString)")
        }

        do {
            let units = try decoder.decode([InventoryUnit].self, from: response.data)
            print("✅ Decoded \(units.count) units")

            if let unit = units.first {
                print("✅ Found unit in database: \(unit.id)")

                // Fetch product info
                var productInfo: ProductInfo?
                if let productResponse = try? await supabase
                    .from("products")
                    .select("id, name, sku, featured_image")
                    .eq("id", value: unit.productId.uuidString)
                    .single()
                    .execute() {
                    productInfo = try? decoder.decode(ProductInfo.self, from: productResponse.data)
                }

                // Fetch location info
                var locationInfo: LocationInfo?
                if let locationResponse = try? await supabase
                    .from("locations")
                    .select("id, name, type")
                    .eq("id", value: unit.currentLocationId.uuidString)
                    .single()
                    .execute() {
                    locationInfo = try? decoder.decode(LocationInfo.self, from: locationResponse.data)
                }

                return LookupResult(
                    success: true,
                    found: true,
                    qrCode: QRCodeRecord(id: unit.qrCodeId ?? unit.id, code: unit.qrCode, name: unit.productName, type: unit.qrPrefix),
                    unit: unit,
                    product: productInfo,
                    location: locationInfo,
                    lineage: nil,
                    children: nil,
                    scanHistory: nil,
                    error: nil
                )
            }

            print("⚠️ No unit found in database for: \(qrCode)")
            return LookupResult(
                success: true,
                found: false,
                qrCode: nil,
                unit: nil,
                product: nil,
                location: nil,
                lineage: nil,
                children: nil,
                scanHistory: nil,
                error: "Unit not found"
            )
        } catch {
            print("❌ Decode error: \(error)")
            // Print detailed error info
            if let decodingError = error as? DecodingError {
                switch decodingError {
                case .keyNotFound(let key, let context):
                    print("❌ Missing key: \(key.stringValue) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                case .typeMismatch(let type, let context):
                    print("❌ Type mismatch: expected \(type) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                case .valueNotFound(let type, let context):
                    print("❌ Value not found: \(type) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                case .dataCorrupted(let context):
                    print("❌ Data corrupted: \(context.debugDescription)")
                @unknown default:
                    print("❌ Unknown decoding error")
                }
            }
            throw error
        }
    }

    // MARK: - Sale from Portion

    /// Draw quantity from a tracked portion for retail sale
    func saleFromPortion(
        sourceQRCode: String,
        quantityToSell: Double,
        storeId: UUID,
        locationId: UUID,
        orderId: UUID?,
        customerId: UUID?,
        userId: UUID?,
        pricingTierId: String?,
        unitPrice: Decimal?,
        productName: String?,
        productImageUrl: String?
    ) async throws -> SaleFromPortionResult {
        logger.info("Selling \(quantityToSell)g from \(sourceQRCode)")

        var body: [String: Any] = [
            "action": "sale_from_portion",
            "store_id": storeId.uuidString,
            "source_qr_code": sourceQRCode,
            "quantity_to_sell": quantityToSell,
            "location_id": locationId.uuidString,
            "user_id": userId?.uuidString ?? ""
        ]

        if let orderId = orderId {
            body["order_id"] = orderId.uuidString
        }
        if let customerId = customerId {
            body["customer_id"] = customerId.uuidString
        }
        if let pricingTierId = pricingTierId {
            body["pricing_tier_id"] = pricingTierId
        }
        if let unitPrice = unitPrice {
            body["unit_price"] = NSDecimalNumber(decimal: unitPrice).doubleValue
        }
        if let productName = productName {
            body["product_name"] = productName
        }
        if let productImageUrl = productImageUrl {
            body["product_image_url"] = productImageUrl
        }

        return try await callFunction(body: body)
    }

    // MARK: - Get Available Units

    /// Get available inventory units at a location for a product
    func getAvailableUnits(
        productId: UUID,
        storeId: UUID,
        locationId: UUID?,
        tierIds: [String]? = nil
    ) async throws -> [InventoryUnit] {
        logger.info("Fetching available units for product \(productId)")

        var query = supabase
            .from("inventory_units")
            .select()
            .eq("product_id", value: productId.uuidString)
            .eq("store_id", value: storeId.uuidString)
            .eq("status", value: "available")

        if let locationId = locationId {
            query = query.eq("current_location_id", value: locationId.uuidString)
        }

        if let tierIds = tierIds, !tierIds.isEmpty {
            query = query.in("tier_id", values: tierIds)
        }

        let response = try await query
            .order("received_at", ascending: true)
            .execute()

        let units = try JSONDecoder().decode([InventoryUnit].self, from: response.data)
        logger.info("Found \(units.count) available units")
        return units
    }

    // MARK: - Get Conversion Tiers

    /// Get conversion tier template for a category
    func getConversionTiers(categoryId: UUID, storeId: UUID) async throws -> [ConversionTier] {
        logger.info("Fetching conversion tiers for category \(categoryId)")

        let response = try await supabase
            .from("unit_conversion_tiers")
            .select()
            .eq("category_id", value: categoryId.uuidString)
            .eq("store_id", value: storeId.uuidString)
            .eq("is_active", value: true)
            .single()
            .execute()

        let template = try JSONDecoder().decode(UnitConversionTierTemplate.self, from: response.data)
        logger.info("Found \(template.conversionTiers.count) conversion tiers")
        return template.conversionTiers
    }

    /// Register inventory units from label printing (supports any unit type)
    func registerUnitsFromLabels(
        product: Product,
        labelUnit: (id: String, label: String, quantity: Double, unit: String),
        count: Int,
        batchNumber: String?,
        binLocation: String?,
        storeId: UUID,
        locationId: UUID,
        userId: UUID?
    ) async throws -> [InventoryUnit] {
        logger.info("Registering \(count) units for product \(product.name) at \(labelUnit.label)")

        // Determine QR prefix based on quantity (bulk vs distribution vs retail)
        let qrPrefix: String
        let labelTemplate: String
        if labelUnit.quantity >= 453.6 {
            qrPrefix = "B"  // Bulk (lb+)
            labelTemplate = "bulk"
        } else if labelUnit.quantity >= 28 {
            qrPrefix = "D"  // Distribution (oz+)
            labelTemplate = "distribution"
        } else {
            qrPrefix = "I"  // Individual/retail
            labelTemplate = "retail"
        }

        var units: [InventoryUnit] = []

        for i in 0..<count {
            let body: [String: Any] = [
                "action": "register",
                "store_id": storeId.uuidString,
                "product_id": product.id.uuidString,
                "location_id": locationId.uuidString,
                "tier_id": labelUnit.id,
                "tier_label": labelUnit.label,
                "quantity": labelUnit.quantity,
                "base_unit": labelUnit.unit,
                "batch_number": batchNumber ?? "",
                "bin_location": binLocation ?? "",
                "qr_prefix": qrPrefix,
                "label_template": labelTemplate,
                "product_name": product.name,
                "product_image_url": product.featuredImage ?? "",
                "user_id": userId?.uuidString ?? ""
            ]

            do {
                let result: RegisterUnitResponse = try await callFunction(body: body)

                if result.success, let unit = result.unit {
                    var mutableUnit = unit
                    mutableUnit.productName = product.name
                    mutableUnit.productSKU = product.sku
                    if let imageUrl = product.featuredImage {
                        mutableUnit.productImageURL = URL(string: imageUrl)
                    }
                    units.append(mutableUnit)
                    logger.debug("Registered unit \(i + 1)/\(count): \(unit.qrCode)")
                } else {
                    logger.error("Failed to register unit \(i + 1): \(result.error ?? "Unknown error")")
                }
            } catch {
                logger.error("Error registering unit \(i + 1): \(error.localizedDescription)")
            }
        }

        logger.info("Successfully registered \(units.count)/\(count) units")
        return units
    }

    /// Get default conversion tiers (flower standard)
    func getDefaultFlowerTiers() -> [ConversionTier] {
        return [
            ConversionTier(
                id: "lb",
                label: "Pound (453.6g)",
                quantity: 453.6,
                baseUnit: "g",
                tierLevel: 1,
                locationTypes: ["warehouse"],
                qrPrefix: "B",
                canConvertTo: ["hp", "qp", "oz"],
                labelTemplate: "bulk",
                icon: "cube.box.fill"
            ),
            ConversionTier(
                id: "hp",
                label: "Half Pound (226.8g)",
                quantity: 226.8,
                baseUnit: "g",
                tierLevel: 2,
                locationTypes: ["warehouse", "distribution"],
                qrPrefix: "D",
                canConvertTo: ["qp", "oz"],
                labelTemplate: "distribution",
                icon: "shippingbox.fill"
            ),
            ConversionTier(
                id: "qp",
                label: "Quarter Pound (112g)",
                quantity: 112,
                baseUnit: "g",
                tierLevel: 2,
                locationTypes: ["warehouse", "distribution"],
                qrPrefix: "D",
                canConvertTo: ["oz"],
                labelTemplate: "distribution",
                icon: "shippingbox"
            ),
            ConversionTier(
                id: "oz",
                label: "Ounce (28g)",
                quantity: 28,
                baseUnit: "g",
                tierLevel: 3,
                locationTypes: ["distribution", "retail"],
                qrPrefix: "D",
                canConvertTo: ["retail"],
                labelTemplate: "distribution_small",
                icon: "leaf.fill"
            )
        ]
    }

    // MARK: - Private Helpers

    private func callFunction<T: Decodable>(body: [String: Any]) async throws -> T {
        guard let url = URL(string: functionURL) else {
            throw InventoryUnitError.invalidURL
        }

        print("📡 Calling edge function: \(url)")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Get auth token
        if let session = try? await supabase.auth.session {
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
            print("📡 Auth token attached")
        } else {
            print("⚠️ No auth session available")
        }

        // Add API key
        if let apiKey = Bundle.main.infoDictionary?["SUPABASE_ANON_KEY"] as? String {
            request.setValue(apiKey, forHTTPHeaderField: "apikey")
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw InventoryUnitError.invalidResponse
        }

        print("📡 HTTP Status: \(httpResponse.statusCode)")

        // Log raw response for debugging
        if let rawResponse = String(data: data, encoding: .utf8) {
            print("📡 Raw response: \(rawResponse.prefix(500))")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw InventoryUnitError.serverError(errorResponse.error ?? "Unknown error")
            }
            throw InventoryUnitError.httpError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            print("❌ JSON decode error: \(error)")
            throw error
        }
    }

    // MARK: - Package Transfers

    /// Create a new transfer package
    func createTransfer(
        storeId: UUID,
        sourceLocationId: UUID,
        destinationLocationId: UUID,
        items: [(productId: UUID, quantity: Double)],
        notes: String?,
        userId: UUID?
    ) async throws -> InventoryTransfer {
        print("📦 Creating transfer: \(sourceLocationId) → \(destinationLocationId)")

        // Generate transfer number
        let transferNumber = "TRF-\(Int(Date().timeIntervalSince1970) % 1000000)"

        struct TransferInsert: Encodable {
            let id: String
            let store_id: String
            let transfer_number: String
            let source_location_id: String
            let destination_location_id: String
            let status: String
            let notes: String?
            let created_by_user_id: String?
        }

        let transferId = UUID()
        let transferInsert = TransferInsert(
            id: transferId.uuidString,
            store_id: storeId.uuidString,
            transfer_number: transferNumber,
            source_location_id: sourceLocationId.uuidString,
            destination_location_id: destinationLocationId.uuidString,
            status: "in_transit",
            notes: notes,
            created_by_user_id: userId?.uuidString
        )

        try await supabase
            .from("inventory_transfers")
            .insert(transferInsert)
            .execute()

        // Insert items
        struct ItemInsert: Encodable {
            let transfer_id: String
            let product_id: String
            let quantity: Double
        }

        for item in items {
            let itemInsert = ItemInsert(
                transfer_id: transferId.uuidString,
                product_id: item.productId.uuidString,
                quantity: item.quantity
            )
            try await supabase
                .from("inventory_transfer_items")
                .insert(itemInsert)
                .execute()
        }

        print("✅ Transfer created: \(transferNumber) with \(items.count) items")

        // Return the transfer
        return InventoryTransfer(
            id: transferId,
            storeId: storeId,
            transferNumber: transferNumber,
            sourceLocationId: sourceLocationId,
            destinationLocationId: destinationLocationId,
            status: .inTransit,
            notes: notes,
            trackingNumber: nil,
            shippedAt: Date(),
            receivedAt: nil,
            cancelledAt: nil,
            createdAt: Date(),
            updatedAt: Date(),
            createdByUserId: userId,
            approvedByUserId: nil,
            receivedByUserId: nil,
            cancelledByUserId: nil,
            sourceLocationName: nil,
            destinationLocationName: nil,
            items: nil,
            itemCount: items.count,
            totalQuantity: items.reduce(0) { $0 + $1.quantity }
        )
    }

    /// Lookup a transfer by QR code (P prefix)
    func lookupTransfer(qrCode: String, storeId: UUID) async throws -> TransferLookupResult {
        print("📦 Looking up transfer: \(qrCode)")

        // Extract transfer ID from QR (P + UUID)
        let transferIdString = String(qrCode.dropFirst()) // Remove P prefix
        guard let transferId = UUID(uuidString: transferIdString) else {
            return TransferLookupResult(success: false, found: false, transfer: nil, items: nil, error: "Invalid transfer QR")
        }

        // Fetch transfer with location names
        let response = try await supabase
            .from("inventory_transfers")
            .select("""
                *,
                source:locations!inventory_transfers_source_location_id_fkey(name),
                destination:locations!inventory_transfers_destination_location_id_fkey(name)
            """)
            .eq("id", value: transferId.uuidString)
            .eq("store_id", value: storeId.uuidString)
            .single()
            .execute()

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: dateString) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: dateString) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date")
        }

        var transfer = try decoder.decode(InventoryTransfer.self, from: response.data)

        // Fetch items with product info
        let itemsResponse = try await supabase
            .from("inventory_transfer_items")
            .select("""
                *,
                product:products(name, sku, featured_image)
            """)
            .eq("transfer_id", value: transferId.uuidString)
            .execute()

        let items = try decoder.decode([InventoryTransferItem].self, from: itemsResponse.data)
        transfer.items = items

        print("✅ Found transfer \(transfer.transferNumber) with \(items.count) items")

        return TransferLookupResult(
            success: true,
            found: true,
            transfer: transfer,
            items: items,
            error: nil
        )
    }

    /// Receive a transfer package (mark as completed, update inventory)
    func receiveTransfer(
        transferId: UUID,
        storeId: UUID,
        locationId: UUID,
        userId: UUID?,
        itemConditions: [UUID: ItemCondition]? = nil
    ) async throws -> Bool {
        print("📦 Receiving transfer: \(transferId)")

        let now = ISO8601DateFormatter().string(from: Date())

        // 1. Get transfer details including source/destination
        struct TransferInfo: Decodable {
            let id: UUID
            let source_location_id: UUID
            let destination_location_id: UUID
            let store_id: UUID
        }

        let transferResponse = try await supabase
            .from("inventory_transfers")
            .select("id, source_location_id, destination_location_id, store_id")
            .eq("id", value: transferId.uuidString)
            .single()
            .execute()

        let transfer = try JSONDecoder().decode(TransferInfo.self, from: transferResponse.data)
        print("📦 Transfer: \(transfer.source_location_id) → \(transfer.destination_location_id)")

        // 2. Get transfer items with product info and qr_code_id
        struct TransferItem: Decodable {
            let id: UUID
            let product_id: UUID
            let quantity: Double
            let qr_code_id: UUID?
        }

        let itemsResponse = try await supabase
            .from("inventory_transfer_items")
            .select("id, product_id, quantity, qr_code_id")
            .eq("transfer_id", value: transferId.uuidString)
            .execute()

        let items = try JSONDecoder().decode([TransferItem].self, from: itemsResponse.data)
        print("📦 Processing \(items.count) items")

        // 3. For each item, update inventory (deduct from source, add to destination)
        for item in items {
            print("📦 Processing item: product=\(item.product_id), qty=\(item.quantity)")

            // For QR-based transfers, skip inventory table updates
            // The QR code itself tracks location - no need to modify inventory table
            if item.qr_code_id != nil {
                print("📦 QR-based transfer - skipping inventory table updates (QR code is source of truth)")

                // Still update the transfer item's received_quantity
                struct ItemUpdate: Encodable {
                    let received_quantity: Double
                    let updated_at: String
                }
                try await supabase
                    .from("inventory_transfer_items")
                    .update(ItemUpdate(received_quantity: item.quantity, updated_at: now))
                    .eq("id", value: item.id.uuidString)
                    .execute()
                print("📦 Updated transfer item received_quantity: \(item.quantity)")

                continue
            }

            // 3a. Deduct from source location inventory
            // First check if inventory record exists at source
            let sourceInvResponse = try await supabase
                .from("inventory")
                .select("id, quantity")
                .eq("product_id", value: item.product_id.uuidString)
                .eq("location_id", value: transfer.source_location_id.uuidString)
                .limit(1)
                .execute()

            struct InvRecord: Decodable {
                let id: UUID
                let quantity: Double
            }

            let sourceRecords = try JSONDecoder().decode([InvRecord].self, from: sourceInvResponse.data)

            if let sourceInv = sourceRecords.first {
                let newSourceQty = max(0, sourceInv.quantity - item.quantity)

                struct InvUpdate: Encodable {
                    let quantity: Double
                    let updated_at: String
                }

                try await supabase
                    .from("inventory")
                    .update(InvUpdate(quantity: newSourceQty, updated_at: now))
                    .eq("id", value: sourceInv.id.uuidString)
                    .execute()

                print("📦 Source inventory updated: \(sourceInv.quantity) → \(newSourceQty)")

                // Log transfer_out transaction
                struct TransactionInsert: Encodable {
                    let store_id: String
                    let location_id: String
                    let product_id: String
                    let inventory_id: String
                    let transaction_type: String
                    let quantity_before: Double
                    let quantity_change: Double
                    let quantity_after: Double
                    let reason: String
                    let reference_type: String
                    let reference_id: String
                    let performed_by_user_id: String?
                }

                let outTxn = TransactionInsert(
                    store_id: transfer.store_id.uuidString,
                    location_id: transfer.source_location_id.uuidString,
                    product_id: item.product_id.uuidString,
                    inventory_id: sourceInv.id.uuidString,
                    transaction_type: "transfer_out",
                    quantity_before: sourceInv.quantity,
                    quantity_change: -item.quantity,
                    quantity_after: newSourceQty,
                    reason: "Transfer to destination",
                    reference_type: "inventory_transfer",
                    reference_id: transferId.uuidString,
                    performed_by_user_id: userId?.uuidString
                )

                try await supabase
                    .from("inventory_transactions")
                    .insert(outTxn)
                    .execute()

                print("📦 Logged transfer_out transaction")
            }

            // 3b. Add to destination location inventory
            let destInvResponse = try await supabase
                .from("inventory")
                .select("id, quantity")
                .eq("product_id", value: item.product_id.uuidString)
                .eq("location_id", value: transfer.destination_location_id.uuidString)
                .limit(1)
                .execute()

            let destRecords = try JSONDecoder().decode([InvRecord].self, from: destInvResponse.data)

            if let destInv = destRecords.first {
                // Update existing record
                let newDestQty = destInv.quantity + item.quantity

                struct InvUpdate: Encodable {
                    let quantity: Double
                    let updated_at: String
                }

                try await supabase
                    .from("inventory")
                    .update(InvUpdate(quantity: newDestQty, updated_at: now))
                    .eq("id", value: destInv.id.uuidString)
                    .execute()

                print("📦 Destination inventory updated: \(destInv.quantity) → \(newDestQty)")

                // Log transfer_in transaction
                struct TransactionInsert: Encodable {
                    let store_id: String
                    let location_id: String
                    let product_id: String
                    let inventory_id: String
                    let transaction_type: String
                    let quantity_before: Double
                    let quantity_change: Double
                    let quantity_after: Double
                    let reason: String
                    let reference_type: String
                    let reference_id: String
                    let performed_by_user_id: String?
                }

                let inTxn = TransactionInsert(
                    store_id: transfer.store_id.uuidString,
                    location_id: transfer.destination_location_id.uuidString,
                    product_id: item.product_id.uuidString,
                    inventory_id: destInv.id.uuidString,
                    transaction_type: "transfer_in",
                    quantity_before: destInv.quantity,
                    quantity_change: item.quantity,
                    quantity_after: newDestQty,
                    reason: "Transfer from source",
                    reference_type: "inventory_transfer",
                    reference_id: transferId.uuidString,
                    performed_by_user_id: userId?.uuidString
                )

                try await supabase
                    .from("inventory_transactions")
                    .insert(inTxn)
                    .execute()

                print("📦 Logged transfer_in transaction")
            } else {
                // Create new inventory record at destination
                struct InvInsert: Encodable {
                    let store_id: String
                    let location_id: String
                    let product_id: String
                    let quantity: Double
                }

                let newInv = InvInsert(
                    store_id: transfer.store_id.uuidString,
                    location_id: transfer.destination_location_id.uuidString,
                    product_id: item.product_id.uuidString,
                    quantity: item.quantity
                )

                let insertResponse = try await supabase
                    .from("inventory")
                    .insert(newInv)
                    .select("id")
                    .single()
                    .execute()

                struct InsertedInv: Decodable {
                    let id: UUID
                }

                let insertedInv = try JSONDecoder().decode(InsertedInv.self, from: insertResponse.data)

                print("📦 Created new inventory record at destination: \(insertedInv.id)")

                // Log transfer_in transaction for new record
                struct TransactionInsert: Encodable {
                    let store_id: String
                    let location_id: String
                    let product_id: String
                    let inventory_id: String
                    let transaction_type: String
                    let quantity_before: Double
                    let quantity_change: Double
                    let quantity_after: Double
                    let reason: String
                    let reference_type: String
                    let reference_id: String
                    let performed_by_user_id: String?
                }

                let inTxn = TransactionInsert(
                    store_id: transfer.store_id.uuidString,
                    location_id: transfer.destination_location_id.uuidString,
                    product_id: item.product_id.uuidString,
                    inventory_id: insertedInv.id.uuidString,
                    transaction_type: "transfer_in",
                    quantity_before: 0,
                    quantity_change: item.quantity,
                    quantity_after: item.quantity,
                    reason: "Transfer from source (new location)",
                    reference_type: "inventory_transfer",
                    reference_id: transferId.uuidString,
                    performed_by_user_id: userId?.uuidString
                )

                try await supabase
                    .from("inventory_transactions")
                    .insert(inTxn)
                    .execute()

                print("📦 Logged transfer_in transaction for new record")
            }

            // 3c. Update any linked QR code
            if let qrCodeId = item.qr_code_id {
                struct QRUpdate: Encodable {
                    let status: String
                    let current_transfer_id: String?
                    let location_id: String
                    let updated_at: String
                }

                try await supabase
                    .from("qr_codes")
                    .update(QRUpdate(
                        status: "available",
                        current_transfer_id: nil,
                        location_id: transfer.destination_location_id.uuidString,
                        updated_at: now
                    ))
                    .eq("id", value: qrCodeId.uuidString)
                    .execute()

                print("📦 Updated QR code \(qrCodeId) - status=available, location=destination")
            }

            // Update item received_quantity and condition
            struct ItemUpdate: Encodable {
                let received_quantity: Double
                let updated_at: String
                var condition: String?
            }

            var itemUpdate = ItemUpdate(received_quantity: item.quantity, updated_at: now)
            if let conditions = itemConditions, let condition = conditions[item.id] {
                itemUpdate.condition = condition.rawValue
            }

            try await supabase
                .from("inventory_transfer_items")
                .update(itemUpdate)
                .eq("id", value: item.id.uuidString)
                .execute()
        }

        // 4. Mark transfer as completed
        struct TransferUpdate: Encodable {
            let status: String
            let received_at: String
            let received_by_user_id: String?
            let updated_at: String
        }

        let update = TransferUpdate(
            status: "completed",
            received_at: now,
            received_by_user_id: userId?.uuidString,
            updated_at: now
        )

        try await supabase
            .from("inventory_transfers")
            .update(update)
            .eq("id", value: transferId.uuidString)
            .execute()

        print("✅ Transfer received with \(items.count) items - inventory updated!")
        return true
    }
}

// MARK: - Scan Operation

enum ScanOperation: String, Sendable {
    case receiving
    case transferOut = "transfer_out"
    case transferIn = "transfer_in"
    case conversionIn = "conversion_in"
    case conversionOut = "conversion_out"
    case audit
    case sale
    case damage
    case adjustment
    case lookup
    case reprint
    case binMove = "bin_move"
}

// MARK: - Errors

enum InventoryUnitError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case serverError(String)
    case unitNotFound
    case insufficientQuantity

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid service URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .serverError(let message):
            return message
        case .unitNotFound:
            return "Inventory unit not found"
        case .insufficientQuantity:
            return "Insufficient quantity available"
        }
    }
}

private struct ErrorResponse: Decodable {
    let success: Bool
    let error: String?
}
