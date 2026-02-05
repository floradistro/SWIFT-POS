//
//  OrderStore.swift
//  Whale
//
//  Order state management with real-time updates.
//  @MainActor for SwiftUI integration.
//
//  ARCHITECTURE NOTE (2026-01-01):
//  Filtering and permission logic has been moved to the backend.
//  The database now handles:
//  - Location-based order visibility (get_orders_for_location RPC)
//  - Permission checks for order updates (update_order_status RPC)
//  - Status workflow transitions (get_next_order_status RPC)
//  This store now primarily manages UI state and Realtime subscriptions.
//

import Foundation
import SwiftUI
import Combine
import Supabase
import os.log

// MARK: - Order Store

@MainActor
final class OrderStore: ObservableObject {

    // MARK: - Orders State
    // Orders are pre-filtered by the backend - no client-side filtering needed

    private(set) var orders: [Order] = [] {
        didSet {
            rebuildIndexes()
        }
    }
    private(set) var isLoading = false
    private(set) var error: String?

    // MARK: - Indexes for O(1) Lookups

    /// Orders indexed by status for fast filtering
    private var ordersByStatus: [OrderStatus: [Order]] = [:]

    /// Orders indexed by type for fast filtering
    private var ordersByType: [OrderType: [Order]] = [:]

    /// Order lookup by ID for fast selection
    private var ordersById: [UUID: Order] = [:]

    /// Cached counts by status group
    private var cachedOrderCounts: [OrderStatusGroup: Int] = [:]

    // MARK: - Filters (sent to backend RPC)

    @Published var searchText = ""
    @Published var selectedStatusGroup: OrderStatusGroup?  // nil = show all orders
    @Published var selectedOrderType: OrderType?
    @Published var selectedPaymentStatus: PaymentStatus?
    @Published var dateRangeStart: Date?
    @Published var dateRangeEnd: Date?
    @Published var amountMin: Decimal?
    @Published var amountMax: Decimal?
    @Published var showOnlineOrdersOnly: Bool = false  // Quick filter for online orders (pickup, shipping, delivery)

    // MARK: - Selection
    // NOT @Published - we control updates manually

    var selectedOrderId: UUID?

    // MARK: - Context

    private var storeId: UUID?
    private var locationId: UUID?
    private var realtimeTask: Task<Void, Never>?
    private var realtimeChannel: RealtimeChannelV2?
    private var isSubscribed = false
    private var isSubscribing = false  // Prevent concurrent subscription attempts

    /// Callback for new orders that belong to the current location
    /// Callback when a new order arrives for the current location
    var onNewOrderForLocation: ((Order) -> Void)?

    // MARK: - Synchronization

    /// Actor-based lock to prevent concurrent mutations without spin-waiting
    private let mutationLock = MutationLock()

    private actor MutationLock {
        private var isLocked = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func acquire() async {
            if !isLocked {
                isLocked = true
                return
            }
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }

        func release() {
            if let next = waiters.first {
                waiters.removeFirst()
                next.resume()
            } else {
                isLocked = false
            }
        }
    }

    private func withMutationLock<T>(_ block: () async throws -> T) async rethrows -> T {
        await mutationLock.acquire()
        do {
            let result = try await block()
            await mutationLock.release()
            return result
        } catch {
            await mutationLock.release()
            throw error
        }
    }

    // MARK: - Singleton

    static let shared = OrderStore()
    private init() {
        setupScenePhaseObserver()
        setupFilterObservers()
        setupStoreChangeObserver()
    }

