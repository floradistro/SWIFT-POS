//
//  CustomersView.swift
//  Whale
//
//  Customer management view - optimized for 8000+ customers.
//  Uses UIKit UITableView for butter-smooth 60fps scrolling.
//

import SwiftUI
import UIKit
import Combine
import Supabase

struct CustomersView: View {
    @StateObject private var viewModel = CustomersViewModel()
    @EnvironmentObject private var session: SessionObserver
    @State private var selectedCustomer: Customer?
    @State private var showAddCustomer = false

    // Scroll-based header visibility
    @State private var showSearchAndFilters = true

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            // High-performance table view
            CustomerTableView(
                viewModel: viewModel,
                onSelect: { customer in
                    selectedCustomer = customer
                    Haptics.medium()
                },
                onScrollDirectionChange: { scrollingDown in
                    if scrollingDown && showSearchAndFilters {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            showSearchAndFilters = false
                        }
                    } else if !scrollingDown && !showSearchAndFilters {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            showSearchAndFilters = true
                        }
                    }
                },
                topPadding: showSearchAndFilters ? 140 : 80
            )
            .ignoresSafeArea(edges: .bottom)

            // Floating header
            VStack(spacing: 0) {
                headerView
                    .padding(.horizontal, 12)
                    .padding(.top, SafeArea.top + 10)
                    .padding(.bottom, 8)

                Spacer()
            }

            // Top fade
            VStack {
                LinearGradient(
                    colors: [.black, .black.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 80)
                .allowsHitTesting(false)

                Spacer()
            }
            .ignoresSafeArea()
        }
        .sheet(item: $selectedCustomer) { customer in
            CustomerDetailSheet(customer: customer, store: CustomerStore.shared)
        }
        .onAppear {
            if let storeId = session.store?.id {
                viewModel.setStore(storeId)
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                if showSearchAndFilters {
                    LiquidGlassSearchBar(
                        "Search customers...",
                        text: $viewModel.searchText
                    )
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)).combined(with: .scale(scale: 0.95)),
                        removal: .opacity.combined(with: .move(edge: .top)).combined(with: .scale(scale: 0.95))
                    ))
                }

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    LiquidGlassIconButton(icon: "plus") {
                        Haptics.light()
                        showAddCustomer = true
                    }
                }
            }

            if showSearchAndFilters {
                customerFilters
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)).combined(with: .scale(scale: 0.95, anchor: .top)),
                        removal: .opacity.combined(with: .move(edge: .top)).combined(with: .scale(scale: 0.95, anchor: .top))
                    ))
            }
        }
    }

    // MARK: - Filters

    private var customerFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                LiquidGlassPill(
                    "All",
                    count: viewModel.totalCount,
                    isSelected: viewModel.selectedLoyaltyTier == nil && !viewModel.showVerifiedOnly
                ) {
                    toggleFilter {
                        viewModel.selectedLoyaltyTier = nil
                        viewModel.showVerifiedOnly = false
                    }
                }

                LiquidGlassPill(
                    "Verified",
                    icon: "checkmark.seal.fill",
                    count: viewModel.verifiedCount,
                    isSelected: viewModel.showVerifiedOnly
                ) {
                    toggleFilter {
                        viewModel.showVerifiedOnly.toggle()
                    }
                }

                ForEach(viewModel.loyaltyTiers, id: \.self) { tier in
                    LiquidGlassPill(
                        tier,
                        count: viewModel.customerCounts[tier] ?? 0,
                        isSelected: viewModel.selectedLoyaltyTier == tier
                    ) {
                        toggleFilter {
                            viewModel.selectedLoyaltyTier = tier
                        }
                    }
                }

                Rectangle()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 1, height: 20)

                Menu {
                    ForEach(CustomersViewModel.SortOrder.allCases, id: \.self) { order in
                        Button {
                            viewModel.sortOrder = order
                        } label: {
                            HStack {
                                Text(order.rawValue)
                                if viewModel.sortOrder == order {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 12, weight: .medium))
                        Text(viewModel.sortOrder.rawValue)
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func toggleFilter(_ action: () -> Void) {
        action()
        Haptics.light()
    }
}

// MARK: - ViewModel (Optimized)

@MainActor
final class CustomersViewModel: ObservableObject {
    @Published var searchText = "" {
        didSet { debounceFilter() }
    }
    @Published var selectedLoyaltyTier: String? {
        didSet { applyFilters() }
    }
    @Published var showVerifiedOnly = false {
        didSet { applyFilters() }
    }
    @Published var sortOrder: SortOrder = .nameAsc {
        didSet { applyFilters() }
    }

    @Published private(set) var displayedCustomers: [Customer] = []
    @Published private(set) var isLoading = false

    private var allCustomers: [Customer] = []
    private var storeId: UUID?
    private var filterTask: Task<Void, Never>?

    // Cached counts
    var totalCount: Int { allCustomers.count }
    var verifiedCount: Int { allCustomers.filter { $0.idVerified == true }.count }
    var loyaltyTiers: [String] {
        Array(Set(allCustomers.compactMap { $0.loyaltyTier?.capitalized })).sorted()
    }
    var customerCounts: [String: Int] {
        var counts: [String: Int] = [:]
        for tier in loyaltyTiers {
            counts[tier] = allCustomers.filter { $0.loyaltyTier?.capitalized == tier }.count
        }
        return counts
    }

    enum SortOrder: String, CaseIterable {
        case nameAsc = "Name A-Z"
        case nameDesc = "Name Z-A"
        case spentDesc = "Highest Spent"
        case spentAsc = "Lowest Spent"
        case recentFirst = "Most Recent"
        case oldestFirst = "Oldest First"
    }

    func setStore(_ storeId: UUID) {
        guard self.storeId != storeId else { return }
        self.storeId = storeId
        Task { await loadCustomers() }
    }

    private func loadCustomers() async {
        guard let storeId = storeId else { return }

        isLoading = true

        do {
            var allFetched: [Customer] = []
            let pageSize = 1000
            var offset = 0
            var hasMore = true

            while hasMore {
                let response: [Customer] = try await supabase
                    .from("v_store_customers")
                    .select()
                    .eq("store_id", value: storeId.uuidString)
                    .eq("is_active", value: true)
                    .order("last_name", ascending: true)
                    .range(from: offset, to: offset + pageSize - 1)
                    .execute()
                    .value

                allFetched.append(contentsOf: response)

                if response.count < pageSize {
                    hasMore = false
                } else {
                    offset += pageSize
                }
            }

            // Deduplicate and filter invalid
            var seen = Set<UUID>()
            allCustomers = allFetched.filter { customer in
                guard customer.firstName != nil || customer.lastName != nil else { return false }
                guard customer.displayName != "Unknown Customer" && customer.displayName != "Unknown" else { return false }
                return seen.insert(customer.platformUserId).inserted
            }

            print("Loaded \(allCustomers.count) customers")
            applyFilters()
        } catch {
            print("Failed to load customers: \(error)")
        }

        isLoading = false
    }

    private func debounceFilter() {
        filterTask?.cancel()
        filterTask = Task {
            try? await Task.sleep(nanoseconds: 150_000_000) // 150ms debounce
            if !Task.isCancelled {
                applyFilters()
            }
        }
    }

    private func applyFilters() {
        var result = allCustomers

        // Search filter
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { customer in
                customer.displayName.lowercased().contains(query) ||
                customer.email?.lowercased().contains(query) == true ||
                customer.phone?.contains(query) == true
            }
        }

        // Loyalty tier filter
        if let tier = selectedLoyaltyTier {
            result = result.filter { $0.loyaltyTier?.lowercased() == tier.lowercased() }
        }

        // Verified filter
        if showVerifiedOnly {
            result = result.filter { $0.idVerified == true }
        }

        // Sort
        switch sortOrder {
        case .nameAsc:
            result.sort { ($0.lastName ?? "") < ($1.lastName ?? "") }
        case .nameDesc:
            result.sort { ($0.lastName ?? "") > ($1.lastName ?? "") }
        case .spentDesc:
            result.sort { ($0.totalSpent ?? 0) > ($1.totalSpent ?? 0) }
        case .spentAsc:
            result.sort { ($0.totalSpent ?? 0) < ($1.totalSpent ?? 0) }
        case .recentFirst:
            result.sort { $0.createdAt > $1.createdAt }
        case .oldestFirst:
            result.sort { $0.createdAt < $1.createdAt }
        }

        displayedCustomers = result
    }

    func refresh() async {
        await loadCustomers()
    }
}

// MARK: - UIKit Table View (60fps)

struct CustomerTableView: UIViewRepresentable {
    let viewModel: CustomersViewModel
    let onSelect: (Customer) -> Void
    let onScrollDirectionChange: (Bool) -> Void
    let topPadding: CGFloat

    func makeUIView(context: Context) -> UITableView {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.register(CustomerTableCell.self, forCellReuseIdentifier: "CustomerCell")
        tableView.rowHeight = 72
        tableView.estimatedRowHeight = 72
        tableView.showsVerticalScrollIndicator = false
        tableView.contentInset = UIEdgeInsets(top: topPadding, left: 0, bottom: 120, right: 0)
        return tableView
    }

    func updateUIView(_ tableView: UITableView, context: Context) {
        context.coordinator.customers = viewModel.displayedCustomers
        context.coordinator.onSelect = onSelect
        context.coordinator.onScrollDirectionChange = onScrollDirectionChange

        // Update content inset for header visibility changes
        if tableView.contentInset.top != topPadding {
            UIView.animate(withDuration: 0.3) {
                tableView.contentInset.top = topPadding
            }
        }

        tableView.reloadData()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(customers: viewModel.displayedCustomers, onSelect: onSelect, onScrollDirectionChange: onScrollDirectionChange)
    }

    class Coordinator: NSObject, UITableViewDataSource, UITableViewDelegate {
        var customers: [Customer]
        var onSelect: (Customer) -> Void
        var onScrollDirectionChange: (Bool) -> Void
        private var lastOffsetY: CGFloat = 0

        init(customers: [Customer], onSelect: @escaping (Customer) -> Void, onScrollDirectionChange: @escaping (Bool) -> Void) {
            self.customers = customers
            self.onSelect = onSelect
            self.onScrollDirectionChange = onScrollDirectionChange
        }

        func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
            customers.count
        }

        func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            let cell = tableView.dequeueReusableCell(withIdentifier: "CustomerCell", for: indexPath) as! CustomerTableCell
            let customer = customers[indexPath.row]
            cell.configure(with: customer, isLast: indexPath.row == customers.count - 1)
            return cell
        }

        func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
            tableView.deselectRow(at: indexPath, animated: true)
            let customer = customers[indexPath.row]
            onSelect(customer)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            let currentOffsetY = scrollView.contentOffset.y
            let delta = currentOffsetY - lastOffsetY

            if abs(delta) > 5 {
                let scrollingDown = delta > 0 && currentOffsetY > 50
                onScrollDirectionChange(scrollingDown)
            }

            lastOffsetY = currentOffsetY
        }
    }
}

