//
//  InventoryService.swift
//  Whale
//
//  Inventory management service for audits and adjustments.
//  Calls atomic database functions to ensure data consistency.
//

import Foundation
import Supabase
import os.log

// MARK: - Adjustment Types

enum AdjustmentType: String, CaseIterable, Sendable {
    case countCorrection = "count_correction"
    case damage = "damage"
    case shrinkage = "shrinkage"
    case theft = "theft"
    case expired = "expired"
    case received = "received"
    case returnAdjustment = "return"
    case other = "other"

    var displayName: String {
        switch self {
        case .countCorrection: return "Count Correction"
        case .damage: return "Damage"
        case .shrinkage: return "Shrinkage"
        case .theft: return "Theft"
        case .expired: return "Expired"
        case .received: return "Received"
        case .returnAdjustment: return "Return"
        case .other: return "Other"
        }
    }
}

// MARK: - Adjustment Result

struct AdjustmentResult: Codable, Sendable {
    let adjustmentId: UUID
    let inventoryId: UUID?
    let quantityBefore: Double
    let quantityAfter: Double
    let quantityChange: Double?
    let productTotalStock: Double

    enum CodingKeys: String, CodingKey {
        case adjustmentId = "adjustment_id"
        case inventoryId = "inventory_id"
        case quantityBefore = "quantity_before"
        case quantityAfter = "quantity_after"
        case quantityChange = "quantity_change"
        case productTotalStock = "product_total_stock"
    }
}

// MARK: - RPC Parameters

private nonisolated(unsafe) struct AdjustmentParams: Encodable, Sendable {
    nonisolated let p_store_id: String
    nonisolated let p_product_id: String
    nonisolated let p_location_id: String
    nonisolated let p_adjustment_type: String
    nonisolated let p_quantity_change: Double
    nonisolated let p_reason: String
    nonisolated let p_notes: String?
    nonisolated let p_created_by: String?
    nonisolated let p_idempotency_key: String
    nonisolated let p_set_absolute: Double?
}

private nonisolated(unsafe) struct ConversionParams: Encodable, Sendable {
    nonisolated let p_product_id: String
    nonisolated let p_variant_template_id: String
    nonisolated let p_location_id: String
    nonisolated let p_parent_quantity_to_convert: Double
    nonisolated let p_notes: String
    nonisolated let p_performed_by_user_id: String?
}

// MARK: - Inventory Service

enum InventoryService {

    /// Create an inventory adjustment (audit)
    /// Uses atomic database function to prevent race conditions
    static func createAdjustment(
        storeId: UUID,
        productId: UUID,
        locationId: UUID,
        adjustmentType: AdjustmentType,
        newQuantity: Double,
        currentQuantity: Double,
        reason: String,
        notes: String? = nil
    ) async throws -> AdjustmentResult {
        Log.network.info("📦 Creating inventory adjustment for product: \(productId.uuidString)")

        // Calculate the change
        let quantityChange = newQuantity - currentQuantity

        // Generate idempotency key
        let idempotencyKey = "adj-\(productId.uuidString)-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(8))"

        // Get current user ID (optional - audit still works without it)
        var userId: String? = nil
        do {
            let session = try await supabase.auth.session
            userId = session.user.id.uuidString
        } catch {
            Log.network.warning("⚠️ Could not get user session for audit attribution: \(error.localizedDescription)")
        }

        // Build RPC parameters
        let params = AdjustmentParams(
            p_store_id: storeId.uuidString,
            p_product_id: productId.uuidString,
            p_location_id: locationId.uuidString,
            p_adjustment_type: adjustmentType.rawValue,
            p_quantity_change: quantityChange,
            p_reason: reason,
            p_notes: notes,
            p_created_by: userId,
            p_idempotency_key: idempotencyKey,
            p_set_absolute: nil
        )

        // Call RPC via Supabase SDK
        let response = try await supabase
            .rpc("process_inventory_adjustment", params: params)
            .execute()

        // Decode result
        let results = try JSONDecoder().decode([AdjustmentResult].self, from: response.data)

        guard let result = results.first else {
            throw InventoryError.noResult
        }

        Log.network.info("✅ Adjustment created: \(result.quantityBefore) → \(result.quantityAfter)")
        return result
    }

    /// Quick audit - set quantity to a new value
    /// Uses absolute value to prevent race conditions with concurrent sales
    static func quickAudit(
        product: Product,
        locationId: UUID,
        newQuantity: Double,
        reason: AdjustmentType = .countCorrection
    ) async throws -> AdjustmentResult {
        guard let storeId = product.storeId else {
            throw InventoryError.missingStoreId
        }

        // Pass the ABSOLUTE target value, not a delta
        // This prevents race conditions when sales happen between UI load and audit submit
        return try await createAbsoluteAdjustment(
            storeId: storeId,
            productId: product.id,
            locationId: locationId,
            adjustmentType: reason,
            absoluteQuantity: newQuantity,
            reason: "Quick audit via POS",
            notes: "Set to \(Int(newQuantity)) (absolute)"
        )
    }

