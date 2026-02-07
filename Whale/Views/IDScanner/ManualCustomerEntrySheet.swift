//
//  ManualCustomerEntrySheet.swift
//  Whale
//
//  Unified customer modal - search existing, scan ID, or create new.
//  Redesigned with liquid glass aesthetic and keyboard-optimized layout.
//

import SwiftUI
import UIKit
import os.log
import Supabase

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

private struct CustomerSearchContent: View {
    let storeId: UUID
    @ObservedObject var orderStore: OrderStore
    let scannedID: ScannedID?
    let scannedMatches: [CustomerMatch]?
    let onCustomerCreated: (Customer) -> Void
    let onDismiss: () -> Void

    /// Local state for scanned data (updated by internal scanner)
    @State private var localScannedID: ScannedID? = nil
    @State private var localScannedMatches: [CustomerMatch]? = nil

    /// Effective scanned ID (prefers local state over passed-in)
    private var effectiveScannedID: ScannedID? { localScannedID ?? scannedID }
    private var effectiveScannedMatches: [CustomerMatch]? { localScannedMatches ?? scannedMatches }

    /// Whether we're in scanned mode
    private var isScannedMode: Bool { effectiveScannedID != nil }

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

    @State private var mode: Mode = .search
    @State private var detailAppearAnimation = false
    @State private var searchQuery = ""
    @State private var searchResults: [Customer] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?

    // Create mode fields
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var dateOfBirth = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var isCreating = false
    @State private var errorMessage: String?

    // Loyalty points adjustment
    @State private var showPointsAdjustment = false
    @State private var pointsAdjustmentValue = ""
    @State private var adjustingPointsForCustomer: Customer?
    @State private var isAdjustingPoints = false
    @State private var pointsAdjustmentMessage: String?
    @State private var updatedLoyaltyPoints: Int?  // Immediate UI update after adjustment

    // Customer editing
    @State private var isEditingCustomer = false
    @State private var editFirstName = ""
    @State private var editLastName = ""
    @State private var editEmail = ""
    @State private var editPhone = ""
    @State private var editDateOfBirth = ""
    @State private var isSavingCustomer = false
    @State private var editErrorMessage: String?
    @State private var updatedCustomer: Customer?  // Updated customer after save

