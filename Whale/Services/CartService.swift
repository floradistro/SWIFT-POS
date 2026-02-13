//
//  CartService.swift
//  Whale
//
//  NEW: Thin client for server-side cart operations.
//  Replaces ~400 lines of local cart logic in POSStore.swift
//
//  The app is now a dumb terminal:
//  - User taps "Add to Cart" → POST /cart
//  - Backend calculates, validates, returns new state
//  - Swift renders result
//

import Foundation
import os.log

// MARK: - Cart Service

actor CartService {
    static let shared = CartService()

    private let baseURL: URL
    private let session: URLSession

    private init() {
        guard let url = URL(string: SupabaseConfig.functionsBaseURL) else {
            fatalError("Invalid Supabase functions URL: \(SupabaseConfig.functionsBaseURL)")
        }
        self.baseURL = url
        self.session = URLSession.shared
    }

    // MARK: - Cart Operations

    /// Create a new cart for a customer
    func createCart(storeId: UUID, locationId: UUID, customerId: UUID?, deviceId: String?) async throws -> ServerCart {
        let response: CartResponse = try await post("cart", body: [
            "action": "create",
            "store_id": storeId.uuidString,
            "location_id": locationId.uuidString,
            "customer_id": customerId?.uuidString as Any,
            "device_id": deviceId as Any
        ])
        guard let cart = response.data else {
            throw CartError.serverError(response.error ?? "Unknown error")
        }
        return cart
    }

    /// Get existing cart
    func getCart(cartId: UUID) async throws -> ServerCart? {
        let response: CartResponse = try await post("cart", body: [
            "action": "get",
            "cart_id": cartId.uuidString
        ])
        return response.data
    }

    /// Get or create cart for customer
    /// Always starts fresh (clears existing items) to prevent abandoned cart items from reappearing
    func getOrCreateCart(storeId: UUID, locationId: UUID, customerId: UUID) async throws -> ServerCart {
        // Try to get existing cart - pass location_id so server updates cart if location changed
        // IMPORTANT: fresh_start=true clears any existing items from previous sessions
        // This prevents the bug where old cart items reappear when a customer is scanned
        let response: CartResponse = try await post("cart", body: [
            "action": "get",
            "customer_id": customerId.uuidString,
            "store_id": storeId.uuidString,
            "location_id": locationId.uuidString,
            "fresh_start": true  // Clear existing items - each checkout is a fresh start
        ])

        if let cart = response.data {
            return cart
        }

        // Create new cart
        return try await createCart(storeId: storeId, locationId: locationId, customerId: customerId, deviceId: nil)
    }

    /// Add item to cart
    func addToCart(
        cartId: UUID,
        productId: UUID,
        quantity: Int = 1,
        unitPrice: Decimal? = nil,
        tierLabel: String? = nil,
        tierQuantity: Double? = nil,
        variantId: UUID? = nil,
        variantName: String? = nil,
        conversionRatio: Double? = nil,
        inventoryId: UUID? = nil
    ) async throws -> ServerCart {
        var body: [String: Any] = [
            "action": "add",
            "cart_id": cartId.uuidString,
            "product_id": productId.uuidString,
            "quantity": quantity
        ]

        if let unitPrice = unitPrice {
            body["unit_price"] = NSDecimalNumber(decimal: unitPrice).doubleValue
        }
        if let tierLabel = tierLabel {
            body["tier_label"] = tierLabel
        }
        if let tierQuantity = tierQuantity {
            body["tier_quantity"] = tierQuantity
        }
        if let variantId = variantId {
            body["variant_id"] = variantId.uuidString
        }
        if let variantName = variantName {
            body["variant_name"] = variantName
        }
        if let conversionRatio = conversionRatio {
            body["conversion_ratio"] = conversionRatio
        }
        if let inventoryId = inventoryId {
            body["inventory_id"] = inventoryId.uuidString
        }

        let response: CartResponse = try await post("cart", body: body)
        guard let cart = response.data else {
            throw CartError.serverError(response.error ?? "Failed to add item")
        }
        return cart
    }

    /// Update item quantity
    func updateItemQuantity(cartId: UUID, itemId: UUID, quantity: Int) async throws -> ServerCart {
        let response: CartResponse = try await post("cart", body: [
            "action": "update",
            "cart_id": cartId.uuidString,
            "item_id": itemId.uuidString,
            "quantity": quantity
        ])
        guard let cart = response.data else {
            throw CartError.serverError(response.error ?? "Failed to update item")
        }
        return cart
    }

    /// Apply line item discount
    func applyItemDiscount(cartId: UUID, itemId: UUID, type: String, value: Decimal) async throws -> ServerCart {
        let response: CartResponse = try await post("cart", body: [
            "action": "update",
            "cart_id": cartId.uuidString,
            "item_id": itemId.uuidString,
            "discount_type": type,
            "discount_value": NSDecimalNumber(decimal: value).doubleValue
        ])
        guard let cart = response.data else {
            throw CartError.serverError(response.error ?? "Failed to apply discount")
        }
        return cart
    }

    /// Remove item from cart
    func removeFromCart(cartId: UUID, itemId: UUID) async throws -> ServerCart {
        let response: CartResponse = try await post("cart", body: [
            "action": "remove",
            "cart_id": cartId.uuidString,
            "item_id": itemId.uuidString
        ])
        guard let cart = response.data else {
            throw CartError.serverError(response.error ?? "Failed to remove item")
        }
        return cart
    }

    /// Clear all items from cart
    func clearCart(cartId: UUID) async throws -> ServerCart {
        let response: CartResponse = try await post("cart", body: [
            "action": "clear",
            "cart_id": cartId.uuidString
        ])
        guard let cart = response.data else {
            throw CartError.serverError(response.error ?? "Failed to clear cart")
        }
        return cart
    }

    /// Apply cart-level discount
    func applyCartDiscount(cartId: UUID, type: String?, value: Decimal?, loyaltyPoints: Int? = nil) async throws -> ServerCart {
        var body: [String: Any] = [
            "action": "apply_discount",
            "cart_id": cartId.uuidString
        ]

        if let type = type {
            body["discount_type"] = type
            body["discount_value"] = value.map { NSDecimalNumber(decimal: $0).doubleValue } ?? 0
        }
        if let loyaltyPoints = loyaltyPoints {
            body["loyalty_points"] = loyaltyPoints
        }

        let response: CartResponse = try await post("cart", body: body)
        guard let cart = response.data else {
            throw CartError.serverError(response.error ?? "Failed to apply discount")
        }
        return cart
    }

    // MARK: - Checkout Calculation

    /// Get checkout totals with validation and cash suggestions
    func calculateCheckout(cartId: UUID) async throws -> CheckoutTotals {
        let response: CheckoutResponse = try await post("checkout-calculate", body: [
            "cart_id": cartId.uuidString,
            "include_cash_suggestions": true
        ])
        guard let data = response.data else {
            throw CartError.serverError(response.error ?? "Failed to calculate checkout")
        }
        return data.totals
    }

    // MARK: - HTTP Helpers

    private func post<T: Decodable & Sendable>(_ path: String, body: [String: Any]) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        Log.network.debug("CartService POST \(path) - request body: \(body)")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CartError.networkError
        }

        let responseString = String(data: data, encoding: .utf8) ?? "nil"
        Log.network.debug("CartService RESPONSE (\(path)) status=\(httpResponse.statusCode): \(responseString.prefix(1000))")

        guard httpResponse.statusCode == 200 else {
            throw CartError.httpError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            Log.network.error("CartService decode error: \(error)")
            Log.network.error("CartService raw response: \(responseString)")
            throw error
        }
    }
}