// MARK: - UIKit Cell (Optimized)

final class CustomerTableCell: UITableViewCell {
    private let avatarView = UIView()
    private let initialsLabel = UILabel()
    private let nameLabel = UILabel()
    private let verifiedIcon = UIImageView()
    private let subtitleLabel = UILabel()
    private let spentLabel = UILabel()
    private let tierBadge = PaddedLabel()
    private let separatorLine = UIView()

    private var avatarColor: UIColor = .systemBlue

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        backgroundColor = .clear
        selectionStyle = .none

        // Avatar
        avatarView.layer.cornerRadius = 22
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(avatarView)

        initialsLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        initialsLabel.textAlignment = .center
        initialsLabel.translatesAutoresizingMaskIntoConstraints = false
        avatarView.addSubview(initialsLabel)

        // Name row
        nameLabel.font = .systemFont(ofSize: 17, weight: .medium)
        nameLabel.textColor = .white
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(nameLabel)

        verifiedIcon.image = UIImage(systemName: "checkmark.seal.fill")
        verifiedIcon.tintColor = .systemGreen
        verifiedIcon.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(verifiedIcon)

        // Subtitle
        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textColor = .white.withAlphaComponent(0.4)
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(subtitleLabel)

        // Spent
        spentLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        spentLabel.textColor = .white
        spentLabel.textAlignment = .right
        spentLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(spentLabel)

