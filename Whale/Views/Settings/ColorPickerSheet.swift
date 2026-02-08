//
//  ColorPickerSheet.swift
//  Whale
//
//  SwiftUI ColorPicker wrapper sheet for custom accent color selection.
//

import SwiftUI

struct ColorPickerSheet: View {
    let currentColor: Color
    let onApply: (Color) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedColor: Color

    init(currentColor: Color, onApply: @escaping (Color) -> Void) {
        self.currentColor = currentColor
        self.onApply = onApply
        self._selectedColor = State(initialValue: currentColor)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Preview swatch
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(selectedColor)
                    .frame(height: 80)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Design.Colors.Border.regular, lineWidth: 1)
                    )

                // Native color picker
                ColorPicker("Select Color", selection: $selectedColor, supportsOpacity: false)
                    .font(Design.Typography.subhead).fontWeight(.medium)
                    .foregroundStyle(Design.Colors.Text.primary)

                Spacer()
            }
            .padding(20)
            .navigationTitle("Custom Color")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        onApply(selectedColor)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