    @FocusState private var isSearchFocused: Bool
    @FocusState private var focusedCreateField: CreateField?

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
            print("📋 CustomerSearchContent appeared - isScannedMode: \(isScannedMode), scannedID: \(scannedID?.fullDisplayName ?? "nil"), matches: \(scannedMatches?.count ?? 0)")
        }
    }

    // MARK: - Full Screen Customer Detail

    @ViewBuilder
    private func customerDetailFullScreen(_ customer: Customer) -> some View {
        // Use updated customer if available, otherwise use passed customer
        let displayCustomer = updatedCustomer ?? customer

        VStack(spacing: 0) {
            // Custom header with liquid glass back button
            HStack(spacing: 14) {
                // Back button with liquid glass
                Button {
                    Haptics.light()
                    if isEditingCustomer {
                        // Cancel edit mode
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isEditingCustomer = false
                            editErrorMessage = nil
                        }
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            detailAppearAnimation = false
                            updatedCustomer = nil  // Clear on exit
                            mode = .search
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                        Text(isEditingCustomer ? "Cancel" : "Back")
                            .font(.system(size: 15, weight: .medium))
                    }
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: Capsule())

                Spacer()

                // Edit/Save button
                if isEditingCustomer {
                    Button {
                        Haptics.medium()
                        Task { await saveCustomerEdits(for: customer) }
                    } label: {
                        HStack(spacing: 5) {
                            if isSavingCustomer {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .tint(.white)
                            } else {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            Text("Save")
                                .font(.system(size: 15, weight: .medium))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: Capsule())
                    .disabled(isSavingCustomer)
                } else {
                    Button {
                        Haptics.light()
                        startEditingCustomer(displayCustomer)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "pencil")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Edit")
                                .font(.system(size: 15, weight: .medium))
                        }
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: Capsule())
                }

                // Done button
                Button {
                    Haptics.light()
                    onDismiss()
                } label: {
                    Text("Done")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            // Scrollable content
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    if isEditingCustomer {
                        customerEditContent(displayCustomer)
                    } else {
                        customerDetailContent(displayCustomer)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 34)
                .scaleEffect(detailAppearAnimation ? 1 : 0.96)
                .opacity(detailAppearAnimation ? 1 : 0)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                detailAppearAnimation = true
            }
        }
        .alert("Adjust Loyalty Points", isPresented: $showPointsAdjustment) {
            TextField("New total points", text: $pointsAdjustmentValue)
                .keyboardType(.numberPad)
            Button("Cancel", role: .cancel) {
                pointsAdjustmentValue = ""
                adjustingPointsForCustomer = nil
            }
            Button("Save") {
                applyPointsAdjustment()
            }
        } message: {
            if let customer = adjustingPointsForCustomer {
                Text("Current: \(customer.formattedLoyaltyPoints)\nEnter new total points value.")
            }
        }
        .overlay {
            // Success/error message toast
            if let message = pointsAdjustmentMessage {
                VStack {
                    Spacer()
                    Text(message)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.green.opacity(0.9), in: Capsule())
                        .padding(.bottom, 100)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation { pointsAdjustmentMessage = nil }
                    }
                }
            }
        }
    }

    // MARK: - Full Screen Order Detail

    @ViewBuilder
    private func orderDetailFullScreen(order: Order, customer: Customer) -> some View {
        VStack(spacing: 0) {
            // Header with back button
            HStack(spacing: 14) {
                Button {
                    Haptics.light()
                    withAnimation(.easeInOut(duration: 0.25)) {
                        mode = .detail(customer)
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                        Text(customer.displayName)
                            .font(.system(size: 15, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: Capsule())

                Spacer()

                Text("Order #\(order.shortOrderNumber)")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)

                Spacer()

                // Done button
                Button {
                    Haptics.light()
                    onDismiss()
                } label: {
                    Text("Done")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            // Shared order detail content
            OrderDetailContentView(
                order: order,
                showCustomerInfo: false,  // Already showing customer in header/breadcrumb
                customerOverride: customer  // Pass customer context for email display
            )
        }
    }

    // MARK: - Full Order History

    private func orderHistoryFullScreen(customer: Customer) -> some View {
        VStack(spacing: 0) {
            // Header with back button
            HStack(spacing: 14) {
                Button {
                    Haptics.light()
                    withAnimation(.easeInOut(duration: 0.25)) {
                        mode = .detail(customer)
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                        Text(customer.displayName)
                            .font(.system(size: 15, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: Capsule())

                Spacer()

                Text("Order History")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)

                Spacer()

                // Done button
                Button {
                    Haptics.light()
                    onDismiss()
                } label: {
                    Text("Done")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            // Search bar
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))

                TextField("Search orders...", text: $orderHistorySearchText)
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                if !orderHistorySearchText.isEmpty {
                    Button {
                        orderHistorySearchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.white.opacity(0.06), in: .rect(cornerRadius: 12))
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            // Order list
            if isLoadingFullHistory {
                Spacer()
                ProgressView()
                    .scaleEffect(1.2)
                    .tint(.white.opacity(0.5))
                Spacer()
            } else if filteredOrderHistory.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: orderHistorySearchText.isEmpty ? "bag" : "magnifyingglass")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(.white.opacity(0.15))
                    Text(orderHistorySearchText.isEmpty ? "No orders yet" : "No matching orders")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                }
                Spacer()
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(filteredOrderHistory.enumerated()), id: \.element.id) { index, order in
                            OrderRowCompact(order: order) {
                                Haptics.light()
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    mode = .orderDetail(order, customer)
                                }
                            }

                            if index < filteredOrderHistory.count - 1 {
                                Divider()
                                    .background(.white.opacity(0.08))
                                    .padding(.horizontal, 14)
                            }
                        }
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .glassEffect(.regular, in: .rect(cornerRadius: 14))
                .contentMargins(.vertical, 1, for: .scrollContent)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .onAppear {
            loadFullOrderHistory(for: customer)
        }
    }

    private var filteredOrderHistory: [Order] {
        guard !orderHistorySearchText.isEmpty else { return fullOrderHistory }
        let query = orderHistorySearchText.lowercased()
        return fullOrderHistory.filter { order in
            order.orderNumber.lowercased().contains(query) ||
            order.formattedTotal.lowercased().contains(query) ||
            order.status.displayName.lowercased().contains(query) ||
            order.formattedDate.lowercased().contains(query)
        }
    }

    private func loadFullOrderHistory(for customer: Customer) {
        guard fullOrderHistory.isEmpty else { return }  // Already loaded
        isLoadingFullHistory = true
        Task {
            do {
                let orders = try await fetchOrdersForCustomer(
                    customerId: customer.id,
                    storeId: storeId,
                    limit: 100  // Get full history
                )
                await MainActor.run {
                    fullOrderHistory = orders
                    isLoadingFullHistory = false
                }
            } catch {
                Log.network.error("Failed to load full order history: \(error)")
                await MainActor.run {
                    fullOrderHistory = []
                    isLoadingFullHistory = false
                }
            }
        }
    }

    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: value as NSDecimalNumber) ?? "$0.00"
    }

    private var navigationTitle: String {
        switch mode {
        case .search:
            return isScannedMode ? "ID Scanned" : "Find Customer"
        case .create:
            return "New Customer"
        case .scanner:
            return "Scan ID"
        case .detail, .orderDetail, .orderHistory:
            return ""  // Breadcrumb shows the name
        }
    }

    @ViewBuilder
    private var toolbarActions: some View {
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
                Button {
                    prefillCreateFormFromScan()
                    mode = .create
                } label: {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
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
            EmptyView()  // Breadcrumb handles navigation
        case .scanner:
            EmptyView()
        }
    }

    // MARK: - Search Content

    @ViewBuilder
    private var searchContent: some View {
        // Scanned ID info banner
        if let scanned = effectiveScannedID {
            scannedInfoBanner(scanned)
        }

        // Search field
        searchField

        // Results area
        resultsArea
    }

    // MARK: - Search Field

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))

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
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
    }

    // MARK: - Scanned Info Banner

    private func scannedInfoBanner(_ scanned: ScannedID) -> some View {
        HStack(spacing: 14) {
            // Initials circle with glass
            Text(scanned.initials)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 50, height: 50)
                .glassEffect(.regular, in: .circle)

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
    }

    // MARK: - Results Area

    private var resultsArea: some View {
        AdaptiveScrollView(maxHeight: isScannedMode ? 420 : 380) {
            VStack(alignment: .leading, spacing: 10) {
                // Show scanned matches if available
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

    // MARK: - Scanned Matches Section

    private func scannedMatchesSection(_ matches: [CustomerMatch]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(matches.count == 1 ? "1 Match Found" : "\(matches.count) Matches Found")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.35))
                .textCase(.uppercase)
                .tracking(0.5)
                .padding(.leading, 4)

            // Individual match rows with liquid glass
            VStack(spacing: 8) {
                ForEach(matches.prefix(5), id: \.id) { match in
                    scannedMatchRow(match)
                }
            }

            // Create new button with glass
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
            // Tap row to view profile
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                detailAppearAnimation = false
                mode = .detail(match.customer)
            }
        } label: {
            HStack(spacing: 12) {
                // Avatar with glass
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

                        // Loyalty points badge
                        if let points = match.customer.loyaltyPoints {
                            HStack(spacing: 2) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 8, weight: .bold))
                                Text("\(points)")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(points >= 0 ? .yellow.opacity(0.8) : .red.opacity(0.7))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.white.opacity(0.08), in: .capsule)
                        }
                    }
                }

                Spacer()

                // Quick select button
                Button {
                    Haptics.medium()
                    selectScannedMatch(match)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.3))
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

            Text("Search customers")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }

    // MARK: - Scanned Actions

    private func selectScannedMatch(_ match: CustomerMatch) {
        // Update license if needed
        if match.customer.driversLicenseNumber == nil, let scanned = effectiveScannedID, let license = scanned.licenseNumber {
            Task { await CustomerService.updateCustomerLicense(match.customer.id, licenseNumber: license) }
        }

        ScanFeedback.shared.customerFound()
        onCustomerCreated(match.customer)
    }

    private func prefillCreateFormFromScan() {
        guard let scanned = effectiveScannedID else { return }
        firstName = scanned.firstName ?? ""
        lastName = scanned.lastName ?? ""
        // Convert from YYYY-MM-DD to MM/DD/YYYY for the form
        if let dob = scanned.dateOfBirth {
            let inputFormatter = DateFormatter()
            inputFormatter.dateFormat = "yyyy-MM-dd"
            if let date = inputFormatter.date(from: dob) {
                let outputFormatter = DateFormatter()
                outputFormatter.dateFormat = "MM/dd/yyyy"
                dateOfBirth = outputFormatter.string(from: date)
            }
        }
    }

    // MARK: - Create Content

    @ViewBuilder
    private var createContent: some View {
        // Name fields
        VStack(alignment: .leading, spacing: 8) {
            Text("NAME")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .tracking(0.5)
                .padding(.leading, 4)

            HStack(spacing: 12) {
                HStack(spacing: 12) {
                    TextField("", text: $firstName, prompt: Text("First").foregroundColor(.white.opacity(0.35)))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                        .focused($focusedCreateField, equals: .firstName)
                }
                .padding(.horizontal, 16)
                .frame(height: 48)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))

                HStack(spacing: 12) {
                    TextField("", text: $lastName, prompt: Text("Last").foregroundColor(.white.opacity(0.35)))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                        .focused($focusedCreateField, equals: .lastName)
                }
                .padding(.horizontal, 16)
                .frame(height: 48)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
            }
        }

        // DOB
        VStack(alignment: .leading, spacing: 8) {
            Text("DATE OF BIRTH")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .tracking(0.5)
                .padding(.leading, 4)

            HStack(spacing: 12) {
                Image(systemName: "calendar")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
                TextField("", text: $dateOfBirth, prompt: Text("MM/DD/YYYY").foregroundColor(.white.opacity(0.35)))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                    .keyboardType(.numbersAndPunctuation)
                    .focused($focusedCreateField, equals: .dob)
                    .onChange(of: dateOfBirth) { _, newValue in
                        dateOfBirth = formatDateInput(newValue)
                    }
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
        }

        // Contact
        VStack(alignment: .leading, spacing: 8) {
            Text("CONTACT (OPTIONAL)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .tracking(0.5)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(width: 20)
                    TextField("", text: $phone, prompt: Text("Phone").foregroundColor(.white.opacity(0.35)))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                        .keyboardType(.phonePad)
                        .focused($focusedCreateField, equals: .phone)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider().background(.white.opacity(0.08))

                HStack(spacing: 12) {
                    Image(systemName: "envelope.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(width: 20)
                    TextField("", text: $email, prompt: Text("Email").foregroundColor(.white.opacity(0.35)))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .focused($focusedCreateField, equals: .email)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
        }

        // Error
        if let error = errorMessage {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 15))
                Text(error)
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(Design.Colors.Semantic.error)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 14).fill(Design.Colors.Semantic.error.opacity(0.1)))
        }

        // Create button
        Button {
            Haptics.medium()
            focusedCreateField = nil
            Task { await createCustomer() }
        } label: {
            HStack {
                if isCreating {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.white)
                } else {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Create Customer")
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .foregroundStyle(isCreateValid ? .white : .white.opacity(0.4))
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(.white.opacity(isCreateValid ? 0.15 : 0.08), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(!isCreateValid || isCreating)
    }

    // MARK: - Scanner Content

    @State private var showFullScreenScanner = false

    @ViewBuilder
    private var scannerContent: some View {
        VStack(spacing: 20) {
            ZStack {
                ProgressView()
                    .scaleEffect(1.3)
                    .tint(.white.opacity(0.6))
            }
            .frame(width: 80, height: 80)
            .background(Circle().fill(.white.opacity(0.08)))

            Text("Launching scanner...")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.04)))
        .onAppear {
            showFullScreenScanner = true
        }
        .fullScreenCover(isPresented: $showFullScreenScanner) {
            IDScannerView(
                storeId: storeId,
                onCustomerSelected: { customer in
                    showFullScreenScanner = false
                    selectCustomer(customer)
                },
                onDismiss: {
                    showFullScreenScanner = false
                    mode = .search
                },
                onScannedIDWithMatches: { scannedID, matches in
                    // Update local state instead of presenting a new sheet
                    showFullScreenScanner = false
                    localScannedID = scannedID
                    localScannedMatches = matches
                    mode = .search
                    print("🆔 Scanner returned to sheet - name: \(scannedID.fullDisplayName), matches: \(matches.count)")
                }
            )
        }
    }

    // MARK: - Customer Detail Content

    @State private var customerOrders: [Order] = []
    @State private var isLoadingOrders = false

    // Full order history
    @State private var fullOrderHistory: [Order] = []
    @State private var isLoadingFullHistory = false
    @State private var orderHistorySearchText = ""

    @ViewBuilder
    private func customerDetailContent(_ customer: Customer) -> some View {
        customerProfileCard(customer)
        customerCRMStats(customer)
        customerContactSection(customer)
        customerOrdersSection(customer)

        // Select button
        Button {
            Haptics.medium()
            selectCustomer(updatedCustomer ?? customer)
        } label: {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                Text("Select Customer")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(ScaleButtonStyle())
        .onAppear {
            loadCustomerOrders(for: customer)
        }
    }

    // MARK: - Customer Edit Content

    @ViewBuilder
    private func customerEditContent(_ customer: Customer) -> some View {
        // Name fields
        VStack(alignment: .leading, spacing: 8) {
            Text("NAME")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .tracking(0.5)
                .padding(.leading, 4)

            HStack(spacing: 12) {
                HStack(spacing: 12) {
                    TextField("", text: $editFirstName, prompt: Text("First").foregroundColor(.white.opacity(0.35)))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 16)
                .frame(height: 48)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))

                HStack(spacing: 12) {
                    TextField("", text: $editLastName, prompt: Text("Last").foregroundColor(.white.opacity(0.35)))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 16)
                .frame(height: 48)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
            }
        }

        // Contact fields
        VStack(alignment: .leading, spacing: 8) {
            Text("CONTACT INFORMATION")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .tracking(0.5)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(width: 20)
                    TextField("", text: $editPhone, prompt: Text("Phone").foregroundColor(.white.opacity(0.35)))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                        .keyboardType(.phonePad)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider().background(.white.opacity(0.08))

                HStack(spacing: 12) {
                    Image(systemName: "envelope.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(width: 20)
                    TextField("", text: $editEmail, prompt: Text("Email").foregroundColor(.white.opacity(0.35)))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider().background(.white.opacity(0.08))

                HStack(spacing: 12) {
                    Image(systemName: "calendar")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(width: 20)
                    TextField("", text: $editDateOfBirth, prompt: Text("MM/DD/YYYY").foregroundColor(.white.opacity(0.35)))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                        .keyboardType(.numbersAndPunctuation)
                        .onChange(of: editDateOfBirth) { _, newValue in
                            editDateOfBirth = formatDateInput(newValue)
                        }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
        }

        // Error message
        if let error = editErrorMessage {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 15))
                Text(error)
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(Design.Colors.Semantic.error)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 14).fill(Design.Colors.Semantic.error.opacity(0.1)))
        }

        // Hint text
        Text("Tap Save to update customer information")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white.opacity(0.4))
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
    }

    private func startEditingCustomer(_ customer: Customer) {
        editFirstName = customer.firstName ?? ""
        editLastName = customer.lastName ?? ""
        editEmail = customer.email ?? ""
        editPhone = customer.phone ?? ""

        // Convert DOB from YYYY-MM-DD to MM/DD/YYYY for editing
        if let dob = customer.dateOfBirth, !dob.isEmpty {
            let inputFormatter = DateFormatter()
            inputFormatter.dateFormat = "yyyy-MM-dd"
            if let date = inputFormatter.date(from: dob) {
                let outputFormatter = DateFormatter()
                outputFormatter.dateFormat = "MM/dd/yyyy"
                editDateOfBirth = outputFormatter.string(from: date)
            } else {
                editDateOfBirth = ""
            }
        } else {
            editDateOfBirth = ""
        }

        editErrorMessage = nil
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isEditingCustomer = true
        }
    }

    private func saveCustomerEdits(for customer: Customer) async {
        editErrorMessage = nil
        isSavingCustomer = true
        defer { isSavingCustomer = false }

        // Validate
        let trimmedFirst = editFirstName.trimmingCharacters(in: .whitespaces)
        let trimmedLast = editLastName.trimmingCharacters(in: .whitespaces)

        if trimmedFirst.isEmpty || trimmedLast.isEmpty {
            editErrorMessage = "First and last name are required"
            return
        }

        // Parse DOB if provided
        var dobFormatted: String? = nil
        if !editDateOfBirth.isEmpty {
            guard let parsed = parseDate(editDateOfBirth) else {
                editErrorMessage = "Invalid date format (use MM/DD/YYYY)"
                return
            }
            dobFormatted = parsed
        }

        // Build update fields
        let fields = CustomerUpdateFields(
            firstName: trimmedFirst,
            lastName: trimmedLast,
            email: editEmail.trimmingCharacters(in: .whitespaces).isEmpty ? nil : editEmail.trimmingCharacters(in: .whitespaces),
            phone: editPhone.trimmingCharacters(in: .whitespaces).isEmpty ? nil : editPhone.trimmingCharacters(in: .whitespaces),
            dateOfBirth: dobFormatted
        )

        let result = await CustomerService.updateCustomer(customer.id, fields: fields)

        await MainActor.run {
            switch result {
            case .success(let updated):
                print("✅ Customer updated: \(updated.displayName)")
                updatedCustomer = updated
                Haptics.success()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isEditingCustomer = false
                    pointsAdjustmentMessage = "Customer updated successfully"
                }
            case .failure(let error):
                print("❌ Customer update failed: \(error)")
                editErrorMessage = "Update failed: \(error.localizedDescription)"
                Haptics.error()
            }
        }
    }

    private func customerProfileCard(_ customer: Customer) -> some View {
        HStack(spacing: 16) {
            // Monochrome avatar
            ZStack {
                Circle()
                    .fill(.white.opacity(0.1))
                    .frame(width: 72, height: 72)

                Text(customer.initials)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(customer.displayName)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)

                HStack(spacing: 12) {
                    // Loyalty tier badge
                    HStack(spacing: 5) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text(customer.loyaltyTierDisplay)
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.1), in: .capsule)

                    // Member since
                    Text("Since \(formatMemberSince(customer.createdAt))")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }

            Spacer()
        }
        .padding(20)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    private func customerCRMStats(_ customer: Customer) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("METRICS")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .tracking(0.5)
                .padding(.leading, 4)

            // 2x2 grid of stats
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ], spacing: 10) {
                CRMStatBox(
                    title: "Lifetime Value",
                    value: formatCurrency(customer.totalSpent ?? 0),
                    icon: "dollarsign.circle.fill"
                )

                CRMStatBox(
                    title: "Total Orders",
                    value: "\(customer.totalOrders ?? 0)",
                    icon: "bag.fill"
                )

                // Loyalty Points - long-press to adjust
                EditableLoyaltyStatBox(
                    value: displayLoyaltyPoints(for: customer),
                    isAdjusting: isAdjustingPoints && adjustingPointsForCustomer?.id == customer.id
                ) {
                    Haptics.medium()
                    adjustingPointsForCustomer = customer
                    pointsAdjustmentValue = ""
                    updatedLoyaltyPoints = nil  // Clear any previous override
                    showPointsAdjustment = true
                }

                CRMStatBox(
                    title: "Avg. Order",
                    value: formatAverageOrder(totalSpent: customer.totalSpent, orderCount: customer.totalOrders),
                    icon: "chart.bar.fill"
                )
            }
        }
    }

    private func customerContactSection(_ customer: Customer) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CONTACT INFORMATION")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .tracking(0.5)
                .padding(.leading, 4)

            VStack(spacing: 1) {
                if let phone = customer.formattedPhone {
                    ContactInfoRow(icon: "phone.fill", label: "Phone", value: phone)
                }
                if let email = customer.email, !email.isEmpty {
                    ContactInfoRow(icon: "envelope.fill", label: "Email", value: email)
                }
                if let dob = customer.dateOfBirth, !dob.isEmpty {
                    ContactInfoRow(icon: "calendar", label: "Date of Birth", value: formatDOBWithAge(dob))
                }
                if let address = customer.formattedAddress {
                    ContactInfoRow(icon: "location.fill", label: "Address", value: address)
                }

                // Always show at least one row
                if customer.formattedPhone == nil && (customer.email ?? "").isEmpty {
                    HStack {
                        Spacer()
                        Text("No contact info on file")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.3))
                        Spacer()
                    }
                    .padding(.vertical, 16)
                }
            }
            .glassEffect(.regular, in: .rect(cornerRadius: 14))
        }
    }

    private func customerOrdersSection(_ customer: Customer) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("RECENT ORDERS")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .tracking(0.5)

                Spacer()

                if isLoadingOrders {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(.white.opacity(0.4))
                } else if customerOrders.count > 0 {
                    Button {
                        Haptics.light()
                        withAnimation(.easeInOut(duration: 0.25)) {
                            mode = .orderHistory(customer)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("See All")
                                .font(.system(size: 13, weight: .medium))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, 4)

            if customerOrders.isEmpty && !isLoadingOrders {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "bag")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(.white.opacity(0.15))
                        Text("No order history")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    .padding(.vertical, 28)
                    Spacer()
                }
                .glassEffect(.regular, in: .rect(cornerRadius: 14))
            } else {
                VStack(spacing: 0) {
                    // Limit to 3 recent orders for dynamic modal height
                    ForEach(Array(customerOrders.prefix(3).enumerated()), id: \.element.id) { index, order in
                        OrderRowCompact(order: order) {
                            Haptics.light()
                            withAnimation(.easeInOut(duration: 0.25)) {
                                mode = .orderDetail(order, customer)
                            }
                        }

                        // Divider between rows (not after last)
                        if index < min(customerOrders.count, 3) - 1 {
                            Divider()
                                .background(.white.opacity(0.08))
                                .padding(.horizontal, 14)
                        }
                    }
                }
                .glassEffect(.regular, in: .rect(cornerRadius: 14))
            }
        }
    }

    private func loadCustomerOrders(for customer: Customer) {
        isLoadingOrders = true
        Task {
            do {
                // Fetch orders directly by customer_id from Supabase
                let orders = try await fetchOrdersForCustomer(customerId: customer.id, storeId: storeId, limit: 5)
                await MainActor.run {
                    customerOrders = orders
                    isLoadingOrders = false
                }
            } catch {
                Log.network.error("Failed to load customer orders: \(error)")
                await MainActor.run {
                    customerOrders = []
                    isLoadingOrders = false
                }
            }
        }
    }

    /// Fetch orders directly by customer_id (relationship ID from v_store_customers)
    private func fetchOrdersForCustomer(customerId: UUID, storeId: UUID, limit: Int) async throws -> [Order] {
        let response = try await supabase
            .from("orders")
            .select("*, order_items(*), v_store_customers(first_name, last_name, email, phone), users!orders_created_by_user_id_fkey(id, first_name, last_name, email), locations!orders_location_id_fkey(id, name)")
            .eq("store_id", value: storeId.uuidString)
            .eq("customer_id", value: customerId.uuidString)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()

        // Debug: Log raw response
        if let jsonString = String(data: response.data, encoding: .utf8) {
            print("📋 Orders raw response (\(jsonString.count) chars):")
            print(jsonString.prefix(3000))

            // Check if order_items key exists
            if jsonString.contains("\"order_items\"") {
                print("📋 ✅ JSON contains 'order_items' key")
                // Try to count items
                let itemMatches = jsonString.components(separatedBy: "\"product_name\"").count - 1
                print("📋 Found ~\(itemMatches) items in JSON")
            } else {
                print("📋 ❌ JSON missing 'order_items' key - items not joined!")
            }
            if jsonString.contains("\"users\"") {
                print("📋 ✅ JSON contains 'users' key")
            } else {
                print("📋 ❌ JSON missing 'users' key - FK join not working")
            }
            if jsonString.contains("\"locations\"") {
                print("📋 ✅ JSON contains 'locations' key")
            } else {
                print("📋 ❌ JSON missing 'locations' key - FK join not working")
            }
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let orders = try decoder.decode([Order].self, from: response.data)
            print("📋 Decoded \(orders.count) orders")
            for order in orders.prefix(2) {
                print("📋 Order \(order.shortOrderNumber):")
                print("   - items: \(order.items?.count ?? 0)")
                print("   - employee: \(order.employee?.fullName ?? "NIL") (id: \(order.employee?.id?.uuidString ?? "nil"))")
                print("   - location: \(order.location?.name ?? "NIL") (id: \(order.location?.id?.uuidString ?? "nil"))")
                print("   - employeeId: \(order.employeeId?.uuidString ?? "nil")")
                print("   - locationId: \(order.locationId?.uuidString ?? "nil")")
            }
            return orders
        } catch {
            print("📋 Decode error: \(error)")
            if let jsonString = String(data: response.data, encoding: .utf8) {
                print("📋 Failed JSON: \(jsonString.prefix(500))")
            }
            throw error
        }
    }

    /// Formats a DOB string from YYYY-MM-DD to readable format with age
    private func formatDOBWithAge(_ dateString: String) -> String {
        let inputFormatter = DateFormatter()
        inputFormatter.dateFormat = "yyyy-MM-dd"
        guard let date = inputFormatter.date(from: dateString) else {
            return dateString
        }
        let outputFormatter = DateFormatter()
        outputFormatter.dateFormat = "MMM d, yyyy"
        let formatted = outputFormatter.string(from: date)

        // Calculate age
        let calendar = Calendar.current
        let ageComponents = calendar.dateComponents([.year], from: date, to: Date())
        if let age = ageComponents.year {
            return "\(formatted) (\(age) yrs)"
        }
        return formatted
    }

    private func formatMemberSince(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter.string(from: date)
    }

    private func formatAverageOrder(totalSpent: Decimal?, orderCount: Int?) -> String {
        guard let spent = totalSpent, let count = orderCount, count > 0 else { return "$0" }
        let average = spent / Decimal(count)
        return formatCurrency(average)
    }

    // MARK: - Helpers

    private var displayName: String {
        let first = firstName.trimmingCharacters(in: .whitespaces)
        let last = lastName.trimmingCharacters(in: .whitespaces)
        if first.isEmpty && last.isEmpty { return "" }
        return "\(first) \(last)".trimmingCharacters(in: .whitespaces)
    }

    private var isCreateValid: Bool {
        !firstName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !lastName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func performSearch(query: String) {
        searchTask?.cancel()

        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            searchResults = []
            isSearching = false
            return
        }

        isSearching = true

        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }

            let results = await CustomerService.searchCustomers(
                query: trimmed,
                storeId: storeId,
                limit: 10
            )

            guard !Task.isCancelled else { return }

            await MainActor.run {
                searchResults = results
                isSearching = false
            }
        }
    }

    private func selectCustomer(_ customer: Customer) {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )

        Haptics.success()
        onCustomerCreated(customer)
    }

    private func formatDateInput(_ input: String) -> String {
        let digits = input.filter { $0.isNumber }
        let limited = String(digits.prefix(8))

        var result = ""
        for (index, char) in limited.enumerated() {
            if index == 2 || index == 4 { result += "/" }
            result.append(char)
        }
        return result
    }

    private func parseDate(_ dateString: String) -> String? {
        let parts = dateString.split(separator: "/")
        guard parts.count == 3,
              let month = Int(parts[0]), month >= 1, month <= 12,
              let day = Int(parts[1]), day >= 1, day <= 31,
              let year = Int(parts[2]), year >= 1900, year <= 2100 else {
            return nil
        }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private func createCustomer() async {
        errorMessage = nil
        isCreating = true
        defer { isCreating = false }

        var dobFormatted: String? = nil
        if !dateOfBirth.isEmpty {
            guard let parsed = parseDate(dateOfBirth) else {
                errorMessage = "Invalid date format"
                return
            }
            dobFormatted = parsed
        }

        // Use scanned ID data for address/license if available
        let scanned = effectiveScannedID

        let customerData = NewCustomerFromScan(
            firstName: firstName.trimmingCharacters(in: .whitespaces),
            middleName: scanned?.middleName,
            lastName: lastName.trimmingCharacters(in: .whitespaces),
            dateOfBirth: dobFormatted,
            streetAddress: scanned?.streetAddress,
            city: scanned?.city,
            state: scanned?.state,
            postalCode: scanned?.zipCode,
            driversLicenseNumber: scanned?.licenseNumber
        )

        let phoneValue = phone.trimmingCharacters(in: .whitespaces).isEmpty ? nil : phone
        let emailValue = email.trimmingCharacters(in: .whitespaces).isEmpty ? nil : email

        let result = await CustomerService.createCustomer(customerData, storeId: storeId, phone: phoneValue, email: emailValue)

        switch result {
        case .success(let customer):
            Haptics.success()
            onCustomerCreated(customer)
        case .failure(let error):
            Haptics.error()
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Loyalty Points Adjustment

    private func applyPointsAdjustment() {
        guard let customer = adjustingPointsForCustomer,
              let newPoints = Int(pointsAdjustmentValue.trimmingCharacters(in: .whitespaces)),
              newPoints >= 0 else {
            pointsAdjustmentValue = ""
            adjustingPointsForCustomer = nil
            return
        }

        isAdjustingPoints = true
        pointsAdjustmentValue = ""

        Task {
            do {
                print("📊 Adjusting points for customer \(customer.id) to \(newPoints)")
                // Set the new balance directly via RPC
                let result = try await LoyaltyService.shared.setPoints(
                    customerId: customer.id,
                    points: newPoints,
                    reason: "staff_adjustment"
                )

                await MainActor.run {
                    print("✅ Points adjustment succeeded: \(result.balanceBefore ?? 0) → \(result.balanceAfter ?? 0)")
                    // Update local state immediately for instant UI feedback
                    updatedLoyaltyPoints = result.balanceAfter ?? newPoints
                    isAdjustingPoints = false
                    adjustingPointsForCustomer = nil

                    let message: String
                    if let adjustment = result.adjustment, adjustment != 0 {
                        let sign = adjustment > 0 ? "+" : ""
                        message = "Points: \(result.balanceBefore ?? 0) → \(result.balanceAfter ?? 0) (\(sign)\(adjustment))"
                    } else {
                        message = result.message ?? "Points updated"
                    }
                    withAnimation {
                        pointsAdjustmentMessage = message
                    }
                    Haptics.success()
                }
            } catch {
                print("❌ Points adjustment failed: \(error)")
                await MainActor.run {
                    isAdjustingPoints = false
                    adjustingPointsForCustomer = nil
                    withAnimation {
                        pointsAdjustmentMessage = "Failed: \(error.localizedDescription)"
                    }
                    Haptics.error()
                }
            }
        }
    }

    /// Get display points value - uses override if recently updated
    private func displayLoyaltyPoints(for customer: Customer) -> String {
        if let override = updatedLoyaltyPoints, adjustingPointsForCustomer == nil {
            // Check if this customer matches the one we updated
            if case .detail(let currentCustomer) = mode, currentCustomer.id == customer.id {
                return "\(override)"
            }
        }
        return customer.formattedLoyaltyPoints
    }
}

// MARK: - CRM Stat Box (Monochrome Professional)

private struct CRMStatBox: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(value)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }
}

