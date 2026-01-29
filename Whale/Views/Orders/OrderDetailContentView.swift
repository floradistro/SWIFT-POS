//
//  OrderDetailContentView.swift
//  Whale
//
//  Shared order detail content view used by both:
//  - OrderDetailSheet (via SheetCoordinator)
//  - ManualCustomerEntrySheet (inline order detail)
//

import SwiftUI

struct OrderDetailContentView: View {
    let order: Order
    var loyaltyTransactions: [LoyaltyTransaction] = []
    var showCustomerInfo: Bool = true
    var showActions: Bool = true
    var customerOverride: Customer? = nil  // Use when order.customers might be nil but we have customer from context

    // Effective customer - prefer order's customer, fallback to override
    private var effectiveCustomer: OrderCustomer? {
        if let orderCustomer = order.customers {
            return orderCustomer
        }
        // Convert Customer to OrderCustomer if we have an override
        if let customer = customerOverride {
            return OrderCustomer(customer: customer)
        }
        return nil
    }

    private var effectiveCustomerEmail: String? {
        effectiveCustomer?.email ?? customerOverride?.email
    }

    // MARK: - State for Actions

    @State private var isPrintingLabels = false
    @State private var isSendingReceipt = false
    @State private var actionMessage: String?
    @State private var showActionMessage = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                // Action Buttons
                if showActions {
                    actionsCard
                }

                // Status & Channel Card
                statusCard

                // Customer Info
                if showCustomerInfo, let customer = order.customers {
                    customerCard(customer)
                }

                // Location Info
                if let locationName = orderLocationName {
                    locationCard(locationName)
                }

                // Staff Info
                if let employee = order.employee {
                    staffCard(employee)
                }

                // Line Items
                if let items = order.items, !items.isEmpty {
                    itemsCard(items)
                }

                // Totals (includes loyalty points earned/redeemed as line items)
                totalsCard

                // Fulfillment
                if let fulfillments = order.fulfillments, !fulfillments.isEmpty {
                    fulfillmentCard(fulfillments)
                }

