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

        static func == (lhs: Mode, rhs: Mode) -> Bool {
            switch (lhs, rhs) {
            case (.search, .search), (.create, .create), (.scanner, .scanner):
                return true
            case (.detail(let c1), .detail(let c2)):
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
            }
        }
    }

    @State private var mode: Mode = .search
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

    @FocusState private var isSearchFocused: Bool
    @FocusState private var focusedCreateField: CreateField?

    enum CreateField: Hashable {
        case firstName, lastName, dob, phone, email
    }


    var body: some View {
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
                    case .detail(let customer):
                        customerDetailContent(customer)
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
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
        .onAppear {
            print("📋 CustomerSearchContent appeared - isScannedMode: \(isScannedMode), scannedID: \(scannedID?.fullDisplayName ?? "nil"), matches: \(scannedMatches?.count ?? 0)")
        }
    }

    private var navigationTitle: String {
        switch mode {
        case .search:
            return isScannedMode ? "ID Scanned" : "Find Customer"
        case .create:
            return "New Customer"
        case .scanner:
            return "Scan ID"
        case .detail:
            return "Customer"
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
        case .create, .detail:
            Button {
                mode = .search
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }
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
                                onSelect: { selectCustomer(customer) }
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
            Haptics.medium()
            selectScannedMatch(match)
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
                }

                Spacer()

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
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(.white, in: RoundedRectangle(cornerRadius: 12))
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
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
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
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
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
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
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
                        .tint(.black)
                } else {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Create Customer")
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .foregroundStyle(isCreateValid ? .black : .black.opacity(0.5))
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(isCreateValid ? .white : .white.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
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

    @ViewBuilder
    private func customerDetailContent(_ customer: Customer) -> some View {
        customerProfileCard(customer)
        customerCRMStats(customer)
        customerContactSection(customer)
        customerOrdersSection(customer)

        // Select button
        Button {
            Haptics.medium()
            selectCustomer(customer)
        } label: {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                Text("Select Customer")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(.white, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .onAppear {
            loadCustomerOrders(for: customer)
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
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
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

                CRMStatBox(
                    title: "Loyalty Points",
                    value: customer.formattedLoyaltyPoints,
                    icon: "star.fill"
                )

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
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
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
                if customer.formattedPhone == nil && (customer.email == nil || customer.email!.isEmpty) {
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
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
                    .tracking(0.5)

                Spacer()

                if isLoadingOrders {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(.white.opacity(0.4))
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
                            SheetCoordinator.shared.present(.orderDetail(order: order))
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
            .select("""
                id, order_number, store_id, customer_id, order_type, status, payment_status,
                subtotal, discount_amount, tax_amount, total_amount, created_at, updated_at,
                v_store_customers(first_name, last_name, email, phone)
            """)
            .eq("store_id", value: storeId.uuidString)
            .eq("customer_id", value: customerId.uuidString)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([Order].self, from: response.data)
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

    private func formatCurrency(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: amount as NSDecimalNumber) ?? "$0"
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

    var body: some View {
        HStack(spacing: 10) {
            // Main content - tappable to select
            Button {
                Haptics.light()
                onSelect()
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

                    // Monochrome stats
                    HStack(spacing: 6) {
                        if let points = customer.loyaltyPoints, points > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 9, weight: .bold))
                                Text("\(points)")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(.white.opacity(0.5))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
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
