//
//  POSContentBrowser.swift
//  Whale
//
//  Content browser for POS - shows Products or Orders with search and filters.
//  Swipeable between tabs with smooth iOS 26 liquid glass animations.
//

import SwiftUI
import Combine

struct POSContentBrowser: View {
    @EnvironmentObject private var session: SessionObserver
    @Environment(\.posWindowSession) private var windowSession: POSWindowSession?
    @Binding var selectedTab: POSTab
    @Binding var searchText: String
    @ObservedObject var productStore: POSStore
    @ObservedObject var orderStore: OrderStore
    @ObservedObject private var multiSelect = MultiSelectManager.shared

    // Callbacks from POSMainView for menu actions
    var onScanID: (() -> Void)?
    var onFindCustomer: (() -> Void)?
    var onSafeDrop: (() -> Void)?
    var onPrinterSettings: (() -> Void)?
    var onCreateTransfer: (() -> Void)?
    var onEndSession: (() -> Void)?
    @Binding var showRegisterPicker: Bool

    // Track windowSession changes to trigger re-renders when products load
    @State private var windowSessionTrigger = UUID()
    // Track product count to force TabView page re-evaluation
    @State private var productCountTrigger: Int = 0

    @Namespace private var animation


    // MARK: - Data accessors
    // ISOLATED WINDOWS: Each window has its own data via windowSession
    // windowSession holds products, categories, carts - all isolated per window
    // Only fall back to productStore for legacy/backwards compat

    /// True only when this is a multi-window session with its own location
    private var isMultiWindowSession: Bool {
        windowSession?.location != nil
    }

    // Use windowSession when isolated, otherwise fall back to productStore
    private var products: [Product] {
        isMultiWindowSession ? (windowSession?.products ?? []) : productStore.products
    }

    private var filteredProducts: [Product] {
        isMultiWindowSession ? (windowSession?.filteredProducts ?? []) : productStore.filteredProducts
    }

    private var categories: [ProductCategory] {
        isMultiWindowSession ? (windowSession?.categories ?? []) : productStore.categories
    }

    private var isLoadingProducts: Bool {
        isMultiWindowSession ? (windowSession?.isLoadingProducts ?? false) : productStore.isLoadingProducts
    }

    private var productsError: String? {
        isMultiWindowSession ? windowSession?.productsError : productStore.productsError
    }

    private var currentLocation: Location? {
        windowSession?.location ?? session.selectedLocation
    }

    private var selectedCategoryId: UUID? {
        isMultiWindowSession ? windowSession?.selectedCategoryId : productStore.selectedCategoryId
    }

    private func selectCategory(_ categoryId: UUID?) {
        if isMultiWindowSession, let ws = windowSession {
            ws.selectedCategoryId = categoryId
        } else {
            productStore.selectedCategoryId = categoryId
        }
    }

    @State private var tierSelectorProduct: Product?
    @State private var isPrintingBulkLabels = false

    @State private var showDatePicker = false

    // Order detail - now via SheetCoordinator
    @State private var selectedOrderForDetail: Order?

    // Scroll-based header visibility (Amazon-style)
    @State private var showSearchAndFilters = true
    @State private var lastScrollY: CGFloat = 0
    @State private var scrollVelocity: CGFloat = 0
    private let hideThreshold: CGFloat = 50  // How far to scroll before hiding

    private var showingProducts: Bool {
        selectedTab == .products
    }

