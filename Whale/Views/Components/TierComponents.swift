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
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 14, weight: .semibold))
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
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
        }
    }
}
