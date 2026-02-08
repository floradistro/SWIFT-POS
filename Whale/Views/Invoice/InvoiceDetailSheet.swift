//
//  InvoiceDetailSheet.swift
//  Whale
//
//  Invoice detail view with tracking information, resend capability.
//

import SwiftUI

struct InvoiceDetailSheet: View {
    let invoice: Invoice
    let onDismiss: () -> Void

    @State private var isResending = false
    @State private var isSendingReminder = false
    @State private var showResendSuccess = false
    @State private var showReminderSuccess = false
    @State private var errorMessage: String?
    @State private var copiedLink = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header with status
                    headerSection

                    // Tracking timeline
                    trackingSection

                    // Line items (what was invoiced)
                    if let lineItems = invoice.lineItems, !lineItems.isEmpty {
                        lineItemsSection(lineItems)
                    }

                    // Customer info
                    customerSection

                    // Amount
                    amountSection

                    // Payment info (if paid)
                    if invoice.paidAt != nil {
                        paymentInfoSection
                    }

                    // Actions
                    actionsSection
                }
                .padding(20)
            }
            .background(Design.Colors.backgroundPrimary)
            .navigationTitle("Invoice Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { onDismiss() }
                        .foregroundStyle(Design.Colors.Semantic.accent)
                }
            }
        }
        .alert("Email Sent", isPresented: $showResendSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Invoice email has been resent to \(invoice.customerEmail)")
        }
        .alert("Reminder Sent", isPresented: $showReminderSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Payment reminder has been sent to \(invoice.customerEmail)")
        }
        .alert("Error", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            // Invoice number with status badge
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(invoice.invoiceNumber)
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .foregroundStyle(Design.Colors.Text.primary)

                    Text("Created \(invoice.createdAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(Design.Typography.footnote)
                        .foregroundStyle(Design.Colors.Text.disabled)
                }

                Spacer()

                statusBadge
            }

            // Due date warning if applicable
            if let dueDate = invoice.dueDate {
                let isOverdue = dueDate < Date() && invoice.paidAt == nil
                HStack(spacing: 8) {
                    Image(systemName: isOverdue ? "exclamationmark.triangle.fill" : "calendar")
                        .font(Design.Typography.footnote)
                    Text(isOverdue ? "Overdue" : "Due \(dueDate.formatted(date: .abbreviated, time: .omitted))")
                        .font(Design.Typography.footnote).fontWeight(.medium)
                }
                .foregroundStyle(isOverdue ? Design.Colors.Semantic.error : Design.Colors.Text.disabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isOverdue ? Design.Colors.Semantic.error.opacity(0.15) : Design.Colors.Glass.thin)
                )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Design.Colors.Glass.thin)
        )
    }

    private var statusBadge: some View {
        let color = statusColor
        return Text(invoice.status.displayName.uppercased())
            .font(Design.Typography.caption2).fontWeight(.bold)
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(color.opacity(0.15))
            )
    }

    private var statusColor: Color {
        switch invoice.status {
        case .draft: return .gray
        case .sent: return Design.Colors.Semantic.accent
        case .viewed: return Design.Colors.Semantic.warning
        case .paid: return Design.Colors.Semantic.success
        case .partiallyPaid: return .orange
        case .overdue: return Design.Colors.Semantic.error
        case .cancelled, .refunded: return .gray
        }
    }

    // MARK: - Tracking Section

    private var trackingSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Activity")
                .font(Design.Typography.subhead).fontWeight(.semibold)
                .foregroundStyle(Design.Colors.Text.primary)

            VStack(spacing: 0) {
                trackingStep(
                    icon: "paperplane.fill",
                    title: "Invoice Sent",
                    timestamp: invoice.sentAt,
                    isComplete: invoice.sentAt != nil,
                    isLast: false
                )

                trackingStep(
                    icon: "eye.fill",
                    title: "Invoice Viewed",
                    timestamp: invoice.viewedAt,
                    isComplete: invoice.viewedAt != nil,
                    isLast: false
                )

                if invoice.reminderSentAt != nil {
                    trackingStep(
                        icon: "bell.fill",
                        title: "Reminder Sent",
                        timestamp: invoice.reminderSentAt,
                        isComplete: true,
                        isLast: false
                    )
                }

                trackingStep(
                    icon: "checkmark.circle.fill",
                    title: "Paid",
                    timestamp: invoice.paidAt,
                    isComplete: invoice.paidAt != nil,
                    isLast: true
                )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Design.Colors.Glass.thin)
        )
    }

    private func trackingStep(icon: String, title: String, timestamp: Date?, isComplete: Bool, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Icon and line
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(isComplete ? Design.Colors.Semantic.success : Design.Colors.Glass.thick)
                        .frame(width: 32, height: 32)

                    Image(systemName: icon)
                        .font(Design.Typography.footnote).fontWeight(.semibold)
                        .foregroundStyle(isComplete ? Design.Colors.Text.primary : Design.Colors.Text.placeholder)
                }

                if !isLast {
                    Rectangle()
                        .fill(isComplete ? Design.Colors.Semantic.success.opacity(0.3) : Design.Colors.Glass.thick)
                        .frame(width: 2, height: 24)
                }
            }

            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Design.Typography.footnote).fontWeight(.medium)
                    .foregroundStyle(isComplete ? Design.Colors.Text.primary : Design.Colors.Text.subtle)

                if let timestamp = timestamp {
                    Text(timestamp.formatted(date: .abbreviated, time: .shortened))
                        .font(Design.Typography.caption1)
                        .foregroundStyle(Design.Colors.Text.disabled)
                } else {
                    Text("Pending")
                        .font(Design.Typography.caption1)
                        .foregroundStyle(Design.Colors.Text.placeholder)
                }
            }
            .padding(.bottom, isLast ? 0 : 16)

            Spacer()
        }
    }

    // MARK: - Customer Section

    private var customerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Customer")
                .font(Design.Typography.subhead).fontWeight(.semibold)
                .foregroundStyle(Design.Colors.Text.primary)

            VStack(spacing: 10) {
                infoRow(icon: "person.fill", value: invoice.displayCustomerName)
                infoRow(icon: "envelope.fill", value: invoice.customerEmail)
                if let phone = invoice.customerPhone {
                    infoRow(icon: "phone.fill", value: phone)
                }
            }

            if let notes = invoice.notes, !notes.isEmpty {
                Divider()
                    .background(Design.Colors.Border.regular)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Notes")
                        .font(Design.Typography.caption1).fontWeight(.medium)
                        .foregroundStyle(Design.Colors.Text.disabled)
                    Text(notes)
                        .font(Design.Typography.footnote)
                        .foregroundStyle(Design.Colors.Text.tertiary)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Design.Colors.Glass.thin)
        )
    }

    private func infoRow(icon: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(Design.Typography.footnote)
                .foregroundStyle(Design.Colors.Text.disabled)
                .frame(width: 20)

            Text(value)
                .font(Design.Typography.footnote)
                .foregroundStyle(Design.Colors.Text.tertiary)

            Spacer()
        }
    }

    // MARK: - Line Items Section

    private func lineItemsSection(_ items: [InvoiceLineItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Items")
                .font(Design.Typography.subhead).fontWeight(.semibold)
                .foregroundStyle(Design.Colors.Text.primary)

            VStack(spacing: 8) {
                ForEach(items) { item in
                    HStack(alignment: .top, spacing: 12) {
                        // Quantity badge
                        Text("\(item.quantity)×")
                            .font(Design.Typography.footnoteRounded).fontWeight(.semibold)
                            .foregroundStyle(Design.Colors.Text.disabled)
                            .frame(width: 30, alignment: .leading)

                        // Product name
                        Text(item.productName)
                            .font(Design.Typography.footnote)
                            .foregroundStyle(Design.Colors.Text.secondary)
                            .lineLimit(2)

                        Spacer()

                        // Line total
                        Text(CurrencyFormatter.format(item.total))
                            .font(Design.Typography.footnote).fontWeight(.medium)
                            .foregroundStyle(Design.Colors.Text.tertiary)
                    }
                    .padding(.vertical, 8)

                    if item.id != items.last?.id {
                        Divider()
                            .background(Design.Colors.Border.regular)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Design.Colors.Glass.thin)
        )
    }

    // MARK: - Amount Section

    private var amountSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Subtotal")
                    .font(Design.Typography.footnote)
                    .foregroundStyle(Design.Colors.Text.disabled)
                Spacer()
                Text(CurrencyFormatter.format(invoice.subtotal))
                    .font(Design.Typography.footnote)
                    .foregroundStyle(Design.Colors.Text.tertiary)
            }

            if invoice.discountAmount > 0 {
                HStack {
                    Text("Discount")
                        .font(Design.Typography.footnote)
                        .foregroundStyle(Design.Colors.Text.disabled)
                    Spacer()
                    Text("-\(CurrencyFormatter.format(invoice.discountAmount))")
                        .font(Design.Typography.footnote)
                        .foregroundStyle(Design.Colors.Semantic.success)
                }
            }

            HStack {
                Text("Tax")
                    .font(Design.Typography.footnote)
                    .foregroundStyle(Design.Colors.Text.disabled)
                Spacer()
                Text(CurrencyFormatter.format(invoice.taxAmount))
                    .font(Design.Typography.footnote)
                    .foregroundStyle(Design.Colors.Text.tertiary)
            }

            Divider()
                .background(Design.Colors.Border.regular)

            HStack {
                Text("Total")
                    .font(Design.Typography.callout).fontWeight(.semibold)
                    .foregroundStyle(Design.Colors.Text.primary)
                Spacer()
                Text(CurrencyFormatter.format(invoice.totalAmount))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Design.Colors.Text.primary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Design.Colors.Glass.thin)
        )
    }

    // MARK: - Payment Info Section

    private var paymentInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .font(Design.Typography.callout)
                    .foregroundStyle(Design.Colors.Semantic.success)
                Text("Payment Received")
                    .font(Design.Typography.subhead).fontWeight(.semibold)
                    .foregroundStyle(Design.Colors.Text.primary)
            }

            VStack(spacing: 10) {
                // Payment date
                if let paidAt = invoice.paidAt {
                    paymentInfoRow(
                        icon: "calendar",
                        label: "Paid on",
                        value: paidAt.formatted(date: .abbreviated, time: .shortened)
                    )
                }

                // Payment method
                if let method = invoice.paymentMethod {
                    let displayMethod = formatPaymentMethod(method)
                    paymentInfoRow(
                        icon: paymentMethodIcon(method),
                        label: "Method",
                        value: displayMethod
                    )
                }

                // Card info (if available)
                if let cardType = invoice.cardType, let lastFour = invoice.cardLastFour {
                    paymentInfoRow(
                        icon: "creditcard.fill",
                        label: "Card",
                        value: "\(cardType.capitalized) •••• \(lastFour)"
                    )
                }

                // Transaction ID
                if let transactionId = invoice.transactionId, !transactionId.isEmpty {
                    paymentInfoRow(
                        icon: "number",
                        label: "Transaction",
                        value: String(transactionId.prefix(16)) + (transactionId.count > 16 ? "..." : "")
                    )
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Design.Colors.Semantic.success.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Design.Colors.Semantic.success.opacity(0.3), lineWidth: 1)
                )
        )
    }

    private func paymentInfoRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(Design.Typography.footnote)
                .foregroundStyle(Design.Colors.Text.disabled)
                .frame(width: 20)

            Text(label)
                .font(Design.Typography.footnote)
                .foregroundStyle(Design.Colors.Text.disabled)

            Spacer()

            Text(value)
                .font(Design.Typography.footnote).fontWeight(.medium)
                .foregroundStyle(Design.Colors.Text.secondary)
        }
    }

    private func formatPaymentMethod(_ method: String) -> String {
        switch method.lowercased() {
        case "card", "credit_card", "debit_card": return "Card"
        case "cash": return "Cash"
        case "apple_pay", "applepay": return "Apple Pay"
        case "google_pay", "googlepay": return "Google Pay"
        case "bank_transfer", "ach": return "Bank Transfer"
        default: return method.capitalized
        }
    }

    private func paymentMethodIcon(_ method: String) -> String {
        switch method.lowercased() {
        case "card", "credit_card", "debit_card": return "creditcard"
        case "cash": return "banknote"
        case "apple_pay", "applepay": return "apple.logo"
        case "google_pay", "googlepay": return "g.circle"
        case "bank_transfer", "ach": return "building.columns"
        default: return "dollarsign.circle"
        }
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        VStack(spacing: 12) {
            // Copy payment link (only if URL exists)
            if let paymentUrl = invoice.paymentUrl, !paymentUrl.isEmpty {
                Button {
                    UIPasteboard.general.string = paymentUrl
                    copiedLink = true
                    Haptics.success()
                    Task { @MainActor in try? await Task.sleep(for: .seconds(2));
                        copiedLink = false
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: copiedLink ? "checkmark" : "doc.on.doc")
                            .font(Design.Typography.footnote).fontWeight(.semibold)
                        Text(copiedLink ? "Link Copied!" : "Copy Payment Link")
                            .font(Design.Typography.footnote).fontWeight(.semibold)
                    }
                    .foregroundStyle(copiedLink ? Design.Colors.Semantic.success : Design.Colors.Text.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(copiedLink ? Design.Colors.Semantic.success.opacity(0.15) : Design.Colors.Glass.thick)
                    )
                }
            }

            // Unpaid invoice actions
            if invoice.paidAt == nil {
                // Send Payment Reminder (if invoice has been viewed or is overdue)
                if invoice.viewedAt != nil || isOverdue {
                    Button {
                        Task { await sendReminder() }
                    } label: {
                        HStack(spacing: 8) {
                            if isSendingReminder {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: Design.Colors.Text.primary))
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "bell.badge")
                                    .font(Design.Typography.footnote).fontWeight(.semibold)
                            }
                            Text(reminderButtonText)
                                .font(Design.Typography.footnote).fontWeight(.semibold)
                        }
                        .foregroundStyle(Design.Colors.Text.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Design.Colors.Semantic.warning)
                        )
                    }
                    .disabled(isSendingReminder)
                }

                // Resend Invoice Email
                Button {
                    Task { await resendEmail() }
                } label: {
                    HStack(spacing: 8) {
                        if isResending {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: Design.Colors.Text.primary))
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(Design.Typography.footnote).fontWeight(.semibold)
                        }
                        Text(isResending ? "Sending..." : "Resend Invoice Email")
                            .font(Design.Typography.footnote).fontWeight(.semibold)
                    }
                    .foregroundStyle(Design.Colors.Text.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Design.Colors.Semantic.accent)
                    )
                }
                .disabled(isResending)
            }
        }
    }

    private var isOverdue: Bool {
        guard let dueDate = invoice.dueDate else { return false }
        return dueDate < Date()
    }

    private var reminderButtonText: String {
        if isSendingReminder {
            return "Sending..."
        }
        if let lastReminder = invoice.reminderSentAt {
            let daysSince = Calendar.current.dateComponents([.day], from: lastReminder, to: Date()).day ?? 0
            if daysSince < 1 {
                return "Reminder Sent Today"
            }
            return "Send Another Reminder"
        }
        return "Send Payment Reminder"
    }

    // MARK: - Actions

    private func resendEmail() async {
        isResending = true
        defer { isResending = false }

        do {
            let success = try await InvoiceService.resendInvoice(invoiceId: invoice.id)
            if success {
                showResendSuccess = true
                Haptics.success()
            }
        } catch {
            errorMessage = error.localizedDescription
            Haptics.error()
        }
    }

    private func sendReminder() async {
        isSendingReminder = true
        defer { isSendingReminder = false }

        do {
            let success = try await InvoiceService.sendReminder(invoiceId: invoice.id)
            if success {
                showReminderSuccess = true
                Haptics.success()
            }
        } catch {
            errorMessage = error.localizedDescription
            Haptics.error()
        }
    }
}

