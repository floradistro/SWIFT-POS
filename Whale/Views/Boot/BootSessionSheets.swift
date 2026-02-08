//
//  BootSessionSheets.swift
//  Whale
//
//  Session management modals - end shift and safe drop.
//  Extracted from BootSheet for Apple engineering standards compliance.
//

import SwiftUI
import os.log

// MARK: - End Session Modal

struct BootEndSessionSheet: View {
    @EnvironmentObject private var session: SessionObserver
    @Environment(\.posWindowSession) private var windowSession: POSWindowSession?

    let posSession: POSSession
    let onDismiss: () -> Void
    let onEndShift: (Decimal) -> Void
    let onChangeRegister: () -> Void
    let onChangeLocation: () -> Void
    let onSignOut: () -> Void

    // Use window session's location/register if available, otherwise fall back to global
    private var displayLocation: Location? {
        windowSession?.location ?? session.selectedLocation
    }

    private var displayRegister: Register? {
        windowSession?.register ?? session.selectedRegister
    }

    enum SheetMode {
        case main
        case safeDrop
    }

    @State private var mode: SheetMode = .main
    @State private var closingCash = ""
    @State private var safeDropAmount = ""
    @State private var safeDropNotes = ""
    @State private var cashDrops: [CashDrop] = []
    @State private var modalScale: CGFloat = 0.9
    @State private var modalOpacity: CGFloat = 0
    @State private var contentOpacity: CGFloat = 0

    private var closingAmount: Decimal {
        Decimal(string: closingCash) ?? 0
    }

    private var safeDropDecimal: Decimal {
        Decimal(string: safeDropAmount) ?? 0
    }

