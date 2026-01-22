//
//  OrderService.swift
//  Whale
//
//  Order operations with Supabase.
//  - Fetching with real-time subscriptions
//  - Atomic POS order creation with idempotency
//
//  ARCHITECTURE NOTE (2026-01-01):
//  Order filtering and permission logic has been moved to the database.
//  This service now uses RPC functions for:
//  - get_orders_for_location: Location-aware order fetching with filters
//  - update_order_status: Permission-checked status updates
//  - is_order_visible_to_location: Realtime visibility checks
//  - get_next_order_status: Status workflow transitions
//

import Foundation
import Supabase
import os.log

// MARK: - Order Service Errors

enum OrderServiceError: LocalizedError {
    case duplicateOrder(existingOrderNumber: String)
    case invalidCart
    case databaseError(String)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .duplicateOrder(let orderNumber):
            return "Order already exists: \(orderNumber)"
        case .invalidCart:
            return "Invalid cart data"
        case .databaseError(let message):
            return "Database error: \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        }
    }
}

// MARK: - Order Service

enum OrderService {

    /// Fetch a single order by ID with all joins (v_store_customers, items, locations, order_locations)
    static func fetchOrder(orderId: UUID) async throws -> Order? {
        Log.network.debug("Fetching order: \(orderId.uuidString)")

        let response = try await supabase
            .from("orders")
            .select("""
                *,
                v_store_customers(
                    first_name,
                    last_name,
                    email,
                    phone
                ),
                pickup_location:pickup_location_id(
                    name
                ),
                order_items(
                    id,
                    order_id,
                    product_id,
                    product_name,
                    quantity,
                    unit_price,
                    line_total,
                    location_id,
                    pickup_location_name,
                    location:location_id(
                        name
                    )
                ),
                order_locations(
                    id,
                    order_id,
                    location_id,
                    item_count,
                    total_quantity,
                    fulfillment_status,
                    notes,
                    tracking_number,
                    tracking_url,
                    shipping_label_url,
                    shipping_carrier,
                    shipping_service,
                    shipping_cost,
                    shipped_at,
                    fulfilled_at,
                    created_at,
                    updated_at,
                    location:location_id(
                        name,
                        address_line1,
                        city,
                        state
                    )
                )
            """)
            .eq("id", value: orderId.uuidString)
            .limit(1)
            .execute()

        let data = response.data

        // Debug: Log raw response
        if let jsonString = String(data: data, encoding: .utf8) {
            Log.network.debug("OrderService.fetchOrder raw response: \(jsonString.prefix(2000))")
        }

        let orders = try await Task.detached {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([Order].self, from: data)
        }.value

        // Debug: Log parsed order
        if let order = orders.first {
            Log.network.debug("OrderService.fetchOrder parsed: items=\(order.items?.count ?? 0), pickupLocation=\(order.pickupLocation?.name ?? "nil"), firstItemLocation=\(order.items?.first?.pickupLocationName ?? "nil")")
        }

        return orders.first
    }

    /// Fetch orders for a store at a specific location using backend RPC with filters
    /// All filtering logic is now in the database
    static func fetchOrdersWithFilters(
        storeId: UUID,
        locationId: UUID,
        statusGroup: String? = nil,
        orderType: String? = nil,
        paymentStatus: String? = nil,
        search: String? = nil,
        dateStart: Date? = nil,
        dateEnd: Date? = nil,
        amountMin: Decimal? = nil,
        amountMax: Decimal? = nil,
        onlineOnly: Bool = false,
        limit: Int = 200
    ) async throws -> [Order] {
        Log.network.info("Fetching orders via RPC for store: \(storeId.uuidString), location: \(locationId.uuidString)")

        // Build RPC parameters
        var params: [String: AnyJSON] = [
            "p_store_id": .string(storeId.uuidString),
            "p_location_id": .string(locationId.uuidString),
            "p_limit": .integer(limit)
        ]

        if let statusGroup = statusGroup {
            params["p_status_group"] = .string(statusGroup)
        }
        if let orderType = orderType {
            params["p_order_type"] = .string(orderType)
        }
        if let paymentStatus = paymentStatus {
            params["p_payment_status"] = .string(paymentStatus)
        }
        if let search = search {
            params["p_search"] = .string(search)
        }
        if let dateStart = dateStart {
            params["p_date_start"] = .string(ISO8601DateFormatter().string(from: dateStart))
        }
        if let dateEnd = dateEnd {
            params["p_date_end"] = .string(ISO8601DateFormatter().string(from: dateEnd))
        }
        if let amountMin = amountMin {
            params["p_amount_min"] = .double(NSDecimalNumber(decimal: amountMin).doubleValue)
        }
        if let amountMax = amountMax {
            params["p_amount_max"] = .double(NSDecimalNumber(decimal: amountMax).doubleValue)
        }
        if onlineOnly {
            params["p_online_only"] = .bool(true)
        }

        let response = try await supabase
            .rpc("get_orders_for_location", params: params)
            .execute()

        // Decode off main thread to avoid blocking UI
        let data = response.data
        let orders = try await Task.detached {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            // RPC returns array of {order_data: jsonb}
            struct RPCResult: Decodable {
                let order_data: Order
            }
            let results = try decoder.decode([RPCResult].self, from: data)
            return results.map { $0.order_data }
        }.value

        Log.network.info("Fetched \(orders.count) orders via RPC (already filtered by location)")

        return orders
    }

