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
    @StateObject private var productStore = POSStore.shared
    @StateObject private var orderStore = OrderStore.shared
    @StateObject private var multiSelect = MultiSelectManager.shared

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
        let _ = Log.session.debug("POSMainView.body - windowSession: \(windowSession != nil), locationId: \(effectiveLocationId?.uuidString ?? "nil"), storeId: \(effectiveStoreId?.uuidString ?? "nil")")

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

            VStack(spacing: 0) {
                // Top nav bar
                locationNavBar

                // Location cards — vertically centered
                Spacer(minLength: 24)

                locationCardGrid
                    .frame(maxWidth: 720)

                Spacer(minLength: 24)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await session.fetchLocations()
        }
    }

    // MARK: - Location Nav Bar

    private var locationNavBar: some View {
        HStack {
            // Left: orders-style icon button (settings on location screen)
            LiquidGlassIconButton(icon: "gearshape") {
                SheetCoordinator.shared.present(.posSettings)
            }

            Spacer()

            // Right: store logo button — same as POS homeMenuButton
            // Tap = switch store (if multi-store), long press = settings
            Button {
                Haptics.light()
                if session.hasMultipleStores {
                    SheetCoordinator.shared.present(.storePicker)
                }
            } label: {
                if let logoUrl = session.store?.fullLogoUrl {
                    CachedAsyncImage(url: logoUrl, placeholderLogoUrl: nil, dimAmount: 0)
                        .frame(width: 28, height: 28)
                        .clipShape(Circle())
                        .frame(width: 44, height: 44)
                } else {
                    Image(systemName: "building.2")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 44, height: 44)
                }
            }
            .buttonStyle(LiquidPressStyle())
            .glassEffect(.regular.interactive(), in: .circle)
        }
        .padding(.horizontal, 20)
        .padding(.top, SafeArea.top + 10)
    }

    // MARK: - Location Card Grid

    private var locationCardGrid: some View {
        VStack(spacing: 24) {
            // Title
            VStack(spacing: 6) {
                Text("Select Location")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)

                if let storeName = session.store?.businessName {
                    Text(storeName)
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }

            if session.locations.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "mappin.slash")
                        .font(.system(size: 36))
                        .foregroundStyle(.white.opacity(0.2))
                    Text("No locations available")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .padding(.top, 40)
            } else {
                VStack(spacing: 12) {
                    ForEach(session.locations) { location in
                        locationCard(location)
                    }
                }
                .padding(.horizontal, 24)
            }
        }
    }

    private func locationCard(_ location: Location) -> some View {
        let isSelected = session.selectedLocation?.id == location.id

        return Button {
            Haptics.medium()
            Task {
                await session.selectLocation(location)
            }
        } label: {
            HStack(spacing: 16) {
                // Store logo
                StoreLogo(
                    url: session.store?.fullLogoUrl,
                    size: 44,
                    storeName: session.store?.businessName
                )

                // Text
                VStack(alignment: .leading, spacing: 3) {
                    Text(location.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)

                    if let address = location.displayAddress {
                        Text(address)
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.4))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                // Type pill
                Text(location.type.capitalized)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.06), in: Capsule())

                // Checkmark
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.2))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.08) : Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        isSelected ? Color.white.opacity(0.2) : Color.white.opacity(0.06),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(GridCardPressStyle())
    }

    private func locationIcon(for location: Location) -> String {
        if location.isWarehouse { return "shippingbox.fill" }
        if location.isRetail { return "storefront.fill" }
        return "mappin.circle.fill"
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

            // Floating cart or bulk actions at bottom
            if multiSelect.isMultiSelectMode && multiSelect.hasSelection {
                floatingBulkActions
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .bottom)),
                        removal: .opacity
                    ))
            } else {
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
                    },
                    selectedTab: $selectedTab
                )
            }

            // Error sheet (shown via SheetCoordinator)
            EmptyView()
                .onChange(of: cartError) { _, error in
                    if let error = error {
                        SheetCoordinator.shared.showError(title: "Cart Error", message: error)
                        // Clear the error after showing
                        if isMultiWindowSession {
                            windowSession?.clearCartError()
                        } else {
                            productStore.clearCartError()
                        }
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

                Log.session.debug("POSMainView: Loading products into windowSession for location \(ws.location?.name ?? "unknown")")
                Log.cart.info("POSMainView.task starting - storeId: \(storeId), locationId: \(effectiveLocationId?.uuidString ?? "nil"), isMultiWindow: true")

                // Configure stores with this window's location
                if let locationId = effectiveLocationId {
                    // Connect to EventBus for realtime cart/queue updates
                    await RealtimeEventBus.shared.connect(to: locationId)

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
                    // Connect to EventBus for realtime cart/queue updates
                    await RealtimeEventBus.shared.connect(to: locationId)

                    productStore.configure(storeId: storeId, locationId: locationId)
                    orderStore.configure(storeId: storeId, locationId: locationId)

                    async let products: () = productStore.loadProducts()
                    async let orders: () = orderStore.loadOrders()

                    _ = await (products, orders)
                }
            }
        }
    }

    // MARK: - Floating Bulk Actions

    private var floatingBulkActions: some View {
        VStack(spacing: 8) {
            Spacer()

            HStack(spacing: 12) {
                // Selection count
                Text("\(multiSelect.selectedCount) selected")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)

                Spacer()

                if multiSelect.isProductSelectMode {
                    // Print labels
                    Button {
                        Haptics.medium()
                        let selected = productStore.products.filter { multiSelect.isProductSelected($0.id) }
                        SheetCoordinator.shared.present(.labelTemplate(products: selected)) {
                            multiSelect.exitMultiSelect()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "printer.fill")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Print")
                                .font(.system(size: 14, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(LiquidPressStyle())
                    .glassEffect(.regular.interactive(), in: .capsule)

                    // Export CSV
                    Button {
                        Haptics.medium()
                        exportSelectedProducts()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Export")
                                .font(.system(size: 14, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(LiquidPressStyle())
                    .glassEffect(.regular.interactive(), in: .capsule)
                } else {
                    // Order bulk actions
                    Button {
                        Haptics.medium()
                        let selected = orderStore.orders.filter { multiSelect.isSelected($0.id) }
                        SheetCoordinator.shared.present(.orderLabelTemplate(orders: selected)) {
                            multiSelect.exitMultiSelect()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "printer.fill")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Print")
                                .font(.system(size: 14, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(LiquidPressStyle())
                    .glassEffect(.regular.interactive(), in: .capsule)

                    Button {
                        Haptics.medium()
                        bulkMarkReady()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Ready")
                                .font(.system(size: 14, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(LiquidPressStyle())
                    .glassEffect(.regular.interactive(), in: .capsule)
                }

                // Cancel
                Button {
                    Haptics.light()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        multiSelect.exitMultiSelect()
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(LiquidPressStyle())
                .glassEffect(.regular.interactive(), in: .circle)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: 500)
            .glassEffect(.regular, in: .capsule)
            .shadow(color: .black.opacity(0.3), radius: 20, y: 10)

            // Page indicator
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.white.opacity(selectedTab == .products ? 0.9 : 0.3))
                    .frame(width: 7, height: 7)
                Circle()
                    .fill(Color.white.opacity(selectedTab == .orders ? 0.9 : 0.3))
                    .frame(width: 7, height: 7)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, SafeArea.bottom + 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: multiSelect.selectedCount)
    }

    private func exportSelectedProducts() {
        let selectedProducts = productStore.products.filter { multiSelect.isProductSelected($0.id) }
        var csv = "Name,SKU,Price,Category\n"
        for product in selectedProducts {
            let name = product.name.replacingOccurrences(of: ",", with: ";")
            let sku = product.sku ?? ""
            let price = CurrencyFormatter.format(product.displayPrice)
            let category = product.categoryName ?? ""
            csv += "\(name),\(sku),\(price),\(category)\n"
        }

        let data = csv.data(using: .utf8) ?? Data()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("products_export.csv")
        try? data.write(to: url)

        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = rootVC.view
                popover.sourceRect = CGRect(x: rootVC.view.bounds.midX, y: rootVC.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            rootVC.present(activityVC, animated: true)
        }

        Haptics.success()
        multiSelect.exitMultiSelect()
    }

    private func bulkMarkReady() {
        Task {
            let selectedIds = Array(multiSelect.selectedOrderIds)
            for orderId in selectedIds {
                await orderStore.updateStatus(orderId: orderId, status: .ready)
            }
            Haptics.success()
            multiSelect.exitMultiSelect()
        }
    }

    private func handleCustomerScanned(_ customer: Customer) {
        Task {
            await addCustomerToQueue(customer)
        }
        Haptics.success()
    }

    private func handleCustomerSelected(_ customer: Customer) {
        Log.cart.debug("handleCustomerSelected: \(customer.firstName ?? "?") \(customer.lastName ?? "?")")
        Task {
            await addCustomerToQueue(customer)
        }
        Haptics.success()
    }

    /// Add customer to cart and backend location queue
    private func addCustomerToQueue(_ customer: Customer) async {
        let locationId = effectiveLocationId
        Log.cart.debug("addCustomerToQueue: customer=\(customer.firstName ?? "?") \(customer.lastName ?? "?"), locationId=\(locationId?.uuidString ?? "NIL")")

        // First, add customer to local cart (creates server cart)
        var cartId: UUID?
        if isMultiWindowSession, let ws = windowSession {
            await ws.addCustomer(customer)
            if let error = ws.cartError {
                Log.cart.error("Failed to add customer: \(error)")
                return
            }
            cartId = ws.activeCart?.id
            Log.cart.debug("addCustomerToQueue: windowSession cart created, cartId=\(cartId?.uuidString ?? "NIL")")
        } else {
            await productStore.addCustomer(customer)
            if let error = productStore.cartError {
                Log.cart.error("Failed to add customer: \(error)")
                return
            }
            cartId = productStore.activeCart?.id
            Log.cart.debug("addCustomerToQueue: productStore cart created, cartId=\(cartId?.uuidString ?? "NIL")")
        }

        // Then add to backend location queue
        guard let locationId = locationId, let cartId = cartId else {
            Log.cart.error("addCustomerToQueue: FAILED - locationId=\(locationId?.uuidString ?? "NIL"), cartId=\(cartId?.uuidString ?? "NIL")")
            return
        }

        Log.cart.info("addCustomerToQueue: Adding to queue - locationId=\(locationId), cartId=\(cartId)")
        let queueStore = LocationQueueStore.shared(for: locationId)
        await queueStore.addToQueue(
            cartId: cartId,
            customerId: customer.id,
            userId: session.userId
        )
        Log.cart.info("addCustomerToQueue: Done!")
    }

}

// MARK: - Preview

#Preview {
    POSMainView()
        .environmentObject(SessionObserver.shared)
}
