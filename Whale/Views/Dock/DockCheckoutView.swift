//  DockCheckoutView.swift - Checkout flow content

import SwiftUI

struct DockCheckoutView: View {
    @Environment(\.posWindowSession) private var windowSession: POSWindowSession?
    @ObservedObject var posStore: POSStore
    let totals: CheckoutTotals
    @Binding var selectedPaymentMethod: DockPaymentMethod

    // Multi-window support
    private var isMultiWindowSession: Bool {
        windowSession?.location != nil
    }

    private var cartItems: [CartItem] {
        isMultiWindowSession ? (windowSession?.cartItems ?? []) : posStore.cartItems
    }

    private var selectedCustomer: Customer? {
        isMultiWindowSession ? windowSession?.selectedCustomer : posStore.selectedCustomer
    }

    // Payment inputs
    @Binding var cashAmount: String
    @Binding var splitCashAmount: String
    @Binding var card1Percentage: Double

    // Invoice
    @Binding var invoiceEmail: String
    @Binding var invoiceDueDate: Date
    @Binding var invoiceNotes: String
    @Binding var showDueDatePicker: Bool

    // Loyalty points
    @Binding var pointsToRedeem: Int
    @ObservedObject var dealStore: DealStore

    let onDismiss: () -> Void
    let onAddCustomer: () -> Void
    let onProcessPayment: () async -> Void
    let onSendInvoice: () async -> Void

    /// Discount applied (server-calculated)
    private var hasDiscount: Bool {
        totals.discountAmount > 0
    }

    /// Customer has loyalty points to redeem
    private var hasLoyaltyPoints: Bool {
        (selectedCustomer?.loyaltyPoints ?? 0) > 0
    }

    /// Calculate loyalty discount from points (simple: $0.01 per point)
    private var calculatedLoyaltyDiscount: Decimal {
        Decimal(pointsToRedeem) * Decimal(string: "0.01")!
    }

    /// Display total after loyalty discount is applied
    private var displayTotal: Decimal {
        totals.total - calculatedLoyaltyDiscount
    }

    /// Whether loyalty discount is being applied
    private var hasLoyaltyDiscount: Bool {
        pointsToRedeem > 0
    }

    private var canSendInvoice: Bool {
        guard selectedCustomer != nil else { return false }
        let hasCustomerEmail = selectedCustomer?.email?.isEmpty == false
        let emailRegex = #"^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        let hasValidManualEmail = !invoiceEmail.isEmpty && invoiceEmail.range(of: emailRegex, options: .regularExpression) != nil
        return !cartItems.isEmpty && (hasCustomerEmail || hasValidManualEmail)
    }

    private var needsScroll: Bool {
        // Only scroll when content truly exceeds available space
        let hasExtendedContent = selectedPaymentMethod == .invoice && showDueDatePicker
        let hasManyItems = cartItems.count > 8
        let hasLoyaltySection = hasLoyaltyPoints || !dealStore.availableDeals.isEmpty
        return hasExtendedContent || hasManyItems || (hasLoyaltySection && cartItems.count > 5)
    }

