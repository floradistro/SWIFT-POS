//
//  FloatingCart.swift
//  Whale
//
//  Beautiful floating cart with glass effects and smooth animations.
//  Backend-driven customer queue shared across all registers at a location.
//

import SwiftUI
import Combine


struct FloatingCart: View {
    @ObservedObject var posStore: POSStore
    @Environment(\.posWindowSession) private var windowSession: POSWindowSession?
    @EnvironmentObject private var session: SessionObserver

    @StateObject private var paymentStore = PaymentStore()
    @StateObject private var dealStore = DealStore.shared
    @StateObject private var sheetCoordinator = SheetCoordinator.shared

    var onScanID: () -> Void
    var onFindCustomer: (() -> Void)?
    @Binding var selectedTab: POSTab

    // MARK: - State

    @State private var cartUpdateCounter = 0
    @State private var queueStore: LocationQueueStore?
    @State private var queueUpdateCounter = 0  // Incremented via NotificationCenter

    // MARK: - Computed Properties

    private var isMultiWindowSession: Bool {
        windowSession?.location != nil
    }

    private var effectiveLocationId: UUID? {
        windowSession?.locationId ?? session.selectedLocation?.id
    }

    // Queue from backend
    private var queue: [QueueEntry] {
        queueStore?.queue ?? []
    }

    private var selectedCartId: UUID? {
        queueStore?.selectedCartId
    }

    private var selectedEntry: QueueEntry? {
        queueStore?.selectedEntry
    }

    // Current cart data (from POSStore/WindowSession based on selected cart)
    private var activeCart: ServerCart? {
        guard let cartId = selectedCartId else { return nil }
        if isMultiWindowSession {
            return windowSession?.carts.first { $0.id == cartId }
        } else {
            return posStore.carts.first { $0.id == cartId }
        }
    }

    private var cartItems: [CartItem] {
        activeCart?.items.map { CartItem(from: $0) } ?? []
    }

    private var totals: CheckoutTotals? {
        activeCart?.totals
    }

    private var hasItems: Bool { !cartItems.isEmpty }
    private var itemCount: Int { cartItems.reduce(0) { $0 + $1.quantity } }

    // MARK: - Body

    private var shouldHide: Bool {
        sheetCoordinator.isPresenting
    }

