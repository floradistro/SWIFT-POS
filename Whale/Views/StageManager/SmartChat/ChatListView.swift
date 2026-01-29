//
//  ChatListView.swift
//  Whale
//
//  iMessage-style conversation list for the Smart Dock.
//  Shows AI agent chats, staff messages, all in one unified view.
//  Native iOS 26 Liquid Glass design.
//

import SwiftUI

// MARK: - Chat List View

struct ChatListView: View {
    @ObservedObject var store: ChatListStore
    let onSelectChat: (ChatConversation) -> Void
    let onNewChat: () -> Void

    @State private var searchText = ""
    @State private var showNewChatOptions = false
    @FocusState private var isSearchFocused: Bool

    private var filteredConversations: [ChatConversation] {
        if searchText.isEmpty {
            return store.conversations
        }
        return store.conversations.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            ($0.lastMessage?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            // Search bar - native iOS 26 glass
            searchBar
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

            // Active agents banner (if any)
            if !store.activeAgents.isEmpty {
                activeAgentsBanner
            }

            // Conversation list
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    // Pinned section
                    if !store.pinnedConversations.isEmpty {
                        sectionHeader("Pinned")
                        ForEach(store.pinnedConversations.filter { conv in
                            searchText.isEmpty || conv.title.localizedCaseInsensitiveContains(searchText)
                        }) { conversation in
                            ChatRowView(conversation: conversation) {
                                onSelectChat(conversation)
                            }
                        }
                    }

                    // Recent section
                    let unpinned = store.unpinnedConversations.filter { conv in
                        searchText.isEmpty || conv.title.localizedCaseInsensitiveContains(searchText)
                    }
                    if !unpinned.isEmpty {
                        sectionHeader(store.pinnedConversations.isEmpty ? "" : "Recent")
                        ForEach(unpinned) { conversation in
                            ChatRowView(conversation: conversation) {
                                onSelectChat(conversation)
                            }
                        }
                    }

                    // Empty state
                    if filteredConversations.isEmpty {
                        emptyState
                    }
                }
                .padding(.bottom, 20)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Messages")
                .font(.system(size: 22, weight: .bold))

            Spacer()

            // New chat button - 44pt minimum per Apple HIG
            LiquidGlassIconButton(icon: "square.and.pencil", size: 44) {
                showNewChatOptions = true
            }
            .confirmationDialog("New Conversation", isPresented: $showNewChatOptions) {
                Button("New AI Chat") {
                    onNewChat()
                }
                Button("Message Staff") {
                    // TODO: Staff picker
                }
                Button("Cancel", role: .cancel) { }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    // MARK: - Search Bar (Native iOS 26 Glass)

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isSearchFocused ? .primary : .secondary)

            TextField("Search", text: $searchText)
                .font(.system(size: 15))
                .focused($isSearchFocused)

            if !searchText.isEmpty {
                Button {
                    Haptics.light()
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    // MARK: - Active Agents Banner

    private var activeAgentsBanner: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(store.activeAgents) { agent in
                    ActiveAgentPill(conversation: agent) {
                        onSelectChat(agent)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 12)
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String) -> some View {
        Group {
            if !title.isEmpty {
                HStack {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                        .textCase(.uppercase)
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 8)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.tertiary)

            Text("No conversations yet")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)

            // Liquid glass button
            LiquidGlassButton(title: "Start a new chat", icon: "plus.bubble", style: .primary) {
                onNewChat()
            }
            .frame(width: 200)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

// MARK: - Active Agent Pill (Liquid Glass)

struct ActiveAgentPill: View {
    let conversation: ChatConversation
    let onTap: () -> Void

    /// Store logo for AI agent avatar
    private var storeLogoUrl: URL? {
        SessionObserver.shared.store?.fullLogoUrl
    }

    @State private var isPulsing = false

    var body: some View {
        // Uses highPriorityGesture to avoid gesture gate conflicts
        HStack(spacing: 8) {
            // Pulsing status dot
            Circle()
                .fill(conversation.agentStatus?.color ?? .blue)
                .frame(width: 8, height: 8)
                .scaleEffect(isPulsing ? 1.2 : 1.0)
                .shadow(color: (conversation.agentStatus?.color ?? .blue).opacity(isPulsing ? 0.8 : 0.4), radius: isPulsing ? 6 : 3)

            // Title only - no verbose status
            Text(conversation.title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)

            // Simple typing dots
            HStack(spacing: 2) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(.secondary)
                        .frame(width: 3, height: 3)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Capsule())
        .glassEffect(.regular.interactive(), in: .capsule)
        .highPriorityGesture(
            TapGesture()
                .onEnded {
                    Haptics.light()
                    onTap()
                }
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        ChatListView(
            store: ChatListStore.shared,
            onSelectChat: { _ in },
            onNewChat: { }
        )
        .frame(width: 400, height: 500)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.regularMaterial)
        )
    }
}
