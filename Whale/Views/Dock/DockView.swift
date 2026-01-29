//  DockView.swift - Smart Dock command center for POS operations

import SwiftUI
import Combine
import os.log

struct DockView: View {
    @ObservedObject var posStore: POSStore
    @ObservedObject var orderStore: OrderStore
    let posSession: POSSession
    @EnvironmentObject private var session: SessionObserver
    @Environment(\.posWindowSession) private var windowSession: POSWindowSession?

    var onScanID: () -> Void
    var onEndSession: () -> Void
    var onSafeDrop: (() -> Void)?
    var onFindCustomer: (() -> Void)?
    var onCreateTransfer: (() -> Void)?
    var onPrinterSettings: (() -> Void)?

    // MARK: - State

    @State private var expansion: DockExpansion = .collapsed
    @ObservedObject private var tabManager = DockTabManager.shared
    @ObservedObject private var multiSelect = MultiSelectManager.shared
    @ObservedObject private var modalManager = ModalManager.shared

    @State private var pulseScale: CGFloat = 1.0
    @State private var isFirstRun = true

    // Checkout state
    @StateObject private var paymentStore = PaymentStore()
    @State private var selectedPaymentMethod: DockPaymentMethod = .card
    @State private var cashAmount: String = ""
    @State private var splitCashAmount: String = ""
    @State private var card1Percentage: Double = 50
    @State private var showErrorAlert = false
    @State private var errorMessage = ""

    // Invoice
    @State private var invoiceNotes: String = ""
    @State private var invoiceEmail: String = ""
    @State private var invoiceDueDate: Date = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var showDueDatePicker = false

    // Loyalty points redemption
    @State private var pointsToRedeem: Int = 0
    @State private var loyaltyDiscountAmount: Decimal = 0
    @ObservedObject private var dealStore = DealStore.shared

    // Success
    @State private var completedOrder: SaleCompletion?
    @State private var copiedLink = false
    @State private var autoPrintFailed = false

    // Processing amount (for split/multi-card to show the current charge amount)
    @State private var processingAmount: Decimal?
    @State private var processingLabel: String?

    // Order detail modal
    @State private var selectedOrderForDetail: Order?
    @State private var showOrderDetailModal = false

    // Register picker modal (for isolated windows)
    @State private var showRegisterPicker = false

    // Checkout sheet (backend-driven)
    @State private var showCheckoutSheet = false

    // Trigger re-render when windowSession publishes changes
    @State private var windowSessionUpdateTrigger = UUID()

    // MARK: - Cart Accessors
    // Use windowSession ONLY when it has a location (multi-window mode)
    // Main window has windowSession but no location - fall back to posStore

    /// True only when this is a multi-window session with its own location
    private var isMultiWindowSession: Bool {
        windowSession?.location != nil
    }

    private var carts: [ServerCart] {
        isMultiWindowSession ? (windowSession?.carts ?? []) : posStore.carts
    }

    private var activeCartIndex: Int {
        isMultiWindowSession ? (windowSession?.activeCartIndex ?? -1) : posStore.activeCartIndex
    }

    private var activeCart: ServerCart? {
        isMultiWindowSession ? windowSession?.activeCart : posStore.activeCart
    }

    private var cartItems: [CartItem] {
        isMultiWindowSession ? (windowSession?.cartItems ?? []) : posStore.cartItems
    }

    private var selectedCustomer: Customer? {
        isMultiWindowSession ? windowSession?.selectedCustomer : posStore.selectedCustomer
    }

    // MARK: - Computed

    private var hasItems: Bool { !cartItems.isEmpty }
    private var hasCustomer: Bool { selectedCustomer != nil }

    /// Use session carts for tab logic when available (multi-window support)
    private var hasTabs: Bool {
        !carts.isEmpty || !tabManager.orderTabs.isEmpty
    }

    private var dockStateHash: Int {
        var hasher = Hasher()
        hasher.combine(hasItems)
        hasher.combine(hasCustomer)
        hasher.combine(carts.count)
        hasher.combine(activeCartIndex)
        // Include trigger to force re-compute when windowSession publishes changes
        hasher.combine(windowSessionUpdateTrigger)
        return hasher.finalize()
    }

