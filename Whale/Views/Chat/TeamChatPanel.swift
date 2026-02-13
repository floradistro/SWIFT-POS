//
//  TeamChatPanel.swift
//  Whale
//
//  iMessage-style chat interface.
//  iPad: Split view with conversation list + messages
//  iPhone: Navigation stack with list → detail push
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers
import Combine
import os.log

// MARK: - Main Chat Panel (Adaptive Layout)

struct TeamChatPanel: View {
    @ObservedObject var chatStore: ChatStore
    @EnvironmentObject private var session: SessionObserver
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        Group {
            if sizeClass == .regular {
                // iPad: Split view like iMessage
                iPadChatSplitView(chatStore: chatStore)
            } else {
                // iPhone: Navigation stack
                iPhoneChatStackView(chatStore: chatStore)
            }
        }
        .task {
            // Request notification permission on first launch
            await ChatNotificationService.shared.requestPermissionIfNeeded()
            ChatNotificationService.shared.setupNotificationCategories()
        }
    }
}

// MARK: - iPad Split View

private struct iPadChatSplitView: View {
    @ObservedObject var chatStore: ChatStore
    @State private var selectedConversation: ChatConversation?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            ConversationListView(
                chatStore: chatStore,
                selectedConversation: $selectedConversation
            )
            .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 400)
        } detail: {
            if let conversation = selectedConversation ?? chatStore.activeConversation {
                MessageThreadView(chatStore: chatStore, conversation: conversation)
            } else {
                emptyDetailView
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: selectedConversation) { _, newValue in
            if let conv = newValue {
                chatStore.activeConversationId = conv.id
                Task { await chatStore.loadMessages() }
                // Clear notifications for this conversation
                ChatNotificationService.shared.clearNotifications(for: conv.id)
            }
        }
        .onAppear {
            // Auto-select first conversation if none selected
            if selectedConversation == nil, let first = chatStore.conversations.first {
                selectedConversation = first
            }
        }
        .onChange(of: chatStore.conversations) { _, convs in
            if selectedConversation == nil, let first = convs.first {
                selectedConversation = first
            }
        }
    }

    private var emptyDetailView: some View {
        VStack(spacing: 16) {
            // Simple icon like iMessage
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 64, weight: .thin))
                .foregroundStyle(Design.Colors.Text.tertiary)

            VStack(spacing: 4) {
                Text("No Conversation Selected")
                    .font(Design.Typography.title3).fontWeight(.semibold)
                    .foregroundStyle(Design.Colors.Text.primary)

                Text("Choose a conversation from the sidebar")
                    .font(Design.Typography.subhead)
                    .foregroundStyle(Design.Colors.Text.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Design.Colors.backgroundPrimary)
    }
}

// MARK: - iPhone Navigation Stack

private struct iPhoneChatStackView: View {
    @ObservedObject var chatStore: ChatStore
    @State private var selectedConversation: ChatConversation?

    var body: some View {
        ZStack {
            // Conversation list (always rendered, hidden when thread is shown)
            ConversationListView(
                chatStore: chatStore,
                selectedConversation: $selectedConversation,
                onSelect: { conversation in
                    chatStore.activeConversationId = conversation.id
                    Task { await chatStore.loadMessages() }
                    ChatNotificationService.shared.clearNotifications(for: conversation.id)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                        selectedConversation = conversation
                    }
                }
            )
            .navigationTitle("Messages")
            .navigationBarTitleDisplayMode(.large)
            .opacity(selectedConversation == nil ? 1 : 0)

            // Message thread (slides in from right)
            if let conversation = selectedConversation {
                MessageThreadView(
                    chatStore: chatStore,
                    conversation: conversation,
                    onBack: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                            selectedConversation = nil
                        }
                    }
                )
                .transition(.move(edge: .trailing))
            }
        }
    }
}

// MARK: - Conversation List (Sidebar)

