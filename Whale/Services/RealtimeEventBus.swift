//
//  RealtimeEventBus.swift
//  Whale
//
//  Created: 2026-01-22
//  Purpose: Centralized, typed realtime event system for Supabase
//
//  IMPORTANT: This works with CURRENT schema (location_queue, carts, cart_items)
//  When migration happens, just update table names (see comments marked MIGRATION)
//

import Foundation
import Supabase
import Combine
import os.log

// MARK: - Typed Events

/// All realtime events from the database
/// These are TYPE-SAFE - no more unsafe casting!
enum RealtimeEvent: Equatable, CustomStringConvertible {

    // MARK: Queue Events

    /// Queue was updated (generic - use when you don't know specific change)
    case queueUpdated(locationId: UUID)

    /// Customer was added to queue
    case queueCustomerAdded(locationId: UUID, customerId: UUID)

    /// Customer was removed from queue
    case queueCustomerRemoved(locationId: UUID, customerId: UUID)

    // MARK: Cart Events

    /// Cart was updated (totals, status, etc.)
    case cartUpdated(cartId: UUID)

    /// Item was added to cart
    case cartItemAdded(cartId: UUID, itemId: UUID)

    /// Item was removed from cart
    case cartItemRemoved(cartId: UUID, itemId: UUID)

    /// Item quantity changed
    case cartItemQuantityChanged(cartId: UUID, itemId: UUID, newQuantity: Int)

    // MARK: Order Events (Future)

    /// Order was created
    case orderCreated(orderId: UUID)

    /// Order status changed
    case orderStatusChanged(orderId: UUID, newStatus: String)

    // MARK: Inventory Events

    /// Inventory was updated (stock levels changed)
    case inventoryUpdated(locationId: UUID)

    // MARK: CustomStringConvertible

    var description: String {
        switch self {
        case .queueUpdated(let locationId):
            return "queueUpdated(location: \(locationId))"
        case .queueCustomerAdded(let locationId, let customerId):
            return "queueCustomerAdded(location: \(locationId), customer: \(customerId))"
        case .queueCustomerRemoved(let locationId, let customerId):
            return "queueCustomerRemoved(location: \(locationId), customer: \(customerId))"
        case .cartUpdated(let cartId):
            return "cartUpdated(cart: \(cartId))"
        case .cartItemAdded(let cartId, let itemId):
            return "cartItemAdded(cart: \(cartId), item: \(itemId))"
        case .cartItemRemoved(let cartId, let itemId):
            return "cartItemRemoved(cart: \(cartId), item: \(itemId))"
        case .cartItemQuantityChanged(let cartId, let itemId, let quantity):
            return "cartItemQuantityChanged(cart: \(cartId), item: \(itemId), qty: \(quantity))"
        case .orderCreated(let orderId):
            return "orderCreated(order: \(orderId))"
        case .orderStatusChanged(let orderId, let status):
            return "orderStatusChanged(order: \(orderId), status: \(status))"
        case .inventoryUpdated(let locationId):
            return "inventoryUpdated(location: \(locationId))"
        }
    }
}

// MARK: - Event Bus

@MainActor
final class RealtimeEventBus: ObservableObject {

    // MARK: Singleton

    static let shared = RealtimeEventBus()

    // MARK: - Published State

    @Published private(set) var connectionState: ConnectionState = .disconnected

    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected(locationIds: Set<UUID>)
        case error(String)

