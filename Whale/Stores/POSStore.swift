//
//  POSStore_Migrated.swift
//  Whale
//
//  MIGRATED: Cart operations now go through CartService → Backend
//
//  BEFORE: 668 lines with local cart logic
//  AFTER: ~200 lines - just state holding and API calls
//
//  The app is now a dumb terminal:
//  - addToCart() → POST /cart/add → render returned cart
//  - No local price calculations
//  - No local discount logic
//  - Server is the source of truth
//

import Foundation
import SwiftUI
import Combine
import os.log

// MARK: - POS Store (Migrated)

@MainActor
final class POSStore: ObservableObject {

    // MARK: - Products State (unchanged)

    private(set) var products: [Product] = []
    private(set) var categories: [ProductCategory] = []
    private(set) var isLoadingProducts = false
    private(set) var productsError: String?

    @Published var searchText = ""
    @Published var selectedCategoryId: UUID?

    // MARK: - Server-Side Carts

    /// All active carts (one per customer)
    @Published private(set) var carts: [ServerCart] = []

    /// Currently selected cart index
    @Published var activeCartIndex: Int = -1

    /// Loading state for cart operations
    @Published private(set) var isCartLoading = false
    @Published private(set) var cartError: String?

    func clearCartError() {
        cartError = nil
    }

    // MARK: - Computed Properties

    var activeCart: ServerCart? {
        guard activeCartIndex >= 0 && activeCartIndex < carts.count else { return nil }
        return carts[activeCartIndex]
    }

    var cartItems: [CartItem] {
        activeCart?.items.map { CartItem(from: $0) } ?? []
    }

    /// Server cart items (native type)
    var serverCartItems: [ServerCartItem] {
        activeCart?.items ?? []
    }

    var cartTotal: Decimal {
        activeCart?.total ?? 0
    }

    var cartItemCount: Int {
        activeCart?.itemCount ?? 0
    }

    var hasCartItems: Bool {
        activeCart?.items.isEmpty == false
    }

    /// Currently selected customer (from active cart)
    var selectedCustomer: Customer? {
        // This needs to be looked up from the customer ID
        // For now, we store customers locally when they're added
        guard let customerId = activeCart?.customerId else { return nil }
        return _customerCache[customerId]
    }

    /// Customer cache (populated when customers are added)
    private var _customerCache: [UUID: Customer] = [:]

    /// Look up customer by ID from cache
    func customer(for customerId: UUID?) -> Customer? {
        guard let id = customerId else { return nil }
        return _customerCache[id]
    }

    var filteredProducts: [Product] {
        var result = products

        if let categoryId = selectedCategoryId {
            result = result.filter { $0.primaryCategoryId == categoryId }
        }

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { product in
                product.name.lowercased().contains(query) ||
                product.sku?.lowercased().contains(query) == true
            }
        }

