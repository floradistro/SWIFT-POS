//
//  OpenCashDrawerModal.swift
//  Whale
//
//  Cash drawer count modal - uses UnifiedModal.
//  Entry point to POS - matches Dock checkout style.
//

import SwiftUI

struct OpenCashDrawerModal: View {
    @Binding var isPresented: Bool
    let onSubmit: (Decimal, String) -> Void

    @State private var openingCash = ""
    @State private var notes = ""
    @FocusState private var isAmountFocused: Bool

    private var hasAmount: Bool {
        guard let value = Decimal(string: openingCash) else { return false }
        return value >= 0
    }

    private var displayAmount: String {
        if let value = Decimal(string: openingCash), value > 0 {
            return CurrencyFormatter.format(value)
        }
        return "$0.00"
    }

    var body: some View {
        UnifiedModal(isPresented: $isPresented, id: "open-cash-drawer") {
            VStack(spacing: 0) {
                // Header with amount as hero
                ModalHeader(displayAmount, subtitle: "Opening Amount", onClose: dismissModal)

                VStack(spacing: 16) {
                    // Amount input section
                    ModalSection {
                        VStack(alignment: .leading, spacing: 10) {
                            ModalSectionLabel("Starting Amount")
                            ModalCurrencyInput(amount: $openingCash)
                                .focused($isAmountFocused)
                        }
                    }

                    // Quick amounts
                    ModalQuickButtons(
                        options: ["$100", "$200", "$300", "$500"],
                        selected: openingCash.isEmpty ? nil : "$\(openingCash)"
                    ) { option in
                        openingCash = String(option.dropFirst())
                    }

                    // Notes input
                    ModalTextInput(placeholder: "Notes (optional)", text: $notes, icon: "note.text")
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)

                // Action buttons
                HStack(spacing: 12) {
                    ModalSecondaryButton(title: "Cancel", action: dismissModal)
                    ModalActionButton("Start Shift", icon: "play.fill", isEnabled: hasAmount) {
                        submitAndDismiss()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .onAppear {
            Task {
                try? await Task.sleep(for: .milliseconds(400))
                isAmountFocused = true
            }
        }
    }

    private func dismissModal() {
        openingCash = ""
        notes = ""
        isPresented = false
    }

    private func submitAndDismiss() {
        let amount = Decimal(string: openingCash) ?? 0
        let notesCopy = notes
        Haptics.success()
        onSubmit(amount, notesCopy)
        openingCash = ""
        notes = ""
        isPresented = false
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        OpenCashDrawerModal(isPresented: .constant(true)) { _, _ in
            // Preview callback
        }
    }
    .preferredColorScheme(.dark)
}
