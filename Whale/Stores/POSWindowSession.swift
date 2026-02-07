//
//  POSWindowSession.swift
//  Whale
//
//  Per-window POS session state for Stage Manager multi-window support.
//  Each window gets its own independent cart state AND location/register.
//

import Foundation
import SwiftUI
import Combine
import Supabase
import os.log

// MARK: - Environment Key

struct POSWindowSessionKey: EnvironmentKey {
    static let defaultValue: POSWindowSession? = nil
}

extension EnvironmentValues {
    var posWindowSession: POSWindowSession? {
        get { self[POSWindowSessionKey.self] }
        set { self[POSWindowSessionKey.self] = newValue }
    }
}

// MARK: - Window Session Manager

@MainActor
final class POSWindowSessionManager: ObservableObject {
    static let shared = POSWindowSessionManager()

    private var sessions: [UUID: POSWindowSession] = [:]

    // MARK: - Product Cache (shared across sessions at same location)

    private var productCache: [UUID: CachedProducts] = [:]  // keyed by locationId
    private let cacheTimeout: TimeInterval = 60  // 1 minute cache

    struct CachedProducts {
        let products: [Product]
        let categories: [ProductCategory]
        let timestamp: Date

        var isValid: Bool {
            Date().timeIntervalSince(timestamp) < 60
        }
    }

    /// Get cached products for a location, or nil if cache is stale/missing
    func getCachedProducts(for locationId: UUID) -> CachedProducts? {
        guard let cached = productCache[locationId], cached.isValid else {
            return nil
        }
        return cached
    }

    /// Cache products for a location
    func cacheProducts(_ products: [Product], categories: [ProductCategory], for locationId: UUID) {
        productCache[locationId] = CachedProducts(
            products: products,
            categories: categories,
            timestamp: Date()
        )
    }

    /// Invalidate cache for a location (call after inventory changes)
    func invalidateCache(for locationId: UUID) {
        productCache.removeValue(forKey: locationId)
    }

    private init() {}

    /// Get or create a session for the given window session ID
    /// NOTE: This creates a session WITHOUT location - for main window only.
    /// Use createSession() to create multi-window sessions with explicit location.
    func session(for sessionId: UUID) -> POSWindowSession {
        if let existing = sessions[sessionId] {
            return existing
        }

        // Create new session WITHOUT location - main window uses global session/productStore
        // Only explicit createSession() calls should set location (for multi-window)
        let newSession = POSWindowSession(
            sessionId: sessionId,
            location: nil,  // Keep nil so isMultiWindowSession returns false
            register: nil
        )
        sessions[sessionId] = newSession
        Log.session.debug("POSWindowSessionManager: Created main window session \(sessionId) (no location - uses global)")
        return newSession
    }

    /// Create a session with a specific location (for new POS windows)
    /// Also creates a POSSession with default opening cash
    func createSession(sessionId: UUID, location: Location, register: Register?, openingCash: Decimal = 200) -> POSWindowSession {
        let newSession = POSWindowSession(
            sessionId: sessionId,
            location: location,
            register: register
        )

        // Auto-create a POSSession for this window
        if let registerId = register?.id {
            let posSession = POSSession.create(
                locationId: location.id,
                registerId: registerId,
                userId: SessionObserver.shared.publicUserId,
                openingCash: openingCash,
                notes: "Stage Manager window session"
            )
            newSession.setPOSSession(posSession)
        }

        sessions[sessionId] = newSession
        Log.session.info("POSWindowSessionManager: Created new session \(sessionId) at location \(location.name)")
        return newSession
    }

    /// Remove a session when window is closed
    func removeSession(_ sessionId: UUID) {
        sessions.removeValue(forKey: sessionId)
        Log.session.info("POSWindowSessionManager: Removed session \(sessionId)")
    }

    /// Get all active session IDs
    var activeSessionIds: [UUID] {
        Array(sessions.keys)
    }
}

// MARK: - Window Session

@MainActor
final class POSWindowSession: ObservableObject, Identifiable {
    let id: UUID
    let sessionId: UUID

    // MARK: - Location/Register (per-window - each window can operate at different location)

    @Published private(set) var location: Location?
    @Published private(set) var register: Register?
    @Published private(set) var posSession: POSSession?

    // MARK: - Drawer Balance (per-register cash tracking)

