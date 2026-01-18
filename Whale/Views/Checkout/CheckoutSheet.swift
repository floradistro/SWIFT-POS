//
//  CheckoutSheet.swift
//  Whale
//
//  Checkout sheet using unified modal system.
//  Uses existing ModalHeader, ModalSection, ModalActionButton components.
//

import SwiftUI

struct CheckoutSheet: View {
    @Environment(\.posWindowSession) private var windowSession: POSWindowSession?
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var posStore: POSStore
    @ObservedObject var paymentStore: PaymentStore
    @ObservedObject var dealStore: DealStore
    let totals: CheckoutTotals
    let sessionInfo: SessionInfo

    var onScanID: () -> Void
    var onComplete: (SaleCompletion?) -> Void

    // State
    @State private var checkoutPhase: CheckoutPhase = .checkout
    @State private var selectedPaymentMethod: DockPaymentMethod = .card
    @State private var cashAmount: String = ""
    @State private var splitCashAmount: String = ""
    @State private var card1Percentage: Double = 50

    // Invoice
    @State private var invoiceNotes: String = ""
    @State private var invoiceEmail: String = ""
    @State private var invoiceDueDate: Date = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var showDueDatePicker = false

    // Loyalty
    @State private var pointsToRedeem: Int = 0

    // Success
    @State private var completedOrder: SaleCompletion?
    @State private var copiedLink = false
    @State private var autoPrintFailed = false

    // Error
    @State private var showErrorAlert = false
    @State private var errorMessage = ""

    // Line Item Discount
    @State private var selectedItemForDiscount: CartItem?
    @State private var showDiscountSheet = false

    // Animation
    @State private var showContent = false

    enum CheckoutPhase { case checkout, processing, success }

    // MARK: - Accessors

    private var isMultiWindowSession: Bool { windowSession?.location != nil }
    private var cartItems: [CartItem] { isMultiWindowSession ? (windowSession?.cartItems ?? []) : posStore.cartItems }
    private var selectedCustomer: Customer? { isMultiWindowSession ? windowSession?.selectedCustomer : posStore.selectedCustomer }

    private var hasLoyaltyPoints: Bool { (selectedCustomer?.loyaltyPoints ?? 0) > 0 }
    private var calculatedLoyaltyDiscount: Decimal { Decimal(pointsToRedeem) * Decimal(string: "0.01")! }
    private var displayTotal: Decimal { totals.total - calculatedLoyaltyDiscount }
    private var hasLoyaltyDiscount: Bool { pointsToRedeem > 0 }

