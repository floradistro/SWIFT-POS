//
//  OrderDetailSections.swift
//  Whale
//
//  Section card views for OrderDetailContentView:
//  status, customer, location, staff, items, totals,
//  fulfillment, and notes cards.
//

import SwiftUI
import os.log

// MARK: - Section Cards

extension OrderDetailContentView {

    // MARK: - Actions Card

    var actionsCard: some View {
        let hasCustomerEmail = effectiveCustomerEmail != nil
        let hasItems = order.items?.isEmpty == false

        return HStack(spacing: 12) {
            actionButton(
                icon: "envelope.fill",
                label: hasCustomerEmail ? "Email Receipt" : "No Email",
                isLoading: isSendingReceipt,
                disabled: !hasCustomerEmail
            ) {
                sendReceipt()
            }

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
            Log.email.debug("actionsCard - customer: \(effectiveCustomer?.fullName ?? "nil"), email: \(effectiveCustomerEmail ?? "nil")")
        }
    }

    func actionButton(icon: String, label: String, isLoading: Bool, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: icon)
                        .font(Design.Typography.footnote).fontWeight(.semibold)
                }
                Text(label)
                    .font(Design.Typography.footnote).fontWeight(.semibold)
            }
            .foregroundStyle(disabled ? .white.opacity(0.4) : .white)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .glassCard()
        }
        .buttonStyle(.plain)
        .disabled(isLoading || disabled)
        .opacity(isLoading ? 0.7 : (disabled ? 0.5 : 1))
        .accessibilityLabel(isLoading ? "\(label), loading" : label)
    }

    func actionMessageBanner(_ message: String) -> some View {
        Text(message)
            .font(Design.Typography.footnote).fontWeight(.medium)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: .capsule)
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
            .onAppear {
                Task { @MainActor in try? await Task.sleep(for: .seconds(2.5));
                    withAnimation { showActionMessage = false }
                }
            }
    }

    // MARK: - Actions

    func sendReceipt() {
        guard let email = effectiveCustomerEmail else { return }

        Log.email.debug("OrderDetailContentView.sendReceipt()")
        Log.email.debug("order.id: \(order.id)")
        Log.email.debug("order.orderNumber: \(order.orderNumber)")
        Log.email.debug("order.totalAmount: \(order.totalAmount)")
        Log.email.debug("order.items?.count: \(order.items?.count ?? 0)")
        Log.email.debug("email: \(email)")

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

    func printLabels() {
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

    var statusCard: some View {
        VStack(spacing: 12) {
            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 10, height: 10)
                    Text(order.status.displayName)
                        .font(Design.Typography.callout).fontWeight(.semibold)
                        .foregroundStyle(.white)
                }

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: order.channel.icon)
                        .font(Design.Typography.caption1)
                    Text(order.channel.displayName)
                        .font(Design.Typography.footnote).fontWeight(.medium)
                }
                .foregroundStyle(.white.opacity(0.5))
            }

            Divider().overlay(Color.white.opacity(0.1))

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

    func customerCard(_ customer: OrderCustomer) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("CUSTOMER")

            VStack(spacing: 8) {
                if let name = customer.fullName {
                    HStack {
                        Image(systemName: "person.fill")
                            .font(Design.Typography.caption1)
                            .foregroundStyle(.white.opacity(0.4))
                        Text(name)
                            .font(Design.Typography.footnote).fontWeight(.medium)
                            .foregroundStyle(.white)
                        Spacer()
                    }
                }
                if let email = customer.email {
                    HStack {
                        Image(systemName: "envelope.fill")
                            .font(Design.Typography.caption1)
                            .foregroundStyle(.white.opacity(0.4))
                        Text(email)
                            .font(Design.Typography.footnote)
                            .foregroundStyle(.white.opacity(0.7))
                        Spacer()
                    }
                }
                if let phone = customer.phone {
                    HStack {
                        Image(systemName: "phone.fill")
                            .font(Design.Typography.caption1)
                            .foregroundStyle(.white.opacity(0.4))
                        Text(phone)
                            .font(Design.Typography.footnote)
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

    func locationCard(_ locationName: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("LOCATION")

            HStack(spacing: 10) {
                Image(systemName: "mappin.circle.fill")
                    .font(Design.Typography.headline)
                    .foregroundStyle(.white.opacity(0.5))
                Text(locationName)
                    .font(Design.Typography.footnote).fontWeight(.medium)
                    .foregroundStyle(.white)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .glassCard()
    }

    // MARK: - Staff Card

    func staffCard(_ employee: OrderEmployee) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("CREATED BY")

            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 40, height: 40)
                    Text(employee.initials)
                        .font(Design.Typography.footnote).fontWeight(.semibold)
                        .foregroundStyle(.white.opacity(0.6))
                }

                VStack(alignment: .leading, spacing: 2) {
                    if let name = employee.fullName {
                        Text(name)
                            .font(Design.Typography.footnote).fontWeight(.medium)
                            .foregroundStyle(.white)
                    }
                    if let email = employee.email {
                        Text(email)
                            .font(Design.Typography.caption1)
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }

                Spacer()

                Image(systemName: "person.badge.clock")
                    .font(Design.Typography.callout)
                    .foregroundStyle(.white.opacity(0.3))
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .glassCard()
    }

    // MARK: - Items Card

    func itemsCard(_ items: [OrderItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("ITEMS (\(items.count))")

            ForEach(items) { item in
                HStack(spacing: 10) {
                    Text("\(item.quantity)×")
                        .font(Design.Typography.caption1Rounded).fontWeight(.bold)
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(width: 24, alignment: .leading)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.productName)
                            .font(Design.Typography.footnote).fontWeight(.medium)
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        if item.tierLabel != nil || item.variantName != nil || (item.discountAmount ?? 0) > 0 {
                            HStack(spacing: 4) {
                                if let tierLabel = item.tierLabel {
                                    if let tierQty = item.tierQuantity, item.quantity > 1 {
                                        let totalQty = tierQty * Double(item.quantity)
                                        let unit = extractUnit(from: tierLabel)
                                        let formattedTotal = formatQuantity(totalQty, unit: unit)
                                        Text("\(tierLabel) × \(item.quantity) = \(formattedTotal)")
                                    } else {
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
                            .font(Design.Typography.caption2).fontWeight(.medium)
                            .foregroundStyle(.white.opacity(0.4))
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(formatCurrency(item.lineTotal))
                            .font(Design.Typography.footnoteRounded).fontWeight(.semibold)
                            .foregroundStyle(.white.opacity(0.6))

                        if let discount = item.discountAmount, discount > 0 {
                            Text(formatCurrency(item.originalLineTotal))
                                .font(Design.Typography.caption2).fontWeight(.medium)
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

    // MARK: - Totals Card

    var totalsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("TOTALS")

            VStack(spacing: 8) {
                detailRow("Subtotal", value: formatCurrency(order.subtotal))

                if order.discountAmount > 0 {
                    HStack {
                        HStack(spacing: 6) {
                            Image(systemName: "tag.fill")
                                .font(Design.Typography.caption2)
                            Text("Discount")
                        }
                        .font(Design.Typography.footnote)
                        .foregroundStyle(.green)
                        Spacer()
                        Text("-\(formatCurrency(order.discountAmount))")
                            .font(Design.Typography.footnoteRounded).fontWeight(.medium)
                            .foregroundStyle(.green)
                    }
                }

                if let pointsRedeemed = pointsRedeemedOnOrder, pointsRedeemed > 0 {
                    HStack {
                        HStack(spacing: 6) {
                            Image(systemName: "star.fill")
                                .font(Design.Typography.caption2)
                            Text("Points Redeemed")
                        }
                        .font(Design.Typography.footnote)
                        .foregroundStyle(.orange)
                        Spacer()
                        Text("-\(pointsRedeemed) pts")
                            .font(Design.Typography.footnoteRounded).fontWeight(.medium)
                            .foregroundStyle(.orange)
                    }
                }

                if order.taxAmount > 0 {
                    detailRow("Tax", value: formatCurrency(order.taxAmount))
                }

                Divider().overlay(Color.white.opacity(0.1))

                HStack {
                    Text("Total")
                        .font(Design.Typography.callout).fontWeight(.bold)
                        .foregroundStyle(.white)
                    Spacer()
                    Text(order.formattedTotal)
                        .font(Design.Typography.calloutRounded).fontWeight(.bold)
                        .foregroundStyle(.white)
                }

                if let pointsEarned = pointsEarnedOnOrder, pointsEarned > 0 {
                    HStack {
                        HStack(spacing: 6) {
                            Image(systemName: "star.fill")
                                .font(Design.Typography.caption2)
                            Text("Points Earned")
                        }
                        .font(Design.Typography.footnote)
                        .foregroundStyle(.yellow.opacity(0.8))
                        Spacer()
                        Text("+\(pointsEarned) pts")
                            .font(Design.Typography.footnoteRounded).fontWeight(.medium)
                            .foregroundStyle(.yellow.opacity(0.8))
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .glassCard()
    }

    // MARK: - Fulfillment Card

    func fulfillmentCard(_ fulfillments: [OrderFulfillment]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("FULFILLMENT")

            ForEach(fulfillments) { f in
                VStack(spacing: 8) {
                    HStack {
                        HStack(spacing: 6) {
                            Image(systemName: f.type.icon)
                                .font(Design.Typography.footnote)
                            Text(f.type.displayName)
                                .font(Design.Typography.footnote).fontWeight(.medium)
                        }
                        .foregroundStyle(.white)

                        Spacer()

                        Text(f.status.displayName)
                            .font(Design.Typography.footnote)
                            .foregroundStyle(fulfillmentStatusColor(f.status))
                    }

                    if let loc = f.locationName {
                        HStack {
                            Image(systemName: "building.2")
                                .font(Design.Typography.caption2)
                                .foregroundStyle(.white.opacity(0.3))
                            Text(loc)
                                .font(Design.Typography.footnote)
                                .foregroundStyle(.white.opacity(0.5))
                            Spacer()
                        }
                    }

                    if let carrier = f.carrier {
                        HStack {
                            Image(systemName: "shippingbox")
                                .font(Design.Typography.caption2)
                                .foregroundStyle(.white.opacity(0.3))
                            Text(carrier)
                                .font(Design.Typography.footnote)
                                .foregroundStyle(.white.opacity(0.5))
                            Spacer()
                        }
                    }

                    if let tracking = f.trackingNumber {
                        HStack {
                            Image(systemName: "barcode")
                                .font(Design.Typography.caption2)
                                .foregroundStyle(.white.opacity(0.3))
                            Text(tracking)
                                .font(Design.Typography.caption1Mono)
                                .foregroundStyle(.white.opacity(0.5))
                            Spacer()
                            if let url = f.trackingUrl, let trackingURL = URL(string: url) {
                                Link(destination: trackingURL) {
                                    Image(systemName: "arrow.up.right.square")
                                        .font(Design.Typography.caption1)
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }

                    if let shippedAt = f.shippedAt {
                        HStack {
                            Text("Shipped")
                                .font(Design.Typography.caption1)
                                .foregroundStyle(.white.opacity(0.3))
                            Spacer()
                            Text(formatDate(shippedAt))
                                .font(Design.Typography.caption1)
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }

                    if let deliveredAt = f.deliveredAt {
                        HStack {
                            Text("Delivered")
                                .font(Design.Typography.caption1)
                                .foregroundStyle(.white.opacity(0.3))
                            Spacer()
                            Text(formatDate(deliveredAt))
                                .font(Design.Typography.caption1)
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

    func notesCard(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("STAFF NOTES")

            Text(notes)
                .font(Design.Typography.footnote)
                .foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
        }
        .glassCard()
    }
}

// MARK: - Glass Card Modifier

extension View {
    func glassCard() -> some View {
        self.glassEffect(.regular, in: .rect(cornerRadius: 14))
    }
}