    /// Legacy fetch method - now calls the RPC version
    static func fetchOrders(storeId: UUID, locationId: UUID) async throws -> [Order] {
        return try await fetchOrdersWithFilters(storeId: storeId, locationId: locationId)
    }

    /// Check if an order is visible to a location (for realtime updates)
    static func isOrderVisibleToLocation(orderId: UUID, locationId: UUID) async throws -> Bool {
        let response = try await supabase
            .rpc("is_order_visible_to_location", params: [
                "p_order_id": AnyJSON.string(orderId.uuidString),
                "p_location_id": AnyJSON.string(locationId.uuidString)
            ])
            .execute()

        let decoder = JSONDecoder()
        return try decoder.decode(Bool.self, from: response.data)
    }

    /// Update order status via RPC with permission check
    static func updateOrderStatusViaRPC(orderId: UUID, locationId: UUID, status: OrderStatus, userId: UUID?) async throws {
        Log.network.info("Updating order \(orderId.uuidString) to \(status.rawValue) via RPC")

        var params: [String: AnyJSON] = [
            "p_order_id": .string(orderId.uuidString),
            "p_location_id": .string(locationId.uuidString),
            "p_new_status": .string(status.rawValue)
        ]

        if let userId = userId {
            params["p_user_id"] = .string(userId.uuidString)
        }

        let response = try await supabase
            .rpc("update_order_status", params: params)
            .execute()

        // Parse response
        struct UpdateResult: Decodable {
            let success: Bool
            let error: String?
        }

        let decoder = JSONDecoder()
        let result = try decoder.decode(UpdateResult.self, from: response.data)

        guard result.success else {
            throw NSError(
                domain: "OrderService",
                code: 403,
                userInfo: [NSLocalizedDescriptionKey: result.error ?? "Permission denied"]
            )
        }

        Log.network.info("Order status updated successfully via RPC")
    }

    /// Get the next valid status for an order
    static func getNextOrderStatus(orderId: UUID) async throws -> (nextStatus: OrderStatus?, actionLabel: String?) {
        let response = try await supabase
            .rpc("get_next_order_status", params: [
                "p_order_id": AnyJSON.string(orderId.uuidString)
            ])
            .execute()

        struct NextStatusResult: Decodable {
            let current_status: String?
            let next_status: String?
            let order_type: String?
            let action_label: String?
        }

        let decoder = JSONDecoder()
        let result = try decoder.decode(NextStatusResult.self, from: response.data)

        let nextStatus = result.next_status.flatMap { OrderStatus(rawValue: $0) }
        return (nextStatus, result.action_label)
    }