    @Published private(set) var drawerBalance: Decimal = 0
    @Published private(set) var openingCash: Decimal = 0
    @Published private(set) var totalSafeDrops: Decimal = 0
    @Published private(set) var cashSalesTotal: Decimal = 0
    @Published private(set) var safeDrops: [SafeDrop] = []

    /// Expected drawer balance = opening + cash sales - safe drops
    var expectedDrawerBalance: Decimal {
        openingCash + cashSalesTotal - totalSafeDrops
    }

    var storeId: UUID? { location?.storeId ?? SessionObserver.shared.storeId }
    var locationId: UUID? { location?.id }

    /// Create and start a POS session for this window
    func startSession(openingCash: Decimal, notes: String?) async throws {
        guard let locationId = locationId,
              let registerId = register?.id else {
            throw POSWindowSessionError.missingLocationOrRegister
        }

        let newSession = POSSession.create(
            locationId: locationId,
            registerId: registerId,
            userId: SessionObserver.shared.publicUserId,
            openingCash: openingCash,
            notes: notes
        )

        // TODO: Save to database via SessionObserver or POSSessionService
        self.posSession = newSession
    }

    /// End the POS session for this window
    func endSession(closingCash: Decimal) async {
        guard var session = posSession else { return }
        session.closingCash = closingCash
        session.closedAt = Date()
        session.status = .closed
        // TODO: Update in database
        self.posSession = nil
    }

    enum POSWindowSessionError: Error {
        case missingLocationOrRegister
    }

    /// Set POS session (called by POSWindowSessionManager during creation)
    func setPOSSession(_ session: POSSession) {
        self.posSession = session
    }

    // MARK: - Register Management

    /// Set or change the register for this session
    func setRegister(_ newRegister: Register) {
        register = newRegister
        // Reset drawer balance when switching registers
        drawerBalance = 0
        openingCash = 0
        cashSalesTotal = 0
        totalSafeDrops = 0
        safeDrops = []
        Log.session.info("POSWindowSession: Register changed to \(newRegister.displayName) (#\(newRegister.registerNumber))")
        objectWillChange.send()
    }

    // MARK: - Drawer Balance Management

    /// Set opening cash for this register session
    func setOpeningCash(_ amount: Decimal) {
        openingCash = amount
        drawerBalance = amount
        Log.session.info("POSWindowSession: Opening cash set to \(amount) for \(self.register?.displayName ?? "unknown register")")
    }

    /// Record a cash sale (adds to drawer balance)
    func recordCashSale(_ amount: Decimal) {
        cashSalesTotal += amount
        drawerBalance += amount
        objectWillChange.send()
        Log.session.info("POSWindowSession: Cash sale +\(amount), drawer now \(self.drawerBalance)")
    }

    /// Perform a safe drop (removes cash from drawer)
    func performSafeDrop(amount: Decimal, notes: String? = nil) async throws {
        guard amount > 0 else { throw DrawerError.invalidAmount }
        guard amount <= drawerBalance else { throw DrawerError.insufficientFunds }

        let drop = SafeDrop(amount: amount, notes: notes)
        safeDrops.append(drop)
        totalSafeDrops += amount
        drawerBalance -= amount
        objectWillChange.send()

        // TODO: Save to database
        Log.session.info("POSWindowSession: Safe drop -\(amount), drawer now \(self.drawerBalance)")
    }

    /// Get drawer summary for end-of-day
    var drawerSummary: DrawerSummary {
        DrawerSummary(
            openingCash: openingCash,
            cashSales: cashSalesTotal,
            safeDrops: totalSafeDrops,
            expectedBalance: expectedDrawerBalance,
            dropCount: safeDrops.count
        )
    }

    // MARK: - Product State (per-window - location-specific inventory)

    @Published private(set) var products: [Product] = []
    @Published private(set) var categories: [ProductCategory] = []
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var hasLoadedProducts = false
    @Published private(set) var productsError: String?
    @Published var searchText = ""
    @Published var selectedCategoryId: UUID?

    /// Filtered products based on search and category
    var filteredProducts: [Product] {
        var result = products

        if let categoryId = selectedCategoryId {
            result = result.filter { $0.primaryCategoryId == categoryId }
        }

        if !searchText.isEmpty {
            let lowercased = searchText.lowercased()
            result = result.filter {
                $0.name.lowercased().contains(lowercased) ||
                ($0.sku?.lowercased().contains(lowercased) ?? false)
            }
        }

        return result
    }

