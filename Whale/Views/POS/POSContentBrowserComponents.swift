//
//  POSContentBrowserComponents.swift
//  Whale
//
//  Product grid, order grid, shared state views, and filter
//  components extracted from POSContentBrowser.swift.
//

import SwiftUI
import Combine

// MARK: - Product Content

extension POSContentBrowser {

    var productContent: some View {
        let _ = productCountTrigger
        return Group {
            if isLoadingProducts || !hasLoadedProducts {
                loadingState("Loading products...")
            } else if let error = productsError {
                errorState(error) {
                    if isMultiWindowSession, let ws = windowSession {
                        await ws.refresh()
                    } else {
                        await productStore.refresh()
                    }
                }
            } else if filteredProducts.isEmpty {
                emptyState("No products found", icon: "shippingbox")
            } else {
                productGrid
            }
        }
    }

    var productGrid: some View {
        ScrollView(showsIndicators: false) {
            let columns = gridColumnCount
            let displayProducts = filteredProducts
            let totalRows = (displayProducts.count + columns - 1) / columns

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: columns),
                spacing: 0
            ) {
                ForEach(Array(displayProducts.enumerated()), id: \.element.id) { index, product in
                    let col = index % columns
                    let row = index / columns
                    let isLastColumn = col == columns - 1
                    let isLastRow = row == totalRows - 1

                    ProductGridCard(
                        product: product,
                        isSelected: multiSelect.isProductSelected(product.id),
                        isMultiSelectMode: multiSelect.isProductSelectMode,
                        showRightLine: !isLastColumn,
                        showBottomLine: !isLastRow,
                        onTap: { handleProductTap(product) },
                        onShowTierSelector: { handleProductTierSelector(product) },
                        onLongPress: { handleProductLongPress(product) },
                        onAddToCart: { addProductToCart(product) },
                        onPrintLabels: {
                            SheetCoordinator.shared.present(.labelTemplate(products: [product]))
                        },
                        onSelectMultiple: { multiSelect.startProductMultiSelect(product.id) },
                        onShowDetail: {
                            SheetCoordinator.shared.present(.productDetail(product: product))
                        }
                    )
                }
            }
            .background(Design.Colors.backgroundPrimary)
            .overlay(Design.Colors.backgroundPrimary.opacity(0.15).allowsHitTesting(false))
            .mask(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.top, showSearchAndFilters ? 140 : 80)
            .padding(.bottom, multiSelect.isProductSelectMode ? 180 : 120)
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y
        } action: { oldValue, newValue in
            handleScrollChange(oldOffset: oldValue, newOffset: newValue)
        }
        .topBottomFadeMask(topFadeHeight: showSearchAndFilters ? 140 : 80, bottomFadeHeight: 80)
        .refreshable {
            if isMultiWindowSession, let ws = windowSession {
                await ws.refresh()
            } else {
                await productStore.refresh()
            }
        }
        .onReceive(windowSession?.objectWillChange.eraseToAnyPublisher() ?? Empty().eraseToAnyPublisher()) { _ in
            if isMultiWindowSession {
                windowSessionTrigger = UUID()
            }
        }
    }

    var gridColumnCount: Int {
        let screenWidth = UIScreen.main.bounds.width
        if screenWidth > 1200 { return 6 }
        if screenWidth > 900 { return 5 }
        if screenWidth > 700 { return 4 }
        if screenWidth > 500 { return 3 }
        return 2
    }

    // MARK: - Session-aware cart operations

    func addProductToCart(_ product: Product) {
        if isMultiWindowSession, let session = windowSession {
            Task { await session.addToCart(product) }
        } else {
            productStore.addToCart(product)
        }
    }

    func handleProductTap(_ product: Product) {
        if multiSelect.isProductSelectMode {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                multiSelect.toggleProductSelection(product.id)
            }
            Haptics.selection()
        } else if product.hasTieredPricing {
            tierSelectorProduct = product
        } else {
            Haptics.light()
            addProductToCart(product)
        }
    }

    func handleProductTierSelector(_ product: Product) {
        if !multiSelect.isProductSelectMode {
            tierSelectorProduct = product
        } else {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                multiSelect.toggleProductSelection(product.id)
            }
            Haptics.selection()
        }
    }

    func handleProductLongPress(_ product: Product) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            multiSelect.startProductMultiSelect(product.id)
        }
        Haptics.medium()
    }
}

// MARK: - Order Content

extension POSContentBrowser {

    var orderContent: some View {
        Group {
            if orderStore.isLoading {
                loadingState("Loading orders...")
            } else if let error = orderStore.error {
                errorState(error) { await orderStore.refresh() }
            } else if orderStore.filteredOrders.isEmpty {
                emptyState("No orders found", icon: "tray")
            } else {
                orderGrid
            }
        }
    }

    var orderGrid: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(Array(orderStore.filteredOrders.enumerated()), id: \.element.id) { index, order in
                    OrderListRow(
                        order: order,
                        isMultiSelected: multiSelect.isSelected(order.id),
                        isMultiSelectMode: multiSelect.isMultiSelectMode,
                        isLast: index == orderStore.filteredOrders.count - 1,
                        onTap: {
                            handleOrderTap(order)
                        },
                        onLongPress: {
                            multiSelect.startMultiSelect(with: order.id)
                        },
                        onOpenInDock: {
                            SheetCoordinator.shared.present(.orderDetail(order: order))
                            Haptics.medium()
                        },
                        onViewDetails: {
                            SheetCoordinator.shared.present(.orderDetail(order: order))
                            Haptics.medium()
                        },
                        onSelectMultiple: {
                            multiSelect.startMultiSelect(with: order.id)
                        }
                    )
                }
            }
            .padding(.top, showSearchAndFilters ? 140 : 80)
            .padding(.bottom, multiSelect.isMultiSelectMode ? 180 : 120)
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y
        } action: { oldValue, newValue in
            handleScrollChange(oldOffset: oldValue, newOffset: newValue)
        }
        .topBottomFadeMask(topFadeHeight: showSearchAndFilters ? 140 : 80, bottomFadeHeight: 80)
        .refreshable { await orderStore.refresh() }
    }

    func handleOrderTap(_ order: Order) {
        if multiSelect.isMultiSelectMode {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                multiSelect.toggleSelection(order.id)
            }
            Haptics.selection()
        } else {
            SheetCoordinator.shared.present(.orderDetail(order: order))
        }
    }
}

// MARK: - Shared States

extension POSContentBrowser {

    func loadingState(_ message: String) -> some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    func errorState(_ message: String, retry: @escaping () async -> Void) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orange)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                Haptics.light()
                Task { await retry() }
            } label: {
                Text("Try Again")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Design.Colors.Glass.thick, in: Capsule())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func emptyState(_ message: String, icon: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)

            Text(message)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
