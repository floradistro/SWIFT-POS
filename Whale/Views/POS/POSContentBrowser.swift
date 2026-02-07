//
//  POSContentBrowser.swift
//  Whale
//
//  Content browser for POS - shows Products or Orders with search and filters.
//  Swipeable between tabs with smooth iOS 26 liquid glass animations.
//
//  Product/order grids and shared states moved to POSContentBrowserComponents.swift

import SwiftUI
import Combine

struct POSContentBrowser: View {
    @EnvironmentObject private var session: SessionObserver
    @Environment(\.posWindowSession) var windowSession: POSWindowSession?
    @Binding var selectedTab: POSTab
    @Binding var searchText: String
    @ObservedObject var productStore: POSStore
    @ObservedObject var orderStore: OrderStore
    @StateObject var multiSelect = MultiSelectManager.shared

    // Callbacks from POSMainView for menu actions
    var onScanID: (() -> Void)?
    var onFindCustomer: (() -> Void)?
    var onSafeDrop: (() -> Void)?
    var onPrinterSettings: (() -> Void)?
    var onCreateTransfer: (() -> Void)?
    var onEndSession: (() -> Void)?
    @Binding var showRegisterPicker: Bool

    // Track windowSession changes to trigger re-renders when products load
    @State var windowSessionTrigger = UUID()
    // Track product count to force TabView page re-evaluation
    @State var productCountTrigger: Int = 0

    @Namespace private var animation

    // MARK: - Data accessors

    var isMultiWindowSession: Bool {
        windowSession?.location != nil
    }

    var products: [Product] {
        isMultiWindowSession ? (windowSession?.products ?? []) : productStore.products
    }

    var filteredProducts: [Product] {
        isMultiWindowSession ? (windowSession?.filteredProducts ?? []) : productStore.filteredProducts
    }

    var categories: [ProductCategory] {
        isMultiWindowSession ? (windowSession?.categories ?? []) : productStore.categories
    }

    var isLoadingProducts: Bool {
        isMultiWindowSession ? (windowSession?.isLoadingProducts ?? false) : productStore.isLoadingProducts
    }

    var productsError: String? {
        isMultiWindowSession ? windowSession?.productsError : productStore.productsError
    }

    var hasLoadedProducts: Bool {
        isMultiWindowSession ? (windowSession?.hasLoadedProducts ?? false) : productStore.hasLoadedProducts
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

    @State var tierSelectorProduct: Product?
    @State private var isPrintingBulkLabels = false
    @State private var showDatePicker = false
    @State private var selectedOrderForDetail: Order?

    // Scroll-based header visibility (Amazon-style)
    @State var showSearchAndFilters = true
    @State private var lastScrollY: CGFloat = 0
    @State private var scrollVelocity: CGFloat = 0
    private let hideThreshold: CGFloat = 50

    private var showingProducts: Bool {
        selectedTab == .products
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            TabView(selection: $selectedTab) {
                productContent
                    .tag(POSTab.products)

                orderContent
                    .tag(POSTab.orders)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea(edges: .bottom)
            .onChange(of: selectedTab) { _, _ in
                Haptics.selection()
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
            productCountTrigger = newProducts.count
            let urls = newProducts.prefix(20).compactMap { $0.iconUrl }
            Task(priority: .background) {
                await ImageCache.shared.prefetch(urls: urls)
            }
        }
        .onChange(of: searchText) { _, newValue in
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
                LiquidGlassIconButton(
                    icon: showingProducts ? "shippingbox" : "list.clipboard"
                ) {
                    switchProductsOrders()
                }

                if showSearchAndFilters {
                    LiquidGlassSearchBar(
                        showingProducts ? "Search products..." : "Search orders...",
                        text: $searchText
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }

                Spacer(minLength: 0)

                homeMenuButton
            }

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

    // MARK: - Home Menu

    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: value as NSDecimalNumber) ?? "$0.00"
    }

    private var homeMenuButton: some View {
        Button {
            if let storeId = session.storeId {
                SheetCoordinator.shared.present(.idScanner(storeId: storeId))
            }
        } label: {
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
                    Haptics.medium()
                    SheetCoordinator.shared.present(.posSettings)
                }
        )
    }

    // MARK: - Scroll Handling

    func handleScrollChange(oldOffset: CGFloat, newOffset: CGFloat) {
        let delta = newOffset - oldOffset
        scrollVelocity = delta

        if delta > 5 && newOffset > hideThreshold && showSearchAndFilters {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                showSearchAndFilters = false
            }
        }
        else if delta < -5 && !showSearchAndFilters {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                showSearchAndFilters = true
            }
        }
        else if newOffset < 20 && !showSearchAndFilters {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                showSearchAndFilters = true
            }
        }

        lastScrollY = newOffset
    }

    // MARK: - Product Filters

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
    }
}