    /// Checkout totals from server (all calculations done backend)
    private var totals: CheckoutTotals? {
        activeCart?.totals
    }

    /// Session info for payments - uses windowSession when in isolated mode
    private var sessionInfo: SessionInfo? {
        // Use windowSession when available (isolated mode)
        if isMultiWindowSession, let ws = windowSession {
            guard let storeId = session.storeId,
                  let locationId = ws.locationId,
                  let registerId = ws.register?.id else { return nil }
            return SessionInfo(
                storeId: storeId,
                locationId: locationId,
                registerId: registerId,
                sessionId: ws.posSession?.id ?? ws.sessionId,
                userId: session.userId
            )
        }

        // Fall back to global session
        guard let storeId = session.storeId,
              let location = session.selectedLocation,
              let register = session.selectedRegister else { return nil }
        return SessionInfo(
            storeId: storeId,
            locationId: location.id,
            registerId: register.id,
            sessionId: posSession.id,
            userId: session.userId
        )
    }

    // Orders now open in OrderDetailModal, not inline in dock

    // MARK: - Sizing

    private var dockWidth: CGFloat {
        let baseWidth = DockSizing.baseWidth()
        if multiSelect.isMultiSelectMode { return baseWidth }

        if hasTabs && !hasItems {
            let tabCount = carts.count + tabManager.orderTabs.count
            let chipWidth: CGFloat = 100  // Wider for 48pt chips with text
            let buttonsWidth: CGFloat = 120
            let padding: CGFloat = 32
            return min(baseWidth, CGFloat(tabCount) * chipWidth + buttonsWidth + padding)
        }

        switch expansion {
        case .collapsed:
            if !hasItems && !hasCustomer { return DockSizing.idleDockHeight }
            return min(baseWidth, 320)
        case .idleExpanded:
            return DockSizing.idleDockHeight
        case .standard:
            return min(baseWidth, 380)
        case .checkout, .processing, .success:
            return baseWidth
        }
    }

    private var dockHeight: CGFloat {
        if multiSelect.isMultiSelectMode && multiSelect.hasSelection { return 120 }

        switch expansion {
        case .collapsed, .standard:
            if hasTabs {
                if hasItems {
                    return DockSizing.tabBarHeight + DockSizing.cartContentHeight
                } else {
                    // Customer selected but no items - tab bar shows customer info, no extra content
                    return DockSizing.tabBarHeight
                }
            }
            return DockSizing.idleDockHeight
        case .idleExpanded:
            return DockSizing.idleDockHeight
        case .checkout:
            // Dynamic height based on content
            // Deals/loyalty now handled server-side, simplified height calc
            return DockSizing.checkoutHeight(
                for: selectedPaymentMethod,
                itemCount: cartItems.count,
                hasDeals: false,
                hasLoyalty: false
            )
        case .processing:
            return 200
        case .success:
            return 280
        }
    }

    private var needsDismissOverlay: Bool {
        expansion == .checkout
    }

    private var isCheckoutExpanded: Bool {
        expansion == .checkout || expansion == .processing || expansion == .success
    }