        // Tier badge
        tierBadge.font = .systemFont(ofSize: 11, weight: .medium)
        tierBadge.textAlignment = .center
        tierBadge.layer.cornerRadius = 10
        tierBadge.clipsToBounds = true
        tierBadge.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(tierBadge)

        // Separator
        separatorLine.backgroundColor = UIColor.white.withAlphaComponent(0.15)
        separatorLine.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(separatorLine)

        NSLayoutConstraint.activate([
            avatarView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            avatarView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 44),
            avatarView.heightAnchor.constraint(equalToConstant: 44),

            initialsLabel.centerXAnchor.constraint(equalTo: avatarView.centerXAnchor),
            initialsLabel.centerYAnchor.constraint(equalTo: avatarView.centerYAnchor),

            nameLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 14),
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),

            verifiedIcon.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 6),
            verifiedIcon.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
            verifiedIcon.widthAnchor.constraint(equalToConstant: 14),
            verifiedIcon.heightAnchor.constraint(equalToConstant: 14),

            subtitleLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 14),
            subtitleLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: spentLabel.leadingAnchor, constant: -12),

            spentLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            spentLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),

            tierBadge.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            tierBadge.topAnchor.constraint(equalTo: spentLabel.bottomAnchor, constant: 4),
            tierBadge.heightAnchor.constraint(equalToConstant: 20),

            separatorLine.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 74),
            separatorLine.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            separatorLine.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            separatorLine.heightAnchor.constraint(equalToConstant: 0.5)
        ])
    }

    func configure(with customer: Customer, isLast: Bool) {
        let colors: [UIColor] = [
            UIColor(red: 34/255, green: 197/255, blue: 94/255, alpha: 1),
            UIColor(red: 59/255, green: 130/255, blue: 246/255, alpha: 1),
            UIColor(red: 168/255, green: 85/255, blue: 247/255, alpha: 1),
            UIColor(red: 236/255, green: 72/255, blue: 153/255, alpha: 1),
            UIColor(red: 245/255, green: 158/255, blue: 11/255, alpha: 1),
        ]
        avatarColor = colors[abs(customer.id.hashValue) % colors.count]

        avatarView.backgroundColor = avatarColor.withAlphaComponent(0.15)
        initialsLabel.text = customer.initials
        initialsLabel.textColor = avatarColor

        nameLabel.text = customer.displayName
        verifiedIcon.isHidden = customer.idVerified != true

        // Subtitle
        var subtitle = ""
        if let phone = customer.formattedPhone {
            subtitle = phone
        } else if let email = customer.email {
            subtitle = email
        }
        if let orders = customer.totalOrders, orders > 0 {
            if !subtitle.isEmpty { subtitle += " • " }
            subtitle += "\(orders) orders"
        }
        subtitleLabel.text = subtitle

        spentLabel.text = customer.formattedTotalSpent

        // Tier badge
        if let tier = customer.loyaltyTier {
            tierBadge.isHidden = false
            tierBadge.text = "  \(tier.capitalized)  "
            let tierColor = tierUIColor(for: tier)
            tierBadge.textColor = tierColor
            tierBadge.backgroundColor = tierColor.withAlphaComponent(0.15)
        } else {
            tierBadge.isHidden = true
        }

        separatorLine.isHidden = isLast
    }

    private func tierUIColor(for tier: String) -> UIColor {
        switch tier.lowercased() {
        case "gold", "vip": return .systemYellow
        case "silver": return .systemGray
        case "bronze": return .systemOrange
        case "platinum": return .cyan
        default: return .white.withAlphaComponent(0.5)
        }
    }

    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        UIView.animate(withDuration: 0.1) {
            self.contentView.alpha = highlighted ? 0.6 : 1.0
        }
    }
}

// MARK: - Padded Label

final class PaddedLabel: UILabel {
    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + 16, height: size.height + 8)
    }
}
