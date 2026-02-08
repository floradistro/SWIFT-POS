//
//  StorePickerSheet.swift
//  Whale
//
//  Sheet for switching between stores (multi-store users).
//

import SwiftUI

struct StorePickerSheet: View {
    @EnvironmentObject private var session: SessionObserver
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(session.userStoreAssociations) { association in
                        let isSelected = association.storeId == session.storeId

                        Button {
                            Haptics.medium()
                            Task {
                                await session.selectStore(association.storeId)
                                await session.fetchLocations()
                                try? await Task.sleep(for: .milliseconds(150))
                                dismiss()
                            }
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "building.2.fill")
                                    .font(Design.Typography.headline)
                                    .foregroundStyle(isSelected ? Design.Colors.Text.primary : Design.Colors.Text.disabled)
                                    .frame(width: 28)

                                Text(association.displayName)
                                    .font(Design.Typography.callout).fontWeight(.medium)
                                    .foregroundStyle(Design.Colors.Text.primary)

                                Spacer()

                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(Design.Typography.footnote).fontWeight(.semibold)
                                        .foregroundStyle(Design.Colors.Text.primary)
                                }
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 16)
                            .background(
                                isSelected ? Design.Colors.Glass.regular : Design.Colors.Glass.thin,
                                in: RoundedRectangle(cornerRadius: 14)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(isSelected ? Design.Colors.Border.strong : Design.Colors.Border.subtle, lineWidth: 1)
                            )
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("Switch Store")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
