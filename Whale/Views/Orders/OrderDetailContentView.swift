//
//  OrderDetailContentView.swift
//  Whale
//
//  Shared order detail content view used by both:
//  - OrderDetailSheet (via SheetCoordinator)
//  - ManualCustomerEntrySheet (inline order detail)
//
//  Section cards moved to OrderDetailSections.swift

import SwiftUI

struct OrderDetailContentView: View {
    let order: Order
    var loyaltyTransactions: [LoyaltyTransaction] = []
    var showCustomerInfo: Bool = true
    var showActions: Bool = true
    var customerOverride: Customer? = nil

    // Effective customer - prefer order's customer, fallback to override
    var effectiveCustomer: OrderCustomer? {
        if let orderCustomer = order.customers {
            return orderCustomer
        }
        if let customer = customerOverride {
            return OrderCustomer(customer: customer)
        }
        return nil
    }

    var effectiveCustomerEmail: String? {
        effectiveCustomer?.email ?? customerOverride?.email
    }

    // MARK: - State for Actions

    @State var isPrintingLabels = false
    @State var isSendingReceipt = false
    @State var actionMessage: String?
    @State var showActionMessage = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                if showActions {
                    actionsCard
                }

                statusCard

                if showCustomerInfo, let customer = order.customers {
                    customerCard(customer)
                }

                if let locationName = orderLocationName {
                    locationCard(locationName)
                }

                if let employee = order.employee {
                    staffCard(employee)
                }

                if let items = order.items, !items.isEmpty {
                    itemsCard(items)
                }

                totalsCard

                if let fulfillments = order.fulfillments, !fulfillments.isEmpty {
                    fulfillmentCard(fulfillments)
                }

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

    // MARK: - Helpers

    func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(Design.Typography.caption1).fontWeight(.bold)
            .foregroundStyle(Design.Colors.Text.subtle)
            .tracking(1)
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 8)
    }

    func detailRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(Design.Typography.footnote)
                .foregroundStyle(Design.Colors.Text.disabled)
            Spacer()
            Text(value)
                .font(Design.Typography.footnote).fontWeight(.medium)
                .foregroundStyle(Design.Colors.Text.primary)
        }
    }

    var statusColor: Color {
        switch order.status {
        case .pending, .preparing: return Design.Colors.Semantic.warning
        case .ready, .readyToShip: return Design.Colors.Semantic.success
        case .completed, .delivered: return Design.Colors.Semantic.success
        case .shipped: return Design.Colors.Semantic.info
        case .cancelled: return Design.Colors.Semantic.error
        default: return Design.Colors.Text.disabled
        }
    }

    func fulfillmentStatusColor(_ status: FulfillmentStatus) -> Color {
        switch status {
        case .pending, .allocated: return Design.Colors.Semantic.warning
        case .picked, .packed: return Design.Colors.Semantic.info
        case .shipped: return Design.Colors.Semantic.info
        case .delivered: return Design.Colors.Semantic.success
        case .cancelled: return Design.Colors.Semantic.error
        }
    }

    var orderLocationName: String? {
        if let loc = order.location?.locationName {
            return loc
        }
        if let loc = order.primaryFulfillment?.locationName {
            return loc
        }
        if let loc = order.orderLocations?.first?.locationName {
            return loc
        }
        return nil
    }

    var orderLoyaltyTransactions: [LoyaltyTransaction] {
        loyaltyTransactions.filter { $0.referenceId == order.id.uuidString }
    }

    /// Points redeemed on this order (from loyalty transactions)
    var pointsRedeemedOnOrder: Int? {
        let redeemed = orderLoyaltyTransactions
            .filter { $0.transactionType != "earn" }
            .reduce(0) { $0 + $1.points }
        return redeemed > 0 ? redeemed : nil
    }

    /// Points earned on this order (from loyalty transactions)
    var pointsEarnedOnOrder: Int? {
        let earned = orderLoyaltyTransactions
            .filter { $0.transactionType == "earn" }
            .reduce(0) { $0 + $1.points }
        return earned > 0 ? earned : nil
    }

    func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: value as NSDecimalNumber) ?? "$0.00"
    }

    func formatDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .short
        return fmt.string(from: date)
    }

    func formatPaymentMethod(_ method: String) -> String {
        switch method.lowercased() {
        case "cash": return "Cash"
        case "card", "credit_card", "credit": return "Card"
        case "debit", "debit_card": return "Debit"
        case "check": return "Check"
        default: return method.capitalized
        }
    }

    /// Extract unit suffix from tier label (e.g., "g" from "3.5g", "oz" from "1/4 oz")
    func extractUnit(from tierLabel: String) -> String {
        tierLabel.replacingOccurrences(of: "[0-9./]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// Format quantity with unit (e.g., "7g" or "0.5oz")
    func formatQuantity(_ qty: Double, unit: String) -> String {
        if qty == qty.rounded() {
            return "\(Int(qty))\(unit)"
        } else {
            return String(format: "%.1f%@", qty, unit)
        }
    }
}
