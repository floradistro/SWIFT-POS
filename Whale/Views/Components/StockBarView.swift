//  StockBarView.swift - Stock bar with inline quick audit

import SwiftUI

// MARK: - Quick Audit Reason

enum QuickAuditReason: String, CaseIterable {
    case count, damaged, shrinkage, returned, received, adjustment

    var displayName: String {
        switch self {
        case .count: return "Count"
        case .damaged: return "Damaged"
        case .shrinkage: return "Shrinkage"
        case .returned: return "Returned"
        case .received: return "Received"
        case .adjustment: return "Adjustment"
        }
    }

    var icon: String {
        switch self {
        case .count: return "number"
        case .damaged: return "exclamationmark.triangle"
        case .shrinkage: return "arrow.down.circle"
        case .returned: return "arrow.uturn.backward"
        case .received: return "arrow.down.to.line"
        case .adjustment: return "slider.horizontal.3"
        }
    }

    var toAdjustmentType: AdjustmentType {
        switch self {
        case .count: return .countCorrection
        case .damaged: return .damage
        case .shrinkage: return .shrinkage
        case .returned: return .returnAdjustment
        case .received: return .received
        case .adjustment: return .other
        }
    }
}

// MARK: - Stock Bar Row

struct StockBarRow: View {
    let value: Double
    let maxValue: Double
    let label: String
    let color: Color
    let isEditing: Bool
    let isSubmitting: Bool
    let isSuccess: Bool
    let errorMessage: String?
    @Binding var editValue: String
    @Binding var auditReason: QuickAuditReason
    let onTapToEdit: () -> Void
    let onSave: () -> Void
    let onCancel: () -> Void

    @FocusState private var isFocused: Bool

    private var percentage: CGFloat {
        guard value > 0, maxValue > 0 else { return 0 }
        return min(1, max(0.05, value / maxValue))
    }

    private var displayColor: Color {
        if isSuccess { return .green }
        if value <= 10 && value > 0 { return .orange }
        return color
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isEditing {
                editingView
            } else {
                displayView
            }

            if let error = errorMessage {
                Text(error)
                    .font(Design.Typography.caption2)
                    .foregroundStyle(.red)
            }
        }
    }

    private var displayView: some View {
        Button(action: onTapToEdit) {
            HStack(spacing: 8) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.1))
                        RoundedRectangle(cornerRadius: 4)
                            .fill(displayColor.opacity(0.6))
                            .frame(width: geo.size.width * percentage)
                    }
                }
                .frame(height: 8)

                Text("\(formatValue(value)) \(label)")
                    .font(Design.Typography.caption1).fontWeight(.medium)
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(minWidth: 80, alignment: .trailing)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(formatValue(value)) \(label)")
        .accessibilityHint("Double tap to edit quantity")
    }

    private var editingView: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                TextField("Qty", text: $editValue)
                    .keyboardType(.decimalPad)
                    .font(Design.Typography.callout).fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.1)))
                    .focused($isFocused)
                    .onAppear { isFocused = true }

                if isSubmitting {
                    ProgressView().tint(.white)
                } else if isSuccess {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(Design.Typography.title3)
                        .accessibilityLabel("Saved successfully")
                } else {
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .font(Design.Typography.footnote).fontWeight(.semibold)
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Color.white.opacity(0.1)))
                    }
                    .accessibilityLabel("Cancel")
                    Button(action: onSave) {
                        Image(systemName: "checkmark")
                            .font(Design.Typography.footnote).fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Color.white.opacity(0.15)))
                    }
                    .accessibilityLabel("Save quantity")
                }
            }

            // Reason picker
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(QuickAuditReason.allCases, id: \.self) { reason in
                        Button {
                            auditReason = reason
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: reason.icon)
                                    .font(Design.Typography.caption2)
                                Text(reason.displayName)
                                    .font(Design.Typography.caption2).fontWeight(.medium)
                            }
                            .foregroundStyle(auditReason == reason ? .white : .white.opacity(0.5))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(auditReason == reason ? Design.Colors.Semantic.accent.opacity(0.3) : Color.white.opacity(0.05))
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(reason.displayName)
                        .accessibilityAddTraits(auditReason == reason ? .isSelected : [])
                    }
                }
            }
        }
    }

    private func formatValue(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", v) : String(format: "%.1f", v)
    }
}