    var body: some View {
        VStack(spacing: 0) {
            checkoutHeader
                .padding(.top, 16)
                .padding(.bottom, 10)

            if needsScroll {
                ScrollView(showsIndicators: false) {
                    checkoutContent
                }
            } else {
                checkoutContent
            }

            checkoutActionButton
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
    }

    private var checkoutContent: some View {
        VStack(spacing: 12) {
            // Loyalty points slider (native iOS Slider)
            if hasLoyaltyPoints || !dealStore.availableDeals.isEmpty {
                DockDiscountSection(
                    customer: selectedCustomer,
                    subtotal: totals.subtotal,
                    pointsToRedeem: $pointsToRedeem,
                    pointValue: 0.01,  // $0.01 per point
                    dealStore: dealStore
                )
            }

            checkoutItemsSummary
            taxBreakdownSection
            paymentMethodSelector
            paymentInput
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }

    // MARK: - Tax Breakdown Section

    private var taxBreakdownSection: some View {
        VStack(spacing: 8) {
            // Subtotal
            HStack {
                Text("Subtotal")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Text(CurrencyFormatter.format(totals.subtotal))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }

            // Discount (if any)
            if hasDiscount {
                HStack {
                    Text("Discount")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Design.Colors.Semantic.success)
                    Spacer()
                    Text("-\(CurrencyFormatter.format(totals.discountAmount))")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Design.Colors.Semantic.success)
                }
            }

            // Tax breakdown - itemized or combined
            if let breakdown = totals.taxBreakdown, !breakdown.isEmpty {
                ForEach(breakdown.indices, id: \.self) { index in
                    let tax = breakdown[index]
                    HStack {
                        Text("\(tax.name ?? "Tax") (\(formatTaxRate(tax.rate ?? 0))%)")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                        Spacer()
                        Text(CurrencyFormatter.format(tax.amount ?? 0))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
            } else if totals.taxAmount > 0 {
                // Fallback: show combined tax
                HStack {
                    Text("Tax (\(formatTaxRate(totals.taxRate * 100))%)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    Text(CurrencyFormatter.format(totals.taxAmount))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }

            // Loyalty Points Discount (if any)
            if hasLoyaltyDiscount {
                HStack {
                    Text("Points Discount")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Design.Colors.Semantic.success)
                    Spacer()
                    Text("-\(CurrencyFormatter.format(calculatedLoyaltyDiscount))")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Design.Colors.Semantic.success)
                }
            }

            // Separator
            Rectangle()
                .fill(.white.opacity(0.1))
                .frame(height: 1)
                .padding(.vertical, 4)

            // Total (shows displayTotal which includes loyalty discount)
            HStack {
                Text("Total")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                Text(CurrencyFormatter.format(displayTotal))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(hasLoyaltyDiscount ? Design.Colors.Semantic.success : .white)
            }
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }

    private func formatTaxRate(_ rate: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 2
        return formatter.string(from: rate as NSDecimalNumber) ?? "\(rate)"
    }

    // MARK: - Header

    private var checkoutHeader: some View {
        HStack {
            Button {
                Haptics.light()
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
            }
            .tint(.white)
            .glassEffect(.regular.interactive(), in: .circle)

            Spacer()

            VStack(spacing: 2) {
                if hasDiscount || hasLoyaltyDiscount {
                    Text(CurrencyFormatter.format(totals.total))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                        .strikethrough()
                }

                Text(CurrencyFormatter.format(displayTotal))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(hasLoyaltyDiscount ? Design.Colors.Semantic.success : .white)
                    .contentTransition(.numericText())
            }

            Spacer()

            if let customer = selectedCustomer {
                customerChip(customer)
            } else {
                Color.clear.frame(width: 32, height: 32)
            }
        }
        .padding(.horizontal, 20)
    }

    private func customerChip(_ customer: Customer) -> some View {
        HStack(spacing: 8) {
            Text(customer.initials)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Design.Colors.Semantic.success))

            Text(customer.firstName ?? "Guest")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: .capsule)
    }

    // MARK: - Items Summary

    private var checkoutItemsSummary: some View {
        VStack(spacing: 6) {
            ForEach(cartItems) { item in
                CheckoutItemRow(item: item, posStore: posStore)
            }
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }

    // MARK: - Payment Method Selector

    private var paymentMethodSelector: some View {
        HStack(spacing: 8) {
            ForEach([DockPaymentMethod.card, .cash, .split, .multiCard, .invoice], id: \.self) { method in
                let isSelected = selectedPaymentMethod == method
                Button {
                    Haptics.light()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        selectedPaymentMethod = method
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: method.icon)
                            .font(.system(size: 18, weight: .medium))
                        Text(method.label)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                }
                .tint(.white)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
            }
        }
    }

    // MARK: - Payment Input

    @ViewBuilder
    private var paymentInput: some View {
        switch selectedPaymentMethod {
        case .card:
            CardPaymentInput()
        case .cash:
            CashPaymentInput(cashAmount: $cashAmount, total: displayTotal)
        case .split:
            SplitPaymentInput(splitCashAmount: $splitCashAmount, total: displayTotal)
        case .multiCard:
            MultiCardPaymentInput(card1Percentage: $card1Percentage, total: displayTotal)
        case .invoice:
            InvoicePaymentInput(
                customer: selectedCustomer,
                invoiceEmail: $invoiceEmail,
                invoiceDueDate: $invoiceDueDate,
                invoiceNotes: $invoiceNotes,
                showDueDatePicker: $showDueDatePicker,
                onAddCustomer: {
                    onDismiss()
                    onAddCustomer()
                }
            )
        }
    }

    // MARK: - Action Button

    private var checkoutActionButton: some View {
        let isEnabled = selectedPaymentMethod == .invoice ? canSendInvoice : true

        return SlideToPayButton(
            text: actionButtonText,
            icon: selectedPaymentMethod.icon,
            isEnabled: isEnabled,
            onComplete: {
                if selectedPaymentMethod == .invoice {
                    Task { await onSendInvoice() }
                } else {
                    Task { await onProcessPayment() }
                }
            }
        )
    }

    private var actionButtonText: String {
        switch selectedPaymentMethod {
        case .card: return "Pay \(CurrencyFormatter.format(displayTotal))"
        case .cash: return "Pay \(CurrencyFormatter.format(displayTotal)) Cash"
        case .split: return "Pay \(CurrencyFormatter.format(displayTotal)) Split"
        case .multiCard: return "Pay \(CurrencyFormatter.format(displayTotal))"
        case .invoice: return "Send Invoice"
        }
    }
}

// MARK: - Slide to Pay Button (Liquid Glass Style)

struct SlideToPayButton: View {
    let text: String
    let icon: String
    let isEnabled: Bool
    let onComplete: () -> Void

    // Layout constants
    private let trackHeight: CGFloat = 62
    private let thumbDiameter: CGFloat = 52
    private let trackPadding: CGFloat = 5
    private let completionThreshold: CGFloat = 0.80

    @State private var dragOffset: CGFloat = 0
    @State private var isCompleted = false
    @State private var shimmerPhase: CGFloat = 0
    @GestureState private var isDragging = false

    // iOS green
    private let successGreen = Color(red: 52/255, green: 199/255, blue: 89/255)

    var body: some View {
        GeometryReader { geometry in
            let trackWidth = geometry.size.width
            let maxOffset = trackWidth - thumbDiameter - (trackPadding * 2)
            let progress = maxOffset > 0 ? min(max(dragOffset / maxOffset, 0), 1.0) : 0

            ZStack(alignment: .leading) {
                // Shimmer text - centered in track
                IOSShimmerText(text: text, phase: shimmerPhase)
                    .opacity(1.0 - Double(progress) * 2.0)
                    .frame(maxWidth: .infinity)
                    .padding(.leading, thumbDiameter + trackPadding + 8)

                // Liquid glass thumb with icon
                ZStack {
                    Image(systemName: isCompleted ? "checkmark" : icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(isCompleted ? successGreen : .white.opacity(0.9))
                        .contentTransition(.symbolEffect(.replace))
                }
                .frame(width: thumbDiameter, height: thumbDiameter)
                .glassEffect(.regular.interactive(), in: .circle)
                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                .padding(.leading, trackPadding)
                .offset(x: dragOffset)
                .scaleEffect(isDragging ? 0.95 : 1.0)
                .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isDragging)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .updating($isDragging) { _, state, _ in
                            state = true
                        }
                        .onChanged { value in
                            guard isEnabled && !isCompleted else { return }
                            dragOffset = max(0, min(value.translation.width, maxOffset))
                        }
                        .onEnded { _ in
                            guard isEnabled && !isCompleted else { return }
                            let finalProgress = maxOffset > 0 ? dragOffset / maxOffset : 0

                            if finalProgress >= completionThreshold {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    dragOffset = maxOffset
                                    isCompleted = true
                                }
                                ScanFeedback.shared.paymentProcessing()
                                onComplete()
                            } else {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) {
                                    dragOffset = 0
                                }
                            }
                        }
                )
            }
            .frame(height: trackHeight)
            .glassEffect(.regular, in: .capsule)
            .opacity(isEnabled ? 1.0 : 0.5)
            .allowsHitTesting(isEnabled && !isCompleted)
        }
        .frame(height: trackHeight)
        .onAppear {
            // Shimmer animation - continuous sweep
            withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                shimmerPhase = 1.0
            }
        }
        .onChange(of: text) { _, _ in
            if !isCompleted {
                withAnimation(.spring(response: 0.3)) {
                    dragOffset = 0
                }
            }
        }
    }
}