        return result
    }

    // MARK: - Context

    private var storeId: UUID?
    private var locationId: UUID?

    // MARK: - Singleton

    static let shared = POSStore()
    private init() {}

    // MARK: - Configuration

    func configure(storeId: UUID, locationId: UUID) {
        Log.cart.info("POSStore.configure called - storeId: \(storeId), locationId: \(locationId)")
        self.storeId = storeId
        self.locationId = locationId
    }

    // MARK: - Customer Cart Management

    /// Add a customer - creates server-side cart and switches to it
    func addCustomer(_ customer: Customer) async {
        guard let storeId = storeId, let locationId = locationId else {
            let storeIdStr = self.storeId?.uuidString ?? "nil"
            let locationIdStr = self.locationId?.uuidString ?? "nil"
            cartError = "Missing store or location (storeId: \(storeIdStr), locationId: \(locationIdStr))"
            Log.cart.error("addCustomer failed: Missing store or location - storeId: \(storeIdStr), locationId: \(locationIdStr)")
            return
        }

        // Check if customer already has a cart locally
        if let existingIndex = carts.firstIndex(where: { $0.customerId == customer.id }) {
            activeCartIndex = existingIndex
            return
        }

        isCartLoading = true
        cartError = nil

        do {
            Log.cart.info("Creating cart for customer \(customer.id) at location \(locationId)")
            // Get or create cart on server
            let cart = try await CartService.shared.getOrCreateCart(
                storeId: storeId,
                locationId: locationId,
                customerId: customer.id
            )
            Log.cart.info("Cart created successfully: \(cart.id)")
            // Cache customer FIRST so it's available when view re-renders
            _customerCache[customer.id] = customer
            // Calculate new index BEFORE modifying arrays to avoid race conditions
            let newIndex = carts.count
            // Append cart and set index together, then notify
            carts.append(cart)
            activeCartIndex = newIndex
            // Explicitly notify observers since customer cache changed (not @Published)
            objectWillChange.send()
        } catch {
            Log.cart.error("Failed to create cart: \(error)")
            cartError = error.localizedDescription
        }

        isCartLoading = false
    }

    /// Switch to a customer's cart
    func switchToCustomer(_ customerId: UUID) {
        if let index = carts.firstIndex(where: { $0.customerId == customerId }) {
            activeCartIndex = index
        }
    }

    /// Switch to cart at specific index
    func switchToCartAtIndex(_ index: Int) {
        guard index >= 0 && index < carts.count else { return }
        activeCartIndex = index
    }

    /// Remove a customer's cart
    func removeCustomer(_ customerId: UUID) {
        guard let index = carts.firstIndex(where: { $0.customerId == customerId }) else { return }

        carts.remove(at: index)

        if carts.isEmpty {
            activeCartIndex = -1
        } else if activeCartIndex >= carts.count {
            activeCartIndex = carts.count - 1
        } else if activeCartIndex > index {
            activeCartIndex -= 1
        }
    }

    /// Clear all carts
    func clearAllCarts() {
        carts.removeAll()
        activeCartIndex = -1
    }

    /// Load a cart by ID from server (for queue integration)
    /// Returns true if cart was loaded and selected
    @discardableResult
    func loadCartById(_ cartId: UUID) async -> Bool {
        // Check if already loaded
        if let existingIndex = carts.firstIndex(where: { $0.id == cartId }) {
            activeCartIndex = existingIndex
            return true
        }

        // Fetch from server
        do {
            guard let cart = try await CartService.shared.getCart(cartId: cartId) else {
                Log.cart.error("loadCartById: Cart not found on server: \(cartId)")
                return false
            }

            // Cache customer if available
            if let customerId = cart.customerId {
                // We don't have customer details from cart, but we can use placeholder
                // The queue entry should have the customer name
            }

            let newIndex = carts.count
            carts.append(cart)
            activeCartIndex = newIndex
            Log.cart.info("loadCartById: Loaded cart \(cartId) from server, now at index \(newIndex)")
            return true
        } catch {
            Log.cart.error("loadCartById: Failed to load cart \(cartId): \(error)")
            return false
        }
    }

    // MARK: - Cart Item Actions (Sync Wrappers for UI)
    // These fire-and-forget to maintain UI responsiveness

    /// Add product to cart (fire-and-forget for UI)
    func addToCart(_ product: Product, quantity: Int = 1, priceOverride: Decimal? = nil) {
        Task { await addToCartAsync(product, quantity: quantity, priceOverride: priceOverride) }
    }

    /// Add product with tier (fire-and-forget for UI)
    func addToCart(_ product: Product, tier: PricingTier) {
        Task { await addToCartAsync(product, tier: tier) }
    }

    /// Add product variant with tier (fire-and-forget for UI)
    func addToCart(_ product: Product, tier: PricingTier, variant: ProductVariant) {
        Task { await addToCartAsync(product, tier: tier, variant: variant) }
    }

    /// Update item quantity (fire-and-forget for UI)
    func updateCartItemQuantity(_ itemId: UUID, quantity: Int) {
        Task { await updateCartItemQuantityAsync(itemId, quantity: quantity) }
    }

    /// Remove item from cart (fire-and-forget for UI)
    func removeFromCart(_ itemId: UUID) {
        Task { await removeFromCartAsync(itemId) }
    }

    /// Clear cart (fire-and-forget for UI)
    func clearCart() {
        Task { await clearCartAsync() }
    }

    /// Apply manual discount (fire-and-forget for UI)
    func applyManualDiscount(itemId: UUID, type: ManualDiscountType, value: Decimal) {
        Task { await applyManualDiscountAsync(itemId: itemId, type: type, value: value) }
    }

    /// Remove manual discount (fire-and-forget for UI)
    func removeManualDiscount(itemId: UUID) {
        Task { await removeManualDiscountAsync(itemId: itemId) }
    }

    // MARK: - Cart Item Actions (Async - Server-Side)

    /// Add product to the active cart (calls server)
    private func addToCartAsync(_ product: Product, quantity: Int = 1, priceOverride: Decimal? = nil) async {
        guard let cart = activeCart else {
            cartError = "No active cart"
            return
        }

        isCartLoading = true
        cartError = nil

        do {
            let updatedCart = try await CartService.shared.addToCart(
                cartId: cart.id,
                productId: product.id,
                quantity: quantity,
                unitPrice: priceOverride ?? product.displayPrice,
                inventoryId: product.inventory?.id
            )
            updateLocalCart(updatedCart)
        } catch {
            cartError = error.localizedDescription
        }

        isCartLoading = false
    }

    /// Add product with pricing tier
    private func addToCartAsync(_ product: Product, tier: PricingTier) async {
        guard let cart = activeCart else {
            cartError = "No active cart"
            return
        }

        isCartLoading = true
        cartError = nil

        do {
            let updatedCart = try await CartService.shared.addToCart(
                cartId: cart.id,
                productId: product.id,
                quantity: 1,
                unitPrice: tier.defaultPrice,
                tierLabel: tier.label,
                tierQuantity: tier.quantity,
                inventoryId: product.inventory?.id
            )
            updateLocalCart(updatedCart)
        } catch {
            cartError = error.localizedDescription
        }

        isCartLoading = false
    }

    /// Add product variant with tier
    private func addToCartAsync(_ product: Product, tier: PricingTier, variant: ProductVariant) async {
        guard let cart = activeCart else {
            cartError = "No active cart"
            return
        }

        isCartLoading = true
        cartError = nil

        do {
            let updatedCart = try await CartService.shared.addToCart(
                cartId: cart.id,
                productId: product.id,
                quantity: 1,
                unitPrice: tier.defaultPrice,
                tierLabel: tier.label,
                tierQuantity: tier.quantity,
                variantId: variant.variantTemplateId,
                variantName: variant.variantName,
                conversionRatio: variant.conversionRatio,
                inventoryId: product.inventory?.id
            )
            updateLocalCart(updatedCart)
        } catch {
            cartError = error.localizedDescription
        }

        isCartLoading = false
    }

    /// Update item quantity
    private func updateCartItemQuantityAsync(_ itemId: UUID, quantity: Int) async {
        guard let cart = activeCart else { return }

        isCartLoading = true
        cartError = nil

        do {
            let updatedCart = try await CartService.shared.updateItemQuantity(
                cartId: cart.id,
                itemId: itemId,
                quantity: quantity
            )
            updateLocalCart(updatedCart)
        } catch {
            cartError = error.localizedDescription
        }

        isCartLoading = false
    }

    /// Remove item from cart
    private func removeFromCartAsync(_ itemId: UUID) async {
        guard let cart = activeCart else { return }

        isCartLoading = true
        cartError = nil

        do {
            let updatedCart = try await CartService.shared.removeFromCart(
                cartId: cart.id,
                itemId: itemId
            )
            updateLocalCart(updatedCart)
        } catch {
            cartError = error.localizedDescription
        }

        isCartLoading = false
    }

    /// Clear all items from active cart
    private func clearCartAsync() async {
        guard let cart = activeCart else { return }

        isCartLoading = true
        cartError = nil

        do {
            let updatedCart = try await CartService.shared.clearCart(cartId: cart.id)
            updateLocalCart(updatedCart)
        } catch {
            cartError = error.localizedDescription
        }

        isCartLoading = false
    }

    // MARK: - Discounts (Async - Server-Side)

    /// Apply manual discount to a cart item
    private func applyManualDiscountAsync(itemId: UUID, type: ManualDiscountType, value: Decimal) async {
        guard let cart = activeCart else { return }

        isCartLoading = true
        cartError = nil

        do {
            let updatedCart = try await CartService.shared.applyItemDiscount(
                cartId: cart.id,
                itemId: itemId,
                type: type.rawValue,
                value: value
            )
            updateLocalCart(updatedCart)
        } catch {
            cartError = error.localizedDescription
        }

        isCartLoading = false
    }

    /// Remove manual discount from item
    private func removeManualDiscountAsync(itemId: UUID) async {
        guard let cart = activeCart else { return }

        do {
            // Pass nil/0 to clear discount
            let updatedCart = try await CartService.shared.applyItemDiscount(
                cartId: cart.id,
                itemId: itemId,
                type: "fixed",  // Type doesn't matter when value is 0
                value: 0
            )
            updateLocalCart(updatedCart)
        } catch {
            cartError = error.localizedDescription
        }
    }

    // MARK: - Checkout

    /// Get checkout totals from server
    func getCheckoutTotals() async throws -> CheckoutTotals {
        guard let cart = activeCart else {
            throw CartError.serverError("No active cart")
        }
        return try await CartService.shared.calculateCheckout(cartId: cart.id)
    }

    // MARK: - Helpers

    private func updateLocalCart(_ updatedCart: ServerCart) {
        guard let index = carts.firstIndex(where: { $0.id == updatedCart.id }) else { return }
        carts[index] = updatedCart
    }

    // MARK: - Product Loading (unchanged)

    func loadProducts() async {
        guard let storeId = storeId, let locationId = locationId else {
            productsError = "Missing store or location"
            return
        }

        isLoadingProducts = true
        productsError = nil

        do {
            products = try await ProductService.fetchProductsWithVariants(storeId: storeId, locationId: locationId)

            do {
                categories = try await ProductService.fetchCategories(storeId: storeId)
            } catch {
                // Non-fatal
            }
        } catch {
            productsError = error.localizedDescription
        }

        isLoadingProducts = false
    }

    func refresh() async {
        await loadProducts()
    }

    func clearFilters() {
        searchText = ""
        selectedCategoryId = nil
    }
}

