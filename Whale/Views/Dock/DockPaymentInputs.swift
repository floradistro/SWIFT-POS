//  DockPaymentInputs.swift - Payment method input views
//  Backend-driven: Cash suggestions come from server-side Edge Function.

import SwiftUI
import os.log

// MARK: - Card Payment Input

struct CardPaymentInput: View {
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Design.Colors.Semantic.success.opacity(0.2))
                    .frame(width: 36, height: 36)
                Circle()
                    .fill(Design.Colors.Semantic.success)
                    .frame(width: 10, height: 10)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Terminal Ready")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Tap, insert, or swipe card")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            }

            Spacer()

            Image(systemName: "wave.3.right")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Design.Colors.Semantic.success.opacity(0.7))
                .symbolEffect(.pulse, options: .repeating)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }
}

// MARK: - Cash Payment Input

struct CashPaymentInput: View {
    @Binding var cashAmount: String
    let total: Decimal

    @State private var suggestions: [Decimal] = []
    @State private var exactAmount: Decimal = 0
    private let logger = Logger(subsystem: "com.whale.pos", category: "CashPayment")

    private var selectedAmount: Decimal? {
        guard let value = Decimal(string: cashAmount) else { return nil }
        return value
    }

    private var changeAmount: Decimal? {
        guard let cashValue = Decimal(string: cashAmount), cashValue >= total else { return nil }
        return cashValue - total
    }

    var body: some View {
        VStack(spacing: 14) {
            // Amount input field
            HStack(spacing: 8) {
                Text("$")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))
                TextField("0.00", text: $cashAmount)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
                    .keyboardType(.decimalPad)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .glassEffect(.regular, in: .rect(cornerRadius: 14))

            // Smart quick amount buttons - 2x2 grid (backend-driven)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(suggestions, id: \.self) { amount in
                    let isSelected = selectedAmount == amount
                    let isExact = amount == exactAmount

                    Button {
                        Haptics.light()
                        if isExact {
                            cashAmount = String(format: "%.2f", NSDecimalNumber(decimal: exactAmount).doubleValue)
                        } else {
                            cashAmount = String(format: "%.0f", NSDecimalNumber(decimal: amount).doubleValue)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if isExact {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(isSelected ? Design.Colors.Semantic.success : .white.opacity(0.6))
                            }
                            Text(isExact ? "Exact" : CurrencyFormatter.format(amount))
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundStyle(isSelected ? .white : .white.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                    }
                    .tint(.white)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
                }
            }

            // Change display
            if let change = changeAmount {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.turn.down.left")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Design.Colors.Semantic.success.opacity(0.7))
                        Text("Change Due")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    Spacer()
                    Text(CurrencyFormatter.format(change))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(Design.Colors.Semantic.success)
                }
                .padding(.horizontal, 4)
                .padding(.top, 2)
            }
        }
        .onAppear {
            Task { await loadCashSuggestions() }
        }
        .onChange(of: total) { _, _ in
            Task { await loadCashSuggestions() }
        }
    }

    private func loadCashSuggestions() async {
        do {
            let result = try await PaymentCalculatorService.shared.getCashSuggestions(for: total)
            await MainActor.run {
                suggestions = result.suggestions
                exactAmount = result.exactAmount
            }
        } catch {
            logger.error("Failed to load cash suggestions: \(error.localizedDescription)")
            // Fallback to reasonable defaults
            await MainActor.run {
                exactAmount = total.rounded()
                suggestions = [exactAmount, 20, 50, 100]
            }
        }
    }
}

// MARK: - Split Payment Input

struct SplitPaymentInput: View {
    @Binding var splitCashAmount: String
    let total: Decimal