    private var shouldHideDock: Bool {
        modalManager.isModalOpen || showCheckoutSheet
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            if needsDismissOverlay && !shouldHideDock {
                Color.black.opacity(0.01)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { dismissExpandedState() }
                    .transition(.opacity)
                    .zIndex(0)
            }

            dockContainer
                .frame(width: dockWidth, height: dockHeight)
                .padding(.bottom, isCheckoutExpanded ? 0 : 12)
                .background(dockAnchorUpdater)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: isCheckoutExpanded ? .center : .bottom)
                .zIndex(1)
                .offset(y: shouldHideDock ? 200 : 0)
                .opacity(shouldHideDock ? 0 : 1)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: shouldHideDock)
                .animation(.spring(response: 0.5, dampingFraction: 0.85), value: isCheckoutExpanded)

            // Order detail modal - opens when tapping order tab
            if showOrderDetailModal, let order = selectedOrderForDetail {
                OrderDetailModal(order: order, store: orderStore, isPresented: $showOrderDetailModal)
                    .zIndex(10)
            }

        }
        .sheet(isPresented: $showRegisterPicker) {
            RegisterPickerSheetContent(
                isPresented: $showRegisterPicker,
                windowSession: windowSession
            )
        }
        .sheet(isPresented: $showCheckoutSheet) {
            if let totals = totals {
                CheckoutSheet(
                    posStore: posStore,
                    paymentStore: paymentStore,
                    dealStore: dealStore,
                    totals: totals,
                    sessionInfo: buildSessionInfo(),
                    onScanID: onScanID,
                    onComplete: handleCheckoutComplete
                )
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: expansion)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: hasItems)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: hasCustomer)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: tabManager.activeTab)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: multiSelect.isMultiSelectMode)
        .scaleEffect(pulseScale)
        .onAppear { setupOrderNotifications() }
        .onReceive(windowSession?.objectWillChange.eraseToAnyPublisher() ?? Empty().eraseToAnyPublisher()) { _ in
            // Force re-render when windowSession publishes changes (only for multi-window)
            if isMultiWindowSession {
                windowSessionUpdateTrigger = UUID()
            }
        }
        .onChange(of: cartItems.count) { old, new in handleCartChange(from: old, to: new) }
        .onChange(of: tabManager.activeTab) { _, tab in handleTabChange(tab) }
        .task(id: dockStateHash) {
            guard !isFirstRun else { isFirstRun = false; return }
            try? await Task.sleep(nanoseconds: 50_000_000)
            await MainActor.run { updateDockExpansion() }
        }
        // Deals now loaded server-side as part of cart calculation
        .onChange(of: showOrderDetailModal) { _, isShowing in
            if !isShowing { selectedOrderForDetail = nil }
        }
    }

    // MARK: - Dock Container

    private var dockContainer: some View {
        GlassDockContainer(cornerRadius: 28) {
            dockContent
        }
        .shadow(color: .black.opacity(isEmptyState ? 0.15 : 0.3), radius: isEmptyState ? 15 : 20, y: isEmptyState ? 6 : 10)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isEmptyState)
    }

    private var isEmptyState: Bool {
        !hasItems && !hasCustomer && expansion == .collapsed
    }

    private var dockAnchorUpdater: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear { updateDockAnchor(geo) }
                .onChange(of: geo.frame(in: .global)) { _, _ in updateDockAnchor(geo) }
        }
    }

    // MARK: - Dock Content

    @ViewBuilder
    private var dockContent: some View {
        VStack(spacing: 0) {
            if multiSelect.isMultiSelectMode && multiSelect.hasSelection {
                DockBulkActionsView(multiSelect: multiSelect, posStore: posStore, orderStore: orderStore)
            } else {
                if hasTabs && expansion != .checkout && expansion != .processing && expansion != .success {
                    DockTabBar(
                        tabManager: tabManager,
                        posStore: posStore,
                        onScanCustomer: onScanID,
                        onAddCustomer: onFindCustomer,
                        onClearAll: clearEverything,
                        onOpenOrder: { order in
                            selectedOrderForDetail = order
                            showOrderDetailModal = true
                        }
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // Orders are shown via OrderDetailModal, not inline in the dock
                cartTabContent
            }
        }
    }

    @ViewBuilder
    private var cartTabContent: some View {
        switch expansion {
        case .collapsed, .standard, .idleExpanded:
            if hasItems {
                DockCartContent(posStore: posStore) {
                    showCheckoutSheet = true
                }
            } else if !hasTabs {
                // No tabs = no customer, show idle state with menu
                DockIdleContent(
                    storeLogoUrl: session.store?.fullLogoUrl,
                    onScanID: onScanID,
                    onFindCustomer: onFindCustomer,
                    onSafeDrop: onSafeDrop,
                    onCreateTransfer: onCreateTransfer,
                    onPrinterSettings: onPrinterSettings,
                    onAskLisa: { /* AI chat moved to Stage Manager */ },
                    onEndSession: onEndSession,
                    showRegisterPicker: $showRegisterPicker
                )
            }
            // NOTE: When hasTabs is true but hasItems is false, we show nothing here
            // because DockTabBar already displays the customer tabs above this content
        case .checkout, .processing, .success:
            // These states are now handled by CheckoutSheet
            EmptyView()
        }
    }
}

// MARK: - Handlers Extension

extension DockView {
    private func dismissExpandedState() {
        Haptics.light()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            expansion = hasItems ? .standard : .collapsed
        }
    }

    private func dismissCheckout() {
        Haptics.light()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            expansion = hasItems ? .standard : .collapsed
        }
    }

    private func buildSessionInfo() -> SessionInfo {
        // Use windowSession when available (isolated mode)
        if isMultiWindowSession, let ws = windowSession {
            return SessionInfo(
                storeId: session.storeId ?? session.store?.id ?? UUID(),
                locationId: ws.locationId ?? ws.location?.id ?? UUID(),
                registerId: ws.register?.id ?? session.selectedRegister?.id ?? posSession.registerId,
                sessionId: ws.posSession?.id ?? ws.sessionId,
                userId: session.userId
            )
        }

        // Fall back to global session
        let location = session.selectedLocation
        return SessionInfo(
            storeId: session.storeId ?? session.store?.id ?? UUID(),
            locationId: location?.id ?? UUID(),
            registerId: session.selectedRegister?.id ?? posSession.registerId,
            sessionId: posSession.id,
            userId: session.userId
        )
    }

    private func handleCheckoutComplete(_ completion: SaleCompletion?) {
        guard let completion = completion else { return }

        completedOrder = completion
        // Auto-print is handled by CheckoutSheet

        // Reload products from appropriate source
        if let windowSession = windowSession {
            Task { await windowSession.refresh() }
        } else {
            Task { await posStore.refresh() }
        }

        // Clear the cart after successful payment
        if let customer = selectedCustomer {
            if let windowSession = windowSession {
                windowSession.removeCustomer(customer)
            } else {
                tabManager.removeCustomer(customer.id)
            }
        }

        paymentStore.reset()
        resetCheckoutState()
    }

    private func resetCheckoutState() {
        selectedPaymentMethod = .card
        cashAmount = ""
        splitCashAmount = ""
        card1Percentage = 50
        invoiceNotes = ""
        invoiceEmail = ""
        invoiceDueDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        showDueDatePicker = false
        pointsToRedeem = 0
        loyaltyDiscountAmount = 0
        completedOrder = nil
        copiedLink = false
        autoPrintFailed = false
        processingAmount = nil
        processingLabel = nil
    }

    private func clearEverything() {
        Haptics.medium()
        // Use session-specific clearing when in multi-window mode
        if let session = windowSession {
            // Clear all carts in this window session
            for cart in session.carts {
                if let customerId = cart.customerId, let customer = session.customer(for: customerId) {
                    session.removeCustomer(customer)
                }
            }
        } else {
            tabManager.clearAll()
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { expansion = .collapsed }
    }

    private func handleCartChange(from oldCount: Int, to newCount: Int) {
        if newCount > oldCount {
            Haptics.medium()
            pulseAnimation()
            if expansion == .collapsed {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { expansion = .standard }
            }
        } else if newCount == 0 && oldCount > 0 {
            Haptics.light()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                expansion = hasCustomer ? .standard : .collapsed
            }
        }
    }

    private func handleTabChange(_ tab: DockTabType) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            switch tab {
            case .cart, .customerCart:
                expansion = hasItems ? .standard : (hasCustomer ? .standard : .collapsed)
            case .order:
                expansion = .standard
            }
        }
    }

    private func updateDockExpansion() {
        guard expansion != .success else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            if !hasItems && !hasCustomer && carts.count == 0 && !hasTabs {
                expansion = .collapsed
            } else if !hasItems && expansion != .idleExpanded {
                expansion = hasCustomer ? .standard : .collapsed
            }
        }
    }

    private func pulseAnimation() {
        withAnimation(.default) { pulseScale = 1.03 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.default) { pulseScale = 1.0 }
        }
    }

    private func updateDockAnchor(_ geo: GeometryProxy) {
        // Dock anchor tracking removed - no longer needed with native sheet presentation
    }

    private func setupOrderNotifications() {
        orderStore.onNewOrderForLocation = { order in
            DockTabManager.shared.addOrderNotification(order)
        }
    }
}
