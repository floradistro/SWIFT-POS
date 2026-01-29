//  TierComponents.swift - Reusable components for tier selection
//
//  CRITICAL: Touch targets for modal buttons
//  - .contentShape() must be applied to the label INSIDE the Button, not after buttonStyle
//  - Apple HIG: 44pt minimum touch target
//  - Wide buttons need full-width hit testing to prevent modal backdrop from intercepting taps

import SwiftUI

// MARK: - Tier Button

struct TierButton: View {
    let tier: PricingTier
    let onTap: () -> Void

    var body: some View {
        Button {
            Haptics.medium()
            onTap()
        } label: {
            HStack {
                Text(tier.label)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text(CurrencyFormatter.format(tier.defaultPrice))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(Design.Colors.Semantic.accent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .frame(minHeight: 52)
            // CRITICAL: contentShape INSIDE the label makes entire button tappable
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(ScaleButtonStyle())
        // iOS 26: .glassEffect provides both visual styling AND proper interactive hit testing in sheets
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
    }
}

// MARK: - Variant Tab

struct VariantTab: View {
    let name: String
    let isSelected: Bool
    let namespace: Namespace.ID
    let onTap: () -> Void

    var body: some View {
        Button {
            Haptics.light()
            onTap()
        } label: {
            Text(name)
                .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? .white : .white.opacity(0.6))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(minHeight: 44)
                // CRITICAL: contentShape INSIDE the label
                .contentShape(Capsule())
        }
        .buttonStyle(ScaleButtonStyle())
        // iOS 26: .glassEffect with .interactive() is REQUIRED for proper hit testing in sheets
        .glassEffect(.regular.interactive(), in: .capsule)
        .overlay(Capsule().stroke(isSelected ? Design.Colors.Semantic.accent.opacity(0.8) : .clear, lineWidth: 1.5))
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isSelected)
    }
}

// MARK: - Stat Pill

struct StatPill: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
    }
}

// MARK: - Detail Row

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
        }
    }
}