    /// Get order items separated by location (for display in OrderDetailModal)
    static func getOrderItemsForLocation(orderId: UUID, locationId: UUID) async throws -> (forLocation: [OrderItem], other: [OrderItem]) {
        let response = try await supabase
            .rpc("get_order_items_for_location", params: [
                "p_order_id": AnyJSON.string(orderId.uuidString),
                "p_location_id": AnyJSON.string(locationId.uuidString)
            ])
            .execute()

        struct ItemsResult: Decodable {
            let items_for_location: [OrderItem]
            let items_other: [OrderItem]
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let result = try decoder.decode(ItemsResult.self, from: response.data)

        return (result.items_for_location, result.items_other)
    }

    /// Update order status with user attribution
    static func updateOrderStatus(orderId: UUID, status: OrderStatus, updatedByUserId: UUID? = nil) async throws {
        Log.network.info("Updating order \(orderId.uuidString) to status: \(status.rawValue), by user: \(updatedByUserId?.uuidString ?? "unknown")")

        // Build update payload with user attribution
        var updateData: [String: String] = [
            "status": status.rawValue,
            "updated_at": ISO8601DateFormatter().string(from: Date())
        ]

        // Include user attribution for triggers to capture
        if let userId = updatedByUserId {
            updateData["updated_by_user_id"] = userId.uuidString
        }

        // Use select() to get the updated row back - if RLS blocks, we get empty array
        let response = try await supabase
            .from("orders")
            .update(updateData)
            .eq("id", value: orderId.uuidString)
            .select("id")
            .execute()

        // Check if update was actually applied (RLS may silently block)
        let decoder = JSONDecoder()
        struct IdOnly: Decodable { let id: UUID }
        let updated = try? decoder.decode([IdOnly].self, from: response.data)

        if updated?.isEmpty != false {
            Log.network.error("Order update blocked by RLS or order not found")
            throw NSError(domain: "OrderService", code: 403, userInfo: [
                NSLocalizedDescriptionKey: "Permission denied. Please log out and log back in."
            ])
        }

        Log.network.info("Order status updated successfully")
    }

    /// Update order notes with user attribution
    static func updateOrderNotes(orderId: UUID, notes: String, updatedByUserId: UUID? = nil) async throws {
        var updateData: [String: String] = [
            "staff_notes": notes,
            "updated_at": ISO8601DateFormatter().string(from: Date())
        ]

        if let userId = updatedByUserId {
            updateData["updated_by_user_id"] = userId.uuidString
        }

        try await supabase
            .from("orders")
            .update(updateData)
            .eq("id", value: orderId.uuidString)
            .execute()
    }

    /// Update tracking info with user attribution
    static func updateTracking(orderId: UUID, trackingNumber: String, carrier: String, updatedByUserId: UUID? = nil) async throws {
        var trackingUrl: String?
        switch carrier.lowercased() {
        case "usps":
            trackingUrl = "https://tools.usps.com/go/TrackConfirmAction?tLabels=\(trackingNumber)"
        case "ups":
            trackingUrl = "https://www.ups.com/track?tracknum=\(trackingNumber)"
        case "fedex":
            trackingUrl = "https://www.fedex.com/fedextrack/?trknbr=\(trackingNumber)"
        default:
            break
        }

        var updateData: [String: String] = [
            "tracking_number": trackingNumber,
            "shipping_carrier": carrier,
            "updated_at": ISO8601DateFormatter().string(from: Date())
        ]
        if let url = trackingUrl {
            updateData["tracking_url"] = url
        }
        if let userId = updatedByUserId {
            updateData["updated_by_user_id"] = userId.uuidString
        }

        try await supabase
            .from("orders")
            .update(updateData)
            .eq("id", value: orderId.uuidString)
            .execute()
    }

    // NOTE: POS order creation is now handled by the payment-intent Edge Function.
    // The backend creates orders atomically after successful payment processing.
    // See: supabase/functions/payment-intent/index.ts

    // MARK: - Print Optimized Fetch

    /// Fetch order with complete product details for label printing (OPTIMIZED)
    /// Uses single RPC call with database-side joins instead of multiple queries
    /// Returns order + full product data (images, custom fields, COAs) in one round trip
    static func fetchOrderForPrinting(orderId: UUID) async throws -> OrderPrintData? {
        Log.network.info("Fetching order for printing: \(orderId.uuidString)")

        let response = try await supabase
            .rpc("get_order_for_printing", params: [
                "p_order_id": AnyJSON.string(orderId.uuidString)
            ])
            .execute()

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // DEBUG: Log raw JSON response
        if let jsonString = String(data: response.data, encoding: .utf8) {
            print("🏷️ RPC raw response: \(jsonString.prefix(500))")
        }

        // Check for error response
        struct ErrorResponse: Decodable {
            let error: String?
        }

        if let errorResponse = try? decoder.decode(ErrorResponse.self, from: response.data),
           let error = errorResponse.error {
            Log.network.warning("Order not found for printing: \(error)")
            return nil
        }

        do {
            let result = try decoder.decode(OrderPrintData.self, from: response.data)
            Log.network.info("✅ Fetched order for printing with \(result.items.count) items")
            return result
        } catch {
            print("🏷️ Decoding error: \(error)")
            if let decodingError = error as? DecodingError {
                switch decodingError {
                case .keyNotFound(let key, let context):
                    print("🏷️ Missing key: \(key.stringValue) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                case .typeMismatch(let type, let context):
                    print("🏷️ Type mismatch for type: \(type) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                case .valueNotFound(let type, let context):
                    print("🏷️ Value not found for type: \(type) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                case .dataCorrupted(let context):
                    print("🏷️ Data corrupted at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                @unknown default:
                    print("🏷️ Unknown decoding error: \(error)")
                }
            }
            throw error
        }
    }
}
