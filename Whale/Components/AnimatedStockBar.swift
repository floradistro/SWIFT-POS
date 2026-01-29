//
//  AnimatedStockBar.swift
//  Whale
//
//  Elegant animated stock level indicator with Apple-quality animations.
//  Used in tier selector to show parent and variant inventory levels.
//

import SwiftUI

struct AnimatedStockBar: View {
    let value: Double
    let maxValue: Double
    let label: String
    let color: Color
    var lowThreshold: Double = 10
    var delay: Double = 0
    var isVariant: Bool = false

    // Calculate percentage (min 5% if value > 0 for visibility)
    private var percentage: CGFloat {
        if value <= 0 { return 0 }
        let pct = value / max(maxValue, value, 1) * 100
        return min(100, max(5, pct)) / 100
    }

    private var isLow: Bool {
        value <= lowThreshold && value > 0
    }

    private var displayColor: Color {
        // For variants, always use the passed color (red)
        // For parent stock, use yellow when low
        if isVariant {
            return color
        }
        return isLow ? Color(hex: "fbbf24") : color
    }

    var body: some View {
        HStack(spacing: 10) {
            // Track with fill
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track background
                    Capsule()
                        .fill(Color.white.opacity(0.08))

                    // Fill
                    Capsule()
                        .fill(displayColor)
                        .frame(width: geo.size.width * percentage)
                }
            }
            .frame(height: isVariant ? 3 : 4)

            // Label
            Text(label)
                .font(.system(size: isVariant ? 11 : 12, weight: .semibold))
                .foregroundStyle(displayColor)
                .lineLimit(1)
                .frame(minWidth: isVariant ? 60 : 80, alignment: .leading)
        }
    }
}

// MARK: - Variant Inventory Display

struct VariantInventoryDisplay: View {
    let parentStock: Double
    let parentUnit: String
    let variantInventories: [VariantInventoryItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Parent stock bar
            AnimatedStockBar(
                value: parentStock,
                maxValue: max(100, parentStock),
                label: "\(formatStock(parentStock))\(parentUnit) in stock",
                color: Design.Colors.Semantic.success,
                lowThreshold: 10
            )

            // Variant stock bars (always red)
            ForEach(variantInventories) { variant in
                AnimatedStockBar(
                    value: Double(variant.quantity),
                    maxValue: max(50, Double(variant.quantity)),
                    label: "\(variant.quantity) \(variant.variantName)",
                    color: Color(hex: "ef4444"),
                    lowThreshold: 5,
                    isVariant: true
                )
            }
        }
        .padding(.vertical, 4)
    }

    private func formatStock(_ value: Double) -> String {
        if value == floor(value) {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }
}

// MARK: - Variant Inventory Item (for display)

struct VariantInventoryItem: Identifiable {
    let id: UUID
    let variantTemplateId: UUID
    let variantName: String
    let quantity: Int
    let conversionRatio: Double
}

// MARK: - Preview

#Preview("Stock Bars") {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack(spacing: 20) {
            // Full stock
            AnimatedStockBar(
                value: 85,
                maxValue: 100,
                label: "85g in stock",
                color: Design.Colors.Semantic.success
            )

            // Low stock
            AnimatedStockBar(
                value: 8,
                maxValue: 100,
                label: "8g in stock",
                color: Design.Colors.Semantic.success,
                lowThreshold: 10
            )

            // Variant
            AnimatedStockBar(
                value: 12,
                maxValue: 50,
                label: "12 Pre-Roll",
                color: Color(hex: "ef4444"),
                isVariant: true
            )

            Divider().background(Color.white.opacity(0.2))

            // Full display
            VariantInventoryDisplay(
                parentStock: 56.5,
                parentUnit: "g",
                variantInventories: [
                    VariantInventoryItem(
                        id: UUID(),
                        variantTemplateId: UUID(),
                        variantName: "Pre-Roll",
                        quantity: 15,
                        conversionRatio: 0.7
                    )
                ]
            )
        }
        .padding(20)
    }
}
