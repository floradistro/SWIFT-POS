//
//  LocationQueueStore.swift
//  Whale
//
//  Observable store for location queue state.
//  Provides backend-driven customer queue shared across all registers at a location.
//  Uses Supabase Realtime for live updates across all registers.
//

import Foundation
import Combine
import Supabase
import os.log

extension Notification.Name {
    static let queueDidChange = Notification.Name("queueDidChange")
}

@MainActor
final class LocationQueueStore: ObservableObject {

    // MARK: - Singleton per location (keyed by locationId)

    private static var stores: [UUID: LocationQueueStore] = [:]

    static func shared(for locationId: UUID) -> LocationQueueStore {
        if let existing = stores[locationId] {
            return existing
        }
        let store = LocationQueueStore(locationId: locationId)
        stores[locationId] = store
        return store
    }

    // MARK: - Published State

    @Published private(set) var queue: [QueueEntry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published var selectedCartId: UUID?

    /// Callback when queue changes (for views that can't use @ObservedObject)
    var onQueueChanged: (() -> Void)?

    // MARK: - Properties

    let locationId: UUID
    private var refreshTask: Task<Void, Never>?
    private var pollingTask: Task<Void, Never>?
    private var eventCancellable: AnyCancellable?

    // MARK: - Computed Properties

    var selectedEntry: QueueEntry? {
        guard let cartId = selectedCartId else { return nil }
        return queue.first { $0.cartId == cartId }
    }

    var count: Int { queue.count }
    var isEmpty: Bool { queue.isEmpty }

    // MARK: - Init

    private init(locationId: UUID) {
        self.locationId = locationId
        setupEventListening()
    }

    // MARK: - EventBus Integration

    private func setupEventListening() {
        // Connect to EventBus (happens once per location globally)
        Task {
            await RealtimeEventBus.shared.connect(to: locationId)
        }

        // Subscribe to queue events for this location
        eventCancellable = RealtimeEventBus.shared
            .queueEvents(for: locationId)
            .sink { [weak self] event in
                Task { @MainActor [weak self] in
                    await self?.handleEvent(event)
                }
            }

        // Polling disabled - rely on EventBus realtime updates
        // startPolling(interval: 3.0)
    }

    private func handleEvent(_ event: RealtimeEvent) async {
        switch event {
        case .queueUpdated(let locationId):
            guard locationId == self.locationId else { return }
            Log.cart.debug("Queue updated for location \(locationId)")
            await loadQueue()

        case .queueCustomerAdded(let locationId, let customerId):
            guard locationId == self.locationId else { return }
            Log.cart.debug("Customer \(customerId) added to queue")
            await loadQueue()

        case .queueCustomerRemoved(let locationId, let customerId):
            guard locationId == self.locationId else { return }
            Log.cart.debug("Customer \(customerId) removed from queue")
            await loadQueue()

        default:
            break
        }
    }

    // MARK: - Queue Operations

    /// Load queue from backend
    func loadQueue() async {
        isLoading = true
        error = nil

        do {
            let entries = try await LocationQueueService.shared.getQueue(locationId: locationId)

            // Notify observers
            objectWillChange.send()
            queue = entries

            // If we have entries but no selection, select the first one
            if selectedCartId == nil, let first = entries.first {
                selectedCartId = first.cartId
            }

            // If selected cart is no longer in queue, clear selection
            if let selectedId = selectedCartId, !entries.contains(where: { $0.cartId == selectedId }) {
                selectedCartId = entries.first?.cartId
            }

            isLoading = false
            // Post notification for UI updates
            NotificationCenter.default.post(name: .queueDidChange, object: locationId)
            Log.cart.info("LocationQueueStore: Queue loaded with \(entries.count) entries")
        } catch {
            self.error = error.localizedDescription
            isLoading = false
        }
    }

    /// Refresh queue (for pull-to-refresh or manual refresh)
    func refresh() async {
        await loadQueue()
    }

    /// Add customer to queue
    func addToQueue(cartId: UUID, customerId: UUID?, userId: UUID?) async {
        do {
            let entries = try await LocationQueueService.shared.addToQueue(
                locationId: locationId,
                cartId: cartId,
                customerId: customerId,
                userId: userId
            )
            queue = entries
            selectedCartId = cartId
            // Post notification for UI updates
            NotificationCenter.default.post(name: .queueDidChange, object: locationId)
            Log.cart.info("LocationQueueStore: Added to queue, now \(entries.count) entries")
        } catch {
            self.error = error.localizedDescription
            Log.cart.error("LocationQueueStore: Failed to add to queue: \(error)")
        }
    }

    /// Remove customer from queue
    func removeFromQueue(cartId: UUID) async {
        do {
            let entries = try await LocationQueueService.shared.removeFromQueue(
                locationId: locationId,
                cartId: cartId
            )
            queue = entries

            // If we removed the selected cart, select the first remaining
            if selectedCartId == cartId {
                selectedCartId = entries.first?.cartId
            }
            // Post notification for UI updates
            NotificationCenter.default.post(name: .queueDidChange, object: locationId)
            Log.cart.info("LocationQueueStore: Removed from queue, now \(entries.count) entries")
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Clear entire queue
    func clearQueue() async {
        do {
            try await LocationQueueService.shared.clearQueue(locationId: locationId)
            queue = []
            selectedCartId = nil
            // Post notification for UI updates
            NotificationCenter.default.post(name: .queueDidChange, object: locationId)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Select a cart from the queue
    func selectCart(_ cartId: UUID) {
        if queue.contains(where: { $0.cartId == cartId }) {
            selectedCartId = cartId
        }
    }

    /// Select cart at index
    func selectCartAtIndex(_ index: Int) {
        guard index >= 0, index < queue.count else { return }
        selectedCartId = queue[index].cartId
    }

    // MARK: - Realtime (Legacy Compatibility)

    /// Subscribe to realtime updates (for backward compatibility)
    /// Now handled automatically by EventBus in init
    func subscribeToRealtime() {
        // EventBus subscription is set up in init - no-op for compatibility
        Log.cart.debug("LocationQueueStore: Using EventBus for realtime (legacy call ignored)")
    }

    /// Unsubscribe from realtime updates (for backward compatibility)
    func unsubscribeFromRealtime() {
        // EventBus manages connection lifecycle - no-op for compatibility
        Log.cart.debug("LocationQueueStore: EventBus manages connection (legacy call ignored)")
    }

    // MARK: - Polling (optional - for real-time sync without websockets)

    /// Start polling for queue updates
    func startPolling(interval: TimeInterval = 5.0) {
        stopPolling()
        pollingTask = Task {
            while !Task.isCancelled {
                await loadQueue()
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    /// Stop polling
    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    // MARK: - Cleanup

    static func removeStore(for locationId: UUID) {
        stores[locationId]?.stopPolling()
        stores[locationId]?.eventCancellable?.cancel()
        stores.removeValue(forKey: locationId)

        // Optionally disconnect from EventBus if this was the last store
        Task {
            await RealtimeEventBus.shared.disconnect(from: locationId)
        }
    }

    deinit {
        eventCancellable?.cancel()
        pollingTask?.cancel()
    }
}

// MARK: - Convenience Extensions

extension LocationQueueStore {
    /// Get entry at index
    func entry(at index: Int) -> QueueEntry? {
        guard index >= 0, index < queue.count else { return nil }
        return queue[index]
    }

    /// Get index of selected entry
    var selectedIndex: Int? {
        guard let cartId = selectedCartId else { return nil }
        return queue.firstIndex { $0.cartId == cartId }
    }

    /// Check if a cart is in the queue
    func contains(cartId: UUID) -> Bool {
        queue.contains { $0.cartId == cartId }
    }
}