    @State private var cardAmount: Decimal = 0
    @State private var isValid = false
    private let logger = Logger(subsystem: "com.whale.pos", category: "SplitPaymentInput")

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                // Cash input
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        Image(systemName: "banknote")
                            .font(.system(size: 11, weight: .medium))
                        Text("CASH")
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(0.5)
                    }
                    .foregroundStyle(.white.opacity(0.5))

                    HStack(spacing: 4) {
                        Text("$")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white.opacity(0.4))
                        TextField("0.00", text: $splitCashAmount)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                            .keyboardType(.decimalPad)
                            .onChange(of: splitCashAmount) { _, newValue in
                                Task { await handleCashInput(newValue) }
                            }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .glassEffect(.regular, in: .rect(cornerRadius: 12))
                }

                // Card display (backend calculated)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        Image(systemName: "creditcard")
                            .font(.system(size: 11, weight: .medium))
                        Text("CARD")
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(0.5)
                    }
                    .foregroundStyle(.white.opacity(0.5))

                    Text(CurrencyFormatter.format(cardAmount))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(cardAmount > 0 ? .white : .white.opacity(0.4))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassEffect(.regular, in: .rect(cornerRadius: 12))
                }
            }

            // Quick split buttons - backend calculates
            HStack(spacing: 8) {
                splitButton("50/50", preset: .fiftyFifty)
                splitButton("$20", preset: .twenty)
                splitButton("$50", preset: .fifty)
                splitButton("$100", preset: .hundred)
            }
        }
        .onAppear {
            Task { await applyPreset(.fiftyFifty) }
        }
    }

    private func splitButton(_ label: String, preset: SplitPreset) -> some View {
        Button {
            Haptics.light()
            Task { await applyPreset(preset) }
        } label: {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
        }
        .tint(.white)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 10))
    }

    private func applyPreset(_ preset: SplitPreset) async {
        do {
            let result = try await PaymentCalculatorService.shared.calculateSplit(
                total: total,
                splitType: .cashCard,
                preset: preset
            )
            await MainActor.run {
                splitCashAmount = String(format: "%.2f", NSDecimalNumber(decimal: result.amount1).doubleValue)
                cardAmount = result.amount2
                isValid = result.isValid
            }
        } catch {
            logger.error("Failed to apply split preset: \(error.localizedDescription)")
        }
    }

    private func handleCashInput(_ value: String) async {
        let cleaned = value.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "")
        guard let parsed = Decimal(string: cleaned) else {
            cardAmount = total
            return
        }
        do {
            let result = try await PaymentCalculatorService.shared.calculateSplit(
                total: total,
                splitType: .cashCard,
                editedField: .amount1,
                editedValue: parsed
            )
            await MainActor.run {
                cardAmount = result.amount2
                isValid = result.isValid
            }
        } catch {
            logger.error("Failed to calculate split: \(error.localizedDescription)")
        }
    }
}

// MARK: - Multi Card Payment Input

struct MultiCardPaymentInput: View {
    @Binding var card1Percentage: Double
    let total: Decimal

    @State private var card1Amount: Decimal = 0
    @State private var card2Amount: Decimal = 0
    @State private var isValid = false
    private let logger = Logger(subsystem: "com.whale.pos", category: "MultiCardPaymentInput")

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                // Card 1 (backend calculated)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        Image(systemName: "1.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text("CARD 1")
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(0.5)
                    }
                    .foregroundStyle(Design.Colors.Semantic.accent.opacity(0.8))

                    Text(CurrencyFormatter.format(card1Amount))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassEffect(.regular, in: .rect(cornerRadius: 12))
                }

                // Card 2 (backend calculated)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        Image(systemName: "2.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text("CARD 2")
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(0.5)
                    }
                    .foregroundStyle(.white.opacity(0.5))

                    Text(CurrencyFormatter.format(card2Amount))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassEffect(.regular, in: .rect(cornerRadius: 12))
                }
            }

            // Quick split buttons - backend calculates
            HStack(spacing: 8) {
                splitButton("50/50", preset: .fiftyFifty)
                splitButton("60/40", preset: .sixtyForty)
                splitButton("70/30", preset: .seventyThirty)
                splitButton("80/20", preset: .eightyTwenty)
            }
        }
        .onAppear {
            Task { await applyPreset(.fiftyFifty) }
        }
    }

    private func splitButton(_ label: String, preset: SplitPreset) -> some View {
        Button {
            Haptics.light()
            Task { await applyPreset(preset) }
        } label: {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
        }
        .tint(.white)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 10))
    }

    private func applyPreset(_ preset: SplitPreset) async {
        do {
            let result = try await PaymentCalculatorService.shared.calculateSplit(
                total: total,
                splitType: .multiCard,
                preset: preset
            )
            await MainActor.run {
                card1Amount = result.amount1
                card2Amount = result.amount2
                isValid = result.isValid
            }
            // Backend calculates percentage from amount
            let percentResult = try await PaymentCalculatorService.shared.calculatePercentageFromAmount(
                total: total,
                amount: result.amount1
            )
            await MainActor.run {
                card1Percentage = percentResult.percentage
            }
        } catch {
            logger.error("Failed to apply multi-card preset: \(error.localizedDescription)")
        }
    }
}

