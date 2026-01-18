//
//  DockTabs.swift
//  Whale
//
//  Tab system for Smart Dock multi-customer support.
//  Simple view layer - POSStore owns the cart data.
//

import SwiftUI
import Combine
import os.log

// MARK: - Dock Tab Manager

/// Manages the visual tab state - syncs with POSStore for actual cart data
@MainActor
final class DockTabManager: ObservableObject {
    static let shared = DockTabManager()

    private var posStore: POSStore { POSStore.shared }

    /// Order tabs (separate from customer carts)
    @Published var orderTabs: [Order] = []
    @Published var activeOrderId: UUID?

    private init() {
        // NOTE: We no longer forward POSStore changes here.
        // DockTabManager only notifies on its OWN state changes (orderTabs, activeOrderId).
        // Views that need POSStore updates should observe POSStore directly.
        // This prevents double-render cascades that were causing freezing.
    }

    // MARK: - Computed Properties

    /// All customer carts from POSStore (server-side carts)
    var customerCarts: [ServerCart] {
        posStore.carts
    }

    /// Currently active cart index
    var activeCartIndex: Int {
        posStore.activeCartIndex
    }

    /// Whether we have any tabs to show
    var hasTabs: Bool {
        !posStore.carts.isEmpty || !orderTabs.isEmpty
    }

    /// Whether there are multiple tabs
    var hasMultipleTabs: Bool {
        posStore.carts.count + orderTabs.count >= 1
    }

    /// Check if showing an order tab
    var isShowingOrder: Bool {
        activeOrderId != nil
    }

    /// Current active tab type for the dock
    var activeTab: DockTabType {
        if let orderId = activeOrderId, let order = orderTabs.first(where: { $0.id == orderId }) {
            return .order(order)
        }
        if posStore.activeCart != nil, let customer = posStore.selectedCustomer {
            return .customerCart(customer)
        }
        return .cart(nil)
    }

    // MARK: - Customer Actions

    func addCustomer(_ customer: Customer) {
        activeOrderId = nil  // Deselect any order
        Task { await posStore.addCustomer(customer) }
    }

    func selectCustomer(_ customerId: UUID) {
        activeOrderId = nil
        posStore.switchToCustomer(customerId)
    }

    func selectCartAtIndex(_ index: Int) {
        activeOrderId = nil
        posStore.switchToCartAtIndex(index)
    }

    func removeCustomer(_ customerId: UUID) {
        posStore.removeCustomer(customerId)
    }

    func clearAll() {
        posStore.clearAllCarts()
        orderTabs.removeAll()
        activeOrderId = nil
    }

    // MARK: - Order Actions

    func openOrder(_ order: Order) {
        if !orderTabs.contains(where: { $0.id == order.id }) {
            orderTabs.append(order)
        }
        activeOrderId = order.id
    }

    /// Add order as a tab notification (doesn't select it, just adds to tabs)
    /// Used when new orders arrive for this location via real-time
    func addOrderNotification(_ order: Order) {
        guard !orderTabs.contains(where: { $0.id == order.id }) else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            orderTabs.insert(order, at: 0)
        }
        Haptics.success()
        Log.ui.info("DockTabManager: Added order notification - \(order.orderNumber)")
    }

    func closeOrder(_ orderId: UUID) {
        orderTabs.removeAll { $0.id == orderId }
        if activeOrderId == orderId {
            activeOrderId = nil
            // Switch back to first cart if available
            if !posStore.carts.isEmpty {
                posStore.switchToCartAtIndex(0)
            }
        }
    }

    func selectOrder(_ orderId: UUID) {
        activeOrderId = orderId
    }

    /// Update an order in the tabs (when order data changes)
    func updateOrder(_ order: Order) {
        if let index = orderTabs.firstIndex(where: { $0.id == order.id }) {
            orderTabs[index] = order
        }
    }

}

// MARK: - DockTabType

enum DockTabType: Equatable, Hashable {
    case cart(Customer?)
    case customerCart(Customer)
    case order(Order)

    var id: String {
        switch self {
        case .cart(let customer):
            return customer != nil ? "cart-\(customer!.id)" : "cart"
        case .order(let order):
            return "order-\(order.id)"
        case .customerCart(let customer):
            return "customer-cart-\(customer.id)"
        }
    }

    var customer: Customer? {
        switch self {
        case .cart(let customer): return customer
        case .customerCart(let customer): return customer
        case .order: return nil
        }
    }

    var isCartTab: Bool {
        switch self {
        case .cart, .customerCart: return true
        case .order: return false
        }
    }

    static func == (lhs: DockTabType, rhs: DockTabType) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Dock Tab Bar
// Apple HIG: 44pt minimum touch targets for all interactive elements

struct DockTabBar: View {
    @ObservedObject var tabManager: DockTabManager
    @ObservedObject var posStore: POSStore
    @Environment(\.posWindowSession) private var windowSession: POSWindowSession?

    let onScanCustomer: (() -> Void)?
    var onAddCustomer: (() -> Void)?
    var onClearAll: (() -> Void)?
    var onOpenOrder: ((Order) -> Void)?

    // Trigger re-render when windowSession publishes changes
    @State private var windowSessionUpdateTrigger = UUID()

    // Apple HIG constants - increased for better touch targets
    private let tabBarHeight: CGFloat = 72

    // MARK: - Session Accessors
    // Use windowSession ONLY when it has a location (multi-window mode)

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