    var body: some View {
        let _ = cartUpdateCounter
        let _ = queueUpdateCounter  // Force refresh when queue changes

        VStack(spacing: 8) {
            Spacer()

            // Customer queue tabs (when there are entries)
            if !queue.isEmpty {
                customerQueueTabs
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .bottom)),
                        removal: .opacity
                    ))
            }

            // Floating cart pill
            floatingCartPill

            // Swipe indicator below cart
            pageIndicator
        }
        .padding(.horizontal, 16)
        .padding(.bottom, SafeArea.bottom + 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .offset(y: shouldHide ? 200 : 0)
        .opacity(shouldHide ? 0 : 1)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: shouldHide)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: queue.count)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: hasItems)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: itemCount)
        .onReceive(NotificationCenter.default.publisher(for: .sheetOrderCompleted)) { notification in
            if let completion = notification.object as? SaleCompletion {
                handleCheckoutComplete(completion)
            }
        }
        .task(id: effectiveLocationId) {
            // Initialize queue store for this location
            guard let locationId = effectiveLocationId else { return }

            let store = LocationQueueStore.shared(for: locationId)
            queueStore = store

            await store.loadQueue()

            // Subscribe to realtime updates
            store.subscribeToRealtime()

            // Load the first cart from queue if one is selected
            if let cartId = store.selectedCartId {
                await loadAndSelectCart(cartId: cartId)
            }
        }
        .onDisappear {
            queueStore?.unsubscribeFromRealtime()
        }
        .onReceive(NotificationCenter.default.publisher(for: .queueDidChange)) { notification in
            // Update UI when queue changes (from any source - local or realtime)
            if let locationId = notification.object as? UUID, locationId == effectiveLocationId {
                queueUpdateCounter += 1
            }
        }
        .onReceive(windowSession?.objectWillChange.eraseToAnyPublisher() ?? Empty().eraseToAnyPublisher()) { _ in
            if isMultiWindowSession {
                cartUpdateCounter += 1
            }
        }
        .onReceive(posStore.objectWillChange) { _ in
            if !isMultiWindowSession {
                cartUpdateCounter += 1
            }
        }
    }

    // MARK: - Customer Queue Tabs

    private var customerQueueTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(queue) { entry in
                    customerTab(for: entry)
                }

                // Add customer button
                Button {
                    onFindCustomer?()
                } label: {
                    Image(systemName: "plus")
                        .font(Design.Typography.footnote).fontWeight(.semibold)
                        .foregroundStyle(Design.Colors.Text.tertiary)
                        .frame(width: 44, height: 44)
                        .glassEffect(.regular, in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add customer to queue")
            }
            .padding(.horizontal, 4)
        }
        .frame(maxWidth: 500)
    }

    private func customerTab(for entry: QueueEntry) -> some View {
        let isActive = entry.cartId == selectedCartId

        return Button {
            Haptics.selection()  // Subtle selection feedback for tab switch
            queueStore?.selectCart(entry.cartId)
            Task { await loadAndSelectCart(cartId: entry.cartId) }
        } label: {
            HStack(spacing: 6) {
                // Customer initials
                Text(entry.customerInitials)
                    .font(Design.Typography.caption1).fontWeight(.bold)
                    .foregroundStyle(Design.Colors.Text.primary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(isActive ? Color.accentColor : Design.Colors.Glass.ultraThick))

                // Item count if any
                if entry.cartItemCount > 0 {
                    Text("\(entry.cartItemCount)")
                        .font(Design.Typography.caption2Rounded).fontWeight(.semibold)
                        .foregroundStyle(Design.Colors.Text.tertiary)
                }

                // Remove button - no haptic, just visual
                Button {
                    Task { await removeFromQueue(cartId: entry.cartId) }
                } label: {
                    Image(systemName: "xmark")
                        .font(Design.Typography.caption2).fontWeight(.bold)
                        .foregroundStyle(Design.Colors.Text.disabled)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Design.Colors.Glass.ultraThick))
                        .padding(13)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(entry.customerName) from queue")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: .capsule)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Floating Cart Pill

    private var floatingCartPill: some View {
        HStack(spacing: 12) {
            // Customer avatar with menu or cart icon
            if let entry = selectedEntry {
                Menu {
                    Section {
                        Text(entry.customerName)
                    }

                    Button(role: .destructive) {
                        clearCurrentCart()
                    } label: {
                        Label("Clear Cart", systemImage: "trash")
                    }

                    Button(role: .destructive) {
                        Task { await removeFromQueue(cartId: entry.cartId) }
                    } label: {
                        Label("Remove Customer", systemImage: "person.badge.minus")
                    }
                } label: {
                    Text(entry.customerInitials)
                        .font(Design.Typography.footnote).fontWeight(.bold)
                        .foregroundStyle(Design.Colors.Text.primary)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.accentColor))
                }
            } else {
                Image(systemName: "cart.fill")
                    .font(Design.Typography.headline).fontWeight(.medium)
                    .foregroundStyle(Design.Colors.Text.disabled)
                    .frame(width: 36, height: 36)
                    .accessibilityHidden(true)
            }

            if hasItems {
                // Item count badge
                Text("\(itemCount)")
                    .font(Design.Typography.footnoteRounded).fontWeight(.bold)
                    .foregroundStyle(Design.Colors.Text.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Design.Colors.Glass.ultraThick))

                Spacer()

                // Total
                if let totals = totals {
                    Text(CurrencyFormatter.format(totals.total))
                        .font(Design.Typography.headlineRounded).fontWeight(.bold)
                        .foregroundStyle(Design.Colors.Text.primary)
                }

                // Checkout button
                Button {
                    Haptics.medium()
                    if let totals = totals {
                        SheetCoordinator.shared.present(.checkout(totals: totals, sessionInfo: buildSessionInfo()))
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "creditcard")
                            .font(Design.Typography.footnote).fontWeight(.semibold)
                        Text("Pay")
                            .font(Design.Typography.footnote).fontWeight(.bold)
                    }
                    .foregroundStyle(Design.Colors.Text.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Design.Colors.Semantic.success, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Checkout, pay \(CurrencyFormatter.format(totals?.total ?? 0))")
            } else if selectedEntry != nil {
                // Has customer but no items
                Text("Add items")
                    .font(Design.Typography.footnote).fontWeight(.medium)
                    .foregroundStyle(Design.Colors.Text.disabled)

                Spacer()
            } else {
                // No customer, no items
                Text("Add customer")
                    .font(Design.Typography.footnote).fontWeight(.medium)
                    .foregroundStyle(Design.Colors.Text.disabled)

                Spacer()

                // Add customer button - no haptic, just visual
                Button {
                    onFindCustomer?()
                } label: {
                    Image(systemName: "person.badge.plus")
                        .font(Design.Typography.callout).fontWeight(.medium)
                        .foregroundStyle(Design.Colors.Text.disabled)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .accessibilityLabel("Add customer")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: 500)
        .glassEffect(.regular, in: .capsule)
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
    }

    // MARK: - Page Indicator

    private var pageIndicator: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(selectedTab == .products ? Design.Colors.Text.primary : Design.Colors.Text.placeholder)
                .frame(width: 7, height: 7)

            Circle()
                .fill(selectedTab == .orders ? Design.Colors.Text.primary : Design.Colors.Text.placeholder)
                .frame(width: 7, height: 7)
        }
        .padding(.top, 4)
        .animation(.easeInOut(duration: 0.2), value: selectedTab)
        .accessibilityHidden(true)
    }

    // MARK: - Actions

    /// Load cart from server and select it (for queue integration)
    private func loadAndSelectCart(cartId: UUID) async {
        if isMultiWindowSession, let ws = windowSession {
            await ws.loadCartById(cartId)
        } else {
            await posStore.loadCartById(cartId)
        }
    }

    private func removeFromQueue(cartId: UUID) async {
        await queueStore?.removeFromQueue(cartId: cartId)

        // Also remove from local store
        if isMultiWindowSession, let ws = windowSession {
            if let cart = ws.carts.first(where: { $0.id == cartId }),
               let customerId = cart.customerId,
               let customer = ws.customer(for: customerId) {
                ws.removeCustomer(customer)
            }
        } else {
            if let cart = posStore.carts.first(where: { $0.id == cartId }),
               let customerId = cart.customerId {
                posStore.removeCustomer(customerId)
            }
        }
    }

    private func clearCurrentCart() {
        if isMultiWindowSession, let ws = windowSession {
            Task { await ws.clearCart() }
        } else {
            posStore.clearCart()
        }
    }

    private func buildSessionInfo() -> SessionInfo {
        if isMultiWindowSession, let ws = windowSession {
            return SessionInfo(
                storeId: session.storeId ?? session.store?.id ?? UUID(),
                locationId: ws.locationId ?? ws.location?.id ?? UUID(),
                registerId: ws.register?.id ?? session.selectedRegister?.id ?? UUID(),
                sessionId: ws.posSession?.id ?? ws.sessionId,
                userId: session.userId
            )
        }

        let location = session.selectedLocation
        return SessionInfo(
            storeId: session.storeId ?? session.store?.id ?? UUID(),
            locationId: location?.id ?? UUID(),
            registerId: session.selectedRegister?.id ?? UUID(),
            sessionId: UUID(),
            userId: session.userId
        )
    }

    private func handleCheckoutComplete(_ order: SaleCompletion?) {
        guard let cartId = selectedCartId else { return }

        Task {
            // Remove from backend queue (this updates selectedCartId to next cart)
            await queueStore?.removeFromQueue(cartId: cartId)

            // Clear the completed cart from local store
            if isMultiWindowSession, let ws = windowSession {
                await ws.clearCart()
            } else {
                await MainActor.run { posStore.clearCart() }
            }

            // Load the next customer's cart if one is now selected
            if let nextCartId = queueStore?.selectedCartId {
                await loadAndSelectCart(cartId: nextCartId)
            }
        }
    }
}