    // MARK: - Cart State (per-window)

    @Published private(set) var carts: [ServerCart] = []
    @Published var activeCartIndex: Int = -1
    @Published private(set) var isCartLoading = false
    @Published private(set) var cartError: String?

    func clearCartError() {
        cartError = nil
    }

    private var _customerCache: [UUID: Customer] = [:]

    // MARK: - Computed Properties

    var activeCart: ServerCart? {
        guard activeCartIndex >= 0 && activeCartIndex < carts.count else { return nil }
        return carts[activeCartIndex]
    }

    var cartItems: [CartItem] {
        activeCart?.items.map { CartItem(from: $0) } ?? []
    }

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

    var selectedCustomer: Customer? {
        guard let customerId = activeCart?.customerId else { return nil }
        return _customerCache[customerId]
    }

    func customer(for customerId: UUID?) -> Customer? {
        guard let id = customerId else { return nil }
        return _customerCache[id]
    }

    // MARK: - Init

    init(sessionId: UUID, location: Location? = nil, register: Register? = nil) {
        self.id = sessionId
        self.sessionId = sessionId
        self.location = location
        self.register = register
        // Don't auto-load here - let the view trigger loading after it's set up observation
    }

    // MARK: - Location Management

    func setLocation(_ location: Location) {
        self.location = location
        // Clear carts when location changes (carts are location-specific)
        carts.removeAll()
        activeCartIndex = -1
        _customerCache.removeAll()
        // Load products for new location
        Task { await loadProducts() }
    }

    // MARK: - Product Loading

    func loadProducts() async {
        guard let storeId = storeId, let locationId = locationId else {
            productsError = "Missing store or location"
            return
        }

        // Skip if already loading
        guard !isLoadingProducts else { return }

        // Check cache first (shared across windows at same location)
        if let cached = POSWindowSessionManager.shared.getCachedProducts(for: locationId) {
            objectWillChange.send()
            products = cached.products
            categories = cached.categories
            Log.session.debug("POSWindowSession: Using cached products for location \(locationId)")
            return
        }

        objectWillChange.send()
        isLoadingProducts = true
        productsError = nil

        do {
            // Load products and categories IN PARALLEL
            async let productsTask = ProductService.fetchProductsWithVariants(storeId: storeId, locationId: locationId)
            async let categoriesTask = ProductService.fetchCategories(storeId: storeId)

            // Wait for both
            let (loadedProducts, loadedCategories) = try await (productsTask, categoriesTask)

            objectWillChange.send()
            products = loadedProducts
            categories = loadedCategories
            isLoadingProducts = false
            hasLoadedProducts = true

            // Cache for other windows at same location
            POSWindowSessionManager.shared.cacheProducts(loadedProducts, categories: loadedCategories, for: locationId)
        } catch {
            objectWillChange.send()
            productsError = error.localizedDescription
            isLoadingProducts = false
            hasLoadedProducts = true
        }
    }

    func refresh() async {
        // Invalidate cache on refresh to force reload
        if let locationId = locationId {
            POSWindowSessionManager.shared.invalidateCache(for: locationId)
        }
        await loadProducts()
    }

    func clearFilters() {
        searchText = ""
        selectedCategoryId = nil
    }

    // MARK: - Customer Cart Management

    func addCustomer(_ customer: Customer) async {
        guard let storeId = storeId,
              let locationId = locationId else {
            cartError = "Missing store or location - please select a location for this session"
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
            let cart = try await CartService.shared.getOrCreateCart(
                storeId: storeId,
                locationId: locationId,
                customerId: customer.id
            )

            // Cache customer FIRST so it's available when view re-renders
            _customerCache[customer.id] = customer
            // Calculate new index BEFORE modifying arrays to avoid race conditions
            let newIndex = carts.count
            // Append cart and set index together, then notify
            carts.append(cart)
            activeCartIndex = newIndex
            isCartLoading = false
            // Explicitly notify observers since customer cache changed (not @Published)
            objectWillChange.send()

        } catch {
            cartError = error.localizedDescription
            isCartLoading = false
        }
    }

    func switchToCustomer(_ customer: Customer) {
        if let index = carts.firstIndex(where: { $0.customerId == customer.id }) {
            activeCartIndex = index
        }
    }