    private var screenWidth: CGFloat {
        UIScreen.main.bounds.width
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            // Native iOS paging - buttery smooth
            TabView(selection: $selectedTab) {
                productContent
                    .tag(POSTab.products)

                orderContent
                    .tag(POSTab.orders)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea(edges: .bottom)
            .onChange(of: selectedTab) { _, _ in
                Haptics.selection()  // Subtle selection feedback for tab switch
            }

            VStack(spacing: 0) {
                headerView
                    .padding(.horizontal, 12)
                    .padding(.top, SafeArea.top + 10)
                    .padding(.bottom, 8)

                Spacer()
            }
        }
        .onChange(of: products) { _, newProducts in
            // Bump trigger so TabView page re-evaluates productContent
            productCountTrigger = newProducts.count
            let urls = newProducts.prefix(20).compactMap { $0.iconUrl }
            Task(priority: .background) {
                await ImageCache.shared.prefetch(urls: urls)
            }
        }
        .onChange(of: searchText) { _, newValue in
            // Update appropriate store based on isolation mode
            if isMultiWindowSession, let ws = windowSession {
                ws.searchText = newValue
            } else {
                productStore.searchText = newValue
            }
            orderStore.searchText = newValue
        }
        .sheet(item: $tierSelectorProduct) { product in
            TierSelectorSheet(
                product: product,
                onSelectTier: { tier in
                    if isMultiWindowSession, let session = windowSession {
                        Task { await session.addToCart(product, tier: tier) }
                    } else {
                        productStore.addToCart(product, tier: tier)
                    }
                },
                onSelectVariantTier: { tier, variant in
                    if isMultiWindowSession, let session = windowSession {
                        Task { await session.addToCart(product, tier: tier, variant: variant) }
                    } else {
                        productStore.addToCart(product, tier: tier, variant: variant)
                    }
                },
                onInventoryUpdated: { _, _ in
                    Task {
                        if isMultiWindowSession, let ws = windowSession {
                            await ws.refresh()
                        } else {
                            await productStore.loadProducts()
                        }
                    }
                },
                onPrintLabels: {
                    SheetCoordinator.shared.present(.labelTemplate(products: [product]))
                },
                onViewCOA: {
                    if let coaUrl = product.coaUrl {
                        UIApplication.shared.open(coaUrl)
                    }
                },
                onShowDetail: {
                    SheetCoordinator.shared.present(.productDetail(product: product))
                }
            )
        }
    }

    // MARK: - Tab Switching

