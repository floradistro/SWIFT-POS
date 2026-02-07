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
                                    .foregroundStyle(isSelected ? .white : .white.opacity(0.5))
                                    .frame(width: 28)

                                Text(association.displayName)
                                    .font(Design.Typography.callout).fontWeight(.medium)
                                    .foregroundStyle(.white)

                                Spacer()

                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(Design.Typography.footnote).fontWeight(.semibold)
                                        .foregroundStyle(.white)
                                }
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 16)
                            .background(
                                isSelected ? Color.white.opacity(0.12) : Color.white.opacity(0.06),
                                in: RoundedRectangle(cornerRadius: 14)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(isSelected ? Color.white.opacity(0.2) : Color.white.opacity(0.08), lineWidth: 1)
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
        .preferredColorScheme(.dark)
    }
}
