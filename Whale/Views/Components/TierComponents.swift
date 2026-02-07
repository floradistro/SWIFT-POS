//
//  TierComponents.swift
//  Whale
//
//  Reusable components for product details.
//

import SwiftUI

// MARK: - Stat Pill

struct StatPill: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 3) {
            Text(label)
                .font(Design.Typography.caption2).fontWeight(.medium)
                .foregroundStyle(.secondary)
            Text(value)
                .font(Design.Typography.footnote).fontWeight(.semibold)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Detail Row

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(Design.Typography.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(Design.Typography.footnote).fontWeight(.medium)
                .foregroundStyle(.primary)
        }
    }
}