// MARK: - Response Types

private struct CartResponse: Decodable, Sendable {
    let success: Bool
    let data: ServerCart?
    let error: String?

    // Custom decoder to handle backend returning partial data (just totals) when no cart exists
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decode(Bool.self, forKey: .success)
        error = try container.decodeIfPresent(String.self, forKey: .error)

        // Try to decode data, but check if it has required fields first
        if container.contains(.data) {
            // Peek at the data to see if it has an 'id' field (indicates a real cart)
            let dataContainer = try? container.nestedContainer(keyedBy: DataKeys.self, forKey: .data)
            if dataContainer?.contains(.id) == true {
                data = try container.decode(ServerCart.self, forKey: .data)
            } else {
                // Backend returned partial data (just totals) - treat as no cart
                data = nil
            }
        } else {
            data = nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case success, data, error
    }

    enum DataKeys: String, CodingKey {
        case id
    }
}

private struct CheckoutResponse: Sendable {
    let success: Bool
    let data: CheckoutData?
    let error: String?

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decode(Bool.self, forKey: .success)
        data = try container.decodeIfPresent(CheckoutData.self, forKey: .data)
        error = try container.decodeIfPresent(String.self, forKey: .error)
    }

    enum CodingKeys: String, CodingKey {
        case success, data, error
    }
}

extension CheckoutResponse: Decodable {}

private struct CheckoutData: Decodable, Sendable {
    let totals: CheckoutTotals
    let cart: ServerCart
}

