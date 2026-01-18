//
//  CustomerDetailSheet.swift
//  Whale
//
//  Customer detail/CRM sheet - clean iOS native design.
//  Animated KPIs, order history, favorite products, staff interactions.
//

import SwiftUI

struct CustomerDetailSheet: View {
    let customer: Customer
    @ObservedObject var store: CustomerStore
    @Environment(\.dismiss) private var dismiss

    // Data loading states
    @State private var orderHistory: [Order] = []
    @State private var isLoadingOrders = false
    @State private var favoriteProducts: [FavoriteProduct] = []
    @State private var preferredLocation: PreferredLocation?
    @State private var staffInteractions: [StaffInteraction] = []

    // Animation states
    @State private var showStats = false
    @State private var showContent = false

    // Notes
    @State private var showAddNote = false
    @State private var newNoteText = ""

    private var currentCustomer: Customer {
        store.filteredCustomers.first(where: { $0.id == customer.id }) ?? customer
    }

    // Computed stats
    private var averageSpend: Decimal {
        guard let total = currentCustomer.totalSpent,
              let orders = currentCustomer.totalOrders, orders > 0 else { return 0 }
        return total / Decimal(orders)
    }

    private var memberSince: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter.string(from: currentCustomer.createdAt)
    }

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader
            sheetContent
        }
        .frame(maxWidth: 580)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task {
            // Stagger animations
            try? await Task.sleep(nanoseconds: 100_000_000)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                showStats = true
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                showContent = true
            }
            await loadAllData()
        }
        .sheet(isPresented: $showAddNote) {
            AddCustomerNoteSheet(
                customerName: currentCustomer.displayName,
                noteText: $newNoteText,
                onSave: { await saveNote() }
            )
        }
    }

    // MARK: - Header

    private var sheetHeader: some View {
        VStack(spacing: 16) {
            HStack(alignment: .center) {
                ModalCloseButton { dismiss() }

                Spacer()

                // Avatar and name
                VStack(spacing: 8) {
                    // Avatar
                    ZStack {
                        Circle()
                            .fill(avatarColor.opacity(0.15))
                            .frame(width: 64, height: 64)

                        Text(currentCustomer.initials)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(avatarColor)
                    }

                    VStack(spacing: 4) {
                        HStack(spacing: 6) {
                            Text(currentCustomer.displayName)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(.white)

                            if currentCustomer.idVerified == true {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.green)
                            }
                        }

                        Text("Customer since \(memberSince)")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }

                Spacer()

                // Tier badge
                if let tier = currentCustomer.loyaltyTier {
                    tierBadge(tier)
                } else {
                    Color.clear.frame(width: 44, height: 44)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var avatarColor: Color {
        let colors: [Color] = [
            Color(red: 34/255, green: 197/255, blue: 94/255),
            Color(red: 59/255, green: 130/255, blue: 246/255),
            Color(red: 168/255, green: 85/255, blue: 247/255),
            Color(red: 236/255, green: 72/255, blue: 153/255),
            Color(red: 245/255, green: 158/255, blue: 11/255),
        ]
        return colors[abs(currentCustomer.id.hashValue) % colors.count]
    }

    private func tierBadge(_ tier: String) -> some View {
        Text(tier.uppercased())
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(tierColor(for: tier))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(tierColor(for: tier).opacity(0.15), in: Capsule())
    }

    private func tierColor(for tier: String) -> Color {
        switch tier.lowercased() {
        case "gold", "vip": return .yellow
        case "silver": return .gray
        case "bronze": return .orange
        case "platinum": return .cyan
        default: return .white.opacity(0.6)
        }
    }

    // MARK: - Content

    private var sheetContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                // Animated KPIs
                if showStats {
                    kpiSection
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.9).combined(with: .opacity),
                            removal: .opacity
                        ))
                }

                if showContent {
                    // Contact info
                    contactSection

                    // Preferred location
                    if preferredLocation != nil {
                        preferredLocationSection
                    }

                    // Favorite products
                    if !favoriteProducts.isEmpty {
                        favoriteProductsSection
                    }

                    // Order history
                    orderHistorySection

                    // Staff interactions
                    if !staffInteractions.isEmpty {
                        staffInteractionsSection
                    }

                    // Add note button
                    addNoteButton
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: - KPI Section (Animated)

    private var kpiSection: some View {
        VStack(spacing: 12) {
            // Top row - main KPIs
            HStack(spacing: 12) {
                AnimatedKPICard(
                    value: currentCustomer.totalSpent ?? 0,
                    label: "Lifetime Value",
                    format: .currency,
                    delay: 0
                )

                AnimatedKPICard(
                    value: Decimal(currentCustomer.totalOrders ?? 0),
                    label: "Total Orders",
                    format: .number,
                    delay: 0.1
                )
            }

            // Bottom row - secondary KPIs
            HStack(spacing: 12) {
                AnimatedKPICard(
                    value: averageSpend,
                    label: "Avg. Order",
                    format: .currency,
                    delay: 0.2
                )

                AnimatedKPICard(
                    value: Decimal(currentCustomer.loyaltyPoints ?? 0),
                    label: "Points",
                    format: .number,
                    delay: 0.3
                )
            }
        }
    }

    // MARK: - Contact Section

    private var contactSection: some View {
        VStack(spacing: 0) {
            if let phone = currentCustomer.formattedPhone ?? currentCustomer.phone {
                contactRow(label: "Phone", value: phone) {
                    if let url = URL(string: "tel:\(phone.filter { $0.isNumber })") {
                        UIApplication.shared.open(url)
                    }
                }
            }

            if let email = currentCustomer.email {
                contactRow(label: "Email", value: email) {
                    if let url = URL(string: "mailto:\(email)") {
                        UIApplication.shared.open(url)
                    }
                }
            }

            if let dob = currentCustomer.dateOfBirth {
                let ageText = currentCustomer.age.map { "\(dob) (\($0) yrs)" } ?? dob
                contactRow(label: "Birthday", value: ageText, action: nil)
            }

            if let address = currentCustomer.formattedAddress {
                contactRow(label: "Address", value: address, action: nil)
            }
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }

    private func contactRow(label: String, value: String, action: (() -> Void)?) -> some View {
        Group {
            if let action = action {
                Button(action: action) {
                    contactRowContent(label: label, value: value, hasAction: true)
                }
                .buttonStyle(.plain)
            } else {
                contactRowContent(label: label, value: value, hasAction: false)
            }
        }
    }

    private func contactRowContent(label: String, value: String, hasAction: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
                Text(value)
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
            }

            Spacer()

            if hasAction {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Preferred Location Section

    private var preferredLocationSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("PREFERRED LOCATION")

            if let location = preferredLocation {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(location.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)

                        Text("\(location.visitCount) visits • \(location.percentage)% of orders")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.5))
                    }

                    Spacer()

                    // Visit percentage ring
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.1), lineWidth: 3)
                            .frame(width: 44, height: 44)

                        Circle()
                            .trim(from: 0, to: CGFloat(location.percentage) / 100)
                            .stroke(Color.green, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .frame(width: 44, height: 44)
                            .rotationEffect(.degrees(-90))

                        Text("\(location.percentage)%")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .padding(14)
            }
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }

    // MARK: - Favorite Products Section

    private var favoriteProductsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("FAVORITE PRODUCTS")

            ForEach(favoriteProducts.prefix(5)) { product in
                HStack(spacing: 12) {
                    // Product image placeholder
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Text(String(product.name.prefix(1)).uppercased())
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.4))
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(product.name)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Text("Purchased \(product.purchaseCount)×")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.4))
                    }

                    Spacer()

                    Text(formatCurrency(product.totalSpent))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }

    // MARK: - Order History Section

    private var orderHistorySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                sectionHeader("ORDER HISTORY")
                Spacer()
                if isLoadingOrders {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(.white.opacity(0.5))
                        .padding(.trailing, 14)
                        .padding(.top, 14)
                }
            }

            if orderHistory.isEmpty && !isLoadingOrders {
                Text("No orders yet")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(14)
            } else {
                ForEach(orderHistory.prefix(10)) { order in
                    orderRow(order)
                }
            }
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }

    private func orderRow(_ order: Order) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Order info
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("#\(order.shortOrderNumber)")
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white)

                        // Status indicator
                        Circle()
                            .fill(statusColor(for: order.status))
                            .frame(width: 6, height: 6)

                        Text(order.status.displayName)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.5))
                    }

                    HStack(spacing: 8) {
                        Text(order.formattedDate)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.4))

                        if let items = order.items {
                            Text("•")
                                .font(.system(size: 8))
                                .foregroundStyle(.white.opacity(0.2))

                            Text("\(items.count) item\(items.count == 1 ? "" : "s")")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }
                }

                Spacer()

                // Total
                VStack(alignment: .trailing, spacing: 2) {
                    Text(order.formattedTotal)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)

                    Text(order.orderType.displayName)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }

    private func statusColor(for status: OrderStatus) -> Color {
        switch status {
        case .pending, .preparing: return .orange
        case .ready, .readyToShip: return .green
        case .completed, .delivered, .shipped: return .white.opacity(0.4)
        case .cancelled: return .red.opacity(0.7)
        default: return .white.opacity(0.4)
        }
    }

    // MARK: - Staff Interactions Section

    private var staffInteractionsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("STAFF INTERACTIONS")

            ForEach(staffInteractions.prefix(5)) { interaction in
                HStack(spacing: 12) {
                    // Staff avatar
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 36, height: 36)
                        .overlay(
                            Text(interaction.staffInitials)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.5))
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(interaction.staffName)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white)

                        Text("\(interaction.interactionCount) orders together")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.4))
                    }

                    Spacer()

                    Text(interaction.formattedLastSeen)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.3))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }

    // MARK: - Add Note Button

    private var addNoteButton: some View {
        Button {
            Haptics.medium()
            showAddNote = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                Text("Add Note")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(0.7))
            .frame(maxWidth: .infinity)
            .frame(height: 48)
        }
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white.opacity(0.4))
            .tracking(0.5)
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Helpers

    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: value as NSDecimalNumber) ?? "$0"
    }

    // MARK: - Data Loading

    private func loadAllData() async {
        isLoadingOrders = true

        async let orders = CustomerService.fetchOrderHistory(for: currentCustomer.platformUserId, limit: 20)
        async let favorites = loadFavoriteProducts()
        async let location = loadPreferredLocation()
        async let staff = loadStaffInteractions()

        orderHistory = await orders
        favoriteProducts = await favorites
        preferredLocation = await location
        staffInteractions = await staff

        isLoadingOrders = false
    }

    private func loadFavoriteProducts() async -> [FavoriteProduct] {
        // Aggregate from order history
        guard !orderHistory.isEmpty else {
            // Wait for orders first, then calculate
            let orders = await CustomerService.fetchOrderHistory(for: currentCustomer.platformUserId, limit: 50)
            return aggregateFavorites(from: orders)
        }
        return aggregateFavorites(from: orderHistory)
    }

    private func aggregateFavorites(from orders: [Order]) -> [FavoriteProduct] {
        var productStats: [String: (name: String, count: Int, total: Decimal)] = [:]

        for order in orders {
            guard let items = order.items else { continue }
            for item in items {
                let key = item.productId.uuidString
                let existing = productStats[key] ?? (name: item.productName, count: 0, total: 0)
                productStats[key] = (
                    name: item.productName,
                    count: existing.count + item.quantity,
                    total: existing.total + item.lineTotal
                )
            }
        }

        return productStats
            .map { FavoriteProduct(id: UUID(uuidString: $0.key) ?? UUID(), name: $0.value.name, purchaseCount: $0.value.count, totalSpent: $0.value.total) }
            .sorted { $0.purchaseCount > $1.purchaseCount }
    }

    private func loadPreferredLocation() async -> PreferredLocation? {
        // Aggregate location visits from orders
        let orders = orderHistory.isEmpty
            ? await CustomerService.fetchOrderHistory(for: currentCustomer.platformUserId, limit: 50)
            : orderHistory

        var locationCounts: [String: (name: String, count: Int)] = [:]

        for order in orders {
            if let locationName = order.pickupLocationName {
                let existing = locationCounts[locationName] ?? (name: locationName, count: 0)
                locationCounts[locationName] = (name: locationName, count: existing.count + 1)
            }
        }

        guard let top = locationCounts.max(by: { $0.value.count < $1.value.count }) else { return nil }
        let totalOrders = orders.count
        let percentage = totalOrders > 0 ? (top.value.count * 100) / totalOrders : 0

        return PreferredLocation(name: top.value.name, visitCount: top.value.count, percentage: percentage)
    }

    private func loadStaffInteractions() async -> [StaffInteraction] {
        // This would come from order.staff_id relationships
        // For now, return empty - would need to query orders with staff info
        return []
    }

    private func saveNote() async {
        guard !newNoteText.isEmpty else { return }
        // Save note to customer_touches table
        newNoteText = ""
        showAddNote = false
        Haptics.success()
    }
}

