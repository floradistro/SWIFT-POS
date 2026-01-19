//
//  OrdersView.swift
//  Whale
//
//  Orders management view with filtering and search.
//

import SwiftUI

struct OrdersView: View {
    @ObservedObject private var store = OrderStore.shared
    private let tabManager = DockTabManager.shared
    @State private var showAdvancedFilters = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                ordersHeader

                if store.isLoading {
                    loadingState
                } else if store.filteredOrders.isEmpty {
                    emptyState
                } else {
                    ordersGrid
                }
            }

        }
        .sheet(isPresented: $showAdvancedFilters) {
            AdvancedOrderFiltersSheet(store: store, isPresented: $showAdvancedFilters)
        }
    }

    // MARK: - Header

    private var ordersHeader: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                GlassSearchBar("Search orders...", text: $store.searchText)

                GlassIconButton(
                    icon: "line.3.horizontal.decrease.circle",
                    badge: store.activeFilterCount > 0 ? store.activeFilterCount : nil,
                    isSelected: store.hasActiveFilters
                ) {
                    showAdvancedFilters = true
                }
            }

            // Status group filters
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    GlassPill(
                        "All",
                        count: store.orders.count,
                        isSelected: store.selectedStatusGroup == nil && !store.showOnlineOrdersOnly
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            store.selectedStatusGroup = nil
                            store.showOnlineOrdersOnly = false
                        }
                    }

                    GlassPill(
                        "Online",
                        icon: "globe",
                        count: store.onlineOrderCount,
                        isSelected: store.showOnlineOrdersOnly
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            store.showOnlineOrdersOnly.toggle()
                            if store.showOnlineOrdersOnly {
                                store.selectedOrderType = nil
                            }
                        }
                    }

                    ForEach(OrderStatusGroup.allCases, id: \.self) { group in
                        GlassPill(
                            group.displayName,
                            count: store.orderCounts[group] ?? 0,
                            isSelected: store.selectedStatusGroup == group
                        ) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                store.selectedStatusGroup = group
                            }
                        }
                    }
                }
            }

            // Order type filters
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    GlassPill(
                        "All Types",
                        isSelected: store.selectedOrderType == nil && !store.showOnlineOrdersOnly
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            store.selectedOrderType = nil
                            store.showOnlineOrdersOnly = false
                        }
                    }

                    ForEach(OrderType.allCases, id: \.self) { type in
                        GlassPill(
                            type.displayName,
                            icon: type.icon,
                            isSelected: store.selectedOrderType == type
                        ) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                store.selectedOrderType = type
                                store.showOnlineOrdersOnly = false
                            }
                        }
                    }

                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.white.opacity(0.15))
                        .frame(width: 1, height: 20)

                    GlassPill(
                        "Any Payment",
                        isSelected: store.selectedPaymentStatus == nil
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            store.selectedPaymentStatus = nil
                        }
                    }

                    ForEach([PaymentStatus.paid, .pending, .failed], id: \.self) { status in
                        GlassPill(
                            status.displayName,
                            color: statusColor(for: status),
                            isSelected: store.selectedPaymentStatus == status
                        ) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                store.selectedPaymentStatus = status
                            }
                        }
                    }
                }
            }

            if store.hasActiveFilters {
                activeFiltersBar
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func statusColor(for status: PaymentStatus) -> Color {
        switch status {
        case .paid: return Design.Colors.Semantic.success
        case .pending: return .orange
        case .failed: return Design.Colors.Semantic.error
        case .partial: return .yellow
        case .refunded, .partiallyRefunded: return .gray
        }
    }

    // MARK: - Active Filters Bar

    private var activeFiltersBar: some View {
        HStack(spacing: 8) {
            Text("Filters:")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))

            if store.dateRangeStart != nil || store.dateRangeEnd != nil {
                filterChip(text: dateRangeText, icon: "calendar") {
                    store.dateRangeStart = nil
                    store.dateRangeEnd = nil
                }
            }

            if store.amountMin != nil || store.amountMax != nil {
                filterChip(text: amountRangeText, icon: "dollarsign.circle") {
                    store.amountMin = nil
                    store.amountMax = nil
                }
            }

            Spacer()

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    store.clearFilters()
                }
                Haptics.light()
            } label: {
                Text("Clear All")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Design.Colors.Semantic.accent)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }

    private var dateRangeText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        if let start = store.dateRangeStart, let end = store.dateRangeEnd {
            return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
        } else if let start = store.dateRangeStart {
            return "From \(formatter.string(from: start))"
        } else if let end = store.dateRangeEnd {
            return "Until \(formatter.string(from: end))"
        }
        return ""
    }

    private var amountRangeText: String {
        if let min = store.amountMin, let max = store.amountMax {
            return "\(CurrencyFormatter.format(min)) - \(CurrencyFormatter.format(max))"
        } else if let min = store.amountMin {
            return "≥ \(CurrencyFormatter.format(min))"
        } else if let max = store.amountMax {
            return "≤ \(CurrencyFormatter.format(max))"
        }
        return ""
    }

    private func filterChip(text: String, icon: String, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(text)
                .font(.system(size: 11, weight: .medium))
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
            }
        }
        .foregroundStyle(.white.opacity(0.8))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Design.Colors.Semantic.accent.opacity(0.2), in: Capsule())
    }

    // MARK: - Orders List

    private var ordersGrid: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(Array(store.filteredOrders.enumerated()), id: \.element.id) { index, order in
                    OrderListRow(
                        order: order,
                        isMultiSelected: false,
                        isMultiSelectMode: false,
                        isLast: index == store.filteredOrders.count - 1,
                        onTap: {
                            SheetCoordinator.shared.present(.orderDetail(order: order))
                            Haptics.medium()
                        },
                        onLongPress: {},
                        onOpenInDock: {
                            SheetCoordinator.shared.present(.orderDetail(order: order))
                            Haptics.medium()
                        },
                        onViewDetails: {
                            SheetCoordinator.shared.present(.orderDetail(order: order))
                            Haptics.medium()
                        },
                        onSelectMultiple: {}
                    )
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 120)
        }
        .topBottomFadeMask(topFadeHeight: 80, bottomFadeHeight: 80)
        .refreshable {
            await store.refresh()
        }
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)

            Text("Loading orders...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text("No orders found")
                .font(.headline)
                .foregroundStyle(.secondary)

            if !store.searchText.isEmpty || store.selectedStatusGroup != nil || store.selectedOrderType != nil {
                Button {
                    store.clearFilters()
                } label: {
                    Text("Clear filters")
                        .font(.subheadline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.white.opacity(0.1), in: Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
