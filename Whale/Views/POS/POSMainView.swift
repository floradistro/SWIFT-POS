//
//  POSMainView.swift
//  Whale
//
//  Main POS interface - two columns: Cart + Products/Orders.
//  Swipeable tabs with shared search. Liquid glass, minimal, Apple quality.
//

import SwiftUI
import os.log

// MARK: - POS Tab

enum POSTab: String, CaseIterable {
    case products
    case orders

    var title: String {
        switch self {
        case .products: return "Products"
        case .orders: return "Orders"
        }
    }

    var icon: String {
        switch self {
        case .products: return "square.grid.2x2"
        case .orders: return "list.bullet.clipboard"
        }
    }
}

// MARK: - POS Main View

struct POSMainView: View {
    @EnvironmentObject private var session: SessionObserver
    @Environment(\.posWindowSession) private var windowSession: POSWindowSession?
    @ObservedObject private var productStore = POSStore.shared
    @ObservedObject private var orderStore = OrderStore.shared
    private let tabManager = DockTabManager.shared

    @State private var selectedTab: POSTab = .products
    @State private var searchText = ""
    @State private var showRegisterPicker = false

    // New launcher architecture: no more global posSession/onEndSession
    // Each window has its own windowSession with location + register

    /// The effective location for this view (from window session or global session)
    private var effectiveLocationId: UUID? {
        windowSession?.locationId ?? session.selectedLocation?.id
    }

    /// The effective store ID for this view (from location's store, supports multi-store)
    private var effectiveStoreId: UUID? {
        windowSession?.location?.storeId ?? session.selectedLocation?.storeId ?? session.storeId
    }

    /// The effective location object for this view
    private var effectiveLocation: Location? {
        windowSession?.location
    }

    /// The effective register object for this view
    private var effectiveRegister: Register? {
        windowSession?.register
    }

    /// True only when this is a multi-window session with its own location
    private var isMultiWindowSession: Bool {
        windowSession?.location != nil
    }

    /// Placeholder POSSession for DockView compatibility during migration
    /// This will be removed in Phase 4 when DockView is updated to use windowSession
    private var placeholderPOSSession: POSSession {
        POSSession.create(
            locationId: effectiveLocationId ?? UUID(),
            registerId: effectiveRegister?.id ?? UUID(),
            userId: session.publicUserId,
            openingCash: 0,
            notes: "Launcher window"
        )
    }

    /// Cart error from window session or product store
    private var cartError: String? {
        if isMultiWindowSession {
            return windowSession?.cartError
        }
        return productStore.cartError
    }

    @State private var showLocationPicker = false

    var body: some View {
        let _ = print("🛒 POSMainView.body - windowSession: \(windowSession != nil), locationId: \(effectiveLocationId?.uuidString ?? "nil"), storeId: \(effectiveStoreId?.uuidString ?? "nil")")

        // Show location picker if no location selected
        if effectiveLocationId == nil {
            locationRequiredView
        } else {
            mainPOSView
        }
    }

    // MARK: - Location Required View