        var isConnected: Bool {
            if case .connected = self { return true }
            return false
        }
    }

    // MARK: - Private State

    // nonisolated(unsafe) allows capturing in concurrent code for Swift 6
    // Safe because we only call send() via MainActor.run
    nonisolated(unsafe) private let eventSubject = PassthroughSubject<RealtimeEvent, Never>()
    private var activeChannels: [UUID: ChannelState] = [:]
    private var reconnectTasks: [UUID: Task<Void, Never>] = [:]

    private struct ChannelState {
        let channel: RealtimeChannelV2
        let task: Task<Void, Never>
        var reconnectAttempts: Int = 0
    }

    // MARK: - Initialization

    private init() {
        Log.network.info("📡 RealtimeEventBus initialized")
    }

    // MARK: - Public API

    /// Connect to realtime events for a location
    /// Call this ONCE per location (not per view!)
    ///
    /// Example:
    /// ```
    /// Task {
    ///     await RealtimeEventBus.shared.connect(to: locationId)
    /// }
    /// ```
    func connect(to locationId: UUID) async {
        // Already connected?
        guard activeChannels[locationId] == nil else {
            Log.network.info("📡 RealtimeEventBus: Already connected to \(locationId)")
            return
        }

        // Cancel any pending reconnect
        reconnectTasks[locationId]?.cancel()
        reconnectTasks[locationId] = nil

        updateConnectionState()

        do {
            let channelState = try await createChannel(for: locationId)
            activeChannels[locationId] = channelState
            updateConnectionState()

            Log.network.info("✅ RealtimeEventBus: Connected to location \(locationId)")
        } catch {
            let errorMsg = error.localizedDescription
            connectionState = .error(errorMsg)
            Log.network.error("❌ RealtimeEventBus: Failed to connect: \(errorMsg)")

            // Schedule retry with exponential backoff
            scheduleReconnect(to: locationId)
        }
    }

    /// Disconnect from a location
    /// Call this when location is no longer needed
    func disconnect(from locationId: UUID) async {
        reconnectTasks[locationId]?.cancel()
        reconnectTasks[locationId] = nil

        if let state = activeChannels[locationId] {
            state.task.cancel()
            let supabase = await supabaseAsync()
            await state.channel.unsubscribe()
            await supabase.removeChannel(state.channel)
            activeChannels[locationId] = nil
        }

        updateConnectionState()
        Log.network.info("📡 RealtimeEventBus: Disconnected from \(locationId)")
    }

    /// Get all events (unfiltered)
    func events() -> AnyPublisher<RealtimeEvent, Never> {
        eventSubject.eraseToAnyPublisher()
    }

    /// Get queue events for a specific location
    ///
    /// Example:
    /// ```
    /// RealtimeEventBus.shared.queueEvents(for: locationId)
    ///     .sink { event in
    ///         switch event {
    ///         case .queueUpdated:
    ///             await reloadQueue()
    ///         default:
    ///             break
    ///         }
    ///     }
    /// ```
    func queueEvents(for locationId: UUID) -> AnyPublisher<RealtimeEvent, Never> {
        eventSubject
            .filter { event in
                switch event {
                case .queueUpdated(let loc),
                     .queueCustomerAdded(let loc, _),
                     .queueCustomerRemoved(let loc, _):
                    return loc == locationId
                default:
                    return false
                }
            }
            .eraseToAnyPublisher()
    }

    /// Get cart events for a specific cart
    func cartEvents(for cartId: UUID) -> AnyPublisher<RealtimeEvent, Never> {
        eventSubject
            .filter { event in
                switch event {
                case .cartUpdated(let cart),
                     .cartItemAdded(let cart, _),
                     .cartItemRemoved(let cart, _),
                     .cartItemQuantityChanged(let cart, _, _):
                    return cart == cartId
                default:
                    return false
                }
            }
            .eraseToAnyPublisher()
    }

    /// Get inventory events for a specific location
    func inventoryEvents(for locationId: UUID) -> AnyPublisher<RealtimeEvent, Never> {
        eventSubject
            .filter { event in
                switch event {
                case .inventoryUpdated(let loc):
                    return loc == locationId
                default:
                    return false
                }
            }
            .eraseToAnyPublisher()
    }

    // MARK: - Private Implementation

    private func createChannel(for locationId: UUID) async throws -> ChannelState {
        let supabase = await supabaseAsync()
        let channelName = "location-\(locationId.uuidString)"
        let channel = supabase.realtimeV2.channel(channelName)

        // ONE subscription per table - handle all events through the bus
        let queueChanges = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "location_queue",
            filter: "location_id=eq.\(locationId.uuidString)"
        )

        let cartChanges = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "carts",
            filter: "location_id=eq.\(locationId.uuidString)"
        )

        let cartItemChanges = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "cart_items"
        )

        let inventoryChanges = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "inventory",
            filter: "location_id=eq.\(locationId.uuidString)"
        )

        // Subscribe and wait for confirmation using new API
        do {
            try await channel.subscribeWithError()
            Log.network.info("✅ RealtimeEventBus: Successfully subscribed to \(channelName)")
        } catch {
            Log.network.error("❌ RealtimeEventBus: Subscription error for \(channelName): \(error.localizedDescription)")
            throw error
        }

        // Wait a moment for subscription to fully establish
        try await Task.sleep(nanoseconds: 500_000_000) // 500ms

        // Listen to changes and broadcast events - subscribers refetch their own data
        let task = Task { [weak self] in
            guard let self = self else { return }

            await withTaskGroup(of: Void.self) { group in
                // Capture eventSubject to avoid actor isolation issues
                let eventSubject = self.eventSubject

                // Queue changes
                group.addTask {
                    for await _ in queueChanges {
                        await MainActor.run { eventSubject.send(.queueUpdated(locationId: locationId)) }
                    }
                }

                // Cart changes - broadcast location update so all carts at this location refetch
                group.addTask {
                    for await _ in cartChanges {
                        await MainActor.run { eventSubject.send(.queueUpdated(locationId: locationId)) }
                    }
                }

                // Cart item changes - same
                group.addTask {
                    for await _ in cartItemChanges {
                        await MainActor.run { eventSubject.send(.queueUpdated(locationId: locationId)) }
                    }
                }

                // Inventory changes - notify product grids to refetch
                group.addTask {
                    for await _ in inventoryChanges {
                        await MainActor.run { eventSubject.send(.inventoryUpdated(locationId: locationId)) }
                    }
                }
            }
        }

        return ChannelState(channel: channel, task: task)
    }

    // MARK: - Reconnection Logic

    private func scheduleReconnect(to locationId: UUID) {
        let attempts = activeChannels[locationId]?.reconnectAttempts ?? 0
        let delay = min(pow(2.0, Double(attempts)), 32.0)  // Max 32 seconds

        Log.network.info("🔄 RealtimeEventBus: Reconnecting to \(locationId) in \(delay)s (attempt \(attempts + 1))")

        let task = Task {
            try? await Task.sleep(for: .seconds(delay))

            guard !Task.isCancelled else { return }

            // Update reconnect attempts
            if var state = activeChannels[locationId] {
                state.reconnectAttempts += 1
                activeChannels[locationId] = state
            }

            await connect(to: locationId)
        }

        reconnectTasks[locationId] = task
    }

    private func updateConnectionState() {
        if activeChannels.isEmpty {
            connectionState = .disconnected
        } else {
            let connectedIds = Set(activeChannels.keys)
            connectionState = .connected(locationIds: connectedIds)
        }
    }

    // MARK: - Helper Methods for Parsing Supabase Changes

    /// Extract UUID from JSONObject
    private func extractUUID(from jsonObject: JSONObject, key: String) -> UUID? {
        // JSONObject is [String: Any]
        if let stringValue = jsonObject[key] as? String {
            return UUID(uuidString: stringValue)
        }

        if let uuidValue = jsonObject[key] as? UUID {
            return uuidValue
        }

        return nil
    }

    /// Extract Int from JSONObject
    private func extractInt(from jsonObject: JSONObject, key: String) -> Int? {
        if let intValue = jsonObject[key] as? Int {
            return intValue
        }

        if let doubleValue = jsonObject[key] as? Double {
            return Int(doubleValue)
        }

        if let stringValue = jsonObject[key] as? String,
           let intValue = Int(stringValue) {
            return intValue
        }

        return nil
    }

}