    private var canSendInvoice: Bool {
        guard selectedCustomer != nil else { return false }
        let hasEmail = selectedCustomer?.email?.isEmpty == false
        let emailRegex = #"^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        let hasValidManual = !invoiceEmail.isEmpty && invoiceEmail.range(of: emailRegex, options: .regularExpression) != nil
        return !cartItems.isEmpty && (hasEmail || hasValidManual)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            switch checkoutPhase {
            case .checkout: checkoutContent
            case .processing: processingContent
            case .success: successContent
            }
        }
        .frame(maxWidth: 580)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task {
            // Stagger animations like other sheets
            try? await Task.sleep(nanoseconds: 100_000_000)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                showContent = true
            }
        }
        .onChange(of: paymentStore.uiState) { _, state in
            handlePaymentStateChange(state)
        }
        .alert("Payment Failed", isPresented: $showErrorAlert) {
            Button("Retry") { paymentStore.reset() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .overlay {
            if showDiscountSheet {
                lineItemDiscountOverlay
            }
        }
    }

    // MARK: - Line Item Discount Overlay

    private var lineItemDiscountOverlay: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.3)) {
                        showDiscountSheet = false
                    }
                }

            // Glass menu
            if let item = selectedItemForDiscount {
                VStack(spacing: 0) {
                    // Header with item info
                    VStack(spacing: 4) {
                        Text(item.productName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Text(CurrencyFormatter.format(item.originalLineTotal))
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)

                    Divider().background(.white.opacity(0.15))

                    // Discount options
                    VStack(spacing: 0) {
                        // Custom Price
                        discountMenuRow(
                            icon: "dollarsign",
                            title: "Set Price",
                            subtitle: "Custom amount"
                        ) {
                            showDiscountInput(type: .customPrice)
                        }

                        Divider().background(.white.opacity(0.1)).padding(.leading, 48)

                        // Percentage Off
                        discountMenuRow(
                            icon: "percent",
                            title: "Percentage Off",
                            subtitle: "e.g. 10%, 20%"
                        ) {
                            showDiscountInput(type: .percentage)
                        }

                        Divider().background(.white.opacity(0.1)).padding(.leading, 48)

                        // Flat Amount Off
                        discountMenuRow(
                            icon: "minus.circle",
                            title: "Amount Off",
                            subtitle: "e.g. $5, $10"
                        ) {
                            showDiscountInput(type: .flatAmount)
                        }
                    }

                    // Remove discount (if exists)
                    if item.discountAmount > 0 {
                        Divider().background(.white.opacity(0.15))

                        Button {
                            removeLineItemDiscount()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "trash")
                                    .font(.system(size: 14, weight: .medium))
                                    .frame(width: 20)

                                Text("Remove Discount")
                                    .font(.system(size: 15, weight: .medium))

                                Spacer()

                                Text("+\(CurrencyFormatter.format(item.discountAmount))")
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                            }
                            .foregroundStyle(.red)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(width: 280)
                .glassEffect(.regular, in: .rect(cornerRadius: 16))
                .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
                .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showDiscountSheet)
    }

    private func discountMenuRow(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)

                    Text(subtitle)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.white.opacity(0.4))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private enum DiscountInputType {
        case customPrice, percentage, flatAmount
    }

    private func showDiscountInput(type: DiscountInputType) {
        withAnimation(.spring(response: 0.3)) {
            showDiscountSheet = false
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard let item = selectedItemForDiscount else { return }

            let (title, placeholder, message): (String, String, String) = {
                switch type {
                case .customPrice:
                    return ("Set Price", "Enter price", "New price for \(item.productName)")
                case .percentage:
                    return ("Percentage Off", "Enter %", "Discount for \(item.productName)")
                case .flatAmount:
                    return ("Amount Off", "Enter $", "Discount for \(item.productName)")
                }
            }()

            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)

            alert.addTextField { textField in
                textField.placeholder = placeholder
                textField.keyboardType = .decimalPad
                textField.font = .systemFont(ofSize: 24, weight: .semibold)
                textField.textAlignment = .center
            }

            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            alert.addAction(UIAlertAction(title: "Apply", style: .default) { [self] _ in
                guard let text = alert.textFields?.first?.text,
                      let value = Decimal(string: text), value > 0 else { return }

                Task {
                    switch type {
                    case .customPrice:
                        // Calculate discount as difference from original
                        let discount = item.originalLineTotal - value
                        if discount > 0 {
                            await applyDiscount(itemId: item.id, type: .fixed, value: discount)
                        }
                    case .percentage:
                        await applyDiscount(itemId: item.id, type: .percentage, value: value)
                    case .flatAmount:
                        await applyDiscount(itemId: item.id, type: .fixed, value: value)
                    }
                }
            })

            presentAlert(alert)
        }
    }

    private func applyDiscount(itemId: UUID, type: DiscountType, value: Decimal) async {
        if isMultiWindowSession {
            await windowSession?.applyManualDiscount(itemId: itemId, type: type, value: value)
        } else {
            posStore.applyManualDiscount(itemId: itemId, type: ManualDiscountType(rawValue: type.rawValue) ?? .fixed, value: value)
        }
    }

    private func presentAlert(_ alert: UIAlertController) {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            var topVC = rootVC
            while let presented = topVC.presentedViewController {
                topVC = presented
            }
            topVC.present(alert, animated: true)
        }
    }

    private func removeLineItemDiscount() {
        guard let item = selectedItemForDiscount else { return }

        Task {
            if isMultiWindowSession {
                await windowSession?.applyManualDiscount(itemId: item.id, type: .fixed, value: 0)
            } else {
                posStore.removeManualDiscount(itemId: item.id)
            }
            withAnimation(.spring(response: 0.3)) {
                showDiscountSheet = false
            }
        }
    }

    // MARK: - Checkout Content

    private var checkoutContent: some View {
        VStack(spacing: 0) {
            // Header
            sheetHeader

            // Content
            VStack(spacing: 12) {
                // Items
                itemsSection
                    .opacity(showContent ? 1 : 0)
                    .offset(y: showContent ? 0 : 20)

                // Totals
                totalsSection
                    .opacity(showContent ? 1 : 0)
                    .offset(y: showContent ? 0 : 20)

                // Loyalty
                if hasLoyaltyPoints {
                    loyaltySection
                        .opacity(showContent ? 1 : 0)
                        .offset(y: showContent ? 0 : 20)
                }

                // Payment methods
                paymentMethodSection
                    .opacity(showContent ? 1 : 0)
                    .offset(y: showContent ? 0 : 20)

                // Payment input
                paymentInputSection
                    .opacity(showContent ? 1 : 0)
                    .offset(y: showContent ? 0 : 20)

                Spacer(minLength: 16)

                // Action
                actionButton
                    .opacity(showContent ? 1 : 0)
                    .offset(y: showContent ? 0 : 20)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Sheet Header

    private var sheetHeader: some View {
        VStack(spacing: 16) {
            HStack(alignment: .center) {
                ModalCloseButton { dismiss() }

                Spacer()

                // Total and customer
                VStack(spacing: 8) {
                    // Customer chip
                    if let customer = selectedCustomer {
                        HStack(spacing: 6) {
                            Text(customer.initials)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(Color.accentColor))

                            Text(customer.firstName ?? "Customer")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .glassEffect(.regular, in: .capsule)
                    }

                    // Total
                    Text(CurrencyFormatter.format(displayTotal))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())

                    // Item count
                    Text("\(cartItems.count) item\(cartItems.count == 1 ? "" : "s")")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                }

                Spacer()

                // Placeholder for symmetry
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Items Section

    private var itemsSection: some View {
        VStack(spacing: 0) {
            ForEach(Array(cartItems.prefix(5).enumerated()), id: \.element.id) { index, item in
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

                        // Show discount badge if item has discount
                        if item.discountAmount > 0 {
                            Text("-\(CurrencyFormatter.format(item.discountAmount))")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.green)
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(CurrencyFormatter.format(item.lineTotal))
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))

                        // Show original price if discounted
                        if item.discountAmount > 0 {
                            Text(CurrencyFormatter.format(item.originalLineTotal))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.3))
                                .strikethrough()
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
                .onLongPressGesture {
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    selectedItemForDiscount = item
                    withAnimation(.spring(response: 0.3)) {
                        showDiscountSheet = true
                    }
                }
            }

            if cartItems.count > 5 {
                Text("+\(cartItems.count - 5) more items")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.3))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
            }
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }

    // MARK: - Totals Section

    private var totalsSection: some View {
        VStack(spacing: 0) {
            totalsRow(label: "Subtotal", value: CurrencyFormatter.format(totals.subtotal))

            if totals.taxAmount > 0 {
                totalsRow(label: "Tax", value: CurrencyFormatter.format(totals.taxAmount))
            }

            if totals.discountAmount > 0 {
                totalsRow(label: "Discount", value: "-\(CurrencyFormatter.format(totals.discountAmount))", valueColor: .green)
            }

            if hasLoyaltyDiscount {
                totalsRow(label: "Points Redeemed", value: "-\(CurrencyFormatter.format(calculatedLoyaltyDiscount))", valueColor: .green)
            }

            // Divider
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 1)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)

            // Total row
            HStack {
                Text("Total")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text(CurrencyFormatter.format(displayTotal))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }

    private func totalsRow(label: String, value: String, valueColor: Color = .white.opacity(0.6)) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.5))
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(valueColor)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Loyalty Section

    private var loyaltySection: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "star.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.yellow)
                Text("\(selectedCustomer?.loyaltyPoints ?? 0) points available")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                Spacer()
                if hasLoyaltyDiscount {
                    Text("-\(CurrencyFormatter.format(calculatedLoyaltyDiscount))")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.green)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 8)

            Slider(
                value: Binding(
                    get: { Double(pointsToRedeem) },
                    set: { pointsToRedeem = Int($0) }
                ),
                in: 0...Double(min(selectedCustomer?.loyaltyPoints ?? 0, Int(truncating: (totals.total * 100) as NSDecimalNumber))),
                step: 10
            )
            .tint(.yellow)
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }

    // MARK: - Payment Method Section

    private var paymentMethodSection: some View {
        HStack(spacing: 8) {
            ForEach([DockPaymentMethod.card, .cash, .split, .multiCard, .invoice], id: \.self) { method in
                paymentMethodButton(method)
            }
        }
    }

    private func paymentMethodButton(_ method: DockPaymentMethod) -> some View {
        let isSelected = selectedPaymentMethod == method

        return Button {
            Haptics.light()
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                selectedPaymentMethod = method
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: method.icon)
                    .font(.system(size: 16, weight: .medium))
                Text(method.label)
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(isSelected ? .white : .white.opacity(0.5))
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.15))
                }
            }
            .glassEffect(.regular, in: .rect(cornerRadius: 12))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Payment Input

    @ViewBuilder
    private var paymentInputSection: some View {
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
                onAddCustomer: { dismiss(); onScanID() }
            )
        }
    }

    // MARK: - Action Button

    private var actionButton: some View {
        SlideToPayButton(
            text: actionButtonText,
            icon: selectedPaymentMethod.icon,
            isEnabled: selectedPaymentMethod == .invoice ? canSendInvoice : true,
            onComplete: {
                Task {
                    if selectedPaymentMethod == .invoice {
                        await sendInvoice()
                    } else {
                        await processPayment()
                    }
                }
            }
        )
    }

    private var actionButtonText: String {
        switch selectedPaymentMethod {
        case .card: return "Pay \(CurrencyFormatter.format(displayTotal))"
        case .cash: return "Cash \(CurrencyFormatter.format(displayTotal))"
        case .split: return "Split \(CurrencyFormatter.format(displayTotal))"
        case .multiCard: return "2 Cards \(CurrencyFormatter.format(displayTotal))"
        case .invoice: return "Send Invoice"
        }
    }

    // MARK: - Processing Content

    private var processingContent: some View {
        VStack(spacing: 24) {
            Spacer()

            ProgressView()
                .scaleEffect(1.5)
                .tint(.accentColor)

            VStack(spacing: 4) {
                Text("Processing...")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                Text(selectedPaymentMethod.label)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.5))
            }

            Text(CurrencyFormatter.format(displayTotal))
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Spacer()
        }
    }

    // MARK: - Success Content

    private var successContent: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 16) {
                HStack(alignment: .center) {
                    ModalCloseButton {
                        onComplete(completedOrder)
                        dismiss()
                    }

                    Spacer()

                    VStack(spacing: 4) {
                        Text(isInvoice ? "Invoice Sent" : "Payment Complete")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        if let orderNumber = completedOrder?.orderNumber {
                            Text(orderNumber)
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }

                    Spacer()

                    Color.clear.frame(width: 44, height: 44)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            VStack(spacing: 20) {
                Spacer()

                if autoPrintFailed {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Labels failed to print")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.orange.opacity(0.15), in: Capsule())
                }

                Image(systemName: isInvoice ? "paperplane.circle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(isInvoice ? .blue : .green)
                    .symbolEffect(.bounce, value: checkoutPhase)

                Text(CurrencyFormatter.format(completedOrder?.total ?? displayTotal))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(isInvoice ? .blue : .green)

                if isInvoice, let paymentUrl = completedOrder?.paymentUrl {
                    Button {
                        UIPasteboard.general.string = paymentUrl
                        copiedLink = true
                        Haptics.success()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copiedLink = false }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: copiedLink ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 14, weight: .medium))
                            Text(copiedLink ? "Copied!" : "Copy Payment Link")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                    }
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
                    .padding(.horizontal, 20)
                }

                Spacer()

                // Done button
                Button {
                    onComplete(completedOrder)
                    dismiss()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Done")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.green, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
    }

    private var isInvoice: Bool {
        completedOrder?.paymentMethod == .invoice
    }

    // MARK: - Handlers

    private func handlePaymentStateChange(_ state: UIPaymentState) {
        switch state {
        case .idle: break
        case .processing:
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                checkoutPhase = .processing
            }
        case .success(let completion):
            completedOrder = completion
            ScanFeedback.shared.paymentSuccess()
            triggerAutoPrintIfEnabled(with: completion)
            LabelPrinterSettings.shared.stopPrewarming()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                checkoutPhase = .success
            }
        case .failed(let message):
            errorMessage = message
            showErrorAlert = true
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                checkoutPhase = .checkout
            }
            Haptics.error()
        }
    }

    private func processPayment() async {
        LabelPrinterSettings.shared.startPrewarming()
        let loyaltyDiscount = calculatedLoyaltyDiscount
        let effectiveTotal = displayTotal

        do {
            switch selectedPaymentMethod {
            case .card:
                _ = try await paymentStore.processCardPayment(
                    cart: cartItems, totals: totals, sessionInfo: sessionInfo, customer: selectedCustomer,
                    loyaltyPointsRedeemed: pointsToRedeem, loyaltyDiscountAmount: loyaltyDiscount
                )
            case .cash:
                let cashValue = Decimal(string: cashAmount) ?? effectiveTotal
                guard cashValue >= effectiveTotal else {
                    errorMessage = "Cash must be at least \(CurrencyFormatter.format(effectiveTotal))"
                    showErrorAlert = true
                    return
                }
                _ = try await paymentStore.processCashPayment(
                    cart: cartItems, totals: totals, cashTendered: cashValue, sessionInfo: sessionInfo, customer: selectedCustomer,
                    loyaltyPointsRedeemed: pointsToRedeem, loyaltyDiscountAmount: loyaltyDiscount
                )
            case .split:
                guard let cashValue = Decimal(string: splitCashAmount), cashValue > 0 else {
                    errorMessage = "Enter cash amount"
                    showErrorAlert = true
                    return
                }
                let cardAmount = effectiveTotal - cashValue
                guard cardAmount > 0 else {
                    errorMessage = "Card amount must be > $0"
                    showErrorAlert = true
                    return
                }
                _ = try await paymentStore.processSplitPayment(
                    cart: cartItems, totals: totals, cashAmount: cashValue, cardAmount: cardAmount, sessionInfo: sessionInfo, customer: selectedCustomer,
                    loyaltyPointsRedeemed: pointsToRedeem, loyaltyDiscountAmount: loyaltyDiscount
                )
            case .multiCard:
                let splitResult = try await PaymentCalculatorService.shared.calculateSplitPercentage(total: effectiveTotal, percentage: card1Percentage)
                _ = try await paymentStore.processMultiCardPayment(
                    cart: cartItems, totals: totals, card1Amount: splitResult.amount1, card2Amount: splitResult.amount2, sessionInfo: sessionInfo, customer: selectedCustomer,
                    loyaltyPointsRedeemed: pointsToRedeem, loyaltyDiscountAmount: loyaltyDiscount
                )
            case .invoice:
                break
            }
        } catch {
            errorMessage = error.localizedDescription
            showErrorAlert = true
        }
    }

    private func sendInvoice() async {
        guard let customer = selectedCustomer else {
            errorMessage = "Customer required"
            showErrorAlert = true
            return
        }

        let emailRegex = #"^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        let emailToUse: String
        if let customerEmail = customer.email, !customerEmail.isEmpty {
            emailToUse = customerEmail
        } else if !invoiceEmail.isEmpty && invoiceEmail.range(of: emailRegex, options: .regularExpression) != nil {
            emailToUse = invoiceEmail
        } else {
            errorMessage = "Valid email required"
            showErrorAlert = true
            return
        }

        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            checkoutPhase = .processing
        }

        do {
            var invoiceItems: [InvoiceLineItem] = []
            for item in cartItems {
                let lineItem = try await InvoiceLineItem.create(
                    productId: item.productId, productName: item.productName,
                    quantity: item.quantity, unitPrice: item.unitPrice, taxRate: totals.taxRate
                )
                invoiceItems.append(lineItem)
            }

            let response = try await InvoiceService.sendInvoice(
                storeId: sessionInfo.storeId, customer: customer, customerName: customer.displayName, customerEmail: emailToUse,
                customerPhone: customer.phone, lineItems: invoiceItems, taxRate: totals.taxRate,
                notes: invoiceNotes.isEmpty ? nil : invoiceNotes, dueDate: invoiceDueDate, locationId: sessionInfo.locationId
            )

            if response.success, let invoice = response.invoice {
                var completion = SaleCompletion(
                    orderId: invoice.orderId, orderNumber: invoice.invoiceNumber, transactionNumber: invoice.invoiceNumber,
                    total: totals.total, paymentMethod: .invoice, completedAt: Date()
                )
                completion.paymentUrl = invoice.paymentUrl
                completion.invoiceNumber = invoice.invoiceNumber
                completedOrder = completion
                triggerAutoPrintIfEnabled(with: completion)
                LabelPrinterSettings.shared.stopPrewarming()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    checkoutPhase = .success
                }
                Haptics.success()
            } else {
                throw InvoiceError.serverError(response.error ?? "Unknown error")
            }
        } catch {
            errorMessage = error.localizedDescription
            showErrorAlert = true
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                checkoutPhase = .checkout
            }
        }
    }

    private func triggerAutoPrintIfEnabled(with completion: SaleCompletion?) {
        guard LabelPrinterSettings.shared.autoPrintEnabled, let orderId = completion?.orderId else { return }

        Task {
            do {
                let orderForLabels = await OrderStore.shared.orders.first { $0.id == orderId }
                guard let order = orderForLabels else { return }
                try await LabelPrinterManager.shared.printOrder(order)
            } catch {
                await MainActor.run { autoPrintFailed = true }
            }
        }
    }
}
