//
//  StageManagerView.swift
//  Whale
//
//  Shared components for Stage Manager.
//

import SwiftUI
import Supabase

// MARK: - Add Window Button

struct AddWindowButton: View {
    let size: CGSize
    let action: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Button(action: {
                Haptics.medium()
                action()
            }) {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(.white.opacity(0.2), lineWidth: 1)
                    )
                    .overlay(
                        Image(systemName: "plus")
                            .font(.system(size: 48, weight: .ultraLight))
                            .foregroundStyle(.white.opacity(0.6))
                    )
                    .frame(width: size.width, height: size.height)
                    .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
            }
            .buttonStyle(StageManagerButtonStyle())

            Text("New")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
        }
    }
}

struct StageManagerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.2), value: configuration.isPressed)
    }
}

// MARK: - App Launcher Modal

struct AppLauncherModal: View {
    @Binding var isPresented: Bool
    @ObservedObject var store = StageManagerStore.shared
    @EnvironmentObject private var session: SessionObserver

    @State private var creations: [Creation] = []
    @State private var isLoadingCreations = false
    @State private var isLoadingLocations = false
    @State private var showAllCreations = false

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        UnifiedModal(isPresented: $isPresented, id: "app-launcher", maxWidth: 500, hidesDock: false) {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Open")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                    ModalCloseButton { isPresented = false }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 20)

                // Content
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        // POS Locations Section
                        if !session.locations.isEmpty {
                            launcherSection("Point of Sale") {
                                LazyVGrid(columns: columns, spacing: 16) {
                                    ForEach(session.locations, id: \.id) { location in
                                        AppIcon(
                                            icon: "storefront.fill",
                                            label: location.name,
                                            color: .blue,
                                            action: { openPOSWindow(location: location) }
                                        )
                                    }
                                }
                            }
                        } else if isLoadingLocations {
                            launcherSection("Point of Sale") {
                                HStack {
                                    Spacer()
                                    ProgressView()
                                        .tint(.white)
                                    Spacer()
                                }
                                .frame(height: 80)
                            }
                        }

                        // Creations Section
                        if !creations.isEmpty || isLoadingCreations {
                            launcherSection("Creations", showMore: creations.count > 6 ? { showAllCreations = true } : nil) {
                                if isLoadingCreations {
                                    HStack {
                                        Spacer()
                                        ProgressView()
                                            .tint(.white)
                                        Spacer()
                                    }
                                    .frame(height: 80)
                                } else {
                                    LazyVGrid(columns: columns, spacing: 16) {
                                        ForEach(creations.prefix(6)) { creation in
                                            CreationAppIcon(creation: creation) {
                                                openCreation(creation)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
            }
        }
        .task {
            if session.locations.isEmpty {
                isLoadingLocations = true
                await session.fetchLocations()
                isLoadingLocations = false
            }
            await loadCreations()
        }
        .overlay(
            Group {
                if showAllCreations {
                    AllCreationsModal(
                        isPresented: $showAllCreations,
                        creations: creations,
                        onSelect: { creation in
                            showAllCreations = false
                            openCreation(creation)
                        }
                    )
                }
            }
        )
    }

    // MARK: - Section Builder

    private func launcherSection<Content: View>(
        _ title: String,
        showMore: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
                    .tracking(0.5)

                Spacer()

                if let showMore = showMore {
                    Button {
                        Haptics.light()
                        showMore()
                    } label: {
                        Text("See All")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }
            .padding(.horizontal, 4)

            content()
        }
    }

    // MARK: - Actions

    private func loadCreations() async {
        guard let storeId = SessionObserver.shared.storeId else { return }

        isLoadingCreations = true

        do {
            let client = await supabaseAsync()
            let response: [Creation] = try await client
                .from("creations")
                .select("id, name, creation_type, status, thumbnail_url, deployed_url, react_code, created_at, is_public, visibility, location_id, is_pinned, pinned_at, pin_order, is_template")
                .eq("store_id", value: storeId.uuidString.lowercased())
                .order("created_at", ascending: false)
                .limit(50)
                .execute()
                .value

            await MainActor.run {
                creations = response
                isLoadingCreations = false
            }
        } catch {
            print("Failed to load creations: \(error)")
            await MainActor.run {
                isLoadingCreations = false
            }
        }
    }

    private func openCreation(_ creation: Creation) {
        isPresented = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            store.addCreation(
                id: creation.id.uuidString,
                name: creation.name,
                url: creation.deployed_url,
                reactCode: creation.react_code
            )
        }
    }

    private func openPOSWindow(location: Location) {
        isPresented = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            store.addApp(location: location, register: nil)
        }
    }
}

// MARK: - App Icon

struct AppIcon: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.medium()
            action()
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(color.gradient)
                        .frame(width: 60, height: 60)
                        .shadow(color: color.opacity(0.4), radius: 8, y: 4)

                    Image(systemName: icon)
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(.white)
                }

                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
                    .frame(maxWidth: 70)
            }
        }
        .buttonStyle(AppIconButtonStyle())
    }
}