                // Notes
                if let notes = order.staffNotes, !notes.isEmpty {
                    notesCard(notes)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 34)
        }
        .scrollBounceBehavior(.basedOnSize)
        .overlay(alignment: .top) {
            if showActionMessage, let message = actionMessage {
                actionMessageBanner(message)
            }
        }
    }

    // MARK: - Actions Card

    private var actionsCard: some View {
        let hasCustomerEmail = effectiveCustomerEmail != nil
        let hasItems = order.items?.isEmpty == false

        return HStack(spacing: 12) {
            // Email Receipt - always show, disabled if no email
            actionButton(
                icon: "envelope.fill",
                label: hasCustomerEmail ? "Email Receipt" : "No Email",
                isLoading: isSendingReceipt,
                disabled: !hasCustomerEmail
            ) {
                sendReceipt()
            }

            // Print Labels
            if hasItems {
                actionButton(
                    icon: "printer.fill",
                    label: "Print Labels",
                    isLoading: isPrintingLabels,
                    disabled: false
                ) {
                    printLabels()
                }
            }
        }
        .padding(.horizontal, 4)
        .onAppear {
            print("📧 actionsCard - customer: \(effectiveCustomer?.fullName ?? "nil"), email: \(effectiveCustomerEmail ?? "nil")")
        }
    }

    private func actionButton(icon: String, label: String, isLoading: Bool, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(label)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(disabled ? .white.opacity(0.4) : .white)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .glassCard()
        }
        .buttonStyle(.plain)
        .disabled(isLoading || disabled)
        .opacity(isLoading ? 0.7 : (disabled ? 0.5 : 1))
    }

    private func actionMessageBanner(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: .capsule)
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    withAnimation { showActionMessage = false }
                }
            }
    }

    // MARK: - Actions

    private func sendReceipt() {
        guard let email = effectiveCustomerEmail else { return }

        print("📧 OrderDetailContentView.sendReceipt()")
        print("📧 order.id: \(order.id)")
        print("📧 order.orderNumber: \(order.orderNumber)")
        print("📧 order.totalAmount: \(order.totalAmount)")
        print("📧 order.items?.count: \(order.items?.count ?? 0)")
        print("📧 email: \(email)")

        isSendingReceipt = true

        Task {
            do {
                try await EmailReceiptService.sendReceipt(for: order, to: email)
                await MainActor.run {
                    isSendingReceipt = false
                    actionMessage = "Receipt sent to \(email)"
                    withAnimation { showActionMessage = true }
                    Haptics.success()
                }
            } catch {
                await MainActor.run {
                    isSendingReceipt = false
                    actionMessage = "Failed to send receipt"
                    withAnimation { showActionMessage = true }
                    Haptics.error()
                }
            }
        }
    }

    private func printLabels() {
        isPrintingLabels = true

        Task {
            let success = await LabelPrintService.printOrderLabels([order])
            await MainActor.run {
                isPrintingLabels = false
                actionMessage = success ? "Labels sent to printer" : "Print failed - check printer"
                withAnimation { showActionMessage = true }
                if success {
                    Haptics.success()
                } else {
                    Haptics.error()
                }
            }
        }
    }

    // MARK: - Status Card

    private var statusCard: some View {
        VStack(spacing: 12) {
            // Status row
            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 10, height: 10)
                    Text(order.status.displayName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: order.channel.icon)
                        .font(.system(size: 12))
                    Text(order.channel.displayName)
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(.white.opacity(0.5))
            }

            Divider().overlay(Color.white.opacity(0.1))

            // Details
            VStack(spacing: 8) {
                detailRow("Order", value: "#\(order.shortOrderNumber)")
                detailRow("Created", value: order.formattedDate)
                if let completedAt = order.completedAt {
                    detailRow("Completed", value: formatDate(completedAt))
                }
                detailRow("Payment", value: order.paymentStatus.displayName)
                if let method = order.paymentMethod {
                    detailRow("Method", value: formatPaymentMethod(method))
                }
            }
        }
        .padding(14)
        .glassCard()
    }

    // MARK: - Customer Card

    private func customerCard(_ customer: OrderCustomer) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("CUSTOMER")

            VStack(spacing: 8) {
                if let name = customer.fullName {
                    HStack {
                        Image(systemName: "person.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.4))
                        Text(name)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white)
                        Spacer()
                    }
                }
                if let email = customer.email {
                    HStack {
                        Image(systemName: "envelope.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.4))
                        Text(email)
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.7))
                        Spacer()
                    }
                }
                if let phone = customer.phone {
                    HStack {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.4))
                        Text(phone)
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.7))
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .glassCard()
    }

    // MARK: - Location Card

    private func locationCard(_ locationName: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("LOCATION")

            HStack(spacing: 10) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.5))
                Text(locationName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .glassCard()
    }

    // MARK: - Staff Card

    private func staffCard(_ employee: OrderEmployee) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("CREATED BY")

            HStack(spacing: 12) {
                // Staff avatar
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 40, height: 40)
                    Text(employee.initials)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }

                VStack(alignment: .leading, spacing: 2) {
                    if let name = employee.fullName {
                        Text(name)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    if let email = employee.email {
                        Text(email)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }

                Spacer()

                Image(systemName: "person.badge.clock")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .glassCard()
    }

    // MARK: - Items Card

    private func itemsCard(_ items: [OrderItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("ITEMS (\(items.count))")

            ForEach(items) { item in
                HStack(spacing: 10) {
                    Text("\(item.quantity)×")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(width: 24, alignment: .leading)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.productName)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        // Tier/pricing info: show tier label, total qty, and variant
                        if item.tierLabel != nil || item.variantName != nil || (item.discountAmount ?? 0) > 0 {
                            HStack(spacing: 4) {
                                // Show tier with total quantity (e.g., "3.5g × 2 = 7g")
                                if let tierLabel = item.tierLabel {
                                    if let tierQty = item.tierQuantity, item.quantity > 1 {
                                        // Show full breakdown: "3.5g × 2 = 7g"
                                        let totalQty = tierQty * Double(item.quantity)
                                        let unit = extractUnit(from: tierLabel)
                                        let formattedTotal = formatQuantity(totalQty, unit: unit)
                                        Text("\(tierLabel) × \(item.quantity) = \(formattedTotal)")
                                    } else {
                                        // Single unit, just show tier
                                        Text(tierLabel)
                                    }
                                }
                                if let variantName = item.variantName {
                                    if item.tierLabel != nil {
                                        Text("·")
                                    }
                                    Text(variantName)
                                }
                                if let discount = item.discountAmount, discount > 0 {
                                    Text("·")
                                    Text("-\(formatCurrency(discount))")
                                        .foregroundStyle(.green)
                                }
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.4))
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(formatCurrency(item.lineTotal))
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))

                        // Show original price if discounted
                        if let discount = item.discountAmount, discount > 0 {
                            Text(formatCurrency(item.originalLineTotal))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.3))
                                .strikethrough()
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                if item.id != items.last?.id {
                    Divider()
                        .overlay(Color.white.opacity(0.05))
                        .padding(.horizontal, 14)
                }
            }
        }
        .glassCard()
    }

    /// Extract unit suffix from tier label (e.g., "g" from "3.5g", "oz" from "1/4 oz")
    private func extractUnit(from tierLabel: String) -> String {
        tierLabel.replacingOccurrences(of: "[0-9./]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// Format quantity with unit (e.g., "7g" or "0.5oz")
    private func formatQuantity(_ qty: Double, unit: String) -> String {
        if qty == qty.rounded() {
            return "\(Int(qty))\(unit)"
        } else {
            return String(format: "%.1f%@", qty, unit)
        }
    }

    // MARK: - Totals Card

    private var totalsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("TOTALS")

            VStack(spacing: 8) {
                detailRow("Subtotal", value: formatCurrency(order.subtotal))

                if order.discountAmount > 0 {
                    HStack {
                        HStack(spacing: 6) {
                            Image(systemName: "tag.fill")
                                .font(.system(size: 10))
                            Text("Discount")
                        }
                        .font(.system(size: 14))
                        .foregroundStyle(.green)
                        Spacer()
                        Text("-\(formatCurrency(order.discountAmount))")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.green)
                    }
                }

                // Points redeemed (shown as line item)
                if let pointsRedeemed = pointsRedeemedOnOrder, pointsRedeemed > 0 {
                    HStack {
                        HStack(spacing: 6) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10))
                            Text("Points Redeemed")
                        }
                        .font(.system(size: 14))
                        .foregroundStyle(.orange)
                        Spacer()
                        Text("-\(pointsRedeemed) pts")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.orange)
                    }
                }

                if order.taxAmount > 0 {
                    detailRow("Tax", value: formatCurrency(order.taxAmount))
                }

                Divider().overlay(Color.white.opacity(0.1))

                HStack {
                    Text("Total")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text(order.formattedTotal)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }

                // Points earned (shown below total)
                if let pointsEarned = pointsEarnedOnOrder, pointsEarned > 0 {
                    HStack {
                        HStack(spacing: 6) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10))
                            Text("Points Earned")
                        }
                        .font(.system(size: 13))
                        .foregroundStyle(.yellow.opacity(0.8))
                        Spacer()
                        Text("+\(pointsEarned) pts")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.yellow.opacity(0.8))
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .glassCard()
    }

    /// Points redeemed on this order (from loyalty transactions)
    private var pointsRedeemedOnOrder: Int? {
        let redeemed = orderLoyaltyTransactions
            .filter { $0.transactionType != "earn" }
            .reduce(0) { $0 + $1.points }
        return redeemed > 0 ? redeemed : nil
    }

    /// Points earned on this order (from loyalty transactions)
    private var pointsEarnedOnOrder: Int? {
        let earned = orderLoyaltyTransactions
            .filter { $0.transactionType == "earn" }
            .reduce(0) { $0 + $1.points }
        return earned > 0 ? earned : nil
    }

    // MARK: - Fulfillment Card

    private func fulfillmentCard(_ fulfillments: [OrderFulfillment]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("FULFILLMENT")

            ForEach(fulfillments) { f in
                VStack(spacing: 8) {
                    HStack {
                        HStack(spacing: 6) {
                            Image(systemName: f.type.icon)
                                .font(.system(size: 13))
                            Text(f.type.displayName)
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundStyle(.white)

                        Spacer()

                        Text(f.status.displayName)
                            .font(.system(size: 13))
                            .foregroundStyle(fulfillmentStatusColor(f.status))
                    }

                    if let loc = f.locationName {
                        HStack {
                            Image(systemName: "building.2")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.3))
                            Text(loc)
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.5))
                            Spacer()
                        }
                    }

                    if let carrier = f.carrier {
                        HStack {
                            Image(systemName: "shippingbox")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.3))
                            Text(carrier)
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.5))
                            Spacer()
                        }
                    }

                    if let tracking = f.trackingNumber {
                        HStack {
                            Image(systemName: "barcode")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.3))
                            Text(tracking)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.5))
                            Spacer()
                            if let url = f.trackingUrl, let trackingURL = URL(string: url) {
                                Link(destination: trackingURL) {
                                    Image(systemName: "arrow.up.right.square")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }

                    if let shippedAt = f.shippedAt {
                        HStack {
                            Text("Shipped")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.3))
                            Spacer()
                            Text(formatDate(shippedAt))
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }

                    if let deliveredAt = f.deliveredAt {
                        HStack {
                            Text("Delivered")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.3))
                            Spacer()
                            Text(formatDate(deliveredAt))
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                if f.id != fulfillments.last?.id {
                    Divider()
                        .overlay(Color.white.opacity(0.05))
                        .padding(.horizontal, 14)
                }
            }
        }
        .glassCard()
    }

    // MARK: - Notes Card

    private func notesCard(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("STAFF NOTES")

            Text(notes)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
        }
        .glassCard()
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white.opacity(0.4))
            .tracking(1)
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 8)
    }

    private func detailRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.5))
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
        }
    }

    private var statusColor: Color {
        switch order.status {
        case .pending, .preparing: return .orange
        case .ready, .readyToShip: return .green
        case .completed, .delivered, .shipped: return .white.opacity(0.6)
        case .cancelled: return .red
        default: return .white.opacity(0.5)
        }
    }

    private func fulfillmentStatusColor(_ status: FulfillmentStatus) -> Color {
        switch status {
        case .pending, .allocated: return .orange
        case .picked, .packed: return .blue
        case .shipped: return .cyan
        case .delivered: return .green
        case .cancelled: return .red
        }
    }

    private var orderLocationName: String? {
        // Try direct location join first (orders.location_id)
        if let loc = order.location?.locationName {
            return loc
        }
        // Try fulfillment location
        if let loc = order.primaryFulfillment?.locationName {
            return loc
        }
        // Try order locations
        if let loc = order.orderLocations?.first?.locationName {
            return loc
        }
        return nil
    }

    private var orderLoyaltyTransactions: [LoyaltyTransaction] {
        loyaltyTransactions.filter { $0.referenceId == order.id.uuidString }
    }

    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: value as NSDecimalNumber) ?? "$0.00"
    }

    private func formatDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .short
        return fmt.string(from: date)
    }

    private func formatPaymentMethod(_ method: String) -> String {
        switch method.lowercased() {
        case "cash": return "Cash"
        case "card", "credit_card", "credit": return "Card"
        case "debit", "debit_card": return "Debit"
        case "check": return "Check"
        default: return method.capitalized
        }
    }
}

// MARK: - Glass Card Modifier

private extension View {
    func glassCard() -> some View {
        self.glassEffect(.regular, in: .rect(cornerRadius: 14))
    }
}