    /// Observe store changes to clear data when user switches stores
    private func setupStoreChangeObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleStoreChange),
            name: .storeDidChange,
            object: nil
        )
    }

    /// Clear all store-specific data when switching stores
    /// This prevents data from one store "flowing over" into another
    @objc private func handleStoreChange() {
        Log.ui.info("OrderStore: Store changed - clearing all data")
        clearAllStoreData()
    }

    /// Clear ALL store-specific data
    func clearAllStoreData() {
        orders = []
        selectedOrderId = nil
        storeId = nil
        locationId = nil
        error = nil
        clearFilters()

        // Clean up realtime subscription
        Task {
            await cleanupRealtimeSubscription()
        }

        objectWillChange.send()
        Log.ui.info("OrderStore: All store data cleared")
    }

    // MARK: - Filter Change Observers

    /// Setup Combine subscribers to reload orders when filters change
    private func setupFilterObservers() {
        // Debounce filter changes to avoid rapid reloads
        // Combine all filter publishers into a single stream
        Publishers.CombineLatest4(
            $selectedStatusGroup,
            $selectedOrderType,
            $selectedPaymentStatus,
            $showOnlineOrdersOnly
        )
        .dropFirst() // Skip initial values
        .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
        .sink { [weak self] _, _, _, _ in
            Task { @MainActor [weak self] in
                await self?.loadOrders()
            }
        }
        .store(in: &cancellables)

        // Date range changes
        Publishers.CombineLatest($dateRangeStart, $dateRangeEnd)
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    await self?.loadOrders()
                }
            }
            .store(in: &cancellables)

        // Amount range changes
        Publishers.CombineLatest($amountMin, $amountMax)
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    await self?.loadOrders()
                }
            }
            .store(in: &cancellables)

        // Search text with longer debounce
        $searchText
            .dropFirst()
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.loadOrders()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Scene Phase Handling

    private func setupScenePhaseObserver() {
        // Observe app lifecycle to pause/resume realtime subscription
        // Store BOTH subscriptions properly to prevent memory leaks
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.pauseRealtime()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.resumeRealtime()
                }
            }
            .store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()

    private func pauseRealtime() {
        Log.network.info("OrderStore: Pausing realtime (app backgrounded)")
        Task {
            await cleanupRealtimeSubscription()
        }
    }

    private func resumeRealtime() async {
        guard storeId != nil, !isSubscribed else { return }
        Log.network.info("OrderStore: Resuming realtime (app foregrounded)")
        // Refresh orders and resubscribe
        await loadOrders()
    }

    // MARK: - Index Management

    /// Rebuild all indexes when orders change - O(n) but only runs on data change
    private func rebuildIndexes() {
        // Clear existing indexes
        ordersByStatus.removeAll(keepingCapacity: true)
        ordersByType.removeAll(keepingCapacity: true)
        ordersById.removeAll(keepingCapacity: true)
        cachedOrderCounts.removeAll(keepingCapacity: true)

        // Build indexes in single pass
        for order in orders {
            // Index by status
            ordersByStatus[order.status, default: []].append(order)

            // Index by type
            ordersByType[order.orderType, default: []].append(order)

            // Index by ID
            ordersById[order.id] = order
        }

        // Pre-compute status group counts
        for group in OrderStatusGroup.allCases {
            var count = 0
            for status in group.statuses {
                count += ordersByStatus[status]?.count ?? 0
            }
            cachedOrderCounts[group] = count
        }
    }

    // MARK: - Computed Properties

    /// Count of active filters for UI badge
    var activeFilterCount: Int {
        var count = 0
        if selectedStatusGroup != nil { count += 1 }
        if selectedOrderType != nil { count += 1 }
        if selectedPaymentStatus != nil { count += 1 }
        if dateRangeStart != nil || dateRangeEnd != nil { count += 1 }
        if amountMin != nil || amountMax != nil { count += 1 }
        if showOnlineOrdersOnly { count += 1 }
        if !searchText.isEmpty { count += 1 }
        return count
    }

    /// Whether any filters are active
    var hasActiveFilters: Bool {
        activeFilterCount > 0
    }

    /// Online order types for quick filtering (pickup + shipping only, we don't support delivery)
    static let onlineOrderTypes: Set<OrderType> = [.pickup, .shipping]

    /// Walk-in order types (walk_in and pos are the same thing)
    static let walkInOrderTypes: Set<OrderType> = [.walkIn, .pos]

    /// Filtered orders with client-side filtering as fallback
    /// Note: Backend should handle filtering via get_orders_for_location RPC,
    /// but we apply client-side filtering as fallback/supplement
    var filteredOrders: [Order] {
        var result = orders

        // Filter by status group
        if let statusGroup = selectedStatusGroup {
            let statuses = statusGroup.statuses
            result = result.filter { statuses.contains($0.status) }
        }

        // Filter by order type
        if let orderType = selectedOrderType {
            result = result.filter { $0.orderType == orderType }
        }

        // Filter by payment status
        if let paymentStatus = selectedPaymentStatus {
            result = result.filter { $0.paymentStatus == paymentStatus }
        }

        // Filter by search text
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { order in
                order.orderNumber.lowercased().contains(query) ||
                order.customers?.firstName?.lowercased().contains(query) == true ||
                order.customers?.lastName?.lowercased().contains(query) == true ||
                (order.customers?.fullName?.lowercased().contains(query) == true)
            }
        }

        // Filter by date range
        if let startDate = dateRangeStart {
            result = result.filter { $0.createdAt >= startDate }
        }
        if let endDate = dateRangeEnd {
            result = result.filter { $0.createdAt <= endDate }
        }

        // Filter by amount range
        if let minAmount = amountMin {
            result = result.filter { $0.totalAmount >= minAmount }
        }
        if let maxAmount = amountMax {
            result = result.filter { $0.totalAmount <= maxAmount }
        }

        // Filter online orders only
        if showOnlineOrdersOnly {
            result = result.filter { Self.onlineOrderTypes.contains($0.orderType) }
        }

        return result
    }

    /// Count of online orders (pickup, shipping, delivery) for filter badge
    var onlineOrderCount: Int {
        orders.filter { Self.onlineOrderTypes.contains($0.orderType) }.count
    }

    /// Count of orders needing attention (pending + not paid)
    var ordersNeedingAttention: Int {
        orders.filter { $0.status == .pending && $0.paymentStatus != .paid }.count
    }

    /// Selected order - O(1) lookup using index
    var selectedOrder: Order? {
        guard let id = selectedOrderId else { return nil }
        return ordersById[id]
    }

    /// Order counts by status group - O(1) using cached counts
    var orderCounts: [OrderStatusGroup: Int] {
        cachedOrderCounts
    }

    // MARK: - Actions

    /// Configure store with store and location
    func configure(storeId: UUID, locationId: UUID) {
        self.storeId = storeId
        self.locationId = locationId
    }

    /// Load orders using backend RPC with filters
    func loadOrders() async {
        guard let storeId = storeId, let locationId = locationId else {
            Log.ui.error("OrderStore: Cannot load orders - missing storeId or locationId")
            error = "Missing store or location"
            objectWillChange.send()
            return
        }

        isLoading = true
        error = nil
        objectWillChange.send()  // ONE notification for loading start

        do {
            // Use backend RPC for location-filtered orders with all filters applied
            let fetchedOrders = try await OrderService.fetchOrdersWithFilters(
                storeId: storeId,
                locationId: locationId,
                statusGroup: selectedStatusGroup?.rawValue,
                orderType: selectedOrderType?.rawValue,
                paymentStatus: selectedPaymentStatus?.rawValue,
                search: searchText.isEmpty ? nil : searchText,
                dateStart: dateRangeStart,
                dateEnd: dateRangeEnd,
                amountMin: amountMin,
                amountMax: amountMax,
                onlineOnly: showOnlineOrdersOnly
            )
            self.orders = fetchedOrders
            Log.ui.info("OrderStore: Loaded \(self.orders.count) orders via RPC")

            // Gate realtime subscription until UI is idle
            // This reduces input system churn during initial render
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms

            // Start real-time subscription
            await subscribeToOrders()
        } catch let fetchError {
            Log.ui.error("OrderStore: Failed to load orders - \(fetchError)")
            self.error = fetchError.localizedDescription
        }

        isLoading = false
        objectWillChange.send()  // ONE notification for loading complete
    }

    /// Refresh orders
    func refresh() async {
        await loadOrders()
    }

    /// Refresh a single order by ID
    func refreshOrder(orderId: UUID) async {
        do {
            guard let updatedOrder = try await OrderService.fetchOrder(orderId: orderId) else {
                Log.network.warning("OrderStore: Could not fetch order \(orderId) for refresh")
                return
            }

            await withMutationLock {
                if let index = self.orders.firstIndex(where: { $0.id == orderId }) {
                    self.orders[index] = updatedOrder
                    Log.network.info("OrderStore: Refreshed order \(updatedOrder.orderNumber)")
                }
            }
        } catch {
            Log.network.error("OrderStore: Failed to refresh order: \(error.localizedDescription)")
        }
    }

    /// Update order status via backend RPC
    /// Backend handles permission checks and status transition validation
    func updateStatus(orderId: UUID, status: OrderStatus) async {
        guard let currentLocationId = self.locationId else {
            Log.ui.error("OrderStore: Cannot update - no location set")
            self.error = "No location set"
            Haptics.error()
            return
        }

        // Serialize mutation to prevent race conditions
        await withMutationLock {
            // Find the order for optimistic update
            guard let order = self.orders.first(where: { $0.id == orderId }) else {
                Log.ui.error("OrderStore: Cannot update - order not found")
                self.error = "Order not found"
                Haptics.error()
                return
            }

            // Store previous status for potential revert
            let previousStatus = order.status

            // Optimistic update FIRST (before network call) to update UI immediately
            if let index = self.orders.firstIndex(where: { $0.id == orderId }) {
                var updatedOrder = self.orders[index]
                updatedOrder.status = status
                self.orders[index] = updatedOrder
            }

            do {
                // Refresh session to ensure JWT has latest user metadata (including store_id)
                do {
                    try await supabase.auth.refreshSession()
                } catch {
                    Log.session.warning("Session refresh failed: \(error.localizedDescription)")
                }

                // Get current user ID for attribution tracking
                let currentUserId = SessionObserver.shared.userId

                // Use backend RPC which handles:
                // 1. Permission check (can this location update this order?)
                // 2. Status transition validation (is this a valid status change?)
                // 3. Atomic update with user attribution
                try await OrderService.updateOrderStatusViaRPC(
                    orderId: orderId,
                    locationId: currentLocationId,
                    status: status,
                    userId: currentUserId
                )

                Log.ui.info("OrderStore: Status updated to \(status.rawValue) via RPC")
                Haptics.success()
            } catch {
                Log.ui.error("OrderStore: Failed to update status - \(error.localizedDescription)")
                // Revert to previous status locally instead of full reload
                if let index = self.orders.firstIndex(where: { $0.id == orderId }) {
                    var revertedOrder = self.orders[index]
                    revertedOrder.status = previousStatus
                    self.orders[index] = revertedOrder
                }
                Haptics.error()
                // Set error for UI
                self.error = "Failed to update: \(error.localizedDescription)"
            }
        }
    }

    /// Select an order
    func selectOrder(_ order: Order?) {
        selectedOrderId = order?.id
        objectWillChange.send()
    }

    /// Clear filters
    func clearFilters() {
        searchText = ""
        selectedStatusGroup = nil
        selectedOrderType = nil
        selectedPaymentStatus = nil
        dateRangeStart = nil
        dateRangeEnd = nil
        amountMin = nil
        amountMax = nil
        showOnlineOrdersOnly = false
    }

    /// Reset to show active orders only (common use case)
    func showActiveOrders() {
        clearFilters()
        selectedStatusGroup = .active
    }

    /// Quick filter: Show only online orders needing attention
    func showOnlineOrdersNeedingAttention() {
        clearFilters()
        showOnlineOrdersOnly = true
        selectedStatusGroup = .active
    }

    /// Set date range filter with preset options
    func setDateRange(_ range: DateRangePreset) {
        let calendar = Calendar.current
        let now = Date()

        switch range {
        case .today:
            dateRangeStart = calendar.startOfDay(for: now)
            dateRangeEnd = now
        case .yesterday:
            let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
            dateRangeStart = calendar.startOfDay(for: yesterday)
            dateRangeEnd = calendar.startOfDay(for: now)
        case .last7Days:
            dateRangeStart = calendar.date(byAdding: .day, value: -7, to: now)
            dateRangeEnd = now
        case .last30Days:
            dateRangeStart = calendar.date(byAdding: .day, value: -30, to: now)
            dateRangeEnd = now
        case .thisMonth:
            dateRangeStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now))
            dateRangeEnd = now
        case .lastMonth:
            let firstOfThisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
            dateRangeStart = calendar.date(byAdding: .month, value: -1, to: firstOfThisMonth)
            dateRangeEnd = calendar.date(byAdding: .day, value: -1, to: firstOfThisMonth)
        case .custom:
            // Custom range is set directly via dateRangeStart/dateRangeEnd
            break
        case .all:
            dateRangeStart = nil
            dateRangeEnd = nil
        }
    }

    enum DateRangePreset {
        case today
        case yesterday
        case last7Days
        case last30Days
        case thisMonth
        case lastMonth
        case custom
        case all
    }

    // MARK: - Real-time

    private func subscribeToOrders() async {
        guard let storeId = storeId else { return }

        // Skip if already subscribed or currently subscribing
        guard !isSubscribed, !isSubscribing else {
            Log.network.info("OrderStore: Already subscribed or subscribing, skipping")
            return
        }

        // Mark as subscribing to prevent concurrent attempts
        isSubscribing = true

        // Clean up any existing subscription first - fire and forget
        Task.detached { [weak self] in
            guard let self else { return }
            await self.cleanupRealtimeSubscription()
        }

        // Create a unique channel name with timestamp to ensure fresh channel
        let channelName = "orders-\(storeId.uuidString.prefix(8))-\(UInt64(Date().timeIntervalSince1970 * 1000))"

        Log.network.info("OrderStore: Creating realtime channel: \(channelName)")

        // Capture supabase client before detaching (it may have main actor isolation)
        let client = supabase

        // Do ALL channel setup in background to avoid any main thread blocking
        // Supabase SDK can do synchronous work during channel creation
        Task.detached { [weak self] in
            guard let self else { return }

            // Create channel off main thread
            let channel = client.channel(channelName)

            // Add postgres change listener
            let changes = channel.postgresChange(
                AnyAction.self,
                schema: "public",
                table: "orders",
                filter: "store_id=eq.\(storeId.uuidString)"
            )

            // Store reference for cleanup
            await MainActor.run { [weak self] in
                self?.realtimeChannel = channel
            }

            // Subscribe (blocking network call)
            await channel.subscribe()

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isSubscribed = true
                self.isSubscribing = false
                Log.network.info("OrderStore: Subscribed to real-time orders successfully")
            }

            // Start listening for changes
            let task = Task { [weak self] in
                for await change in changes {
                    guard let self = self, !Task.isCancelled else { break }
                    await self.handleRealtimeChange(change)
                }
                await MainActor.run { [weak self] in
                    self?.isSubscribed = false
                }
            }

            await MainActor.run { [weak self] in
                self?.realtimeTask = task
            }
        }
    }

    private func cleanupRealtimeSubscription() async {
        // Cancel the listening task first
        realtimeTask?.cancel()
        realtimeTask = nil

        // Unsubscribe and remove channel in background to avoid blocking
        if let channel = realtimeChannel {
            Log.network.info("OrderStore: Cleaning up realtime channel")
            let channelToCleanup = channel
            realtimeChannel = nil

            // Fire and forget - don't block on cleanup
            Task.detached {
                await channelToCleanup.unsubscribe()
                await supabase.removeChannel(channelToCleanup)
            }
        }

        isSubscribed = false
    }

    private func handleRealtimeChange(_ change: AnyAction) async {
        // Process realtime changes off main thread to avoid blocking UI
        switch change {
        case .insert(let action):
            // Decode basic order info to get the ID
            let storeId = self.storeId
            let currentLocationId = self.locationId
            let basicOrder: Order? = await Task.detached {
                Self.decodeRealtimeOrder(from: action.record)
            }.value

            guard let basicOrder = basicOrder, basicOrder.storeId == storeId else { return }

            // Fetch the complete order with all joins (customers, items, locations)
            // Real-time events only contain raw row data without joins
            // Add a small delay to ensure order_items are inserted (they may be in a separate transaction)
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms

            do {
                var completeOrder = try await OrderService.fetchOrder(orderId: basicOrder.id)

                // If items are still empty, retry once after another delay
                if completeOrder?.items?.isEmpty ?? true {
                    Log.network.info("OrderStore: Order items empty, retrying after delay...")
                    try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                    completeOrder = try await OrderService.fetchOrder(orderId: basicOrder.id)
                }

                guard let completeOrder = completeOrder else {
                    Log.network.warning("OrderStore: Could not fetch complete order for \(basicOrder.orderNumber)")
                    return
                }

                // Check if this order is visible to the current location via backend RPC
                guard let locationId = currentLocationId else { return }

                let isVisible = try await OrderService.isOrderVisibleToLocation(
                    orderId: completeOrder.id,
                    locationId: locationId
                )

                guard isVisible else {
                    Log.network.info("OrderStore: Order \(completeOrder.orderNumber) not visible to this location, skipping")
                    return
                }

                await withMutationLock {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        self.orders.insert(completeOrder, at: 0)
                    }
                    Haptics.light()
                }
                Log.network.info("OrderStore: New order received - \(completeOrder.orderNumber) type=\(completeOrder.orderType.rawValue)")

                // Notify dock for non-walk-in/POS orders that belong to this location
                if completeOrder.orderType != .walkIn && completeOrder.orderType != .pos {
                    Log.network.info("OrderStore: Notifying dock of new order \(completeOrder.orderNumber)")
                    if let callback = self.onNewOrderForLocation {
                        Log.network.info("OrderStore: Callback is set, calling it")
                        await MainActor.run {
                            callback(completeOrder)
                        }
                    } else {
                        Log.network.warning("OrderStore: onNewOrderForLocation callback is nil!")
                    }
                }
            } catch {
                Log.network.error("OrderStore: Failed to fetch complete order: \(error.localizedDescription)")
            }

        case .update(let action):
            // Decode basic order info to get the ID
            let basicOrder: Order? = await Task.detached {
                Self.decodeRealtimeOrder(from: action.record)
            }.value

            guard let basicOrder = basicOrder else { return }

            // Fetch the complete order with all joins
            do {
                guard let completeOrder = try await OrderService.fetchOrder(orderId: basicOrder.id) else {
                    Log.network.warning("OrderStore: Could not fetch complete order for update")
                    return
                }

                await withMutationLock {
                    if let index = self.orders.firstIndex(where: { $0.id == completeOrder.id }) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            self.orders[index] = completeOrder
                        }
                    }
                }
                Log.network.info("OrderStore: Order updated - \(completeOrder.orderNumber)")
            } catch {
                Log.network.error("OrderStore: Failed to fetch complete order for update: \(error.localizedDescription)")
            }

        case .delete(let action):
            if let idString = action.oldRecord["id"] as? String,
               let id = UUID(uuidString: idString) {
                await withMutationLock {
                    withAnimation(.easeOut(duration: 0.25)) {
                        self.orders.removeAll { $0.id == id }
                    }
                }
                Log.network.info("OrderStore: Order deleted - \(idString)")
            }

        default:
            break
        }
    }

    func cleanup() {
        Task {
            await cleanupRealtimeSubscription()
        }
        Log.network.info("OrderStore: Cleaned up realtime subscription")
    }

    // MARK: - JSON Decoding (Nonisolated - runs off main thread)

    /// Decode an order from realtime record, handling Supabase's AnyJSON types
    private nonisolated static func decodeRealtimeOrder(from record: [String: Any]) -> Order? {
        do {
            let sanitizedRecord = sanitizeForJSON(record)
            let data = try JSONSerialization.data(withJSONObject: sanitizedRecord)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(Order.self, from: data)
        } catch {
            Log.network.error("OrderStore: Failed to decode realtime order - \(error)")
            return nil
        }
    }

    /// Recursively sanitize a dictionary to convert Supabase AnyJSON types to JSON-compatible types.
    /// This is nonisolated and runs off main thread for performance.
    private nonisolated static func sanitizeForJSON(_ value: Any) -> Any {
        // Handle AnyJSON from Supabase Realtime SDK
        if let anyJSON = value as? AnyJSON {
            return sanitizeAnyJSON(anyJSON)
        }

        if let dict = value as? [String: Any] {
            var result: [String: Any] = [:]
            for (key, val) in dict {
                result[key] = sanitizeForJSON(val)
            }
            return result
        }

        if let array = value as? [Any] {
            return array.map { sanitizeForJSON($0) }
        }

        // Primitive types that JSONSerialization handles natively
        if let string = value as? String { return string }
        if let bool = value as? Bool { return bool }
        if let int = value as? Int { return int }
        if let double = value as? Double { return double }
        if let decimal = value as? Decimal { return NSDecimalNumber(decimal: decimal).doubleValue }
        if value is NSNull { return NSNull() }
        if let number = value as? NSNumber { return number }

        // Fallback: convert to string (no logging to avoid spam)
        return String(describing: value)
    }

    /// Convert Supabase AnyJSON to a JSON-serializable type
    private nonisolated static func sanitizeAnyJSON(_ anyJSON: AnyJSON) -> Any {
        switch anyJSON {
        case .null:
            return NSNull()
        case .bool(let b):
            return b
        case .integer(let i):
            return i
        case .double(let d):
            return d
        case .string(let s):
            return s
        case .array(let arr):
            return arr.map { sanitizeAnyJSON($0) }
        case .object(let dict):
            var result: [String: Any] = [:]
            for (key, val) in dict {
                result[key] = sanitizeAnyJSON(val)
            }
            return result
        }
    }
}
