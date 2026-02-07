//
//  ManualCustomerEntrySheet.swift
//  Whale
//
//  Unified customer modal - search existing, scan ID, or create new.
//  Redesigned with liquid glass aesthetic and keyboard-optimized layout.
//

import SwiftUI
import os.log

struct ManualCustomerEntrySheet: View {
    let storeId: UUID
    let onCustomerCreated: (Customer) -> Void
    let onCancel: () -> Void
    var orderStore: OrderStore = OrderStore.shared

    // Optional scanned ID data (when coming from ID scanner)
    var scannedID: ScannedID? = nil
    var scannedMatches: [CustomerMatch]? = nil

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        CustomerSearchContent(
            storeId: storeId,
            orderStore: orderStore,
            scannedID: scannedID,
            scannedMatches: scannedMatches,
            onCustomerCreated: { customer in
                dismiss()
                onCustomerCreated(customer)
            },
            onDismiss: {
                dismiss()
                onCancel()
            }
        )
    }
}

// MARK: - Customer Search Modal Content

struct CustomerSearchContent: View {
    let storeId: UUID
    @ObservedObject var orderStore: OrderStore
    let scannedID: ScannedID?
    let scannedMatches: [CustomerMatch]?
    let onCustomerCreated: (Customer) -> Void
    let onDismiss: () -> Void

    /// Local state for scanned data (updated by internal scanner)
    @State var localScannedID: ScannedID? = nil
    @State var localScannedMatches: [CustomerMatch]? = nil

    /// Effective scanned ID (prefers local state over passed-in)
    var effectiveScannedID: ScannedID? { localScannedID ?? scannedID }
    var effectiveScannedMatches: [CustomerMatch]? { localScannedMatches ?? scannedMatches }

    /// Whether we're in scanned mode
    var isScannedMode: Bool { effectiveScannedID != nil }

    enum Mode: Hashable {
        case search
        case create
        case scanner
        case detail(Customer)
        case orderDetail(Order, Customer)
        case orderHistory(Customer)

        static func == (lhs: Mode, rhs: Mode) -> Bool {
            switch (lhs, rhs) {
            case (.search, .search), (.create, .create), (.scanner, .scanner):
                return true
            case (.detail(let c1), .detail(let c2)):
                return c1.id == c2.id
            case (.orderDetail(let o1, _), .orderDetail(let o2, _)):
                return o1.id == o2.id
            case (.orderHistory(let c1), .orderHistory(let c2)):
                return c1.id == c2.id
            default:
                return false
            }
        }

        func hash(into hasher: inout Hasher) {
            switch self {
            case .search: hasher.combine(0)
            case .create: hasher.combine(1)
            case .scanner: hasher.combine(2)
            case .detail(let customer): hasher.combine(customer.id)
            case .orderDetail(let order, _): hasher.combine(order.id)
            case .orderHistory(let customer): hasher.combine(100 + customer.id.hashValue)
            }
        }
    }

    @State var mode: Mode = .search
    @State var detailAppearAnimation = false
    @State var searchQuery = ""
    @State var searchResults: [Customer] = []
    @State var isSearching = false
    @State var searchTask: Task<Void, Never>?

    // Create mode fields
    @State var firstName = ""
    @State var lastName = ""
    @State var dateOfBirth = ""
    @State var phone = ""
    @State var email = ""
    @State var isCreating = false
    @State var errorMessage: String?

    // Loyalty points adjustment
    @State var showPointsAdjustment = false
    @State var pointsAdjustmentValue = ""
    @State var adjustingPointsForCustomer: Customer?
    @State var isAdjustingPoints = false
    @State var pointsAdjustmentMessage: String?
    @State var updatedLoyaltyPoints: Int?

    // Customer editing
    @State var isEditingCustomer = false
    @State var editFirstName = ""
    @State var editLastName = ""
    @State var editEmail = ""
    @State var editPhone = ""
    @State var editDateOfBirth = ""
    @State var isSavingCustomer = false
    @State var editErrorMessage: String?
    @State var updatedCustomer: Customer?