    private func getCustomer(for customerId: UUID?) -> Customer? {
        isMultiWindowSession
            ? windowSession?.customer(for: customerId)
            : posStore.customer(for: customerId)
    }

    private var hasTabs: Bool {
        !carts.isEmpty || !tabManager.orderTabs.isEmpty
    }

    var body: some View {
        HStack(spacing: 8) {
            // Customer cart tabs
            ForEach(Array(carts.enumerated()), id: \.element.id) { index, cart in
                if let customer = getCustomer(for: cart.customerId) {
                    CustomerTabChip(
                        customer: customer,
                        itemCount: cart.itemCount,
                        isActive: !tabManager.isShowingOrder && activeCartIndex == index,
                        onTap: {
                            Haptics.light()
                            if let session = windowSession {
                                // Switch in session - just use the customer we already have
                                session.switchToCustomer(customer)
                            } else {
                                tabManager.selectCartAtIndex(index)
                            }
                        },
                        onClose: {
                            Haptics.medium()
                            if let session = windowSession {
                                session.removeCustomer(customer)
                            } else if let customerId = cart.customerId {
                                tabManager.removeCustomer(customerId)
                            }
                        }
                    )
                }
            }

            // Order tabs - tapping opens OrderDetailModal
            ForEach(tabManager.orderTabs, id: \.id) { order in
                OrderTabChip(
                    order: order,
                    isActive: false,  // No longer "active" in dock - opens modal instead
                    onTap: {
                        Haptics.light()
                        onOpenOrder?(order)
                    },
                    onClose: {
                        Haptics.medium()
                        tabManager.closeOrder(order.id)
                    }
                )
            }

            Spacer(minLength: 0)

            // Action buttons - 44pt touch targets (Apple HIG)
            HStack(spacing: 6) {
                // + button opens customer search
                if let onAdd = onAddCustomer {
                    DockActionButton(icon: "plus", action: onAdd)
                } else if let onScan = onScanCustomer {
                    DockActionButton(icon: "plus", action: onScan)
                }

                if let onClear = onClearAll, hasTabs {
                    DockActionButton(icon: "xmark", isDestructive: true, action: onClear)
                }
            }
        }
        .frame(height: tabBarHeight)
        .padding(.horizontal, 16)
        .onReceive(windowSession?.objectWillChange.eraseToAnyPublisher() ?? Empty().eraseToAnyPublisher()) { _ in
            if isMultiWindowSession {
                windowSessionUpdateTrigger = UUID()
            }
        }
    }
}

// MARK: - Dock Action Button (Liquid Glass - 48pt touch target)

private struct DockActionButton: View {
    let icon: String
    var isDestructive: Bool = false
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.medium()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isDestructive ? .white.opacity(0.5) : .white)
                .frame(width: 44, height: 44)
        }
        .tint(.white)
        .glassEffect(.regular.interactive(), in: .circle)
    }
}

// MARK: - Customer Tab Chip (Liquid Glass - 48pt touch target)

struct CustomerTabChip: View {
    let customer: Customer
    let itemCount: Int
    let isActive: Bool
    let onTap: () -> Void
    let onClose: () -> Void

    private var chipColor: Color {
        let colors: [Color] = [
            Color(red: 34/255, green: 197/255, blue: 94/255),   // Green
            Color(red: 59/255, green: 130/255, blue: 246/255),  // Blue
            Color(red: 168/255, green: 85/255, blue: 247/255),  // Purple
            Color(red: 236/255, green: 72/255, blue: 153/255),  // Pink
            Color(red: 245/255, green: 158/255, blue: 11/255),  // Amber
        ]
        return colors[abs(customer.id.hashValue) % colors.count]
    }

    var body: some View {
        Button {
            Haptics.light()
            onTap()
        } label: {
            HStack(spacing: 8) {
                // Customer color dot
                Circle()
                    .fill(chipColor)
                    .frame(width: 10, height: 10)

                Text(customer.initials)
                    .font(.system(size: 15, weight: .bold))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                // Item count badge (only if items)
                if itemCount > 0 {
                    Text("\(itemCount)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.white.opacity(0.1), in: .capsule)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(isActive ? .white : .white.opacity(0.7))
            .padding(.horizontal, 16)
            .frame(height: 44)
        }
        .tint(.white)
        .glassEffect(.regular.interactive(), in: .capsule)
        .contextMenu {
            Button(role: .destructive) {
                onClose()
            } label: {
                Label("Remove \(customer.firstName ?? "Customer")", systemImage: "trash")
            }
        }
    }
}

// MARK: - Order Tab Chip (Liquid Glass - 48pt touch target)

struct OrderTabChip: View {
    let order: Order
    let isActive: Bool
    let onTap: () -> Void
    let onClose: () -> Void

    private let orderColor = Color(red: 245/255, green: 158/255, blue: 11/255) // Amber

    var body: some View {
        Button {
            Haptics.light()
            onTap()
        } label: {
            HStack(spacing: 8) {
                // Order color dot
                Circle()
                    .fill(orderColor)
                    .frame(width: 10, height: 10)

                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 14, weight: .semibold))

                Text("#\(order.shortOrderNumber)")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
            }
            .foregroundStyle(isActive ? .white : .white.opacity(0.7))
            .padding(.horizontal, 16)
            .frame(height: 44)
        }
        .tint(.white)
        .glassEffect(.regular.interactive(), in: .capsule)
        .contextMenu {
            Button(role: .destructive) {
                onClose()
            } label: {
                Label("Close Order", systemImage: "xmark")
            }
        }
    }
}