// MARK: - Compact Invoice Tracking View (for Order Detail)

struct InvoiceTrackingBadges: View {
    let invoice: Invoice

    var body: some View {
        HStack(spacing: 8) {
            trackingBadge(
                icon: "paperplane.fill",
                label: "Sent",
                isComplete: invoice.sentAt != nil
            )

            trackingBadge(
                icon: "eye.fill",
                label: "Viewed",
                isComplete: invoice.viewedAt != nil
            )

            trackingBadge(
                icon: "checkmark.circle.fill",
                label: "Paid",
                isComplete: invoice.paidAt != nil
            )
        }
    }

    private func trackingBadge(icon: String, label: String, isComplete: Bool) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(Design.Typography.footnote)
                .foregroundStyle(isComplete ? Design.Colors.Semantic.success : Design.Colors.Text.placeholder)

            Text(label)
                .font(Design.Typography.caption2).fontWeight(.medium)
                .foregroundStyle(isComplete ? Design.Colors.Text.tertiary : Design.Colors.Text.placeholder)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isComplete ? Design.Colors.Semantic.success.opacity(0.1) : Design.Colors.Glass.thin)
        )
    }
}

// MARK: - Preview

#Preview {
    InvoiceDetailSheet(
        invoice: Invoice(
            id: UUID(),
            invoiceNumber: "INV-2024-001",
            orderId: UUID(),
            storeId: UUID(),
            customerId: UUID(),
            customerName: "John Doe",
            customerEmail: "john@example.com",
            customerPhone: "555-1234",
            description: "Sample invoice",
            lineItems: nil,
            subtotal: 100.00,
            taxAmount: 8.00,
            discountAmount: 0,
            totalAmount: 108.00,
            status: .sent,
            paymentStatus: "pending",
            amountPaid: 0,
            amountDue: 108.00,
            dueDate: Date().addingTimeInterval(86400 * 7),
            notes: "Thank you for your business!",
            paymentToken: "abc123",
            paymentUrl: "https://example.com/pay/abc123",
            sentAt: Date().addingTimeInterval(-86400),
            viewedAt: Date().addingTimeInterval(-3600),
            paidAt: nil,
            reminderSentAt: nil,
            paymentMethod: nil,
            transactionId: nil,
            cardLastFour: nil,
            cardType: nil,
            createdAt: Date().addingTimeInterval(-86400),
            updatedAt: Date()
        ),
        onDismiss: {}
    )
}