// MARK: - Editable Loyalty Stat Box (with long-press)

private struct EditableLoyaltyStatBox: View {
    let value: String
    var isAdjusting: Bool = false
    let onLongPress: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "star.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.yellow.opacity(0.8))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                if isAdjusting {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.white)
                } else {
                    Text(value)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                HStack(spacing: 4) {
                    Text("Loyalty Points")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                    Text("• Hold")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
        .onLongPressGesture(minimumDuration: 0.5) {
            onLongPress()
        }
    }
}

// MARK: - Contact Info Row

private struct ContactInfoRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.35))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.3))
                    .tracking(0.5)

                Text(value)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

// MARK: - Order Row Compact (for Customer Detail - clickable)

private struct OrderRowCompact: View {
    let order: Order
    let onTap: () -> Void

    var body: some View {
        Button {
            onTap()
        } label: {
            HStack(spacing: 12) {
                // Order number
                Text("#\(order.shortOrderNumber)")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.8))

                // Order type icon
                Image(systemName: order.orderType.icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))

                Spacer()

                // Date
                Text(formatOrderDate(order.createdAt))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))

                // Amount
                Text(formatAmount(order.totalAmount))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                // Status text (monochrome)
                Text(order.status.displayName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.1), in: .capsule)

                // Chevron to indicate tappable
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(OrderRowButtonStyle())
    }

    private func formatOrderDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }

    private func formatAmount(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 2
        return formatter.string(from: amount as NSDecimalNumber) ?? "$0"
    }
}