    func removeCustomer(_ customer: Customer) {
        guard let index = carts.firstIndex(where: { $0.customerId == customer.id }) else { return }

        // Close cart on server
        let cart = carts[index]
        Task {
            try? await CartService.shared.clearCart(cartId: cart.id)
        }

        carts.remove(at: index)
        _customerCache.removeValue(forKey: customer.id)

        // Adjust active index
        if carts.isEmpty {
            activeCartIndex = -1
        } else if activeCartIndex >= carts.count {
            activeCartIndex = carts.count - 1
        }
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
                Log.session.error("POSWindowSession: loadCartById - Cart not found on server: \(cartId)")
                return false
            }

            // Fetch and cache customer if cart has a customer ID
            if let customerId = cart.customerId, let storeId = storeId {
                do {
                    let customer: Customer = try await supabase
                        .from("v_store_customers")
                        .select()
                        .eq("id", value: customerId.uuidString)
                        .eq("store_id", value: storeId.uuidString)
                        .single()
                        .execute()
                        .value
                    _customerCache[customerId] = customer
                    Log.session.info("POSWindowSession: loadCartById - Cached customer \(customer.displayName) for cart \(cartId)")
                } catch {
                    Log.session.error("POSWindowSession: loadCartById - Failed to fetch customer \(customerId): \(error)")
                }
            }