// MARK: - Invoice Payment Input

struct InvoicePaymentInput: View {
    let customer: Customer?
    @Binding var invoiceEmail: String
    @Binding var invoiceDueDate: Date
    @Binding var invoiceNotes: String
    @Binding var showDueDatePicker: Bool
    let onAddCustomer: () -> Void

    private var dueDateLabel: String {
        let days = Calendar.current.dateComponents([.day], from: Date(), to: invoiceDueDate).day ?? 0
        if days == 0 { return "Today" }
        if days == 1 { return "Tomorrow" }
        if days == 7 { return "1 week" }
        if days == 14 { return "2 weeks" }
        if days == 30 { return "1 month" }
        return "\(days) days"
    }

    var body: some View {
        VStack(spacing: 14) {
            customerEmailSection
            dueDateSection
            notesSection
        }
    }

    @ViewBuilder
    private var customerEmailSection: some View {
        if let customer = customer {
            if let email = customer.email, !email.isEmpty {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Design.Colors.Semantic.success.opacity(0.2))
                            .frame(width: 40, height: 40)
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Design.Colors.Semantic.success)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("SENDING TO")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(0.5)
                            .foregroundStyle(.white.opacity(0.4))
                        Text(email)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                    }

                    Spacer()
                }
                .padding(14)
                .glassEffect(.regular, in: .rect(cornerRadius: 14))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "envelope")
                            .font(.system(size: 12, weight: .medium))
                        Text("EMAIL ADDRESS")
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(0.5)
                    }
                    .foregroundStyle(.white.opacity(0.5))

                    TextField("Enter customer email...", text: $invoiceEmail)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .padding(14)
                        .glassEffect(.regular, in: .rect(cornerRadius: 12))
                }
            }
        } else {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Design.Colors.Semantic.warning.opacity(0.2))
                        .frame(width: 40, height: 40)
                    Image(systemName: "person.crop.circle.badge.exclamationmark")
                        .font(.system(size: 18))
                        .foregroundStyle(Design.Colors.Semantic.warning)
                }

                Text("Add a customer to send invoice")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))

                Spacer()

                Button {
                    Haptics.light()
                    onAddCustomer()
                } label: {
                    Text("Add")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                }
                .tint(.white)
                .glassEffect(.regular.interactive(), in: .capsule)
            }
            .padding(14)
            .glassEffect(.regular, in: .rect(cornerRadius: 14))
        }
    }

    private var dueDateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 12, weight: .medium))
                Text("DUE DATE")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.5)
            }
            .foregroundStyle(.white.opacity(0.5))

            Button {
                showDueDatePicker.toggle()
                Haptics.light()
            } label: {
                HStack {
                    Text(invoiceDueDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 15, weight: .semibold))

                    Spacer()

                    Text(dueDateLabel)
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .glassEffect(.regular, in: .capsule)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                        .rotationEffect(.degrees(showDueDatePicker ? 180 : 0))
                }
                .foregroundStyle(.white)
                .padding(14)
            }
            .tint(.white)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))

            if showDueDatePicker {
                DatePicker("", selection: $invoiceDueDate, in: Date()..., displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(Design.Colors.Semantic.accent)
                    .colorScheme(.dark)
                    .padding(10)
                    .glassEffect(.regular, in: .rect(cornerRadius: 14))
            }
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "note.text")
                    .font(.system(size: 12, weight: .medium))
                Text("NOTES (OPTIONAL)")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.5)
            }
            .foregroundStyle(.white.opacity(0.5))

            TextField("Add notes for the customer...", text: $invoiceNotes)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .padding(14)
                .glassEffect(.regular, in: .rect(cornerRadius: 12))
        }
    }
}