// MARK: - Order Row Button Style (subtle highlight on press)

private struct OrderRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? .white.opacity(0.05) : .clear)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}


// MARK: - Customer Row (Monochrome Liquid Glass)

private struct CustomerRow: View {
    let customer: Customer
    let onSelect: () -> Void
    var onViewProfile: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            // Main content - tappable to view profile (or select if no profile handler)
            Button {
                Haptics.light()
                if let viewProfile = onViewProfile {
                    viewProfile()
                } else {
                    onSelect()
                }
            } label: {
                HStack(spacing: 12) {
                    // Monochrome avatar
                    ZStack {
                        Circle()
                            .fill(.white.opacity(0.1))
                            .frame(width: 44, height: 44)

                        Text(customer.initials)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white.opacity(0.8))
                    }

                    // Customer info
                    VStack(alignment: .leading, spacing: 3) {
                        Text(customer.displayName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        HStack(spacing: 8) {
                            if let phone = customer.formattedPhone {
                                Text(phone)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.45))
                            } else if let email = customer.email, !email.isEmpty {
                                Text(email)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.45))
                                    .lineLimit(1)
                            }
                        }
                    }

                    Spacer(minLength: 4)

                    // Stats badges
                    HStack(spacing: 6) {
                        // Loyalty points badge (always show if customer has points field)
                        if let points = customer.loyaltyPoints {
                            HStack(spacing: 2) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 8, weight: .bold))
                                Text("\(points)")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(points >= 0 ? .yellow.opacity(0.8) : .red.opacity(0.7))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.white.opacity(0.08), in: .capsule)
                        }

                        if let orders = customer.totalOrders, orders > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: "bag.fill")
                                    .font(.system(size: 9, weight: .bold))
                                Text("\(orders)")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(.white.opacity(0.5))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.white.opacity(0.08), in: .capsule)
                        }
                    }

                    // Quick select button (only if profile view is available)
                    if onViewProfile != nil {
                        Button {
                            Haptics.medium()
                            onSelect()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 24, weight: .medium))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                    }

                    // Chevron inline with the row
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.3))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                // CRITICAL: contentShape INSIDE the label makes entire row tappable
                .contentShape(RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(ScaleButtonStyle())
            // iOS 26: .glassEffect provides proper interactive hit testing in sheets
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
        }
    }
}


// MARK: - ScannedID Extensions

private extension ScannedID {
    var initials: String {
        let first = firstName?.first.map(String.init) ?? ""
        let last = lastName?.first.map(String.init) ?? ""
        return (first + last).uppercased()
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