// MARK: - iOS Shimmer Text (exactly like "slide to power off")

private struct IOSShimmerText: View {
    let text: String
    let phase: CGFloat

    var body: some View {
        // Base text in dim white
        Text(text)
            .font(.system(size: 18, weight: .regular))
            .foregroundStyle(.white.opacity(0.4))
            .overlay(
                // Bright shimmer highlight that sweeps across
                Text(text)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(.white)
                    .mask(
                        GeometryReader { geo in
                            // Moving highlight band
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0),
                                    .init(color: .clear, location: 0.3),
                                    .init(color: .white, location: 0.5),
                                    .init(color: .clear, location: 0.7),
                                    .init(color: .clear, location: 1)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: geo.size.width * 0.6)
                            .offset(x: -geo.size.width * 0.3 + geo.size.width * 1.3 * phase)
                        }
                    )
            )
    }
}

// MARK: - Processing View

struct DockProcessingView: View {
    let amount: Decimal
    let label: String?

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.3)
                .tint(.white)

            VStack(spacing: 4) {
                Text("Processing payment...")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))

                if let label = label {
                    Text(label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }

            Text(CurrencyFormatter.format(amount))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Success View

struct DockSuccessView: View {
    let completedOrder: SaleCompletion?
    let total: Decimal
    @Binding var copiedLink: Bool
    let autoPrintFailed: Bool
    let onDone: () -> Void

    private var isInvoice: Bool {
        completedOrder?.paymentMethod == .invoice
    }

    var body: some View {
        VStack(spacing: 16) {
            if autoPrintFailed {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text("Labels failed to print - print manually")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.red.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            Image(systemName: isInvoice ? "paperplane.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(isInvoice ? Design.Colors.Semantic.accent : Design.Colors.Semantic.success)

            VStack(spacing: 4) {
                Text(isInvoice ? "Invoice Sent" : "Payment Complete")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)

                if let order = completedOrder {
                    Text(order.orderNumber)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }

            Text(CurrencyFormatter.format(completedOrder?.total ?? total))
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(isInvoice ? Design.Colors.Semantic.accent : Design.Colors.Semantic.success)

            if isInvoice, let paymentUrl = completedOrder?.paymentUrl {
                Button {
                    UIPasteboard.general.string = paymentUrl
                    copiedLink = true
                    Haptics.success()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        copiedLink = false
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: copiedLink ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 14, weight: .semibold))
                        Text(copiedLink ? "Link Copied!" : "Copy Payment Link")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .tint(.white)
                .glassEffect(.regular.interactive(), in: .capsule)
            }

            Button {
                Haptics.light()
                onDone()
            } label: {
                Text("Done")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
            }
            .tint(.white)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
            .padding(.horizontal, 20)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 20)
    }
}
