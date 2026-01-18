//
//  SmartDockView.swift
//  Whale
//
//  The main Smart AI Chat Dock for Stage Manager.
//  iMessage-style: conversation list → individual chat with back navigation.
//  Supports multiple AI agent chats + staff messaging.
//
//  REFACTORED: Now uses Apple's native .sheet with Liquid Glass styling
//  per WWDC25 guidelines. The collapsed dock triggers a native sheet
//  which provides proper gesture handling and system integration.
//

import SwiftUI
import Combine
import Supabase

// MARK: - Animation Constants

private enum DockAnimation {
    // Navigation spring - used for list ↔ chat transitions
    static let navigation = Animation.spring(response: 0.42, dampingFraction: 0.86, blendDuration: 0)

    // Quick spring - used for micro-interactions
    static let quick = Animation.spring(response: 0.32, dampingFraction: 0.78, blendDuration: 0)
}

// MARK: - Native Glass Button
// Per Apple docs: Use .contentShape() to fix hit-testing issues with glass effects
// Reference: https://juniperphoton.substack.com/p/adopting-liquid-glass-experiences

private struct NativeGlassButton: View {
    let icon: String
    var size: CGFloat = 44
    var iconSize: CGFloat?
    var badge: Int?
    var isSelected: Bool = false
    let action: () -> Void

    private var computedIconSize: CGFloat {
        iconSize ?? (size * 0.40)
    }

    var body: some View {
        Button {
            Haptics.light()
            action()
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: icon)
                    .font(.system(size: computedIconSize, weight: .semibold))
                    .foregroundStyle(isSelected ? .blue : .white)
                    .frame(width: size, height: size)
                    // CRITICAL: contentShape INSIDE label defines tappable area
                    .contentShape(Circle())

                if let badge = badge, badge > 0 {
                    Text("\(min(badge, 99))")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(.red, in: Circle())
                        .offset(x: 6, y: -6)
                }
            }
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
    }
}

// MARK: - Native Glass Capsule Button

private struct NativeGlassCapsuleButton: View {
    let title: String
    var icon: String?
    var color: Color = .blue
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.light()
            action()
        } label: {
            HStack(spacing: 6) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 15, weight: .medium))
            }
            .foregroundStyle(color)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            // CRITICAL: contentShape INSIDE label defines tappable area
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
    }
}

// MARK: - Hub Tab

enum HubTab: String, CaseIterable {
    case messages = "Messages"
    case apps = "Apps"
    case creations = "Creations"
    case media = "Media"

    var icon: String {
        switch self {
        case .messages: return "bubble.left.and.bubble.right.fill"
        case .apps: return "square.grid.2x2.fill"
        case .creations: return "paintbrush.fill"
        case .media: return "photo.fill"
        }
    }
}

// MARK: - Navigation State

enum ChatNavigationState: Equatable {
    case list
    case chat(UUID)

    var isInChat: Bool {
        if case .chat = self { return true }
        return false
    }
}

// MARK: - Smart Dock View

struct SmartDockView: View {
    @ObservedObject private var chatStore = AIChatStore.shared
    @ObservedObject private var chatListStore = ChatListStore.shared
    @ObservedObject private var stageManager = StageManagerStore.shared

    @State private var selectedTab: HubTab = .messages
    @State private var keyboardHeight: CGFloat = 0
    @State private var hasLoadedList = false

    // Navigation state derived from store (persists across open/close)
    private var navigationState: ChatNavigationState {
        if chatListStore.isInChatView, let id = chatListStore.selectedConversationId {
            return .chat(id)
        }
        return .list
    }

    // Helper to navigate to a chat (updates store)
    private func navigateToChat(_ conversationId: UUID) {
        chatListStore.selectedConversationId = conversationId
        chatListStore.isInChatView = true
    }

    // Helper to navigate back to list (updates store)
    private func navigateToList() {
        chatListStore.isInChatView = false
    }

    // Apps tab state
    @State private var creations: [Creation] = []
    @State private var collections: [CreationCollection] = []
    @State private var isLoadingCreations = false
    @State private var isLoadingCollections = false
    @State private var showAllCreations = false
    @State private var selectedCollection: CreationCollection? = nil

    // Bulk selection state
    @State private var isSelectMode = false
    @State private var selectedCreationIds: Set<UUID> = []
    @State private var showDeleteConfirmation = false
    @State private var showCollectionPicker = false
    @State private var showCollectionEditor: CreationCollection? = nil
    @State private var showNewCollectionSheet = false

    // Convenience accessors for AIChatStore workspace
    private var messages: [ChatMessage] { chatStore.workspace.messages }
    private var isStreaming: Bool { chatStore.workspace.isStreaming }

    private var hasWindows: Bool {
        !stageManager.windows.isEmpty
    }

    // Cache screen size - avoid GeometryReader overhead
    private var screenWidth: CGFloat { UIScreen.main.bounds.width }
    private var screenHeight: CGFloat { UIScreen.main.bounds.height }

    // MARK: - Body
    // Shows the chat/apps sheet directly over the background (no collapsed dock)

    var body: some View {
        // Sheet content shown directly - no collapsed state
        sheetContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onReceive(Self.keyboardPublisher) { height in
                withAnimation(DockAnimation.navigation) {
                    keyboardHeight = height
                }
            }
            .task {
                // Load conversations on appear
                if !hasLoadedList {
                    hasLoadedList = true
                    await chatListStore.loadConversations()
                }
            }
            // Sync streaming state to list store
            .onChange(of: chatStore.workspace.isStreaming) { _, streaming in
                guard let selectedId = chatListStore.selectedConversationId else { return }
                if streaming {
                    chatListStore.updateAgentStatus(selectedId, status: .working)
                } else {
                    chatListStore.updateAgentStatus(selectedId, status: .idle)
                    if let lastMessage = messages.last {
                        chatListStore.updateLastMessage(selectedId, message: String(lastMessage.content.prefix(100)))
                    }
                }
            }
    }

    // MARK: - Sheet Content
    // The content shown inside the native sheet

    private var sheetContent: some View {
        NavigationStack {
            // iMessage-style navigation
            Group {
                switch navigationState {
                case .list:
                    listModeContent

                case .chat:
                    chatModeContent
                }
            }
            .animation(DockAnimation.navigation, value: navigationState)
        }
    }

    // MARK: - List Mode Content (Hub)

