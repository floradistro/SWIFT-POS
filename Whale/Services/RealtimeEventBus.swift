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
enum RealtimeEvent: Equatable {

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

    private let eventSubject = PassthroughSubject<RealtimeEvent, Never>()
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

    // MARK: - Private Implementation

    private func createChannel(for locationId: UUID) async throws -> ChannelState {
        let supabase = await supabaseAsync()
        let channelName = "location-\(locationId.uuidString)"
        let channel = supabase.realtimeV2.channel(channelName)

        // MIGRATION: When you migrate, change table name here:
        // "location_queue" → "queues"
        let queueChanges = await channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "location_queue",  // MIGRATION: Change to "queues"
            filter: "location_id=eq.\(locationId.uuidString)"
        )

        // MIGRATION: Update "carts" table name if changed
        let cartChanges = await channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "carts",  // MIGRATION: Update if table renamed
            filter: "location_id=eq.\(locationId.uuidString)"
        )

        // MIGRATION: Update "cart_items" table name if changed
        let cartItemChanges = await channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "cart_items"  // MIGRATION: Update if table renamed
        )

        try await channel.subscribe()

        // Start listening to all change streams
        let task = Task { [weak self] in
            await withTaskGroup(of: Void.self) { group in
                // Queue changes
                group.addTask {
                    for await change in queueChanges {
                        await self?.handleQueueChange(locationId, change)
                    }
                }

                // Cart changes
                group.addTask {
                    for await change in cartChanges {
                        await self?.handleCartChange(change)
                    }
                }

                // Cart item changes
                group.addTask {
                    for await change in cartItemChanges {
                        await self?.handleCartItemChange(change)
                    }
                }
            }
        }

        return ChannelState(channel: channel, task: task)
    }

    // MARK: - Event Handlers

    private func handleQueueChange(_ locationId: UUID, _ change: AnyAction) {
        Log.network.info("📡 Queue change for location \(locationId)")

        // For now, just send generic update
        // Future: Parse INSERT/UPDATE/DELETE for specific events
        eventSubject.send(.queueUpdated(locationId: locationId))
    }

    private func handleCartChange(_ change: AnyAction) {
        Log.network.info("📡 Cart change")

        // Future: Parse cart_id and broadcast typed event
    }

    private func handleCartItemChange(_ change: AnyAction) {
        Log.network.info("📡 Cart item change")

        // Future: Parse cart_id and item_id and broadcast typed event
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
}