    private func switchProductsOrders() {
        if selectedTab == .products {
            selectedTab = .orders
        } else {
            selectedTab = .products
        }
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                // Toggle Products/Orders - LEFT of search bar with animated icon
                LiquidGlassIconButton(
                    icon: showingProducts ? "shippingbox" : "list.clipboard"
                ) {
                    switchProductsOrders()
                }

                // Liquid Glass Search Bar (hideable on scroll)
                if showSearchAndFilters {
                    LiquidGlassSearchBar(
                        showingProducts ? "Search products..." : "Search orders...",
                        text: $searchText
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }

                Spacer(minLength: 0)

                // Home menu dropdown - RIGHT of search bar
                homeMenuButton
            }

            // Filters (hideable on scroll)
            if showSearchAndFilters {
                Group {
                    if showingProducts {
                        productFilters
                    } else {
                        orderFilters
                    }
                }
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: selectedTab)
            }
        }
    }

    // MARK: - Home Menu Dropdown

    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: value as NSDecimalNumber) ?? "$0.00"
    }

    /// Home button with store logo - Tap = scanner, Long press = settings
    /// Uses same LiquidPressStyle as the orders toggle button
    private var homeMenuButton: some View {
        Button {
            // Tap action = open ID scanner
            if let storeId = session.storeId {
                SheetCoordinator.shared.present(.idScanner(storeId: storeId))
            }
        } label: {
            // Logo or fallback icon
            if let logoUrl = session.store?.fullLogoUrl {
                CachedAsyncImage(url: logoUrl, placeholderLogoUrl: nil, dimAmount: 0)
                    .frame(width: 28, height: 28)
                    .clipShape(Circle())
                    .frame(width: 44, height: 44)
            } else {
                Image(systemName: "viewfinder")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 44, height: 44)
            }
        }
        .buttonStyle(LiquidPressStyle())
        .glassEffect(.regular.interactive(), in: .circle)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in
                    // Long press completed = open settings
                    Haptics.medium()
                    SheetCoordinator.shared.present(.posSettings)
                }
        )
    }

    // MARK: - Scroll Handling

    private func handleScrollChange(oldOffset: CGFloat, newOffset: CGFloat) {
        // newOffset is how far we've scrolled from top (increases as we scroll down)
        let delta = newOffset - oldOffset
        scrollVelocity = delta

        // Scrolling down (delta > 0) and scrolled past threshold = hide
        if delta > 5 && newOffset > hideThreshold && showSearchAndFilters {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                showSearchAndFilters = false
            }
        }
        // Scrolling up (delta < 0) = show
        else if delta < -5 && !showSearchAndFilters {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                showSearchAndFilters = true
            }
        }
        // Near top = always show
        else if newOffset < 20 && !showSearchAndFilters {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                showSearchAndFilters = true
            }
        }

        lastScrollY = newOffset
    }

    // MARK: - Product Filters

    /// Categories that have at least one in-stock product
    private var categoriesWithStock: [ProductCategory] {
        let productsByCategory = Dictionary(grouping: products) { $0.primaryCategoryId }
        return categories.filter { category in
            productsByCategory[category.id]?.contains { $0.inStock } ?? false
        }
    }

    private var productFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                CategoryPill(name: "All", isSelected: selectedCategoryId == nil) {
                    selectCategory(nil)
                }

                ForEach(categoriesWithStock, id: \.id) { category in
                    CategoryPill(name: category.name, isSelected: selectedCategoryId == category.id) {
                        selectCategory(category.id)
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Order Filters

    private var orderFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(
                    label: "All",
                    count: orderStore.orders.count,
                    isSelected: !orderStore.hasActiveFilters
                ) {
                    orderStore.clearFilters()
                }

                filterDivider

                FilterChip(
                    label: "Needs Action",
                    icon: "exclamationmark.circle",
                    count: orderStore.orderCounts[.active] ?? 0,
                    isSelected: orderStore.selectedStatusGroup == .active
                ) {
                    toggleFilter { orderStore.selectedStatusGroup = orderStore.selectedStatusGroup == .active ? nil : .active }
                }

                FilterChip(
                    label: "In Transit",
                    icon: "airplane",
                    count: orderStore.orderCounts[.inProgress] ?? 0,
                    isSelected: orderStore.selectedStatusGroup == .inProgress
                ) {
                    toggleFilter { orderStore.selectedStatusGroup = orderStore.selectedStatusGroup == .inProgress ? nil : .inProgress }
                }

                FilterChip(
                    label: "Completed",
                    icon: "checkmark.circle",
                    count: orderStore.orderCounts[.completed] ?? 0,
                    isSelected: orderStore.selectedStatusGroup == .completed
                ) {
                    toggleFilter { orderStore.selectedStatusGroup = orderStore.selectedStatusGroup == .completed ? nil : .completed }
                }

                filterDivider

                FilterChip(
                    label: "Pickup",
                    icon: "bag",
                    isSelected: orderStore.selectedOrderType == .pickup
                ) {
                    toggleFilter { orderStore.selectedOrderType = orderStore.selectedOrderType == .pickup ? nil : .pickup }
                }

                FilterChip(
                    label: "Ship",
                    icon: "shippingbox",
                    isSelected: orderStore.selectedOrderType == .shipping
                ) {
                    toggleFilter { orderStore.selectedOrderType = orderStore.selectedOrderType == .shipping ? nil : .shipping }
                }

                FilterChip(
                    label: "Walk-in",
                    icon: "storefront",
                    isSelected: orderStore.selectedOrderType == .walkIn || orderStore.selectedOrderType == .pos
                ) {
                    toggleFilter { orderStore.selectedOrderType = orderStore.selectedOrderType == .walkIn ? nil : .walkIn }
                }

                FilterChip(
                    label: "Invoice",
                    icon: "doc.text",
                    isSelected: orderStore.selectedOrderType == .direct
                ) {
                    toggleFilter { orderStore.selectedOrderType = orderStore.selectedOrderType == .direct ? nil : .direct }
                }

                filterDivider

                FilterChip(
                    label: "Unpaid",
                    icon: "creditcard",
                    isSelected: orderStore.selectedPaymentStatus == .pending
                ) {
                    toggleFilter { orderStore.selectedPaymentStatus = orderStore.selectedPaymentStatus == .pending ? nil : .pending }
                }

                filterDivider

                DateFilterChip(
                    startDate: $orderStore.dateRangeStart,
                    endDate: $orderStore.dateRangeEnd,
                    showPicker: $showDatePicker
                )
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        }
        .sheet(isPresented: $showDatePicker) {
            DateRangePickerSheet(
                startDate: $orderStore.dateRangeStart,
                endDate: $orderStore.dateRangeEnd
            )
        }
    }

    private var filterDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.15))
            .frame(width: 1, height: 20)
    }

    private func toggleFilter(_ action: () -> Void) {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            action()
        }
        // No haptics for filter toggles - visual feedback is enough
    }

    // MARK: - Product Content

    private var hasLoadedProducts: Bool {
        isMultiWindowSession ? (windowSession?.hasLoadedProducts ?? false) : productStore.hasLoadedProducts
    }

    private var productContent: some View {
        // Reference productCountTrigger so SwiftUI re-evaluates when products load
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

    private var productGrid: some View {
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
            .background(Color.black)
            .overlay(Color.black.opacity(0.15).allowsHitTesting(false))
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
        .topBottomFadeMask(topFadeHeight: 80, bottomFadeHeight: 80)
        .refreshable {
            if isMultiWindowSession, let ws = windowSession {
                await ws.refresh()
            } else {
                await productStore.refresh()
            }
        }
        .onReceive(windowSession?.objectWillChange.eraseToAnyPublisher() ?? Empty().eraseToAnyPublisher()) { _ in
            // Trigger re-render when windowSession publishes changes (products loaded, etc)
            if isMultiWindowSession {
                windowSessionTrigger = UUID()
            }
        }
    }

    private var gridColumnCount: Int {
        let screenWidth = UIScreen.main.bounds.width
        if screenWidth > 1200 { return 6 }
        if screenWidth > 900 { return 5 }
        if screenWidth > 700 { return 4 }
        if screenWidth > 500 { return 3 }
        return 2
    }

    // MARK: - Session-aware cart operations

    private func addProductToCart(_ product: Product) {
        if isMultiWindowSession, let session = windowSession {
            Task { await session.addToCart(product) }
        } else {
            productStore.addToCart(product)
        }
    }

    private func handleProductTap(_ product: Product) {
        if multiSelect.isProductSelectMode {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                multiSelect.toggleProductSelection(product.id)
            }
            Haptics.selection()  // Subtle for multi-select toggle
        } else if product.hasTieredPricing {
            tierSelectorProduct = product
            // No haptic - sheet presentation provides feedback
        } else {
            Haptics.light()  // Light for add to cart confirmation
            addProductToCart(product)
        }
    }

    private func handleProductTierSelector(_ product: Product) {
        if !multiSelect.isProductSelectMode {
            tierSelectorProduct = product
            // No haptic - sheet presentation provides feedback
        } else {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                multiSelect.toggleProductSelection(product.id)
            }
            Haptics.selection()
        }
    }

    private func handleProductLongPress(_ product: Product) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            multiSelect.startProductMultiSelect(product.id)
        }
        Haptics.medium()  // Medium for long press recognition
    }

    // MARK: - Order Content

    private var orderContent: some View {
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

    private var orderGrid: some View {
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
        .topBottomFadeMask(topFadeHeight: 80, bottomFadeHeight: 80)
        .refreshable { await orderStore.refresh() }
    }

    private func handleOrderTap(_ order: Order) {
        if multiSelect.isMultiSelectMode {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                multiSelect.toggleSelection(order.id)
            }
            Haptics.selection()  // Subtle for multi-select
        } else {
            SheetCoordinator.shared.present(.orderDetail(order: order))
            // No haptic - sheet presentation provides feedback
        }
    }

    // MARK: - Shared States

    private func loadingState(_ message: String) -> some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String, retry: @escaping () async -> Void) -> some View {
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
                    .background(.white.opacity(0.1), in: Capsule())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func emptyState(_ message: String, icon: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text(message)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}