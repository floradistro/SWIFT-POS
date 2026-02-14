//
//  ConversationListView.swift
//  Whale
//
//  Conversation list sidebar with search, floating iOS 18 search bar, and conversation rows.
//  Extracted from TeamChatPanel.
//

import SwiftUI

// MARK: - Conversation List (Sidebar)

struct ConversationListView: View {
    @ObservedObject var chatStore: ChatStore
    @Binding var selectedConversation: ChatConversation?
    var onSelect: ((ChatConversation) -> Void)?

    @EnvironmentObject private var session: SessionObserver
    @State private var searchText = ""
    @State private var isSearchFocused = false

    @Environment(\.horizontalSizeClass) private var sizeClass
    private var isCompact: Bool { sizeClass == .compact }

    private var filteredConversations: [ChatConversation] {
        if searchText.isEmpty {
            return chatStore.conversations
        }
        return chatStore.conversations.filter {
            $0.displayTitle.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            List {
                ForEach(filteredConversations, id: \.id) { conversation in
                    Button {
                        Haptics.selection()
                        selectedConversation = conversation
                        onSelect?(conversation)
                    } label: {
                        ConversationRow(
                            conversation: conversation,
                            chatStore: chatStore,
                            isSelected: selectedConversation?.id == conversation.id,
                            storeLogoUrl: session.store?.fullLogoUrl
                        )
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowBackground(
                        selectedConversation?.id == conversation.id
                            ? Design.Colors.Glass.regular
                            : Color.clear
                    )
                }

            }
            .listStyle(.plain)
            .contentMargins(.bottom, isCompact ? 80 : 0, for: .scrollContent)

            // iPhone: Floating bottom search bar (iOS 18 iMessage style)
            if isCompact {
                floatingSearchBar
            }
        }
        .navigationTitle("Messages")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            // iPad only: compose button
            if !isCompact {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.light()
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.body)
                            .fontWeight(.medium)
                    }
                }
            }
        }
        // iPad only: search at top in navigation bar
        .modifier(iPadSearchModifier(searchText: $searchText, isCompact: isCompact))
        .refreshable {
            await chatStore.loadConversations()
        }
        .overlay {
            if chatStore.isLoadingConversations && chatStore.conversations.isEmpty {
                ProgressView()
                    .scaleEffect(1.2)
            } else if chatStore.conversations.isEmpty {
                ContentUnavailableView(
                    "No Messages",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Your conversations will appear here")
                )
            }
        }
    }

    // MARK: - Floating Search Bar (iOS 18 iMessage style)

    private var floatingSearchBar: some View {
        HStack(spacing: 12) {
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(Design.Typography.callout)
                    .fontWeight(.medium)
                    .foregroundStyle(Design.Colors.Text.secondary)
                    .accessibilityHidden(true)

                TextField("Search", text: $searchText)
                    .font(Design.Typography.body)
                    .foregroundStyle(Design.Colors.Text.primary)

                // Microphone button
                Button {
                    Haptics.light()
                } label: {
                    Image(systemName: "mic.fill")
                        .font(Design.Typography.callout)
                        .foregroundStyle(Design.Colors.Text.secondary)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Dictate")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .glassEffect(.regular, in: .capsule)

            // Compose button
            Button {
                Haptics.light()
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(Design.Typography.body)
                    .fontWeight(.medium)
                    .foregroundStyle(Design.Colors.Text.primary)
                    .frame(width: 46, height: 46)
                    .glassEffect(.regular, in: .circle)
            }
            .accessibilityLabel("New message")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
}

// MARK: - iPad Search Modifier (conditional searchable)

struct iPadSearchModifier: ViewModifier {
    @Binding var searchText: String
    let isCompact: Bool

    func body(content: Content) -> some View {
        if isCompact {
            // iPhone: no system searchable, we use floating bar
            content
        } else {
            // iPad: system searchable at top
            content.searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search")
        }
    }
}

// MARK: - Conversation Row (List Item)

struct ConversationRow: View {
    let conversation: ChatConversation
    @ObservedObject var chatStore: ChatStore
    var isSelected: Bool = false
    var storeLogoUrl: URL?
    @Environment(\.horizontalSizeClass) private var sizeClass

    // Responsive sizes for mobile vs iPad
    private var avatarSize: CGFloat { sizeClass == .compact ? 44 : 52 }
    private var iconSize: CGFloat { sizeClass == .compact ? 18 : 22 }

    private var lastMessage: ChatMessage? {
        guard chatStore.activeConversationId == conversation.id else { return nil }
        return chatStore.messages.last
    }

    /// Preview from lastMessagePreviews (available for all conversations via realtime)
    private var storedPreview: String? {
        chatStore.lastMessagePreviews[conversation.id]
    }

    private var isUnread: Bool {
        (chatStore.unreadCounts[conversation.id] ?? 0) > 0
    }

    private var isPinned: Bool { chatStore.isPinned(conversation.id) }
    private var isMuted: Bool { chatStore.isMuted(conversation.id) }

    var body: some View {
        HStack(spacing: sizeClass == .compact ? 10 : 12) {
            // Avatar — store logo for team chats, colored icon for AI/alerts/bugs
            ConversationAvatar(
                conversation: conversation,
                size: avatarSize,
                iconSize: iconSize,
                logoUrl: storeLogoUrl
            )
            .accessibilityHidden(true)

            // Content
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(conversation.displayTitle)
                        .font(sizeClass == .compact ? Design.Typography.callout : Design.Typography.body)
                        .fontWeight(isUnread ? .semibold : .regular)
                        .foregroundStyle(Design.Colors.Text.primary)
                        .lineLimit(1)

                    if isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Design.Colors.Text.tertiary)
                            .accessibilityLabel("Pinned")
                    }

                    if isMuted {
                        Image(systemName: "bell.slash.fill")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Design.Colors.Text.tertiary)
                            .accessibilityLabel("Muted")
                    }

                    Spacer()

                    HStack(spacing: 4) {
                        if isUnread {
                            let count = chatStore.unreadCounts[conversation.id] ?? 0
                            Text("\(count)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.accentColor))
                                .accessibilityLabel("\(count) unread")
                        }

                        Text(formatDate(conversation.updatedAt))
                            .font(sizeClass == .compact ? Design.Typography.caption1 : Design.Typography.subhead)
                            .foregroundStyle(isUnread ? Design.Colors.Text.primary : Design.Colors.Text.tertiary)

                        Image(systemName: "chevron.right")
                            .font(sizeClass == .compact ? Design.Typography.caption2 : Design.Typography.caption1)
                            .fontWeight(.semibold)
                            .foregroundStyle(Design.Colors.Text.tertiary)
                            .accessibilityHidden(true)
                    }
                }

                // Preview text - exactly like iMessage
                Text(previewText)
                    .font(sizeClass == .compact ? Design.Typography.caption1 : Design.Typography.subhead)
                    .foregroundStyle(Design.Colors.Text.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, sizeClass == .compact ? 6 : 8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(conversation.displayTitle)\(isPinned ? ", Pinned" : "")\(isMuted ? ", Muted" : ""), \(previewText), \(formatDate(conversation.updatedAt))")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var previewText: String {
        if let last = lastMessage {
            return String(last.content.prefix(100))
        }
        if let preview = storedPreview {
            return preview
        }
        return conversation.chatType == .ai ? "AI Assistant ready to help" : "No messages yet"
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f
    }()

    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        return f
    }()

    private func formatDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return Self.timeFormatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else if let daysAgo = calendar.dateComponents([.day], from: date, to: Date()).day, daysAgo < 7 {
            return Self.dayFormatter.string(from: date)
        } else {
            return Self.shortDateFormatter.string(from: date)
        }
    }
}
