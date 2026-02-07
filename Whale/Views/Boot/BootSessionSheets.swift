//
//  BootSessionSheets.swift
//  Whale
//
//  Session management modals - end shift and safe drop.
//  Extracted from BootSheet for Apple engineering standards compliance.
//

import SwiftUI

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
            Color.black.opacity(0.85)
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
                .fill(Color(white: 0.08))

            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.06),
                            Color.white.opacity(0.02),
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
                            Color.white.opacity(0.15),
                            Color.white.opacity(0.05),
                            Color.white.opacity(0.08)
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
                        .font(.system(size: 12, weight: .medium))
                }
                Text("•")
                if let register = displayRegister {
                    Text(register.displayName)
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .foregroundStyle(.white.opacity(0.4))
            .padding(.bottom, 8)

            // Show total dropped if any
            if totalDropped > 0 {
                Text("\(CurrencyFormatter.format(totalDropped)) dropped to safe")
                    .font(.system(size: 11))
                    .foregroundStyle(Design.Colors.Semantic.success.opacity(0.8))
                    .padding(.bottom, 16)
            } else {
                Spacer().frame(height: 12)
            }

            // Closing cash section
            VStack(spacing: 12) {
                Text("Closing Cash")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))

                // Amount input
                HStack {
                    Text("$")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.white.opacity(0.4))

                    TextField("0", text: $closingCash)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.white)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .frame(width: 120)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.white.opacity(0.06))
                )

                // Quick amounts
                HStack(spacing: 8) {
                    ForEach(["100", "200", "300", "500"], id: \.self) { amount in
                        Button {
                            Haptics.light()
                            closingCash = amount
                        } label: {
                            Text("$\(amount)")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(closingCash == amount ? .white : .white.opacity(0.6))
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
                            .font(.system(size: 14, weight: .medium))
                        Text("Safe")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(.white.opacity(0.8))
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
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.white.opacity(0.15))
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
                .fill(.white.opacity(0.08))
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
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
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
                            .font(.system(size: 12, weight: .semibold))
                        Text("Back")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            // Title
            Text("Drop to Safe")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .padding(.bottom, 20)

            // Amount input
            VStack(spacing: 12) {
                HStack {
                    Text("$")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.white.opacity(0.4))

                    TextField("0", text: $safeDropAmount)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.white)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .frame(width: 120)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.white.opacity(0.06))
                )

                // Quick amounts
                HStack(spacing: 8) {
                    ForEach(["100", "200", "500", "1000"], id: \.self) { amount in
                        Button {
                            Haptics.light()
                            safeDropAmount = amount
                        } label: {
                            Text("$\(amount)")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(safeDropAmount == amount ? .white : .white.opacity(0.6))
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
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
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
                        .font(.system(size: 14, weight: .medium))
                    Text("Drop \(safeDropDecimal > 0 ? CurrencyFormatter.format(safeDropDecimal) : "$0.00")")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(safeDropDecimal > 0 ? .black : .white.opacity(0.4))
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(safeDropDecimal > 0 ? Color.white : Color.clear)
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
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isDestructive ? Design.Colors.Semantic.error.opacity(0.8) : .white.opacity(0.5))
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
            Color.black.opacity(0.85)
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
                .fill(Color(white: 0.08))

            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.06),
                            Color.white.opacity(0.02),
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
                            Color.white.opacity(0.15),
                            Color.white.opacity(0.05),
                            Color.white.opacity(0.08)
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
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .padding(.bottom, 8)

            // Session info - uses window-specific location/register when available
            HStack(spacing: 6) {
                if let location = displayLocation {
                    Text(location.name)
                        .font(.system(size: 12, weight: .medium))
                }
                Text("•")
                if let register = displayRegister {
                    Text(register.displayName)
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .foregroundStyle(.white.opacity(0.4))
            .padding(.bottom, 24)

            // Amount input
            VStack(spacing: 12) {
                HStack {
                    Text("$")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(.white.opacity(0.4))

                    TextField("0", text: $amount)
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(.white)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .frame(width: 140)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.white.opacity(0.06))
                )

                // Quick amounts
                HStack(spacing: 10) {
                    ForEach(["100", "200", "500", "1000"], id: \.self) { quickAmount in
                        Button {
                            Haptics.light()
                            amount = quickAmount
                        } label: {
                            Text("$\(quickAmount)")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(amount == quickAmount ? .white : .white.opacity(0.6))
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
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
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
                        .font(.system(size: 16, weight: .medium))
                    Text("Drop \(amountDecimal > 0 ? CurrencyFormatter.format(amountDecimal) : "$0")")
                        .font(.system(size: 17, weight: .semibold))
                }
                .foregroundStyle(amountDecimal > 0 ? .black : .white.opacity(0.4))
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(amountDecimal > 0 ? Color.white : Color.clear)
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
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
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
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)

            Text(CurrencyFormatter.format(amountDecimal))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))

            if !notes.isEmpty {
                Text(notes)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.4))
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
                    print("Safe drop failed: \(error)")
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            dismiss()
        }
    }

    private func dismiss() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            modalScale = 0.9
            modalOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            isPresented = false
        }
    }
}