            let newIndex = carts.count
            carts.append(cart)
            activeCartIndex = newIndex
            Log.session.info("POSWindowSession: loadCartById - Loaded cart \(cartId) from server, now at index \(newIndex)")
            return true
        } catch {
            Log.session.error("POSWindowSession: loadCartById - Failed to load cart \(cartId): \(error)")
            return false
        }
    }

    // MARK: - Cart Operations

    /// Add product with basic quantity (no tier)
    func addToCart(_ product: Product, quantity: Int = 1) async {
        Log.cart.debug("POSWindowSession.addToCart called - product: \(product.name), activeCartIndex: \(self.activeCartIndex), cartsCount: \(self.carts.count)")
        guard let cart = activeCart else {
            cartError = "No active cart"
            Log.cart.error("POSWindowSession.addToCart FAILED - no active cart")
            return
        }

        Log.cart.debug("POSWindowSession.addToCart - using cart: \(cart.id)")
        isCartLoading = true

        do {
            // Query inventory at cart's location for this product
            var inventoryId: UUID? = nil
            let client = await SupabaseClientWrapper.shared.client()

            struct InventoryID: Codable {
                let id: UUID
            }

            let inventory: [InventoryID] = try await client
                .from("inventory")
                .select("id")
                .eq("product_id", value: product.id.uuidString)
                .eq("location_id", value: cart.locationId.uuidString)
                .gt("available_quantity", value: 0)
                .order("available_quantity", ascending: false)
                .limit(1)
                .execute()
                .value

            inventoryId = inventory.first?.id

            let updatedCart = try await CartService.shared.addToCart(
                cartId: cart.id,
                productId: product.id,
                quantity: quantity,
                inventoryId: inventoryId
            )
            Log.cart.info("POSWindowSession.addToCart SUCCESS - items: \(updatedCart.items.count), inventoryId: \(inventoryId?.uuidString ?? "nil")")

            if let index = carts.firstIndex(where: { $0.id == cart.id }) {
                carts[index] = updatedCart
            }
            isCartLoading = false

        } catch {
            cartError = error.localizedDescription
            Log.cart.error("POSWindowSession.addToCart ERROR: \(error.localizedDescription)")
            isCartLoading = false
        }
    }

    /// Add product with specific pricing tier
    func addToCart(_ product: Product, tier: PricingTier) async {
        Log.cart.debug("POSWindowSession.addToCart(tier) called - product: \(product.name), tier: \(tier.label), activeCartIndex: \(self.activeCartIndex), cartsCount: \(self.carts.count)")
        guard let cart = activeCart else {
            cartError = "No active cart"
            Log.cart.error("POSWindowSession.addToCart(tier) FAILED - no active cart")
            return
        }
        Log.cart.debug("POSWindowSession.addToCart(tier) - using cart: \(cart.id)")

        isCartLoading = true

        do {
            // Query inventory at this location for this product
            // IMPORTANT: Use cart.locationId, not window session locationId
            var inventoryId: UUID? = nil
            let client = await SupabaseClientWrapper.shared.client()

            // Simple struct just for ID query
            struct InventoryID: Codable {
                let id: UUID
            }

            let inventory: [InventoryID] = try await client
                .from("inventory")
                .select("id")
                .eq("product_id", value: product.id.uuidString)
                .eq("location_id", value: cart.locationId.uuidString)
                .gt("available_quantity", value: 0)
                .order("available_quantity", ascending: false)
                .limit(1)
                .execute()
                .value

            inventoryId = inventory.first?.id
            Log.cart.debug("POSWindowSession.addToCart(tier) - inventory_id: \(inventoryId?.uuidString ?? "nil") for location: \(cart.locationId)")

            let updatedCart = try await CartService.shared.addToCart(
                cartId: cart.id,
                productId: product.id,
                quantity: 1,
                unitPrice: tier.defaultPrice,
                tierLabel: tier.label,
                tierQuantity: tier.quantity,
                inventoryId: inventoryId
            )

            if let index = carts.firstIndex(where: { $0.id == cart.id }) {
                carts[index] = updatedCart
            }
            isCartLoading = false

        } catch {
            cartError = error.localizedDescription
            isCartLoading = false
        }
    }

    /// Add product variant with specific pricing tier
    func addToCart(_ product: Product, tier: PricingTier, variant: ProductVariant) async {
        guard let cart = activeCart else {
            cartError = "No active cart"
            return
        }

        isCartLoading = true

        do {
            // Query inventory at cart's location for this product
            var inventoryId: UUID? = nil
            let client = await SupabaseClientWrapper.shared.client()

            struct InventoryID: Codable {
                let id: UUID
            }

            let inventory: [InventoryID] = try await client
                .from("inventory")
                .select("id")
                .eq("product_id", value: product.id.uuidString)
                .eq("location_id", value: cart.locationId.uuidString)
                .gt("available_quantity", value: 0)
                .order("available_quantity", ascending: false)
                .limit(1)
                .execute()
                .value

            inventoryId = inventory.first?.id

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
                inventoryId: inventoryId
            )

            if let index = carts.firstIndex(where: { $0.id == cart.id }) {
                carts[index] = updatedCart
            }
            isCartLoading = false

        } catch {
            cartError = error.localizedDescription
            isCartLoading = false
        }
    }

    func updateCartItemQuantity(_ item: ServerCartItem, quantity: Int) async {
        guard let cart = activeCart else { return }

        isCartLoading = true

        do {
            let updatedCart = try await CartService.shared.updateItemQuantity(
                cartId: cart.id,
                itemId: item.id,
                quantity: quantity
            )

            if let index = carts.firstIndex(where: { $0.id == cart.id }) {
                carts[index] = updatedCart
            }
            isCartLoading = false

        } catch {
            cartError = error.localizedDescription
            isCartLoading = false
        }
    }

    func removeFromCart(_ item: ServerCartItem) async {
        guard let cart = activeCart else { return }

        isCartLoading = true

        do {
            let updatedCart = try await CartService.shared.removeFromCart(
                cartId: cart.id,
                itemId: item.id
            )

            if let index = carts.firstIndex(where: { $0.id == cart.id }) {
                carts[index] = updatedCart
            }
            isCartLoading = false

        } catch {
            cartError = error.localizedDescription
            isCartLoading = false
        }
    }

    func clearCart() async {
        guard let cart = activeCart else { return }

        isCartLoading = true

        do {
            let updatedCart = try await CartService.shared.clearCart(cartId: cart.id)

            if let index = carts.firstIndex(where: { $0.id == cart.id }) {
                carts[index] = updatedCart
            }
            isCartLoading = false

        } catch {
            cartError = error.localizedDescription
            isCartLoading = false
        }
    }

    func applyManualDiscount(itemId: UUID, type: DiscountType, value: Decimal) async {
        guard let cart = activeCart else { return }

        isCartLoading = true

        do {
            let updatedCart = try await CartService.shared.applyItemDiscount(
                cartId: cart.id,
                itemId: itemId,
                type: type.rawValue,
                value: value
            )

            if let index = carts.firstIndex(where: { $0.id == cart.id }) {
                carts[index] = updatedCart
            }
            isCartLoading = false

        } catch {
            cartError = error.localizedDescription
            isCartLoading = false
        }
    }

    func getCheckoutTotals() async -> CheckoutTotals? {
        guard let cart = activeCart else { return nil }

        do {
            return try await CartService.shared.calculateCheckout(cartId: cart.id)
        } catch {
            cartError = error.localizedDescription
            return nil
        }
    }
}
