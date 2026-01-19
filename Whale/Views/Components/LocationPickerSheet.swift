//
//  LocationPickerSheet.swift
//  Whale
//
//  Modern sheet for selecting a location.
//  Clean Apple design - no clutter, just essentials.
//

import SwiftUI

struct LocationPickerSheet: View {
    @EnvironmentObject private var session: SessionObserver
    @Environment(\.dismiss) private var dismiss

    @State private var isLoading = true
    @State private var selectedId: UUID?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    loadingView
                } else if session.locations.isEmpty {
                    emptyView
                } else {
                    locationList
                }
            }
            .navigationTitle("Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .task {
            await session.fetchLocations()
            isLoading = false
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.1)
            Text("Loading locations...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: - Empty

    private var emptyView: some View {
        ContentUnavailableView {
            Label("No Locations", systemImage: "mappin.slash")
        } description: {
            Text("No locations configured for this store.")
        }
    }

    // MARK: - Location List

    private var locationList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(session.locations) { location in
                    locationRow(location)

                    if location.id != session.locations.last?.id {
                        Divider()
                            .padding(.leading, 20)
                    }
                }
            }
            .padding(.top, 8)
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: - Location Row

    private func locationRow(_ location: Location) -> some View {
        Button {
            Haptics.medium()
            selectedId = location.id

            Task {
                await session.selectLocation(location)
                try? await Task.sleep(nanoseconds: 150_000_000)
                dismiss()
            }
        } label: {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(location.name)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)

                    if let address = location.displayAddress, !address.isEmpty {
                        Text(address)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 16)

                if selectedId == location.id {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.tint)
                } else if session.selectedLocation?.id == location.id {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(LocationRowButtonStyle())
    }
}

// MARK: - Button Style

private struct LocationRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.primary.opacity(0.06) : Color.clear)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

#Preview {
    LocationPickerSheet()
        .environmentObject(SessionObserver.shared)
}