    private var listModeContent: some View {
        VStack(spacing: 0) {
            // Show hub header unless we're in a full-screen sub-view
            if !showAllCreations && selectedCollection == nil {
                hubHeader
            }

            // Tab content
            switch selectedTab {
            case .messages:
                ChatListView(
                    store: chatListStore,
                    onSelectChat: { conversation in
                        selectConversation(conversation)
                    },
                    onNewChat: {
                        createNewChat()
                    }
                )
                .transition(.opacity)

            case .apps:
                appsTabContent
                    .transition(.opacity)

            case .creations:
                creationsTabContent
                    .transition(.opacity)

            case .media:
                mediaTabContent
                    .transition(.opacity)
            }
        }
        .animation(DockAnimation.quick, value: selectedTab)
        .animation(DockAnimation.quick, value: showAllCreations)
    }

    // MARK: - Chat Mode Content

    private var chatModeContent: some View {
        VStack(spacing: 0) {
            expandedHeader
            messagesView
            expandedInput
        }
    }

    // MARK: - Hub Header with Tabs
    // Uses native Button with proper contentShape per Apple Liquid Glass guidelines

    private var hubHeader: some View {
        HStack(spacing: 12) {
            // Lock screen button on left
            NativeGlassButton(
                icon: stageManager.isScreenLocked ? "lock.fill" : "lock.open",
                size: 44,
                isSelected: stageManager.isScreenLocked
            ) {
                Haptics.medium()
                stageManager.isScreenLocked.toggle()
            }

            Spacer()

            // Tab picker - centered, icon-based for 4 tabs
            HStack(spacing: 4) {
                ForEach(HubTab.allCases, id: \.self) { tab in
                    Button {
                        Haptics.light()
                        selectedTab = tab
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 16, weight: .semibold))

                            Text(tab.rawValue)
                                .font(.system(size: 9, weight: .medium))
                        }
                        .foregroundStyle(selectedTab == tab ? .white : .white.opacity(0.4))
                        .frame(width: 64, height: 44)
                        .background(
                            selectedTab == tab ?
                            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.15)) :
                            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.clear)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))

            Spacer()

            // New chat/create button on right
            NativeGlassButton(icon: "plus", size: 44) {
                if selectedTab == .messages {
                    createNewChat()
                } else if selectedTab == .creations {
                    createNewCreation()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, SafeArea.top + 12)
        .padding(.bottom, 8)
    }

    // MARK: - Apps Tab Content
    // Quick actions only - Creations have their own tab

    private var appsTabContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 32) {
                // Primary Actions - large, clear
                primaryActionsGrid
                    .padding(.top, 20)

                // Quick access section
                VStack(alignment: .leading, spacing: 16) {
                    Text("Quick Access")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))

                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 4),
                        spacing: 20
                    ) {
                        AppIconTile(icon: "person.2.fill", label: "Customers", color: .cyan) {
                            // TODO: Open customers
                        }
                        AppIconTile(icon: "shippingbox.fill", label: "Orders", color: .orange) {
                            // TODO: Open orders
                        }
                        AppIconTile(icon: "tag.fill", label: "Products", color: .green) {
                            // TODO: Open products
                        }
                        AppIconTile(icon: "building.2.fill", label: "Locations", color: .purple) {
                            // TODO: Open locations
                        }
                    }
                }

                Spacer(minLength: 40)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Creations Tab Content

    private var creationsTabContent: some View {
        Group {
            if showAllCreations {
                allCreationsView
            } else if let collection = selectedCollection {
                collectionDetailView(collection)
            } else {
                creationsMainView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            loadCreations()
            loadCollections()
        }
        .onChange(of: stageManager.windows.count) { _, _ in
            refreshCreations()
        }
    }

    // MARK: - Creations Main View

    private var creationsMainView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                // Collections section
                if !collections.isEmpty {
                    collectionsSection
                }

                // Creations - all shown in 4-column grid
                if !creations.isEmpty {
                    creationsFullSection
                }

                // Loading
                if isLoadingCreations || isLoadingCollections {
                    ProgressView()
                        .tint(.white.opacity(0.5))
                        .padding(.top, 40)
                }

                // Empty state
                if !isLoadingCreations && creations.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "paintbrush")
                            .font(.system(size: 48, weight: .light))
                            .foregroundStyle(.white.opacity(0.3))

                        Text("No creations yet")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))

                        Button {
                            createNewCreation()
                        } label: {
                            Text("Create Something")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(.blue, in: Capsule())
                        }
                    }
                    .padding(.top, 60)
                }

                Spacer(minLength: 40)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Media Tab Content

    private var mediaTabContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                // Media categories
                VStack(alignment: .leading, spacing: 16) {
                    Text("Media Library")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))

                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 4),
                        spacing: 20
                    ) {
                        AppIconTile(icon: "photo.fill", label: "Images", color: .pink) {
                            // TODO: Open images
                        }
                        AppIconTile(icon: "doc.fill", label: "Documents", color: .blue) {
                            // TODO: Open documents
                        }
                        AppIconTile(icon: "video.fill", label: "Videos", color: .red) {
                            // TODO: Open videos
                        }
                        AppIconTile(icon: "waveform", label: "Audio", color: .orange) {
                            // TODO: Open audio
                        }
                    }
                }

                // Recent uploads placeholder
                VStack(alignment: .leading, spacing: 16) {
                    Text("Recent Uploads")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))

                    // Empty state
                    VStack(spacing: 12) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 40, weight: .light))
                            .foregroundStyle(.white.opacity(0.3))

                        Text("No recent uploads")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }

                Spacer(minLength: 40)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Primary Actions

    @State private var locationsLoaded = false
    @State private var showPOSSelector = false
    @State private var posSelectedStoreId: UUID?
    @State private var posLocationsForStore: [Location] = []
    @State private var posLoadingLocations = false

    private var primaryActionsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
            // Sell - opens store/location selector for multi-store users
            Button {
                if SessionObserver.shared.hasMultipleStores {
                    // Multi-store: show selector sheet
                    posSelectedStoreId = SessionObserver.shared.storeId
                    posLocationsForStore = SessionObserver.shared.locations
                    showPOSSelector = true
                } else if SessionObserver.shared.locations.count == 1,
                          let location = SessionObserver.shared.locations.first {
                    // Single location: open directly
                    openPOSWindow(location: location)
                } else {
                    // Single store, multiple locations: show selector
                    posSelectedStoreId = SessionObserver.shared.storeId
                    posLocationsForStore = SessionObserver.shared.locations
                    showPOSSelector = true
                }
            } label: {
                AppIconTile(icon: "cart.fill", label: "Sell", color: .blue)
            }
            .task {
                // Ensure locations are fetched when the Apps tab appears
                if !locationsLoaded {
                    locationsLoaded = true
                    await SessionObserver.shared.fetchLocations()
                }
            }
            .sheet(isPresented: $showPOSSelector) {
                POSLocationSelectorSheet(
                    selectedStoreId: $posSelectedStoreId,
                    locations: $posLocationsForStore,
                    isLoading: $posLoadingLocations,
                    onSelectLocation: { location in
                        showPOSSelector = false
                        openPOSWindow(location: location)
                    }
                )
            }

            // Create
            AppIconTile(icon: "plus", label: "Create", color: .purple) {
                createNewCreation()
            }

            // Reports
            AppIconTile(icon: "chart.bar.fill", label: "Reports", color: .orange) {
                // TODO: Open reports
            }

            // Store Switcher (only show if user has multiple stores)
            if SessionObserver.shared.hasMultipleStores {
                Menu {
                    ForEach(SessionObserver.shared.userStoreAssociations) { association in
                        Button {
                            Task {
                                await SessionObserver.shared.selectStore(association.storeId)
                            }
                        } label: {
                            HStack {
                                if association.storeId == SessionObserver.shared.storeId {
                                    Image(systemName: "checkmark")
                                }
                                Text(association.displayName)
                            }
                        }
                    }
                } label: {
                    AppIconTile(icon: "building.2.fill", label: "Stores", color: .indigo)
                }
            }

            // Settings
            AppIconTile(icon: "gearshape.fill", label: "Settings", color: .gray) {
                // TODO: Open settings
            }
        }
    }

    // MARK: - Collections Section

    private var collectionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Collections")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))

                Spacer()

                // Add new collection
                Button {
                    showNewCollectionSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.blue)
                }
            }

            // Horizontal scroll of collection pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(collections, id: \.id) { collection in
                        CollectionPill(
                            collection: collection,
                            onTap: {
                                withAnimation(DockAnimation.quick) {
                                    selectedCollection = collection
                                }
                            },
                            onRename: { newName in
                                renameCollection(collection, newName: newName)
                            },
                            onDelete: {
                                deleteCollection(collection)
                            }
                        )
                    }
                }
            }
        }
        .sheet(isPresented: $showNewCollectionSheet) {
            NewCollectionSheet(
                onSave: { name, accentColor in
                    createNewCollection(name: name, accentColor: accentColor)
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }

    private func createNewCollection(name: String, accentColor: String?) {
        Haptics.medium()

        Task {
            guard let storeId = SessionObserver.shared.storeId else { return }

            do {
                let client = await supabaseAsync()

                struct NewCollection: Encodable {
                    let store_id: String
                    let name: String
                    let accent_color: String?
                    let is_public: Bool
                }

                try await client
                    .from("collections")
                    .insert(NewCollection(
                        store_id: storeId.uuidString,
                        name: name,
                        accent_color: accentColor,
                        is_public: true
                    ))
                    .execute()

                await MainActor.run {
                    showNewCollectionSheet = false
                    collections = []
                    isLoadingCollections = false
                    loadCollections()
                }
            } catch {
                print("Failed to create collection: \(error)")
            }
        }
    }

    // MARK: - Creations Full Section (4 columns, all shown)

    private var creationsFullSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Creations")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))

                Spacer()

                // Edit button to enter select mode
                Button {
                    withAnimation(DockAnimation.quick) {
                        showAllCreations = true
                        isSelectMode = true
                    }
                } label: {
                    Text("Edit")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.blue)
                }
            }

            // Fixed 4-column grid
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 4),
                spacing: 20
            ) {
                ForEach(creations, id: \.id) { creation in
                    CreationTile(creation: creation) {
                        openCreation(creation)
                    } onEdit: {
                        editCreation(creation)
                    } onDuplicate: {
                        duplicateCreation(creation)
                    } onDelete: {
                        deleteCreation(creation)
                    } onOpenBrowser: {
                        openCreationInBrowser(creation)
                    }
                }
            }
        }
    }

    // MARK: - All Creations View
    // Full modal view - no hub header visible

    private var allCreationsView: some View {
        VStack(spacing: 0) {
            // Full modal header
            HStack {
                // Left button - Done or Cancel
                Button {
                    withAnimation(DockAnimation.quick) {
                        if isSelectMode {
                            isSelectMode = false
                            selectedCreationIds.removeAll()
                        } else {
                            showAllCreations = false
                        }
                    }
                } label: {
                    Text(isSelectMode ? "Cancel" : "Done")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(.blue)
                }

                Spacer()

                // Title with count in select mode
                if isSelectMode && !selectedCreationIds.isEmpty {
                    Text("\(selectedCreationIds.count) Selected")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                } else {
                    Text("Creations")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                }

                Spacer()

                // Right button - Select or Select All
                Button {
                    withAnimation(DockAnimation.quick) {
                        if isSelectMode {
                            // Select All / Deselect All
                            if selectedCreationIds.count == creations.count {
                                selectedCreationIds.removeAll()
                            } else {
                                selectedCreationIds = Set(creations.map { $0.id })
                            }
                        } else {
                            isSelectMode = true
                        }
                    }
                } label: {
                    if isSelectMode {
                        Text(selectedCreationIds.count == creations.count ? "Deselect All" : "Select All")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(.blue)
                    } else {
                        Text("Select")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundStyle(.blue)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            // Grid - fills remaining space, fixed 4 columns
            ScrollView(showsIndicators: false) {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 4),
                    spacing: 20
                ) {
                    ForEach(creations, id: \.id) { creation in
                        if isSelectMode {
                            SelectableCreationTile(
                                creation: creation,
                                isSelected: selectedCreationIds.contains(creation.id)
                            ) {
                                withAnimation(DockAnimation.quick) {
                                    if selectedCreationIds.contains(creation.id) {
                                        selectedCreationIds.remove(creation.id)
                                    } else {
                                        selectedCreationIds.insert(creation.id)
                                    }
                                }
                            }
                        } else {
                            CreationTile(creation: creation) {
                                openCreation(creation)
                            } onEdit: {
                                editCreation(creation)
                            } onDuplicate: {
                                duplicateCreation(creation)
                            } onDelete: {
                                deleteCreation(creation)
                            } onOpenBrowser: {
                                openCreationInBrowser(creation)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, isSelectMode ? 100 : 40)
            }

            // Bulk action bar
            if isSelectMode {
                bulkActionBar
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Bulk Action Bar

    private var bulkActionBar: some View {
        HStack(spacing: 32) {
            // Delete
            Button {
                showDeleteConfirmation = true
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "trash")
                        .font(.system(size: 22, weight: .medium))
                    Text("Delete")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(selectedCreationIds.isEmpty ? .white.opacity(0.3) : .red)
            }
            .disabled(selectedCreationIds.isEmpty)

            // Duplicate
            Button {
                bulkDuplicateCreations()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 22, weight: .medium))
                    Text("Duplicate")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(selectedCreationIds.isEmpty ? .white.opacity(0.3) : .blue)
            }
            .disabled(selectedCreationIds.isEmpty)

            // Add to Collection
            Button {
                showCollectionPicker = true
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 22, weight: .medium))
                    Text("Add to...")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(selectedCreationIds.isEmpty ? .white.opacity(0.3) : .blue)
            }
            .disabled(selectedCreationIds.isEmpty)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial)
        .confirmationDialog(
            "Delete \(selectedCreationIds.count) creation\(selectedCreationIds.count == 1 ? "" : "s")?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                bulkDeleteCreations()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
        .sheet(isPresented: $showCollectionPicker) {
            CollectionPickerSheet(
                collections: collections,
                onSelect: { collection in
                    addCreationsToCollection(collection)
                },
                onCreateNew: {
                    showCollectionPicker = false
                    showNewCollectionSheet = true
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showNewCollectionSheet) {
            NewCollectionSheet(
                onSave: { name, accentColor in
                    createCollectionAndAddCreations(name: name, accentColor: accentColor)
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Bulk Actions

    private func bulkDeleteCreations() {
        guard !selectedCreationIds.isEmpty else { return }
        Haptics.warning()

        let idsToDelete = selectedCreationIds

        Task {
            do {
                let client = await supabaseAsync()

                for id in idsToDelete {
                    try await client
                        .from("creations")
                        .delete()
                        .eq("id", value: id.uuidString)
                        .execute()
                }

                await MainActor.run {
                    creations.removeAll { idsToDelete.contains($0.id) }
                    selectedCreationIds.removeAll()
                    isSelectMode = false
                }
            } catch {
                print("Failed to bulk delete: \(error)")
            }
        }
    }

    private func bulkDuplicateCreations() {
        guard !selectedCreationIds.isEmpty else { return }
        Haptics.medium()

        let idsToDuplicate = selectedCreationIds

        Task {
            guard let storeId = SessionObserver.shared.storeId else { return }

            do {
                let client = await supabaseAsync()

                for id in idsToDuplicate {
                    guard let creation = creations.first(where: { $0.id == id }) else { continue }

                    struct NewCreation: Encodable {
                        let store_id: String
                        let name: String
                        let creation_type: String
                        let react_code: String
                        let status: String
                    }

                    let newCreation = NewCreation(
                        store_id: storeId.uuidString,
                        name: "\(creation.name) (Copy)",
                        creation_type: creation.creation_type,
                        react_code: creation.react_code ?? "",
                        status: "draft"
                    )

                    try await client
                        .from("creations")
                        .insert(newCreation)
                        .execute()
                }

                // Refresh list
                await MainActor.run {
                    selectedCreationIds.removeAll()
                    isSelectMode = false
                    creations = []
                    isLoadingCreations = false
                }
                loadCreations()
            } catch {
                print("Failed to bulk duplicate: \(error)")
            }
        }
    }

    private func addCreationsToCollection(_ collection: CreationCollection) {
        guard !selectedCreationIds.isEmpty else { return }
        Haptics.medium()

        let idsToAdd = selectedCreationIds

        Task {
            do {
                let client = await supabaseAsync()

                for creationId in idsToAdd {
                    struct CollectionCreation: Encodable {
                        let collection_id: String
                        let creation_id: String
                    }

                    try await client
                        .from("collection_creations")
                        .upsert(CollectionCreation(
                            collection_id: collection.id.uuidString,
                            creation_id: creationId.uuidString
                        ))
                        .execute()
                }

                await MainActor.run {
                    selectedCreationIds.removeAll()
                    isSelectMode = false
                    showCollectionPicker = false
                    // Refresh collections to update counts
                    collections = []
                    isLoadingCollections = false
                    loadCollections()
                }
            } catch {
                print("Failed to add to collection: \(error)")
            }
        }
    }

    private func createCollectionAndAddCreations(name: String, accentColor: String?) {
        guard !selectedCreationIds.isEmpty else { return }
        Haptics.medium()

        let idsToAdd = selectedCreationIds

        Task {
            guard let storeId = SessionObserver.shared.storeId else { return }

            do {
                let client = await supabaseAsync()

                struct NewCollection: Encodable {
                    let store_id: String
                    let name: String
                    let accent_color: String?
                    let is_public: Bool
                }

                // Create the collection
                let result: [CreationCollection] = try await client
                    .from("collections")
                    .insert(NewCollection(
                        store_id: storeId.uuidString,
                        name: name,
                        accent_color: accentColor,
                        is_public: true
                    ))
                    .select()
                    .execute()
                    .value

                guard let newCollection = result.first else { return }

                // Add creations to the new collection
                for creationId in idsToAdd {
                    struct CollectionCreation: Encodable {
                        let collection_id: String
                        let creation_id: String
                    }

                    try await client
                        .from("collection_creations")
                        .insert(CollectionCreation(
                            collection_id: newCollection.id.uuidString,
                            creation_id: creationId.uuidString
                        ))
                        .execute()
                }

                await MainActor.run {
                    selectedCreationIds.removeAll()
                    isSelectMode = false
                    showNewCollectionSheet = false
                    // Refresh collections
                    collections = []
                    isLoadingCollections = false
                    loadCollections()
                }
            } catch {
                print("Failed to create collection: \(error)")
            }
        }
    }

    private func deleteCollection(_ collection: CreationCollection) {
        Haptics.warning()

        Task {
            do {
                let client = await supabaseAsync()

                // Delete collection (cascade should handle collection_creations)
                try await client
                    .from("collections")
                    .delete()
                    .eq("id", value: collection.id.uuidString)
                    .execute()

                await MainActor.run {
                    collections.removeAll { $0.id == collection.id }
                    if selectedCollection?.id == collection.id {
                        selectedCollection = nil
                    }
                }
            } catch {
                print("Failed to delete collection: \(error)")
            }
        }
    }

    private func renameCollection(_ collection: CreationCollection, newName: String) {
        Task {
            do {
                let client = await supabaseAsync()

                try await client
                    .from("collections")
                    .update(["name": newName])
                    .eq("id", value: collection.id.uuidString)
                    .execute()

                await MainActor.run {
                    if let index = collections.firstIndex(where: { $0.id == collection.id }) {
                        // Refresh collections to get updated data
                        collections = []
                        isLoadingCollections = false
                        loadCollections()
                    }
                }
            } catch {
                print("Failed to rename collection: \(error)")
            }
        }
    }

    // MARK: - Collection Detail View
    // Full modal view - no hub header visible

    private func collectionDetailView(_ collection: CreationCollection) -> some View {
        CollectionDetailContent(
            collection: collection,
            onDismiss: {
                withAnimation(DockAnimation.quick) {
                    selectedCollection = nil
                }
            },
            onOpenCreation: { creation in
                openCreation(creation)
            },
            onEditCreation: { creation in
                editCreation(creation)
            },
            onDuplicateCreation: { creation in
                duplicateCreation(creation)
            },
            onDeleteCreation: { creation in
                deleteCreation(creation)
            },
            onOpenInBrowser: { creation in
                openCreationInBrowser(creation)
            }
        )
    }

    private func refreshCreations() {
        // Reset and reload
        creations = []
        isLoadingCreations = false
        loadCreations()
    }

    private func loadCollections() {
        guard collections.isEmpty && !isLoadingCollections else { return }
        isLoadingCollections = true

        Task {
            guard let storeId = SessionObserver.shared.storeId else {
                isLoadingCollections = false
                return
            }

            do {
                let client = await supabaseAsync()
                let results: [CreationCollection] = try await client
                    .from("collections")
                    .select("id, name, description, logo_url, accent_color, is_public, location_id, created_at")
                    .eq("store_id", value: storeId.uuidString)
                    .order("created_at", ascending: false)
                    .limit(20)
                    .execute()
                    .value

                await MainActor.run {
                    collections = results
                    isLoadingCollections = false
                }
            } catch {
                await MainActor.run {
                    isLoadingCollections = false
                }
            }
        }
    }

    private func openPOSWindow(location: Location) {
        Haptics.medium()

        // Create a new POS window for this location
        stageManager.addApp(location: location)
    }

    private func openCreation(_ creation: Creation) {
        Haptics.medium()

        stageManager.addCreation(
            id: creation.id.uuidString,
            name: creation.name,
            url: creation.deployed_url,
            reactCode: creation.react_code
        )
    }

    private func createNewCreation() {
        Haptics.medium()

        // Just open chat with creation context - no empty window
        selectedTab = .messages
        let newConversation = chatListStore.createNewAIChat(title: "New Creation")

        withAnimation(DockAnimation.navigation) {
            navigateToChat(newConversation.id)
        }

        Task {
            await chatStore.startNewConversation()
            if let dbId = chatStore.workspace.conversationId {
                chatListStore.linkToDatabase(newConversation.id, databaseId: dbId)
            }
        }
    }

    private func editCreation(_ creation: Creation) {
        Haptics.medium()

        // Open creation as window
        stageManager.addCreation(
            id: creation.id.uuidString,
            name: creation.name,
            url: creation.deployed_url,
            reactCode: creation.react_code
        )

        // Start a chat context for editing this creation
        selectedTab = .messages
        let newConversation = chatListStore.createNewAIChat(title: "Edit: \(creation.name)")

        withAnimation(DockAnimation.navigation) {
            navigateToChat(newConversation.id)
        }

        // Pre-fill context about the creation
        Task {
            await chatStore.startNewConversation()
            if let dbId = chatStore.workspace.conversationId {
                chatListStore.linkToDatabase(newConversation.id, databaseId: dbId)
            }
            // Set creation context
            await MainActor.run {
                chatStore.workspace.inputText = "I want to edit my creation '\(creation.name)'"
            }
        }
    }

    private func duplicateCreation(_ creation: Creation) {
        Haptics.medium()

        Task {
            guard let storeId = SessionObserver.shared.storeId else { return }

            do {
                let client = await supabaseAsync()

                struct NewCreation: Encodable {
                    let store_id: String
                    let name: String
                    let creation_type: String
                    let react_code: String
                    let status: String
                }

                let newCreation = NewCreation(
                    store_id: storeId.uuidString,
                    name: "\(creation.name) (Copy)",
                    creation_type: creation.creation_type,
                    react_code: creation.react_code ?? "",
                    status: "draft"
                )

                try await client
                    .from("creations")
                    .insert(newCreation)
                    .execute()

                // Refresh list
                await MainActor.run {
                    creations = []
                    isLoadingCreations = false
                }
                loadCreations()
            } catch {
                print("Failed to duplicate creation: \(error)")
            }
        }
    }

    private func deleteCreation(_ creation: Creation) {
        Haptics.warning()

        Task {
            do {
                let client = await supabaseAsync()
                try await client
                    .from("creations")
                    .delete()
                    .eq("id", value: creation.id.uuidString)
                    .execute()

                await MainActor.run {
                    creations.removeAll { $0.id == creation.id }
                }
            } catch {
                print("Failed to delete creation: \(error)")
            }
        }
    }

    private func openCreationInBrowser(_ creation: Creation) {
        guard let urlString = creation.deployed_url,
              let url = URL(string: urlString) else { return }
        Haptics.light()
        UIApplication.shared.open(url)
    }

    private func loadCreations() {
        guard creations.isEmpty && !isLoadingCreations else { return }
        isLoadingCreations = true

        Task {
            guard let storeId = SessionObserver.shared.storeId else {
                isLoadingCreations = false
                return
            }

            do {
                let client = await supabaseAsync()
                let results: [Creation] = try await client
                    .from("creations")
                    .select("id, name, creation_type, deployed_url, react_code, thumbnail_url, created_at, status, is_public, visibility")
                    .eq("store_id", value: storeId.uuidString)
                    .order("updated_at", ascending: false)
                    .limit(50)
                    .execute()
                    .value

                await MainActor.run {
                    creations = results
                    isLoadingCreations = false
                }
            } catch {
                await MainActor.run {
                    isLoadingCreations = false
                }
            }
        }
    }

    // MARK: - Dimensions

    private var bottomPadding: CGFloat {
        return keyboardHeight > 0 ? keyboardHeight + 8 : SafeArea.bottom + 20
    }

    // MARK: - Expanded Header (Chat Mode)
    // Uses native Button per Apple Liquid Glass guidelines

    private var expandedHeader: some View {
        HStack(spacing: 12) {
            // Back button - native Button with proper contentShape
            NativeGlassCapsuleButton(title: "Chats", icon: "chevron.left") {
                navigateBack()
            }

            Spacer()

            // Current chat info - centered title area
            HStack(spacing: 8) {
                ZStack(alignment: .bottomTrailing) {
                    lisaAvatar
                        .frame(width: 28, height: 28)

                    // Subtle working indicator on avatar
                    if isStreaming {
                        Circle()
                            .fill(.blue)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(.black, lineWidth: 1.5))
                            .offset(x: 2, y: 2)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    if let selectedId = chatListStore.selectedConversationId,
                       let conversation = chatListStore.conversations.first(where: { $0.id == selectedId }) {
                        Text(conversation.title)
                            .font(.system(size: 14, weight: .semibold))
                    } else {
                        Text("Lisa")
                            .font(.system(size: 14, weight: .semibold))
                    }

                    // Show linked window if any
                    if let convId = chatStore.workspace.conversationId,
                       let linkedWindow = stageManager.window(forConversation: convId) {
                        HStack(spacing: 4) {
                            Image(systemName: linkedWindow.icon)
                                .font(.system(size: 9))
                            Text(linkedWindow.name)
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(.secondary)
                    }
                }

                // Typing indicator when streaming
                if isStreaming {
                    TypingIndicator()
                }
            }

            Spacer()

            // Lock screen button
            NativeGlassButton(
                icon: stageManager.isScreenLocked ? "lock.fill" : "lock.open",
                size: 44,
                isSelected: stageManager.isScreenLocked
            ) {
                Haptics.medium()
                stageManager.isScreenLocked.toggle()
            }

            // New chat button
            NativeGlassButton(icon: "plus.bubble", size: 44) {
                chatStore.clearChat()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Messages View

    private var messagesView: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 16) {
                    if messages.isEmpty && !isStreaming {
                        emptyStateView
                    } else {
                        ForEach(messages) { message in
                            SmartChatBubble(message: message)
                                // CRITICAL: Include streaming counter in ID for streaming messages
                                // This forces SwiftUI to re-render when content changes
                                .id(message.isStreaming ? "\(message.id)-\(chatStore.streamingUpdateCounter)" : message.id.uuidString)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            // Scroll on new messages
            .onChange(of: messages.count) { _, _ in
                scrollToBottom(proxy)
            }
            // CRITICAL: Force re-render when streaming content updates
            .onChange(of: chatStore.streamingUpdateCounter) { _, _ in
                scrollToBottom(proxy)
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard let lastMessage = messages.last else { return }
        // Use the same ID format as the ForEach for proper scrolling
        let scrollId = lastMessage.isStreaming ? "\(lastMessage.id)-\(chatStore.streamingUpdateCounter)" : lastMessage.id.uuidString
        withAnimation(DockAnimation.quick) {
            proxy.scrollTo(scrollId, anchor: .bottom)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("How can I help you today?")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
            SmartSuggestions(
                suggestions: SmartSuggestions.defaultSuggestions,
                onSelect: { text in
                    chatStore.workspace.inputText = text
                    chatStore.sendMessage()
                }
            )
            .padding(.horizontal, 8)
            Spacer()
        }
    }

    // MARK: - Expanded Input

    private var expandedInput: some View {
        SmartChatInput(
            text: $chatStore.workspace.inputText,
            isStreaming: isStreaming,
            onSend: { chatStore.sendMessage() },
            onCancel: { chatStore.cancelStream() }
        )
    }

    // MARK: - Keyboard Publisher (Static)

    private static let keyboardPublisher: AnyPublisher<CGFloat, Never> = {
        Publishers.Merge(
            NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
                .compactMap { ($0.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect)?.height },
            NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
                .map { _ in CGFloat(0) }
        )
        .removeDuplicates()
        .eraseToAnyPublisher()
    }()

    // MARK: - Actions

    private func selectConversation(_ conversation: ChatConversation) {
        Haptics.light()
        chatListStore.selectConversation(conversation.id)

        withAnimation(DockAnimation.navigation) {
            navigateToChat(conversation.id)
        }

        // Always switch to the correct conversation
        Task {
            if let dbId = conversation.databaseId {
                await chatStore.switchConversation(to: dbId)
            } else {
                // New conversation - start fresh and link when created
                await chatStore.startNewConversation()
                if let newDbId = chatStore.workspace.conversationId {
                    chatListStore.linkToDatabase(conversation.id, databaseId: newDbId)
                }
            }
        }
    }

    private func navigateBack() {
        Haptics.light()
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)

        // Update last message in list before going back
        if let lastMessage = messages.last,
           let selectedId = chatListStore.selectedConversationId {
            chatListStore.updateLastMessage(
                selectedId,
                message: lastMessage.content.prefix(100).description
            )
        }

        // Link database ID if conversation was just created
        if let selectedId = chatListStore.selectedConversationId,
           let dbId = chatStore.workspace.conversationId {
            chatListStore.linkToDatabase(selectedId, databaseId: dbId)
        }

        withAnimation(DockAnimation.navigation) {
            navigateToList()
        }
    }

    private func createNewChat() {
        Haptics.light()
        let newConversation = chatListStore.createNewAIChat()

        withAnimation(DockAnimation.navigation) {
            navigateToChat(newConversation.id)
        }

        // Create new conversation in database
        Task {
            await chatStore.startNewConversation()
            if let dbId = chatStore.workspace.conversationId {
                chatListStore.linkToDatabase(newConversation.id, databaseId: dbId)
            }
        }
    }

    // MARK: - Lisa Avatar

    private var lisaAvatar: some View {
        Group {
            if let logoUrl = SessionObserver.shared.store?.fullLogoUrl {
                CachedAsyncImage(url: logoUrl)
            } else {
                // Fallback gradient
                ZStack {
                    LinearGradient(
                        colors: [.purple.opacity(0.8), .blue.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .clipShape(Circle())
    }
}

// MARK: - Sell App Tile (Custom Icon)

private struct SellAppTile: View {
    private let iconURL = URL(string: "https://uaednwpxursknmwdeejn.supabase.co/storage/v1/object/public/product-images/CD2E1122-D511-4EDB-BE5D-98EF274B4BAF/generated-minimal-ios-app-icon-for-selli-1768059373397.png")

    var body: some View {
        VStack(spacing: 8) {
            AsyncImage(url: iconURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    fallbackIcon
                case .empty:
                    fallbackIcon
                @unknown default:
                    fallbackIcon
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .blue.opacity(0.4), radius: 8, y: 4)

            Text("Sell")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
                .frame(maxWidth: 70)
        }
    }

    private var fallbackIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: [.blue.opacity(0.6), .blue.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - App Tile

private struct AppTile: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            AppTileLabel(icon: icon, label: label, color: color)
        }
        .buttonStyle(LiquidPressStyle())
    }
}

// Label-only version for use with Menu
private struct AppTileLabel: View {
    let icon: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.6), color.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 56)

                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .shadow(color: color.opacity(0.4), radius: 8, y: 4)

            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
                .frame(maxWidth: 70)
        }
    }
}

// MARK: - Creation Tile (with context menu)

private struct CreationTile: View {
    let creation: Creation
    let onTap: () -> Void
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    let onOpenBrowser: () -> Void

    private var iconName: String {
        switch creation.type {
        case "display": return "tv.fill"
        case "email": return "envelope.fill"
        case "landing": return "globe"
        case "dashboard": return "chart.bar.fill"
        default: return "doc.fill"
        }
    }

    var body: some View {
        Button {
            Haptics.light()
            onTap()
        } label: {
            VStack(spacing: 8) {
                // Thumbnail or icon
                ZStack {
                    if let thumbnailUrl = creation.thumbnailUrl,
                       let url = URL(string: thumbnailUrl) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            default:
                                iconFallback
                            }
                        }
                    } else {
                        iconFallback
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .purple.opacity(0.4), radius: 8, y: 4)

                Text(creation.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
                    .frame(maxWidth: 70)
            }
        }
        .buttonStyle(LiquidPressStyle())
        .contextMenu {
            Button {
                onEdit()
            } label: {
                Label("Edit with AI", systemImage: "pencil")
            }

            Button {
                onDuplicate()
            } label: {
                Label("Duplicate", systemImage: "doc.on.doc")
            }

            if creation.deployed_url != nil {
                Button {
                    onOpenBrowser()
                } label: {
                    Label("Open in Browser", systemImage: "safari")
                }
            }

            Divider()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var iconFallback: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.purple.opacity(0.6), .purple.opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Image(systemName: iconName)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Collection Picker Sheet

private struct CollectionPickerSheet: View {
    let collections: [CreationCollection]
    let onSelect: (CreationCollection) -> Void
    let onCreateNew: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // Create new collection option
                Button {
                    onCreateNew()
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.blue.opacity(0.2))
                                .frame(width: 40, height: 40)

                            Image(systemName: "plus")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.blue)
                        }

                        Text("New Collection")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.blue)

                        Spacer()
                    }
                }
                .listRowBackground(Color.clear)

                // Existing collections
                ForEach(collections, id: \.id) { collection in
                    Button {
                        onSelect(collection)
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(hex: collection.accentColor ?? "#8B5CF6").opacity(0.3))
                                    .frame(width: 40, height: 40)

                                Image(systemName: "folder.fill")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(Color(hex: collection.accentColor ?? "#8B5CF6"))
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(collection.name)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(.primary)

                                if let count = collection.creationCount {
                                    Text("\(count) item\(count == 1 ? "" : "s")")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Add to Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - New Collection Sheet

private struct NewCollectionSheet: View {
    let onSave: (String, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selectedColor = "#8B5CF6"

    private let colorOptions = [
        "#8B5CF6", // Purple
        "#3B82F6", // Blue
        "#10B981", // Green
        "#F59E0B", // Amber
        "#EF4444", // Red
        "#EC4899", // Pink
        "#6366F1", // Indigo
        "#14B8A6", // Teal
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Collection Name", text: $name)
                }

                Section("Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 16) {
                        ForEach(colorOptions, id: \.self) { color in
                            Button {
                                selectedColor = color
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(Color(hex: color))
                                        .frame(width: 44, height: 44)

                                    if selectedColor == color {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("New Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        onSave(name, selectedColor)
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - Collection Detail Content

private struct CollectionDetailContent: View {
    let collection: CreationCollection
    let onDismiss: () -> Void
    let onOpenCreation: (Creation) -> Void
    let onEditCreation: (Creation) -> Void
    let onDuplicateCreation: (Creation) -> Void
    let onDeleteCreation: (Creation) -> Void
    let onOpenInBrowser: (Creation) -> Void

    @State private var creations: [Creation] = []
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            // Full modal header
            HStack {
                Button(action: onDismiss) {
                    Text("Done")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(.blue)
                }

                Spacer()

                VStack(spacing: 2) {
                    Text(collection.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)

                    if let count = collection.creationCount, count > 0 {
                        Text("\(count) items")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }

                Spacer()

                // Placeholder for balance
                Text("Done")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(.clear)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            // Content
            if isLoading {
                Spacer()
                ProgressView()
                    .tint(.white.opacity(0.5))
                Spacer()
            } else if creations.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "folder")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(.white.opacity(0.3))
                    Text("No creations in this collection")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 4),
                        spacing: 20
                    ) {
                        ForEach(creations, id: \.id) { creation in
                            CreationTile(creation: creation) {
                                onOpenCreation(creation)
                            } onEdit: {
                                onEditCreation(creation)
                            } onDuplicate: {
                                onDuplicateCreation(creation)
                            } onDelete: {
                                onDeleteCreation(creation)
                            } onOpenBrowser: {
                                onOpenInBrowser(creation)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            loadCollectionCreations()
        }
    }

    private func loadCollectionCreations() {
        Task {
            // Use the join approach directly
            await loadViaJoin()
        }
    }

    private func loadViaJoin() async {
        do {
            let client = await supabaseAsync()

            struct CollectionCreationRow: Codable {
                let creation_id: UUID
                let creation: Creation?
            }

            let results: [CollectionCreationRow] = try await client
                .from("collection_creations")
                .select("creation_id, creation:creations(id, name, creation_type, deployed_url, react_code, thumbnail_url, created_at, status, is_public, visibility, location_id, is_pinned, pinned_at, pin_order, is_template)")
                .eq("collection_id", value: collection.id.uuidString)
                .execute()
                .value

            await MainActor.run {
                creations = results.compactMap { $0.creation }
                isLoading = false
            }
        } catch {
            print("Failed to load via join: \(error)")
            await MainActor.run {
                isLoading = false
            }
        }
    }
}

// MARK: - Collection Pill

private struct CollectionPill: View {
    let collection: CreationCollection
    let onTap: () -> Void
    var onRename: ((String) -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    @State private var showRenameAlert = false
    @State private var newName = ""

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                // Icon or logo
                if let logoUrl = collection.logoUrl,
                   let url = URL(string: logoUrl) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 24, height: 24)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        default:
                            defaultIcon
                        }
                    }
                } else {
                    defaultIcon
                }

                Text(collection.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)

                if let count = collection.creationCount, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.white.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(.white.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                newName = collection.name
                showRenameAlert = true
            } label: {
                Label("Rename", systemImage: "pencil")
            }

            Divider()

            Button(role: .destructive) {
                onDelete?()
            } label: {
                Label("Delete Collection", systemImage: "trash")
            }
        }
        .alert("Rename Collection", isPresented: $showRenameAlert) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                if !newName.trimmingCharacters(in: .whitespaces).isEmpty {
                    onRename?(newName)
                }
            }
        }
    }

    private var defaultIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(hex: collection.accentColor ?? "#8B5CF6").opacity(0.6))
                .frame(width: 24, height: 24)

            Image(systemName: "folder.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Selectable Creation Tile (for bulk selection)

private struct SelectableCreationTile: View {
    let creation: Creation
    let isSelected: Bool
    let onTap: () -> Void

    private var iconName: String {
        switch creation.type {
        case "display": return "tv.fill"
        case "email": return "envelope.fill"
        case "landing": return "globe"
        case "dashboard": return "chart.bar.fill"
        default: return "doc.fill"
        }
    }

    var body: some View {
        Button {
            Haptics.light()
            onTap()
        } label: {
            VStack(spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    // Thumbnail or icon
                    ZStack {
                        if let thumbnailUrl = creation.thumbnailUrl,
                           let url = URL(string: thumbnailUrl) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                default:
                                    iconFallback
                                }
                            }
                        } else {
                            iconFallback
                        }
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(isSelected ? .blue : .clear, lineWidth: 3)
                    )

                    // Selection checkmark
                    ZStack {
                        Circle()
                            .fill(isSelected ? .blue : .white.opacity(0.3))
                            .frame(width: 22, height: 22)

                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .offset(x: 6, y: -6)
                }

                Text(creation.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
                    .frame(maxWidth: 70)
            }
        }
        .buttonStyle(.plain)
    }

    private var iconFallback: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.purple.opacity(0.6), .purple.opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Image(systemName: iconName)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - App Icon Tile
// Clean iOS-style app icon with label

private struct AppIconTile: View {
    let icon: String
    let label: String
    let color: Color
    var action: (() -> Void)? = nil

    var body: some View {
        Group {
            if let action = action {
                Button(action: action) {
                    tileContent
                }
                .buttonStyle(LiquidPressStyle())
            } else {
                tileContent
            }
        }
    }

    private var tileContent: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(color.gradient)
                    .frame(width: 60, height: 60)

                Image(systemName: icon)
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(.white)
            }

            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
        }
    }
}

// MARK: - Typing Indicator

private struct TypingIndicator: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(.secondary)
                    .frame(width: 4, height: 4)
                    .offset(y: animating ? -3 : 0)
                    .animation(
                        .easeInOut(duration: 0.4)
                        .repeatForever()
                        .delay(Double(index) * 0.12),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
    }
}

// MARK: - POS Location Selector Sheet

private struct POSLocationSelectorSheet: View {
    @Binding var selectedStoreId: UUID?
    @Binding var locations: [Location]
    @Binding var isLoading: Bool
    let onSelectLocation: (Location) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Store Picker (only if multiple stores)
                if SessionObserver.shared.hasMultipleStores {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SELECT STORE")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(SessionObserver.shared.userStoreAssociations) { association in
                                    Button {
                                        selectStore(association.storeId)
                                    } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: "building.2.fill")
                                            Text(association.displayName)
                                                .fontWeight(.medium)
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                        .background(
                                            selectedStoreId == association.storeId
                                                ? Color.blue
                                                : Color(.systemGray5)
                                        )
                                        .foregroundStyle(
                                            selectedStoreId == association.storeId
                                                ? .white
                                                : .primary
                                        )
                                        .clipShape(Capsule())
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical)

                    Divider()
                }

                // Locations List
                if isLoading {
                    Spacer()
                    ProgressView("Loading locations...")
                    Spacer()
                } else if locations.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "storefront")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("No locations available")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                } else {
                    List(locations) { location in
                        Button {
                            onSelectLocation(location)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(location.name)
                                        .font(.headline)
                                    if let address = location.addressLine1 {
                                        Text(address)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Open POS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func selectStore(_ storeId: UUID) {
        guard storeId != selectedStoreId else { return }
        selectedStoreId = storeId
        isLoading = true
        locations = []

        Task {
            // Fetch locations for this store
            do {
                let fetchedLocations = try await fetchLocationsForStore(storeId)
                await MainActor.run {
                    locations = fetchedLocations
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                }
            }
        }
    }

    private func fetchLocationsForStore(_ storeId: UUID) async throws -> [Location] {
        let response: [Location] = try await supabase
            .from("locations")
            .select()
            .eq("store_id", value: storeId.uuidString)
            .eq("is_active", value: true)
            .eq("pos_enabled", value: true)
            .order("name")
            .execute()
            .value
        return response
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        SmartDockView()
    }
}