private struct ConversationListView: View {
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
                        chatStore.activeConversationId = conversation.id
                        Task { await chatStore.loadMessages() }
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

private struct iPadSearchModifier: ViewModifier {
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

private struct ConversationRow: View {
    let conversation: ChatConversation
    @ObservedObject var chatStore: ChatStore
    var isSelected: Bool = false
    var storeLogoUrl: URL?
    @Environment(\.horizontalSizeClass) private var sizeClass

    // Responsive sizes for mobile vs iPad
    private var avatarSize: CGFloat { sizeClass == .compact ? 44 : 52 }
    private var iconSize: CGFloat { sizeClass == .compact ? 18 : 22 }

    private var lastMessage: ChatMessage? {
        // Only show preview for the active conversation (messages array only has active conversation's messages)
        guard chatStore.activeConversationId == conversation.id else { return nil }
        return chatStore.messages.last
    }

    private var isUnread: Bool {
        // Placeholder for unread logic
        false
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
                        Text(formatDate(conversation.updatedAt))
                            .font(sizeClass == .compact ? Design.Typography.caption1 : Design.Typography.subhead)
                            .foregroundStyle(Design.Colors.Text.tertiary)

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
            // Truncate long messages
            let text = last.content.prefix(100)
            return String(text)
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

// MARK: - Message Thread View

private struct MessageThreadView: View {
    @ObservedObject var chatStore: ChatStore
    let conversation: ChatConversation
    var onBack: (() -> Void)?
    @EnvironmentObject private var session: SessionObserver
    @Environment(\.horizontalSizeClass) private var sizeClass
    @FocusState private var isInputFocused: Bool
    @State private var showSettings = false
    @State private var showMessageSearch = false
    @State private var messageSearchText = ""
    @State private var keyboardHeight: CGFloat = 0
    @State private var isFollowingBottom = true

    var body: some View {
        VStack(spacing: 0) {
            // iPhone back bar — padded below status bar / Dynamic Island
            if sizeClass == .compact, let onBack {
                HStack(spacing: 8) {
                    Button { onBack() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(Design.Typography.body).fontWeight(.semibold)
                            Text("Back")
                                .font(Design.Typography.body)
                        }
                        .foregroundStyle(Design.Colors.Semantic.accent)
                    }
                    Spacer()
                    Button {
                        Haptics.light()
                        showSettings = true
                    } label: {
                        Text(conversation.displayTitle)
                            .font(Design.Typography.headline)
                            .foregroundStyle(Design.Colors.Text.primary)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Color.clear.frame(width: 60)
                }
                .padding(.horizontal, 16)
                .padding(.top, SafeArea.top + 6)
                .padding(.bottom, 10)
                .background(.ultraThinMaterial)
            }

            // In-thread search bar
            if showMessageSearch {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(Design.Typography.callout)
                        .foregroundStyle(Design.Colors.Text.secondary)
                        .accessibilityHidden(true)

                    TextField("Search messages...", text: $messageSearchText)
                        .font(Design.Typography.body)
                        .textFieldStyle(.plain)

                    if !messageSearchText.isEmpty {
                        Button {
                            messageSearchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(Design.Typography.callout)
                                .foregroundStyle(Design.Colors.Text.tertiary)
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            showMessageSearch = false
                            messageSearchText = ""
                        }
                    } label: {
                        Text("Cancel")
                            .font(Design.Typography.callout)
                            .foregroundStyle(Design.Colors.Semantic.accent)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Design.Colors.Glass.thin)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            messagesScrollView

            MessageInputBar(
                chatStore: chatStore,
                isInputFocused: $isInputFocused,
                onSend: {}
            )
        }
        .padding(.bottom, adjustedKeyboardHeight)
        .ignoresSafeArea(.keyboard)
        .background(Design.Colors.backgroundPrimary)
        .navigationTitle(conversation.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if sizeClass == .regular {
                ToolbarItem(placement: .principal) {
                    conversationHeader
                }
            }
        }
        .onAppear {
            Task { await chatStore.loadAgentsIfNeeded() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
            guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            // Only adjust for docked keyboard (not iPad floating keyboard)
            guard frame.maxY >= UIScreen.main.bounds.height - 1 else { return }
            let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
            withAnimation(.easeOut(duration: duration)) {
                keyboardHeight = frame.height
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { notification in
            let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
            withAnimation(.easeOut(duration: duration)) {
                keyboardHeight = 0
            }
        }
        .sheet(isPresented: $showSettings) {
            ChatSettingsSheet(conversation: conversation, chatStore: chatStore, onSearch: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    showMessageSearch = true
                }
            })
        }
    }

    private var adjustedKeyboardHeight: CGFloat {
        guard keyboardHeight > 0 else { return 0 }
        let bottomSafeArea = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first(where: \.isKeyWindow)?.safeAreaInsets.bottom ?? 0
        return max(keyboardHeight - bottomSafeArea, 0)
    }

    private var conversationHeader: some View {
        Button {
            Haptics.light()
            showSettings = true
        } label: {
            VStack(spacing: 4) {
                ConversationAvatar(
                    conversation: conversation,
                    size: 36,
                    iconSize: 16,
                    logoUrl: session.store?.fullLogoUrl
                )
                .accessibilityHidden(true)
                .padding(.top, 8)

                // Title and subtitle in liquid glass pill
                VStack(spacing: 0) {
                    Text(conversation.displayTitle)
                        .font(Design.Typography.subhead)
                        .fontWeight(.semibold)
                        .foregroundStyle(Design.Colors.Text.primary)

                    if conversation.chatType == .ai {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Design.Colors.Semantic.success)
                                .frame(width: 5, height: 5)
                                .accessibilityHidden(true)
                            Text("Active")
                                .font(Design.Typography.caption2)
                                .foregroundStyle(Design.Colors.Text.secondary)
                        }
                    } else if !subtitleText.isEmpty {
                        Text(subtitleText)
                            .font(Design.Typography.caption2)
                            .foregroundStyle(Design.Colors.Text.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .glassEffect(.regular.interactive(), in: .capsule)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(conversation.displayTitle), \(conversation.chatType == .ai ? "Active" : subtitleText)")
    }

    private var subtitleText: String {
        switch conversation.chatType {
        case .team: return "Team"
        case .location: return ""
        case .dm: return "Direct Message"
        case .ai: return "AI Assistant"
        case .alerts: return "Alerts"
        case .bugs: return "Bug Reports"
        }
    }

    private var messagesScrollView: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(groupedMessages, id: \.date) { group in
                            Text(formatDateHeader(group.date))
                                .font(Design.Typography.caption2)
                                .fontWeight(.semibold)
                                .foregroundStyle(Design.Colors.Text.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Design.Colors.Glass.regular.opacity(0.6), in: Capsule())
                                .padding(.vertical, 12)

                            ForEach(group.messages) { message in
                                let isStreaming = chatStore.streamingMessageId == message.id
                                if !message.displayContent.isEmpty || isStreaming {
                                    messageBubbleView(message: message, group: group)
                                }
                            }
                        }

                        // WhaleChat GeneratingBar — always visible during streaming
                        if chatStore.isAgentStreaming {
                            GeneratingBar(toolName: chatStore.agentCurrentTool)
                        }

                        Color.clear.frame(height: 1).id("bottom")
                            .onAppear { isFollowingBottom = true }
                            .onDisappear { /* user scrolled away — DragGesture handles this */ }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                }
                .defaultScrollAnchor(.bottom)
                .scrollDismissesKeyboard(.interactively)
                // Detect user scroll-up to disable auto-follow
                .simultaneousGesture(
                    DragGesture(minimumDistance: 10)
                        .onChanged { value in
                            // Only vertical-dominant drags (avoid horizontal code block scrolls)
                            if abs(value.translation.height) > abs(value.translation.width) {
                                if value.translation.height > 0 {
                                    // Scrolling up (finger dragging down) — stop following
                                    isFollowingBottom = false
                                }
                            }
                        }
                )
                // Streaming scroll: observe cheap UInt version counter, not String content
                .onReceive(
                    chatStore.agentStreamingBuffer.$version
                        .throttle(for: .milliseconds(80), scheduler: DispatchQueue.main, latest: true)
                ) { _ in
                    guard isFollowingBottom && chatStore.isAgentStreaming else { return }
                    // Defer scroll to after SwiftUI layout pass
                    DispatchQueue.main.async {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                // New message: always scroll with animation
                .onChange(of: chatStore.messages.count) { _, _ in
                    isFollowingBottom = true
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                // Keyboard: smooth scroll
                .onChange(of: keyboardHeight) { _, newHeight in
                    if newHeight > 0 {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }

                // Scroll-to-bottom FAB
                if !isFollowingBottom {
                    Button {
                        Haptics.light()
                        isFollowingBottom = true
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Design.Colors.Text.secondary)
                            .frame(width: 36, height: 36)
                            .background(.ultraThinMaterial, in: Circle())
                            .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 12)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityLabel("Scroll to bottom")
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isFollowingBottom)
        }
    }

    private func messageBubbleView(message: ChatMessage, group: MessageGroup) -> some View {
        let index = group.messages.firstIndex(where: { $0.id == message.id }) ?? 0
        let previous = index > 0 ? group.messages[index - 1] : nil

        return iMessageBubble(
            message: message,
            previousMessage: previous,
            isFromCurrentUser: message.senderId == session.userId || message.isUser,
            chatStore: chatStore
        )
    }

    private struct MessageGroup {
        let date: Date
        let messages: [ChatMessage]
    }

    private var groupedMessages: [MessageGroup] {
        let calendar = Calendar.current
        var groups: [Date: [ChatMessage]] = [:]

        let source: [ChatMessage]
        if showMessageSearch && !messageSearchText.isEmpty {
            let query = messageSearchText.lowercased()
            source = chatStore.messages.filter { $0.content.localizedCaseInsensitiveContains(query) }
        } else {
            source = chatStore.messages
        }

        for message in source {
            let startOfDay = calendar.startOfDay(for: message.createdAt)
            groups[startOfDay, default: []].append(message)
        }

        return groups.map { MessageGroup(date: $0.key, messages: $0.value) }
            .sorted { $0.date < $1.date }
    }

    private func formatDateHeader(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, MMMM d"
            return formatter.string(from: date)
        }
    }
}

// MARK: - iMessage Bubble

private struct iMessageBubble: View {
    let message: ChatMessage
    let previousMessage: ChatMessage?
    let isFromCurrentUser: Bool
    @ObservedObject var chatStore: ChatStore

    private var isCompleted: Bool {
        chatStore.completedMessageIds.contains(message.id)
    }

    private var completedTask: ChatTask? {
        chatStore.completedTasks.first { $0.messageId == message.id }
    }

    private var showTimestamp: Bool {
        guard let prev = previousMessage else { return false }
        return message.createdAt.timeIntervalSince(prev.createdAt) > 300
    }

    private var isToolCall: Bool {
        message.content.hasPrefix("tool:") || message.content.hasPrefix("tool_done:")
    }

    private var toolCallInfo: (name: String, done: Bool, success: Bool, summary: String)? {
        let content = message.content
        if content.hasPrefix("tool_done:") {
            let parts = content.dropFirst("tool_done:".count).components(separatedBy: ":")
            if parts.count >= 3 {
                return (parts[1], true, parts[0] == "1", parts.dropFirst(2).joined(separator: ":"))
            }
        } else if content.hasPrefix("tool:") {
            return (String(content.dropFirst("tool:".count)), false, false, "")
        }
        return nil
    }

    // Get sender name for reply
    private var senderName: String {
        if message.isAssistant {
            // Find which agent sent this
            return chatStore.defaultAgent?.displayName ?? "Wilson"
        } else if let senderId = message.senderId {
            return chatStore.senderName(for: senderId)
        }
        return "User"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if showTimestamp {
                Text(formatTime(message.createdAt))
                    .font(Design.Typography.caption2)
                    .foregroundStyle(Design.Colors.Text.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
            }

            if let tool = toolCallInfo {
                ToolCallBubble(toolName: tool.name, isComplete: tool.done, success: tool.success, summary: tool.summary)
            } else if isFromCurrentUser {
                // User message - right aligned bubble with context menu
                VStack(alignment: .trailing, spacing: 4) {
                    HStack {
                        Spacer(minLength: 60)
                        messageBubble(isUser: true)
                            .opacity(isCompleted ? 0.5 : 1.0)
                            .contextMenu { messageContextMenu }
                    }
                    if isCompleted {
                        completionCaption
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isCompleted)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("You: \(message.displayContent)\(isCompleted ? ", Done" : "")")
            } else {
                // AI/other message - full width with context menu
                VStack(alignment: .leading, spacing: 4) {
                    messageBubble(isUser: false)
                        .opacity(isCompleted ? 0.5 : 1.0)
                        .contextMenu { messageContextMenu }

                    if isCompleted {
                        completionCaption
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isCompleted)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(isStreamingMessage ? "\(senderName): streaming response" : "\(senderName): \(message.displayContent)\(isCompleted ? ", Done" : "")")
            }
        }
    }

    @ViewBuilder
    private var completionCaption: some View {
        if let task = completedTask {
            HStack(spacing: 4) {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                Text("Done")
                    .fontWeight(.medium)
                if let name = task.completedByName {
                    Text("·")
                    Text(name)
                }
                Text("·")
                Text(completionRelativeTime(task.createdAt))
            }
            .font(Design.Typography.caption2)
            .foregroundStyle(Design.Colors.Text.secondary)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    private func completionRelativeTime(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "Just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        return "\(Int(interval / 86400))d ago"
    }

    private var isStreamingMessage: Bool {
        chatStore.streamingMessageId == message.id
    }

    @ViewBuilder
    private func messageBubble(isUser: Bool) -> some View {
        if isUser {
            MarkdownContentView(message.displayContent, isFromCurrentUser: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Design.Colors.Semantic.accent)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .accessibilityHidden(true)
        } else if isStreamingMessage {
            // WhaleChat pattern: direct buffer rendering, no phase state machine
            StreamingTextView(buffer: chatStore.agentStreamingBuffer)
                .accessibilityHidden(true)
        } else {
            MarkdownContentView(message.displayContent, isFromCurrentUser: false)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var messageContextMenu: some View {
        // Reply button
        Button {
            replyToMessage()
        } label: {
            Label("Reply", systemImage: "arrowshape.turn.up.left")
        }

        // Copy button
        Button {
            UIPasteboard.general.string = message.displayContent
            Haptics.light()
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }

        // Done / Undo (only for non-streaming messages)
        if !isStreamingMessage {
            if isCompleted {
                Button {
                    chatStore.undoComplete(messageId: message.id)
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
            } else {
                Button {
                    chatStore.completeTask(message: message)
                } label: {
                    Label("Done", systemImage: "checkmark.circle")
                }
            }
        }

        Divider()

        // Reactions
        Button {
            // TODO: Add reaction persistence
            Haptics.light()
        } label: {
            Label("Love", systemImage: "heart.fill")
        }

        Button {
            Haptics.light()
        } label: {
            Label("Like", systemImage: "hand.thumbsup.fill")
        }

        Button {
            Haptics.light()
        } label: {
            Label("Laugh", systemImage: "face.smiling.fill")
        }
    }

    private func replyToMessage() {
        // If replying to AI message, tag the agent
        if message.isAssistant {
            if let agent = chatStore.defaultAgent {
                chatStore.composerText = "@\(agent.displayName) "
            }
        }
        // Focus the input (notification pattern)
        NotificationCenter.default.post(name: .focusChatInput, object: nil)
        Haptics.selection()
    }

    private static let bubbleTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    private func formatTime(_ date: Date) -> String {
        Self.bubbleTimeFormatter.string(from: date)
    }
}

// Notification for focusing chat input
extension Notification.Name {
    static let focusChatInput = Notification.Name("focusChatInput")
}

// MARK: - Tool Call Bubble (clean WhaleChat style)

private struct ToolCallBubble: View {
    let toolName: String
    let isComplete: Bool
    let success: Bool
    let summary: String

    private var displayName: String {
        toolName.replacingOccurrences(of: "_", with: " ").capitalized
    }

    var body: some View {
        HStack(spacing: 10) {
            // Simple icon
            Image(systemName: isComplete ? (success ? "checkmark.circle.fill" : "xmark.circle.fill") : "gear")
                .font(Design.Typography.callout)
                .foregroundStyle(isComplete ? (success ? Design.Colors.Semantic.success : Design.Colors.Semantic.error) : Design.Colors.Text.secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(Design.Typography.caption1)
                    .fontWeight(.medium)
                    .foregroundStyle(Design.Colors.Text.primary)

                Text(isComplete ? summary : "Running...")
                    .font(Design.Typography.caption2)
                    .foregroundStyle(Design.Colors.Text.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Design.Colors.Glass.thin)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(displayName), \(isComplete ? (success ? "completed: \(summary)" : "failed: \(summary)") : "running")")
    }
}

// Safe array subscript
private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Generating Bar (WhaleChat exact port)

private struct GeneratingBar: View {
    var toolName: String?
    @State private var active = false

    var body: some View {
        HStack(spacing: 6) {
            GeneratingDots(active: active)
            Text(toolName.map { $0.replacingOccurrences(of: "_", with: " ").capitalized } ?? "Generating\u{2026}")
                .font(Design.Typography.caption1)
                .fontWeight(.medium)
                .foregroundStyle(Design.Colors.Text.tertiary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .onAppear { active = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(toolName.map { "Running \($0)" } ?? "Generating response")
    }
}

private struct GeneratingDots: View {
    var active: Bool

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Design.Colors.Text.tertiary)
                    .frame(width: 4, height: 4)
                    .scaleEffect(active ? 1.0 : 0.5)
                    .opacity(active ? 1.0 : 0.4)
                    .animation(
                        .easeInOut(duration: 0.5)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.15),
                        value: active
                    )
            }
        }
    }
}

// MARK: - Message Input Bar (iMessage style with @mentions)

private struct MessageInputBar: View {
    @ObservedObject var chatStore: ChatStore
    @FocusState.Binding var isInputFocused: Bool
    var onSend: () -> Void

    @State private var showImagePicker = false
    @State private var showFilePicker = false

    private var canSend: Bool {
        let hasText = !chatStore.composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasAttachments = !chatStore.composerAttachments.isEmpty
        return (hasText || hasAttachments) && !chatStore.isAgentStreaming
    }

    private var isStreaming: Bool { chatStore.isAgentStreaming }

    // Check if typing @mention and get filtered agents
    private var mentionQuery: String? {
        let text = chatStore.composerText
        guard let atIndex = text.lastIndex(of: "@") else { return nil }
        let afterAt = String(text[text.index(after: atIndex)...])
        // Only show if no space yet (still typing the name)
        guard !afterAt.contains(" ") else { return nil }
        return afterAt.lowercased()
    }

    private var filteredAgents: [AIAgent] {
        guard let query = mentionQuery else { return [] }
        if query.isEmpty {
            return chatStore.agents
        }
        // Filter by prefix first, then contains
        let prefixMatches = chatStore.agents.filter { $0.displayName.lowercased().hasPrefix(query) }
        if !prefixMatches.isEmpty { return prefixMatches }
        return chatStore.agents.filter { $0.displayName.lowercased().contains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Agent suggestions (appears above input when typing @)
            if mentionQuery != nil && !filteredAgents.isEmpty {
                agentSuggestions
            }

            // Attachments preview
            if !chatStore.composerAttachments.isEmpty {
                attachmentsPreview
            }

            // Input row
            HStack(alignment: .center, spacing: 8) {
                // Plus button
                Menu {
                    // Agents section
                    Section("Agents") {
                        ForEach(chatStore.agents) { agent in
                            Button {
                                chatStore.composerText += "@\(agent.displayName) "
                                Haptics.selection()
                            } label: {
                                Label(agent.displayName, systemImage: agent.displayIcon)
                            }
                        }
                    }

                    Section("Attachments") {
                        Button {
                            showImagePicker = true
                        } label: {
                            Label("Photo Library", systemImage: "photo.on.rectangle")
                        }
                        Button {
                            showFilePicker = true
                        } label: {
                            Label("Document", systemImage: "doc")
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(Design.Typography.title3)
                        .fontWeight(.medium)
                        .foregroundStyle(isStreaming ? Design.Colors.Text.tertiary : Design.Colors.Text.primary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .disabled(isStreaming)
                .accessibilityLabel("Add attachment or mention agent")

                // Text input
                HStack(alignment: .center, spacing: 0) {
                    TextField("Message", text: $chatStore.composerText, axis: .vertical)
                        .font(Design.Typography.body)
                        .lineLimit(1...6)
                        .focused($isInputFocused)
                        .disabled(isStreaming)
                        .onSubmit {
                            // If showing suggestions, select first one on Enter
                            if mentionQuery != nil, let first = filteredAgents.first {
                                selectAgent(first)
                            } else if canSend {
                                send()
                            }
                        }

                    // Send button
                    if canSend {
                        Button { send() } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(Design.Colors.Semantic.accent)
                        }
                        .buttonStyle(.plain)
                        .transition(.scale.combined(with: .opacity))
                        .padding(.leading, 8)
                        .accessibilityLabel("Send message")
                    }
                }
                .padding(.leading, 16)
                .padding(.trailing, canSend ? 6 : 16)
                .padding(.vertical, 8)
                .glassEffect(.regular.interactive(), in: .capsule)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: canSend)
        }
        .background(Design.Colors.backgroundPrimary.opacity(0.001))
        .sheet(isPresented: $showImagePicker) {
            ChatImagePicker(chatStore: chatStore, onComplete: {})
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.pdf, .image],
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result)
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusChatInput)) { _ in
            isInputFocused = true
        }
    }

    // MARK: - Agent Suggestions (compact row above input)

    private var agentSuggestions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(filteredAgents.prefix(5)) { agent in
                    Button {
                        selectAgent(agent)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: agent.displayIcon)
                                .font(Design.Typography.caption2)
                                .foregroundStyle(Design.Colors.Semantic.accent)
                                .accessibilityHidden(true)
                            Text(agent.displayName)
                                .font(Design.Typography.caption1)
                                .fontWeight(.medium)
                                .foregroundStyle(Design.Colors.Text.primary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Design.Colors.Glass.regular)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private func selectAgent(_ agent: AIAgent) {
        // Replace @partial with @AgentName
        if let atIndex = chatStore.composerText.lastIndex(of: "@") {
            let beforeAt = String(chatStore.composerText[..<atIndex])
            chatStore.composerText = beforeAt + "@\(agent.displayName) "
        } else {
            chatStore.composerText += "@\(agent.displayName) "
        }
        Haptics.selection()
    }

    private var attachmentsPreview: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chatStore.composerAttachments) { attachment in
                    attachmentThumbnail(attachment)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private func attachmentThumbnail(_ attachment: ChatAttachment) -> some View {
        ZStack(alignment: .topTrailing) {
            if let data = attachment.thumbnail, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Design.Colors.Glass.regular)
                    .frame(width: 60, height: 60)
                    .overlay(
                        Image(systemName: attachment.icon)
                            .foregroundStyle(Design.Colors.Text.secondary)
                    )
            }

            Button {
                chatStore.removeAttachment(attachment.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Design.Colors.Text.primary, Design.Colors.Glass.thick)
            }
            .offset(x: 6, y: -6)
        }
    }

    private func send() {
        Haptics.medium()
        Task {
            await chatStore.sendMessage()
            onSend()
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                guard chatStore.composerAttachments.count < ChatStore.maxAttachments else { break }
                guard url.startAccessingSecurityScopedResource() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }

                do {
                    let data = try Data(contentsOf: url)
                    let fileName = url.lastPathComponent
                    let isPDF = url.pathExtension.lowercased() == "pdf"

                    let attachment = ChatAttachment(
                        type: isPDF ? .pdf : .image,
                        fileName: fileName,
                        data: data,
                        thumbnail: isPDF ? nil : data,
                        pageCount: isPDF ? getPDFPageCount(data) : nil
                    )
                    chatStore.addAttachment(attachment)
                } catch {
                    Log.ui.error("Failed to read file: \(error)")
                }
            }
        case .failure(let error):
            Log.ui.error("File picker error: \(error)")
        }
    }

    private func getPDFPageCount(_ data: Data) -> Int? {
        guard let provider = CGDataProvider(data: data as CFData),
              let pdf = CGPDFDocument(provider) else { return nil }
        return pdf.numberOfPages
    }
}


// MARK: - Chat Attachment Picker

struct ChatAttachmentPicker: View {
    @ObservedObject var chatStore: ChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var showImagePicker = false
    @State private var showFilePicker = false

    var body: some View {
        NavigationStack {
            List {
                Button {
                    showImagePicker = true
                } label: {
                    Label("Photo Library", systemImage: "photo.on.rectangle")
                }

                Button {
                    showFilePicker = true
                } label: {
                    Label("Document", systemImage: "doc")
                }
            }
            .navigationTitle("Attach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showImagePicker) {
                ChatImagePicker(chatStore: chatStore, onComplete: { dismiss() })
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.pdf, .image],
                allowsMultipleSelection: true
            ) { result in
                handleFileImport(result)
            }
        }
        .presentationDetents([.medium])
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                guard chatStore.composerAttachments.count < ChatStore.maxAttachments else { break }
                guard url.startAccessingSecurityScopedResource() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }

                do {
                    let data = try Data(contentsOf: url)
                    let fileName = url.lastPathComponent
                    let isPDF = url.pathExtension.lowercased() == "pdf"

                    let attachment = ChatAttachment(
                        type: isPDF ? .pdf : .image,
                        fileName: fileName,
                        data: data,
                        thumbnail: isPDF ? nil : data,
                        pageCount: isPDF ? getPDFPageCount(data) : nil
                    )
                    chatStore.addAttachment(attachment)
                } catch {
                    Log.ui.error("Failed to read file: \(error)")
                }
            }
            dismiss()
        case .failure(let error):
            Log.ui.error("File picker error: \(error)")
        }
    }

    private func getPDFPageCount(_ data: Data) -> Int? {
        guard let provider = CGDataProvider(data: data as CFData),
              let pdf = CGPDFDocument(provider) else { return nil }
        return pdf.numberOfPages
    }
}

// MARK: - Chat Image Picker

struct ChatImagePicker: UIViewControllerRepresentable {
    @ObservedObject var chatStore: ChatStore
    let onComplete: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ChatImagePicker

        init(_ parent: ChatImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage,
               let data = image.jpegData(compressionQuality: 0.8) {

                let thumbnailSize = CGSize(width: 100, height: 100)
                let thumbnail = image.preparingThumbnail(of: thumbnailSize)
                let thumbnailData = thumbnail?.jpegData(compressionQuality: 0.6)

                let fileName = "image_\(Date().timeIntervalSince1970).jpg"
                let attachment = ChatAttachment(
                    type: .image,
                    fileName: fileName,
                    data: data,
                    thumbnail: thumbnailData
                )
                parent.chatStore.addAttachment(attachment)
            }
            parent.onComplete()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onComplete()
        }
    }
}
