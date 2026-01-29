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
    @State private var showScanner = false
    @State private var showSafeDropModal = false
    @State private var showCustomerSearch = false
    @State private var showPrinterSettings = false
    @State private var showRegisterPicker = false
    @State private var showTransferModal = false

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

    var body: some View {
        let _ = print("🛒 POSMainView.body - windowSession: \(windowSession != nil), locationId: \(effectiveLocationId?.uuidString ?? "nil"), storeId: \(effectiveStoreId?.uuidString ?? "nil")")
        ZStack {
            POSContentBrowser(
                selectedTab: $selectedTab,
                searchText: $searchText,
                productStore: productStore,
                orderStore: orderStore,
                onScanID: { showScanner = true },
                onFindCustomer: { showCustomerSearch = true },
                onSafeDrop: { showSafeDropModal = true },
                onPrinterSettings: { showPrinterSettings = true },
                onCreateTransfer: { showTransferModal = true },
                onEndSession: {
                    // Close window via Stage Manager
                    if let ws = windowSession {
                        // Find and close the window with matching session ID
                        if let window = StageManagerStore.shared.windows.first(where: {
                            if case .app(let sessionId) = $0.type {
                                return sessionId == ws.sessionId
                            }
                            return false
                        }) {
                            StageManagerStore.shared.close(window)
                        }
                    }
                    // Go back to Stage Manager
                    StageManagerStore.shared.show()
                },
                showRegisterPicker: $showRegisterPicker
            )

            // Floating cart at bottom
            FloatingCart(
                posStore: productStore,
                onScanID: { showScanner = true },
                onFindCustomer: { showCustomerSearch = true }
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
                            // Clear the error
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

            if showSafeDropModal {
                SafeDropModal(
                    posSession: placeholderPOSSession,  // TODO: Update in Phase 3
                    isPresented: $showSafeDropModal
                )
                .transition(.opacity)
            }
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showSafeDropModal)
        .sheet(isPresented: $showCustomerSearch) {
            if let storeId = effectiveStoreId {
                ManualCustomerEntrySheet(
                    storeId: storeId,
                    onCustomerCreated: { customer in
                        showCustomerSearch = false
                        handleCustomerSelected(customer)
                    },
                    onCancel: {
                        showCustomerSearch = false
                    }
                )
            }
        }
        .fullScreenCover(isPresented: $showScanner) {
            if let storeId = effectiveStoreId {
                IDScannerView(
                    storeId: storeId,
                    onCustomerSelected: { customer in
                        handleCustomerScanned(customer)
                    },
                    onDismiss: {
                        showScanner = false
                    }
                )
            }
        }
        .overlay {
            if showPrinterSettings {
                LabelPrinterSetupView(isPresented: $showPrinterSettings)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showPrinterSettings)
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
        showScanner = false
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