    private var locationRequiredView: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack {
                Spacer()

                // Modal card
                VStack(spacing: 0) {
                    // Store logo
                    StoreLogo(
                        url: session.store?.fullLogoUrl,
                        size: 88,
                        storeName: session.store?.businessName
                    )
                    .shadow(color: .white.opacity(0.08), radius: 20)
                    .padding(.top, 32)
                    .padding(.bottom, 20)

                    // Content
                    VStack(spacing: 20) {
                        // Title
                        VStack(spacing: 6) {
                            Text("Welcome")
                                .font(.title2.bold())
                                .foregroundStyle(.white)

                            if let storeName = session.store?.businessName {
                                Text(storeName)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        // Multi-store selector (if applicable)
                        if session.hasMultipleStores {
                            storeSelector
                        }

                        // Location selector
                        locationSelector

                        // Continue button
                        if session.selectedLocation != nil {
                            Button {
                                Haptics.medium()
                                // Location is selected, view will update
                            } label: {
                                Text("Continue")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(Color.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14)
                                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                    )
                            }
                            .padding(.top, 8)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                }
                .frame(maxWidth: 400)
                .background(setupBackground)
                .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
                .shadow(color: .black.opacity(0.8), radius: 60, y: 25)
                .padding(.horizontal, 40)

                Spacer()
            }
        }
        .preferredColorScheme(.dark)
        .task {
            // Load locations when view appears
            await session.fetchLocations()
        }
    }

    // MARK: - Store Selector

    private var storeSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("STORE")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            Menu {
                ForEach(session.userStoreAssociations) { association in
                    Button {
                        Haptics.light()
                        Task {
                            await session.selectStore(association.storeId)
                            await session.fetchLocations()
                        }
                    } label: {
                        HStack {
                            Text(association.displayName)
                            if association.storeId == session.storeId {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "building.2")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                        .frame(width: 24)

                    Text(session.store?.businessName ?? "Select Store")
                        .font(.body)
                        .foregroundStyle(.white)

                    Spacer()

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
            }
        }
    }

    // MARK: - Location Selector

    private var locationSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LOCATION")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            if session.locations.isEmpty {
                HStack {
                    Image(systemName: "mappin.circle")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                        .frame(width: 24)

                    Text("No locations available")
                        .font(.body)
                        .foregroundStyle(.secondary)

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
            } else {
                VStack(spacing: 8) {
                    ForEach(session.locations) { location in
                        let isSelected = session.selectedLocation?.id == location.id

                        Button {
                            Haptics.light()
                            Task {
                                await session.selectLocation(location)
                            }
                        } label: {
                            HStack {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 18))
                                    .foregroundStyle(isSelected ? .white : .secondary)
                                    .frame(width: 24)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(location.name)
                                        .font(.body)
                                        .foregroundStyle(.white)

                                    if let address = location.displayAddress {
                                        Text(address)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                isSelected ? Color.white.opacity(0.12) : Color.white.opacity(0.06),
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(isSelected ? Color.white.opacity(0.2) : Color.white.opacity(0.08), lineWidth: 1)
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: - Modal Background

    private var setupBackground: some View {
        ZStack {
            // Dark base
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(Color(white: 0.08))

            // Subtle gradient overlay
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.06),
                            Color.white.opacity(0.02),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Border
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.15),
                            Color.white.opacity(0.05),
                            Color.white.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
    }

    // MARK: - Main POS View

    private var mainPOSView: some View {
        ZStack {
            POSContentBrowser(
                selectedTab: $selectedTab,
                searchText: $searchText,
                productStore: productStore,
                orderStore: orderStore,
                onScanID: {
                    if let storeId = effectiveStoreId {
                        SheetCoordinator.shared.present(.idScanner(storeId: storeId))
                    }
                },
                onFindCustomer: {
                    if let storeId = effectiveStoreId {
                        SheetCoordinator.shared.present(.customerSearch(storeId: storeId))
                    }
                },
                onSafeDrop: {
                    SheetCoordinator.shared.present(.safeDrop(session: placeholderPOSSession))
                },
                onPrinterSettings: {
                    SheetCoordinator.shared.present(.printerSettings)
                },
                onCreateTransfer: {
                    if let storeId = effectiveStoreId, let location = effectiveLocation ?? session.selectedLocation {
                        SheetCoordinator.shared.present(.createTransfer(storeId: storeId, sourceLocation: location))
                    }
                },
                onEndSession: {
                    Task {
                        await session.endPOSSession()
                    }
                },
                showRegisterPicker: $showRegisterPicker
            )

            // Floating cart at bottom
            FloatingCart(
                posStore: productStore,
                onScanID: {
                    if let storeId = effectiveStoreId {
                        SheetCoordinator.shared.present(.idScanner(storeId: storeId))
                    }
                },
                onFindCustomer: {
                    if let storeId = effectiveStoreId {
                        SheetCoordinator.shared.present(.customerSearch(storeId: storeId))
                    }
                }
            )

            // Error banner at top
            if let error = cartError {
                VStack {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text(error)
                            .font(.subheadline)
                        Spacer()
                        Button {
                            if isMultiWindowSession {
                                windowSession?.clearCartError()
                            } else {
                                productStore.clearCartError()
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding()
                    Spacer()
                }
            }
        }
        .background(Color.black)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .onReceive(NotificationCenter.default.publisher(for: .sheetCustomerSelected)) { notification in
            if let customer = notification.object as? Customer {
                handleCustomerSelected(customer)
            }
        }
        .task(id: effectiveLocationId) {
            // LAUNCHER ARCHITECTURE: Each window loads into its own windowSession
            // This provides true isolation - each window has its own products/carts

            if isMultiWindowSession, let ws = windowSession {
                // ISOLATED MODE: Load into windowSession (per-window data)
                // Get storeId from the location itself (supports multi-store)
                guard let storeId = ws.location?.storeId ?? session.storeId else {
                    Log.cart.info("POSMainView.task: No store ID, skipping loading")
                    return
                }

                print("🪟 POSMainView: Loading products into windowSession for location \(ws.location?.name ?? "unknown")")
                Log.cart.info("POSMainView.task starting - storeId: \(storeId), locationId: \(effectiveLocationId?.uuidString ?? "nil"), isMultiWindow: true")

                // Configure stores with this window's location
                if let locationId = effectiveLocationId {
                    // Configure both stores - POSStore as fallback, orderStore for orders view
                    productStore.configure(storeId: storeId, locationId: locationId)
                    orderStore.configure(storeId: storeId, locationId: locationId)
                }

                // Load products into windowSession (isolated per window)
                async let products: () = ws.loadProducts()
                async let orders: () = orderStore.loadOrders()

                _ = await (products, orders)
            } else {
                // LEGACY MODE: No windowSession, use global productStore (backwards compat)
                // Get storeId from selected location or session
                guard let storeId = session.selectedLocation?.storeId ?? session.storeId else {
                    Log.cart.info("POSMainView.task: No store ID, skipping loading")
                    return
                }

                Log.cart.info("POSMainView.task starting - storeId: \(storeId), locationId: \(session.selectedLocation?.id.uuidString ?? "nil"), isMultiWindow: false")

                let locationId = session.selectedLocation?.id
                if let locationId = locationId {
                    productStore.configure(storeId: storeId, locationId: locationId)
                    orderStore.configure(storeId: storeId, locationId: locationId)

                    async let products: () = productStore.loadProducts()
                    async let orders: () = orderStore.loadOrders()

                    _ = await (products, orders)
                }
            }
        }
    }

    private func handleCustomerScanned(_ customer: Customer) {
        Task {
            await addCustomerToQueue(customer)
        }
        Haptics.success()
    }

    private func handleCustomerSelected(_ customer: Customer) {
        print("🛒 handleCustomerSelected: \(customer.firstName ?? "?") \(customer.lastName ?? "?")")
        Task {
            await addCustomerToQueue(customer)
        }
        Haptics.success()
    }

    /// Add customer to cart and backend location queue
    private func addCustomerToQueue(_ customer: Customer) async {
        let locationId = effectiveLocationId
        print("🛒 addCustomerToQueue: customer=\(customer.firstName ?? "?") \(customer.lastName ?? "?"), locationId=\(locationId?.uuidString ?? "NIL")")

        // First, add customer to local cart (creates server cart)
        var cartId: UUID?
        if isMultiWindowSession, let ws = windowSession {
            await ws.addCustomer(customer)
            if let error = ws.cartError {
                Log.cart.error("Failed to add customer: \(error)")
                return
            }
            cartId = ws.activeCart?.id
            print("🛒 addCustomerToQueue: windowSession cart created, cartId=\(cartId?.uuidString ?? "NIL")")
        } else {
            await productStore.addCustomer(customer)
            if let error = productStore.cartError {
                Log.cart.error("Failed to add customer: \(error)")
                return
            }
            cartId = productStore.activeCart?.id
            print("🛒 addCustomerToQueue: productStore cart created, cartId=\(cartId?.uuidString ?? "NIL")")
        }

        // Then add to backend location queue
        guard let locationId = locationId, let cartId = cartId else {
            print("🛒 addCustomerToQueue: FAILED - locationId=\(locationId?.uuidString ?? "NIL"), cartId=\(cartId?.uuidString ?? "NIL")")
            return
        }

        print("🛒 addCustomerToQueue: Adding to queue - locationId=\(locationId), cartId=\(cartId)")
        let queueStore = LocationQueueStore.shared(for: locationId)
        await queueStore.addToQueue(
            cartId: cartId,
            customerId: customer.id,
            userId: session.userId
        )
        print("🛒 addCustomerToQueue: Done!")
    }

}

// MARK: - Preview

#Preview {
    POSMainView()
        .environmentObject(SessionObserver.shared)
}