// MARK: - Manual Discount Type

enum ManualDiscountType: String, Sendable, Codable {
    case percentage
    case fixed
}

// MARK: - CartItem (Compatibility Layer)

/// CartItem struct for backward compatibility with existing views
/// Wraps ServerCartItem data - uses server-calculated values for pricing
struct CartItem: Identifiable, Sendable, Equatable {
    let id: UUID
    let productId: UUID
    let productName: String
    let unitPrice: Decimal
    var quantity: Int
    let tierQuantity: Double
    let sku: String?
    let tierLabel: String?
    let inventoryId: UUID?
    let variantId: UUID?
    let variantName: String?
    let conversionRatio: Double?
    var manualDiscountType: ManualDiscountType?
    var manualDiscountValue: Decimal?

    // Server-calculated values (no client-side pricing logic)
    let lineTotal: Decimal
    let discountAmount: Decimal

    /// Create from server cart item
    init(from server: ServerCartItem) {
        self.id = server.id
        self.productId = server.productId
        self.productName = server.productName
        self.unitPrice = server.unitPrice
        self.quantity = server.quantity
        self.tierQuantity = server.tierQuantity
        self.sku = server.sku
        self.tierLabel = server.tierLabel
        self.inventoryId = nil  // Not in server response
        self.variantId = server.variantId
        self.variantName = server.variantName
        self.conversionRatio = nil  // Not in server response
        if let type = server.manualDiscountType {
            self.manualDiscountType = ManualDiscountType(rawValue: type)
        }
        self.manualDiscountValue = server.manualDiscountValue

        // Use server-calculated values - no client-side pricing logic
        self.lineTotal = server.lineTotal
        self.discountAmount = server.discountAmount
    }