// MARK: - Animated KPI Card

private struct AnimatedKPICard: View {
    let value: Decimal
    let label: String
    let format: KPIFormat
    let delay: Double

    @State private var animatedValue: Double = 0
    @State private var hasAnimated = false

    enum KPIFormat {
        case currency
        case number
    }

    private var displayValue: String {
        switch format {
        case .currency:
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.currencyCode = "USD"
            formatter.maximumFractionDigits = 0
            return formatter.string(from: NSDecimalNumber(decimal: Decimal(animatedValue))) ?? "$0"
        case .number:
            return NumberFormatter.localizedString(from: NSNumber(value: Int(animatedValue)), number: .decimal)
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            Text(displayValue)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())

            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
        .onAppear {
            guard !hasAnimated else { return }
            hasAnimated = true

            let targetValue = NSDecimalNumber(decimal: value).doubleValue

            // Animate with delay
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
                    animatedValue = targetValue
                }
            }
        }
    }
}

// MARK: - Supporting Models

struct FavoriteProduct: Identifiable {
    let id: UUID
    let name: String
    let purchaseCount: Int
    let totalSpent: Decimal
}

struct PreferredLocation {
    let name: String
    let visitCount: Int
    let percentage: Int
}

struct StaffInteraction: Identifiable {
    let id: UUID
    let staffId: UUID
    let staffName: String
    let interactionCount: Int
    let lastInteraction: Date