    private var totalDropped: Decimal {
        cashDrops.reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        ZStack {
            // Dimmed background
            Design.Colors.backgroundPrimary.opacity(0.9)
                .ignoresSafeArea()
                .onTapGesture {
                    if mode == .safeDrop {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            mode = .main
                        }
                    } else {
                        onDismiss()
                    }
                }

            // Centered modal
            VStack {
                Spacer()

                VStack(spacing: 0) {
                    // Store logo at top
                    StoreLogo(
                        url: session.store?.fullLogoUrl,
                        size: 72,
                        storeName: session.store?.businessName
                    )
                    .padding(.top, 28)
                    .padding(.bottom, 16)

                    // Content based on mode
                    Group {
                        switch mode {
                        case .main:
                            mainContent
                        case .safeDrop:
                            safeDropContent
                        }
                    }
                    .opacity(contentOpacity)
                }
                .frame(maxWidth: 380)
                .background(modalBackground)
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                .shadow(color: .black.opacity(0.8), radius: 50, y: 20)
                .padding(.horizontal, 32)
                .scaleEffect(modalScale)
                .opacity(modalOpacity)

                Spacer()
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                modalScale = 1.0
                modalOpacity = 1.0
            }
            withAnimation(.easeOut(duration: 0.3).delay(0.1)) {
                contentOpacity = 1
            }
        }
    }

    // MARK: - Modal Background

    private var modalBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(Design.Colors.backgroundSecondary)

            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Design.Colors.Glass.regular,
                            Design.Colors.Glass.ultraThin,
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Design.Colors.Border.strong,
                            Design.Colors.Border.subtle,
                            Design.Colors.Border.regular
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        VStack(spacing: 0) {
            // Session info - uses window-specific location/register when available
            HStack(spacing: 6) {
                if let location = displayLocation {
                    Text(location.name)
                        .font(Design.Typography.caption1).fontWeight(.medium)
                }
                Text("•")
                if let register = displayRegister {
                    Text(register.displayName)
                        .font(Design.Typography.caption1).fontWeight(.medium)
                }
            }
            .foregroundStyle(Design.Colors.Text.subtle)
            .padding(.bottom, 8)

            // Show total dropped if any
            if totalDropped > 0 {
                Text("\(CurrencyFormatter.format(totalDropped)) dropped to safe")
                    .font(Design.Typography.caption2)
                    .foregroundStyle(Design.Colors.Semantic.success.opacity(0.8))
                    .padding(.bottom, 16)
            } else {
                Spacer().frame(height: 12)
            }

            // Closing cash section
            VStack(spacing: 12) {
                Text("Closing Cash")
                    .font(Design.Typography.footnote)
                    .foregroundStyle(Design.Colors.Text.disabled)

                // Amount input
                HStack {
                    Text("$")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(Design.Colors.Text.subtle)

                    TextField("0", text: $closingCash)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(Design.Colors.Text.primary)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .frame(width: 120)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Design.Colors.Border.subtle)
                )

                // Quick amounts
                HStack(spacing: 8) {
                    ForEach(["100", "200", "300", "500"], id: \.self) { amount in
                        Button {
                            Haptics.light()
                            closingCash = amount
                        } label: {
                            Text("$\(amount)")
                                .font(Design.Typography.caption1).fontWeight(.semibold)
                                .foregroundStyle(closingCash == amount ? Design.Colors.Text.primary : Design.Colors.Text.disabled)
                                .frame(maxWidth: .infinity)
                                .frame(height: 34)
                                .contentShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(ScaleButtonStyle())
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 10))
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)

            // Action buttons
            HStack(spacing: 10) {
                // Drop to Safe button
                Button {
                    Haptics.light()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        mode = .safeDrop
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.to.line.compact")
                            .font(Design.Typography.footnote).fontWeight(.medium)
                        Text("Safe")
                            .font(Design.Typography.footnote).fontWeight(.semibold)
                    }
                    .foregroundStyle(Design.Colors.Text.tertiary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .contentShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(ScaleButtonStyle())
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))

                // End Shift button - primary CTA with glass + white fill
                Button {
                    Haptics.medium()
                    onEndShift(closingAmount)
                } label: {
                    Text("End Shift")
                        .font(Design.Typography.callout).fontWeight(.semibold)
                        .foregroundStyle(Design.Colors.Text.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Design.Colors.Glass.ultraThick)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(ScaleButtonStyle())
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)

            // Divider
            Rectangle()
                .fill(Design.Colors.Glass.regular)
                .frame(height: 1)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)

            // Options
            VStack(spacing: 0) {
                sessionOptionButton(title: "Change Register") {
                    onChangeRegister()
                }

                sessionOptionButton(title: "Change Location") {
                    onChangeLocation()
                }

                sessionOptionButton(title: "Sign Out", isDestructive: true) {
                    onSignOut()
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            // Cancel
            Button {
                onDismiss()
            } label: {
                Text("Cancel")
                    .font(Design.Typography.footnote).fontWeight(.medium)
                    .foregroundStyle(Design.Colors.Text.placeholder)
            }
            .padding(.bottom, 20)
        }
    }

    // MARK: - Safe Drop Content

    private var safeDropContent: some View {
        VStack(spacing: 0) {
            // Back button
            HStack {
                Button {
                    Haptics.light()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        mode = .main
                        safeDropAmount = ""
                        safeDropNotes = ""
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(Design.Typography.caption1).fontWeight(.semibold)
                        Text("Back")
                            .font(Design.Typography.footnote).fontWeight(.medium)
                    }
                    .foregroundStyle(Design.Colors.Text.disabled)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            // Title
            Text("Drop to Safe")
                .font(Design.Typography.headline).fontWeight(.bold)
                .foregroundStyle(Design.Colors.Text.primary)
                .padding(.bottom, 20)

            // Amount input
            VStack(spacing: 12) {
                HStack {
                    Text("$")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(Design.Colors.Text.subtle)

                    TextField("0", text: $safeDropAmount)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(Design.Colors.Text.primary)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .frame(width: 120)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Design.Colors.Border.subtle)
                )

                // Quick amounts
                HStack(spacing: 8) {
                    ForEach(["100", "200", "500", "1000"], id: \.self) { amount in
                        Button {
                            Haptics.light()
                            safeDropAmount = amount
                        } label: {
                            Text("$\(amount)")
                                .font(Design.Typography.caption1).fontWeight(.semibold)
                                .foregroundStyle(safeDropAmount == amount ? Design.Colors.Text.primary : Design.Colors.Text.disabled)
                                .frame(maxWidth: .infinity)
                                .frame(height: 34)
                                .contentShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(ScaleButtonStyle())
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 10))
                    }
                }

                // Notes (optional)
                TextField("Notes (optional)", text: $safeDropNotes)
                    .font(Design.Typography.footnote)
                    .foregroundStyle(Design.Colors.Text.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .glassEffect(.regular, in: .rect(cornerRadius: 12))
                    .padding(.top, 4)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)

            // Drop button - primary CTA with glass + white fill
            Button {
                Haptics.success()
                performSafeDrop()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.to.line.compact")
                        .font(Design.Typography.footnote).fontWeight(.medium)
                    Text("Drop \(safeDropDecimal > 0 ? CurrencyFormatter.format(safeDropDecimal) : "$0.00")")
                        .font(Design.Typography.callout).fontWeight(.semibold)
                }
                .foregroundStyle(safeDropDecimal > 0 ? Design.Colors.Text.primary : Design.Colors.Text.subtle)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(safeDropDecimal > 0 ? Design.Colors.Semantic.accent : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(ScaleButtonStyle())
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
            .disabled(safeDropDecimal <= 0)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Actions

    private func performSafeDrop() {
        guard safeDropDecimal > 0 else { return }

        let drop = CashDrop.create(
            sessionId: posSession.id,
            locationId: posSession.locationId,
            registerId: posSession.registerId,
            userId: session.userId,
            amount: safeDropDecimal,
            notes: safeDropNotes.isEmpty ? nil : safeDropNotes
        )

        cashDrops.append(drop)

        // Reset and go back
        safeDropAmount = ""
        safeDropNotes = ""

        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            mode = .main
        }
    }

    private func sessionOptionButton(
        title: String,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(Design.Typography.footnote).fontWeight(.medium)
                .foregroundStyle(isDestructive ? Design.Colors.Semantic.error.opacity(0.8) : Design.Colors.Text.disabled)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
        }
    }
}