    /// Create adjustment using absolute quantity (race-condition safe)
    static func createAbsoluteAdjustment(
        storeId: UUID,
        productId: UUID,
        locationId: UUID,
        adjustmentType: AdjustmentType,
        absoluteQuantity: Double,
        reason: String,
        notes: String? = nil
    ) async throws -> AdjustmentResult {
        Log.network.info("📦 Creating absolute inventory adjustment for product: \(productId.uuidString) -> \(absoluteQuantity)")

        let idempotencyKey = "adj-\(productId.uuidString)-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(8))"

        // Get current user ID (optional)
        var userId: String? = nil
        do {
            let session = try await supabase.auth.session
            userId = session.user.id.uuidString
        } catch {
            Log.network.warning("⚠️ Could not get user session for audit attribution")
        }

        // Build params with p_set_absolute for race-condition-safe absolute value setting
        let params = AdjustmentParams(
            p_store_id: storeId.uuidString,
            p_product_id: productId.uuidString,
            p_location_id: locationId.uuidString,
            p_adjustment_type: adjustmentType.rawValue,
            p_quantity_change: 0,  // Ignored when p_set_absolute is provided
            p_reason: reason,
            p_notes: notes,
            p_created_by: userId,
            p_idempotency_key: idempotencyKey,
            p_set_absolute: absoluteQuantity
        )

        // Call RPC via Supabase SDK
        let response = try await supabase
            .rpc("process_inventory_adjustment", params: params)
            .execute()

        let results = try JSONDecoder().decode([AdjustmentResult].self, from: response.data)

        guard let result = results.first else {
            throw InventoryError.noResult
        }

        Log.network.info("✅ Absolute adjustment: \(result.quantityBefore) → \(result.quantityAfter)")
        return result
    }

    // MARK: - Variant Conversion

    /// Result of a variant conversion operation
    struct ConversionResult: Codable, Sendable {
        let success: Bool
        let variantQuantityCreated: Double
        let newParentQuantity: Double
        let newVariantQuantity: Double
        let conversionId: UUID?
        let errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case success
            case variantQuantityCreated = "variant_quantity_created"
            case newParentQuantity = "new_parent_quantity"
            case newVariantQuantity = "new_variant_quantity"
            case conversionId = "conversion_id"
            case errorMessage = "error_message"
        }
    }

    /// Convert parent inventory to variant inventory
    /// E.g., convert 7g of flower → 10 pre-rolls (at 0.7g each)
    static func convertToVariant(
        product: Product,
        variant: ProductVariant,
        locationId: UUID,
        unitsToCreate: Int
    ) async throws -> ConversionResult {
        guard let conversionRatio = variant.conversionRatio, conversionRatio > 0 else {
            throw InventoryError.invalidConversionRatio
        }

        // Calculate parent stock to deduct (grams)
        let parentQuantityToConvert = Double(unitsToCreate) * conversionRatio
        let currentParentStock = Double(product.availableStock)

        guard parentQuantityToConvert <= currentParentStock else {
            throw InventoryError.insufficientStock(
                required: parentQuantityToConvert,
                available: currentParentStock
            )
        }

        Log.network.info("🔄 Converting \(parentQuantityToConvert)\(variant.conversionUnit ?? "g") → \(unitsToCreate) \(variant.variantName)")

        // Get current user (optional)
        var userId: String? = nil
        do {
            let session = try await supabase.auth.session
            userId = session.user.id.uuidString
        } catch {
            Log.network.warning("⚠️ Could not get user session for conversion attribution")
        }

        // Build params
        let params = ConversionParams(
            p_product_id: product.id.uuidString,
            p_variant_template_id: variant.variantTemplateId.uuidString,
            p_location_id: locationId.uuidString,
            p_parent_quantity_to_convert: parentQuantityToConvert,
            p_notes: "Converted via POS",
            p_performed_by_user_id: userId
        )

        // Call RPC via Supabase SDK
        let response = try await supabase
            .rpc("convert_parent_to_variant_inventory", params: params)
            .execute()

        let results = try JSONDecoder().decode([ConversionResult].self, from: response.data)

        guard let result = results.first else {
            throw InventoryError.noResult
        }

        if !result.success {
            throw InventoryError.conversionFailed(message: result.errorMessage ?? "Unknown error")
        }

        Log.network.info("✅ Conversion complete: \(Int(result.variantQuantityCreated)) \(variant.variantName) created")
        return result
    }
}

// MARK: - Errors

enum InventoryError: LocalizedError {
    case noResult
    case missingStoreId
    case invalidQuantity
    case invalidResponse
    case invalidConversionRatio
    case insufficientStock(required: Double, available: Double)
    case conversionFailed(message: String)
    case rpcFailed(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .noResult:
            return "No result returned from adjustment"
        case .missingStoreId:
            return "Product is missing store ID"
        case .invalidQuantity:
            return "Invalid quantity value"
        case .invalidResponse:
            return "Invalid server response"
        case .invalidConversionRatio:
            return "Invalid conversion ratio for variant"
        case .insufficientStock(let required, let available):
            return "Insufficient stock: need \(String(format: "%.1f", required)), have \(String(format: "%.1f", available))"
        case .conversionFailed(let message):
            return "Conversion failed: \(message)"
        case .rpcFailed(let statusCode, let message):
            return "RPC failed (\(statusCode)): \(message)"
        }
    }
}