    // Scanner
    @State var showFullScreenScanner = false

    // Customer detail orders
    @State var customerOrders: [Order] = []
    @State var isLoadingOrders = false

    // Full order history
    @State var fullOrderHistory: [Order] = []
    @State var isLoadingFullHistory = false
    @State var orderHistorySearchText = ""

    @FocusState var isSearchFocused: Bool
    @FocusState var focusedCreateField: CreateField?

    enum CreateField: Hashable {
        case firstName, lastName, dob, phone, email
    }


    var body: some View {
        Group {
            if case .orderHistory(let customer) = mode {
                // Full order history list
                orderHistoryFullScreen(customer: customer)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else if case .orderDetail(let order, let customer) = mode {
                // Full-height order detail (in-place, no new sheet)
                orderDetailFullScreen(order: order, customer: customer)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else if case .detail(let customer) = mode {
                // Full-height customer detail (no NavigationStack header)
                customerDetailFullScreen(customer)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.94).combined(with: .opacity),
                        removal: .scale(scale: 0.98).combined(with: .opacity)
                    ))
            } else {
                // Standard navigation for search/create/scanner
                NavigationStack {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {
                            switch mode {
                            case .search:
                                searchContent
                            case .create:
                                createContent
                            case .scanner:
                                scannerContent
                            case .detail, .orderDetail, .orderHistory:
                                EmptyView()
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .navigationTitle(navigationTitle)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { onDismiss() }
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        ToolbarItem(placement: .primaryAction) {
                            toolbarActions
                        }
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
        .onAppear {
            Log.scanner.debug("CustomerSearchContent appeared - isScannedMode: \(isScannedMode), scannedID: \(scannedID?.fullDisplayName ?? "nil"), matches: \(scannedMatches?.count ?? 0)")
        }
    }

    // MARK: - Navigation

    var navigationTitle: String {
        switch mode {
        case .search:
            return isScannedMode ? "ID Scanned" : "Find Customer"
        case .create:
            return "New Customer"
        case .scanner:
            return "Scan ID"
        case .detail, .orderDetail, .orderHistory:
            return ""
        }
    }

    @ViewBuilder
    var toolbarActions: some View {
        switch mode {
        case .search:
            HStack(spacing: 8) {
                if isScannedMode, let age = effectiveScannedID?.age {
                    Text("\(age)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Design.Colors.Semantic.success)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Design.Colors.Semantic.success.opacity(0.15)))
                }
                Button {
                    mode = .scanner
                } label: {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .accessibilityLabel("Scan ID")
                Button {
                    prefillCreateFormFromScan()
                    mode = .create
                } label: {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .accessibilityLabel("Create customer")
            }
        case .create:
            Button {
                mode = .search
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }
        case .detail, .orderDetail, .orderHistory:
            EmptyView()
        case .scanner:
            EmptyView()
        }
    }

    // MARK: - Search Content

    @ViewBuilder
    var searchContent: some View {
        if let scanned = effectiveScannedID {
            scannedInfoBanner(scanned)
        }

        searchField

        resultsArea
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
                .accessibilityHidden(true)

            TextField("", text: $searchQuery, prompt: Text("Name, phone, or email...").foregroundColor(.white.opacity(0.35)))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($isSearchFocused)
                .onChange(of: searchQuery) { _, newValue in
                    performSearch(query: newValue)
                }
                .onSubmit {
                    isSearchFocused = false
                }

            if isSearching {
                ProgressView()
                    .scaleEffect(0.8)
                    .tint(.white.opacity(0.5))
            } else if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                    searchResults = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.white.opacity(0.3))
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
    }

    private func scannedInfoBanner(_ scanned: ScannedID) -> some View {
        HStack(spacing: 14) {
            Text(scanned.initials)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 50, height: 50)
                .glassEffect(.regular, in: .circle)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(scanned.fullDisplayName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)

                HStack(spacing: 8) {
                    if let state = scanned.state {
                        Text("\(state) License")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    if scanned.isExpired {
                        Text("EXPIRED")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Design.Colors.Semantic.error))
                    }
                }
            }

            Spacer()
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

    private var resultsArea: some View {
        AdaptiveScrollView(maxHeight: isScannedMode ? 420 : 380) {
            VStack(alignment: .leading, spacing: 10) {
                if isScannedMode, let matches = effectiveScannedMatches, !matches.isEmpty {
                    scannedMatchesSection(matches)
                } else if !searchResults.isEmpty {
                    Text("\(searchResults.count) \(searchResults.count == 1 ? "result" : "results")")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.35))
                        .textCase(.uppercase)
                        .tracking(0.5)
                        .padding(.leading, 4)

                    VStack(spacing: 10) {
                        ForEach(searchResults.prefix(5)) { customer in
                            CustomerRow(
                                customer: customer,
                                onSelect: { selectCustomer(customer) },
                                onViewProfile: {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                        detailAppearAnimation = false
                                        mode = .detail(customer)
                                    }
                                }
                            )
                        }
                    }
                } else if !searchQuery.isEmpty && !isSearching {
                    noResultsView
                } else if isScannedMode {
                    noMatchScannedView
                } else {
                    emptyStateView
                }
            }
        }
    }

    private func scannedMatchesSection(_ matches: [CustomerMatch]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(matches.count == 1 ? "1 Match Found" : "\(matches.count) Matches Found")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.35))
                .textCase(.uppercase)
                .tracking(0.5)
                .padding(.leading, 4)

            VStack(spacing: 8) {
                ForEach(matches.prefix(5), id: \.id) { match in
                    scannedMatchRow(match)
                }
            }

            Button {
                Haptics.light()
                prefillCreateFormFromScan()
                mode = .create
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 14, weight: .medium))
                    Text("Create New Customer")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundStyle(.white.opacity(0.6))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(ScaleButtonStyle())
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
        }
    }

    private func scannedMatchRow(_ match: CustomerMatch) -> some View {
        Button {
            Haptics.light()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                detailAppearAnimation = false
                mode = .detail(match.customer)
            }
        } label: {
            HStack(spacing: 12) {
                Text(match.customer.initials)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .glassEffect(.regular, in: .circle)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(match.customer.displayName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)

                        if match.matchType == .exact {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(Design.Colors.Semantic.success)
                                .accessibilityLabel("Exact match")
                        }
                    }

                    HStack(spacing: 8) {
                        if let phone = match.customer.formattedPhone {
                            Text(phone)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.45))
                        } else if let email = match.customer.email, !email.isEmpty {
                            Text(email)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.45))
                                .lineLimit(1)
                        }

                        if let points = match.customer.loyaltyPoints {
                            HStack(spacing: 2) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 8, weight: .bold))
                                    .accessibilityHidden(true)
                                Text("\(points)")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(points >= 0 ? .yellow.opacity(0.8) : .red.opacity(0.7))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.white.opacity(0.08), in: .capsule)
                            .accessibilityLabel("\(points) loyalty points")
                        }
                    }
                }

                Spacer()

                Button {
                    Haptics.medium()
                    selectScannedMatch(match)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Select \(match.customer.displayName)")

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.3))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(ScaleButtonStyle())
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
    }

    private var noResultsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.slash")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.white.opacity(0.25))
                .accessibilityHidden(true)

            Text("No customers found")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))

            Button {
                Haptics.light()
                mode = .create
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 14, weight: .medium))
                    Text("Create New Customer")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            }
            .buttonStyle(ScaleButtonStyle())
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }

    private var noMatchScannedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(.white.opacity(0.3))
                .accessibilityHidden(true)

            Text("No existing customer found")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))

            Button {
                Haptics.medium()
                prefillCreateFormFromScan()
                mode = .create
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Create Customer")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(ScaleButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.magnifyingglass")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.white.opacity(0.25))
                .accessibilityHidden(true)

            Text("Search customers")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        ManualCustomerEntrySheet(
            storeId: UUID(),
            onCustomerCreated: { _ in },
            onCancel: {}
        )
    }
    .preferredColorScheme(.dark)
}