// MARK: - Safe Drop Modal (Standalone - for use during shift)

struct BootSafeDropSheet: View {
    @EnvironmentObject private var session: SessionObserver
    @Environment(\.posWindowSession) private var windowSession: POSWindowSession?

    let posSession: POSSession
    @Binding var isPresented: Bool

    // Use window session's location/register if available, otherwise fall back to global
    private var displayLocation: Location? {
        windowSession?.location ?? session.selectedLocation
    }

    private var displayRegister: Register? {
        windowSession?.register ?? session.selectedRegister
    }

    @State private var amount = ""
    @State private var notes = ""
    @State private var modalScale: CGFloat = 0.9
    @State private var modalOpacity: CGFloat = 0
    @State private var contentOpacity: CGFloat = 0
    @State private var showSuccess = false

    private var amountDecimal: Decimal {
        Decimal(string: amount) ?? 0
    }

    var body: some View {
        ZStack {
            // Dimmed background
            Design.Colors.backgroundPrimary.opacity(0.9)
                .ignoresSafeArea()
                .onTapGesture {
                    dismiss()
                }

            // Centered modal
            VStack {
                Spacer()

                VStack(spacing: 0) {
                    // Store logo at top
                    StoreLogo(
                        url: session.store?.fullLogoUrl,
                        size: 72,
                        storeName: session.store?.businessName
                    )
                    .padding(.top, 28)
                    .padding(.bottom, 16)

                    // Content
                    if showSuccess {
                        successContent
                    } else {
                        dropContent
                    }
                }
                .frame(maxWidth: 380)
                .background(modalBackground)
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                .shadow(color: .black.opacity(0.8), radius: 50, y: 20)
                .padding(.horizontal, 32)
                .scaleEffect(modalScale)
                .opacity(modalOpacity)

                Spacer()
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                modalScale = 1.0
                modalOpacity = 1.0
            }
            withAnimation(.easeOut(duration: 0.3).delay(0.1)) {
                contentOpacity = 1
            }
        }
    }

    // MARK: - Modal Background