// MARK: - Creation App Icon (with thumbnail)

struct CreationAppIcon: View {
    let creation: Creation
    let action: () -> Void

    private var iconName: String {
        switch creation.creation_type {
        case "display": return "tv.fill"
        case "dashboard": return "chart.bar.fill"
        case "landing": return "globe"
        case "email": return "envelope.fill"
        case "artifact": return "cube.fill"
        case "game": return "gamecontroller.fill"
        default: return "doc.fill"
        }
    }

    private var iconColor: Color {
        switch creation.creation_type {
        case "display": return .purple
        case "dashboard": return .orange
        case "landing": return .cyan
        case "email": return .pink
        case "artifact": return .indigo
        case "game": return .red
        default: return .gray
        }
    }

    var body: some View {
        Button {
            Haptics.medium()
            action()
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    if let thumbnailUrl = creation.thumbnail_url,
                       let url = URL(string: thumbnailUrl) {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            iconPlaceholder
                        }
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    } else {
                        iconPlaceholder
                    }
                }
                .shadow(color: iconColor.opacity(0.3), radius: 6, y: 3)

                Text(creation.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
                    .frame(maxWidth: 70)
            }
        }
        .buttonStyle(AppIconButtonStyle())
    }

    private var iconPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(iconColor.gradient)
                .frame(width: 60, height: 60)

            Image(systemName: iconName)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - App Icon Button Style

struct AppIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - All Creations Modal

struct AllCreationsModal: View {
    @Binding var isPresented: Bool
    let creations: [Creation]
    let onSelect: (Creation) -> Void

    @State private var searchText = ""

    private var filteredCreations: [Creation] {
        if searchText.isEmpty {
            return creations
        }
        return creations.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        UnifiedModal(isPresented: $isPresented, id: "all-creations", maxWidth: 600, hidesDock: false) {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button {
                        Haptics.light()
                        isPresented = false
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    }
                    .buttonStyle(ScaleButtonStyle())

                    Spacer()

                    Text("All Creations")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)

                    Spacer()

                    ModalCloseButton { isPresented = false }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)

                // Search
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))

                    TextField("", text: $searchText, prompt: Text("Search creations...").foregroundColor(.white.opacity(0.3)))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.white.opacity(0.1), lineWidth: 0.5)
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 16)

                // Grid
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(filteredCreations) { creation in
                            CreationAppIcon(creation: creation) {
                                onSelect(creation)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
            }
        }
    }
}

// MARK: - Legacy Sheet (deprecated, kept for compatibility)

struct AddWindowSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store = StageManagerStore.shared
    @EnvironmentObject private var session: SessionObserver

    var body: some View {
        Text("Use AppLauncherModal instead")
            .onAppear { dismiss() }
    }
}