    var staffInitials: String {
        let parts = staffName.split(separator: " ")
        let first = parts.first?.first.map(String.init) ?? ""
        let last = parts.dropFirst().first?.first.map(String.init) ?? ""
        return (first + last).uppercased()
    }

    var formattedLastSeen: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: lastInteraction, relativeTo: Date())
    }
}

// MARK: - Add Note Sheet

struct AddCustomerNoteSheet: View {
    let customerName: String
    @Binding var noteText: String
    let onSave: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .center) {
                ModalCloseButton { dismiss() }

                Spacer()

                VStack(spacing: 4) {
                    Text("ADD NOTE")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.4))
                        .tracking(0.5)

                    Text(customerName)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                }

                Spacer()

                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 16)

            // Text field
            TextEditor(text: $noteText)
                .font(.system(size: 16))
                .foregroundStyle(.white)
                .scrollContentBackground(.hidden)
                .padding(16)
                .frame(maxHeight: 200)
                .glassEffect(.regular, in: .rect(cornerRadius: 14))
                .padding(.horizontal, 20)
                .focused($isTextFieldFocused)

            Spacer()

            // Save button
            Button {
                Haptics.medium()
                isSaving = true
                Task {
                    await onSave()
                    isSaving = false
                    dismiss()
                }
            } label: {
                HStack(spacing: 10) {
                    if isSaving {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(.white)
                    } else {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    Text(isSaving ? "Saving..." : "Save Note")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
            }
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
            .disabled(noteText.isEmpty || isSaving)
            .opacity(noteText.isEmpty ? 0.5 : 1)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onAppear {
            isTextFieldFocused = true
        }
    }
}