    private var modalBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(Design.Colors.backgroundSecondary)

            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Design.Colors.Glass.regular,
                            Design.Colors.Glass.ultraThin,
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Design.Colors.Border.strong,
                            Design.Colors.Border.subtle,
                            Design.Colors.Border.regular
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
    }

    // MARK: - Drop Content

    private var dropContent: some View {
        VStack(spacing: 0) {
            // Title
            Text("Drop to Safe")
                .font(Design.Typography.title2).fontWeight(.bold)
                .foregroundStyle(Design.Colors.Text.primary)
                .padding(.bottom, 8)

            // Session info - uses window-specific location/register when available
            HStack(spacing: 6) {
                if let location = displayLocation {
                    Text(location.name)
                        .font(Design.Typography.caption1).fontWeight(.medium)
                }
                Text("•")
                if let register = displayRegister {
                    Text(register.displayName)
                        .font(Design.Typography.caption1).fontWeight(.medium)
                }
            }
            .foregroundStyle(Design.Colors.Text.subtle)
            .padding(.bottom, 24)

            // Amount input
            VStack(spacing: 12) {
                HStack {
                    Text("$")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(Design.Colors.Text.subtle)

                    TextField("0", text: $amount)
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(Design.Colors.Text.primary)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .frame(width: 140)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Design.Colors.Border.subtle)
                )

                // Quick amounts
                HStack(spacing: 10) {
                    ForEach(["100", "200", "500", "1000"], id: \.self) { quickAmount in
                        Button {
                            Haptics.light()
                            amount = quickAmount
                        } label: {
                            Text("$\(quickAmount)")
                                .font(Design.Typography.subhead).fontWeight(.semibold)
                                .foregroundStyle(amount == quickAmount ? Design.Colors.Text.primary : Design.Colors.Text.disabled)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .contentShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(ScaleButtonStyle())
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
                    }
                }

                // Notes (optional)
                TextField("Notes (optional)", text: $notes)
                    .font(Design.Typography.footnote)
                    .foregroundStyle(Design.Colors.Text.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .glassEffect(.regular, in: .rect(cornerRadius: 12))
                    .padding(.top, 4)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)

            // Drop button - primary CTA with glass + white fill
            Button {
                performDrop()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.to.line.compact")
                        .font(Design.Typography.callout).fontWeight(.medium)
                    Text("Drop \(amountDecimal > 0 ? CurrencyFormatter.format(amountDecimal) : "$0")")
                        .font(Design.Typography.headline)
                }
                .foregroundStyle(amountDecimal > 0 ? Design.Colors.Text.primary : Design.Colors.Text.subtle)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(amountDecimal > 0 ? Design.Colors.Semantic.accent : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(ScaleButtonStyle())
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
            .disabled(amountDecimal <= 0)
            .padding(.horizontal, 24)
            .padding(.bottom, 16)

            // Cancel
            Button {
                dismiss()
            } label: {
                Text("Cancel")
                    .font(Design.Typography.footnote).fontWeight(.medium)
                    .foregroundStyle(Design.Colors.Text.placeholder)
            }
            .padding(.bottom, 24)
        }
        .opacity(contentOpacity)
    }

    // MARK: - Success Content

    private var successContent: some View {
        VStack(spacing: 20) {
            // Checkmark
            ZStack {
                Circle()
                    .fill(Design.Colors.Semantic.success.opacity(0.2))
                    .frame(width: 80, height: 80)

                Image(systemName: "checkmark")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(Design.Colors.Semantic.success)
            }

            Text("Dropped to Safe")
                .font(Design.Typography.title3).fontWeight(.bold)
                .foregroundStyle(Design.Colors.Text.primary)

            Text(CurrencyFormatter.format(amountDecimal))
                .font(Design.Typography.title2Rounded).fontWeight(.bold)
                .foregroundStyle(Design.Colors.Text.tertiary)

            if !notes.isEmpty {
                Text(notes)
                    .font(Design.Typography.footnote)
                    .foregroundStyle(Design.Colors.Text.subtle)
            }
        }
        .padding(.vertical, 40)
        .padding(.horizontal, 24)
        .opacity(contentOpacity)
    }

    // MARK: - Actions

    private func performDrop() {
        guard amountDecimal > 0 else { return }

        Haptics.success()

        // Update window session drawer balance (isolated mode)
        if let ws = windowSession, ws.location != nil {
            Task {
                do {
                    try await ws.performSafeDrop(
                        amount: amountDecimal,
                        notes: notes.isEmpty ? nil : notes
                    )
                } catch {
                    Log.session.error("Safe drop failed: \(error)")
                }
            }
        }

        // Also create legacy CashDrop record for database persistence
        _ = CashDrop.create(
            sessionId: posSession.id,
            locationId: posSession.locationId,
            registerId: posSession.registerId,
            userId: session.userId,
            amount: amountDecimal,
            notes: notes.isEmpty ? nil : notes
        )

        // Show success
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            showSuccess = true
        }

        // Dismiss after delay
        Task { @MainActor in try? await Task.sleep(for: .seconds(1.5));
            dismiss()
        }
    }

    private func dismiss() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            modalScale = 0.9
            modalOpacity = 0
        }
        Task { @MainActor in try? await Task.sleep(for: .seconds(0.2));
            isPresented = false
        }
    }
}