    /// Original line total before any discounts (for display only)
    var originalLineTotal: Decimal {
        unitPrice * Decimal(quantity)
    }

    /// Effective unit price (derived from server lineTotal for accuracy)
    var effectiveUnitPrice: Decimal {
        guard quantity > 0 else { return unitPrice }
        return lineTotal / Decimal(quantity)
    }

    /// Whether this item has a manual discount applied
    var hasManualDiscount: Bool {
        discountAmount > 0
    }

    /// Display string for the discount (e.g., "10% off" or "$5 off")
    var discountDisplayText: String? {
        guard let discountType = manualDiscountType,
              let discountValue = manualDiscountValue,
              discountValue > 0 else {
            return nil
        }

        switch discountType {
        case .percentage:
            return "\(NSDecimalNumber(decimal: discountValue).intValue)% off"
        case .fixed:
            return "\(CurrencyFormatter.format(discountValue)) off"
        }
    }

    var inventoryDeduction: Double {
        tierQuantity * Double(quantity)
    }

    /// Whether this is a variant sale (e.g., Pre-Roll instead of Flower)
    var isVariantSale: Bool {
        variantId != nil
    }

    /// Display name including variant (e.g., "OG Kush (Pre-Roll)")
    var displayName: String {
        if let variantName = variantName {
            return "\(productName) (\(variantName))"
        }
        return productName
    }
}
