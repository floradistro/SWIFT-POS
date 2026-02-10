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
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Design.Colors.Text.primary)

                Text("Choose a conversation from the sidebar")
                    .font(.system(size: 15))
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
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ConversationListView(
                chatStore: chatStore,
                selectedConversation: .constant(nil),
                onSelect: { conversation in
                    chatStore.activeConversationId = conversation.id
                    Task { await chatStore.loadMessages() }
                    navigationPath.append(conversation)
                }
            )
            .navigationDestination(for: ChatConversation.self) { conversation in
                MessageThreadView(chatStore: chatStore, conversation: conversation)
            }
        }
    }
}

// MARK: - Conversation List (Sidebar)

private struct ConversationListView: View {
    @ObservedObject var chatStore: ChatStore
    @Binding var selectedConversation: ChatConversation?
    var onSelect: ((ChatConversation) -> Void)?

    @State private var searchText = ""
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var filteredConversations: [ChatConversation] {
        if searchText.isEmpty {
            return chatStore.conversations
        }
        return chatStore.conversations.filter {
            $0.displayTitle.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List {
            ForEach(filteredConversations) { conversation in
                ConversationRow(
                    conversation: conversation,
                    chatStore: chatStore,
                    isSelected: selectedConversation?.id == conversation.id
                )
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowBackground(
                    selectedConversation?.id == conversation.id
                        ? Design.Colors.Glass.regular
                        : Color.clear
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    Haptics.selection()
                    selectedConversation = conversation
                    chatStore.activeConversationId = conversation.id
                    Task { await chatStore.loadMessages() }
                    onSelect?(conversation)
                }
            }
        }
        .listStyle(.plain)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search")
        .navigationTitle("Messages")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    // New message action
                    Haptics.light()
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.body)
                        .fontWeight(.medium)
                }
            }
        }
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
}

// MARK: - Conversation Row (List Item)

private struct ConversationRow: View {
    let conversation: ChatConversation
    @ObservedObject var chatStore: ChatStore
    var isSelected: Bool = false

    private var lastMessage: ChatMessage? {
        // Get the most recent message for this conversation
        chatStore.messages.last { _ in chatStore.activeConversationId == conversation.id }
    }

    private var isUnread: Bool {
        // Placeholder for unread logic
        false
    }

    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            conversationAvatar

            // Content
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(conversation.displayTitle)
                        .font(.system(size: 17, weight: isUnread ? .semibold : .regular))
                        .foregroundStyle(Design.Colors.Text.primary)
                        .lineLimit(1)

                    Spacer()

                    HStack(spacing: 4) {
                        Text(formatDate(conversation.updatedAt))
                            .font(.system(size: 15))
                            .foregroundStyle(Design.Colors.Text.tertiary)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Design.Colors.Text.tertiary)
                    }
                }

                // Preview text - exactly like iMessage
                Text(previewText)
                    .font(.system(size: 15))
                    .foregroundStyle(Design.Colors.Text.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var conversationAvatar: some View {
        let size: CGFloat = 52
        let iconSize: CGFloat = 22

        switch conversation.chatType {
        case .dm:
            // Person avatar - gradient themed
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Design.Colors.Glass.thick, Design.Colors.Glass.ultraThick],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: size, height: size)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: iconSize, weight: .medium))
                        .foregroundStyle(Design.Colors.Text.primary)
                )

        case .team, .location:
            // Group avatar - themed success color
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Design.Colors.Semantic.success.opacity(0.8), Design.Colors.Semantic.success],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: size, height: size)
                .overlay(
                    Image(systemName: conversation.typeIcon)
                        .font(.system(size: iconSize, weight: .medium))
                        .foregroundStyle(.white)
                )

        case .ai:
            // AI avatar - themed accent gradient
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Design.Colors.Semantic.accent.opacity(0.8), Design.Colors.Semantic.accent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
                .overlay(
                    Image(systemName: "sparkles")
                        .font(.system(size: iconSize, weight: .medium))
                        .foregroundStyle(Design.Colors.Semantic.accentForeground)
                )

        case .alerts, .bugs:
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Design.Colors.Semantic.warning.opacity(0.8), Design.Colors.Semantic.warning],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: size, height: size)
                .overlay(
                    Image(systemName: conversation.typeIcon)
                        .font(.system(size: iconSize, weight: .medium))
                        .foregroundStyle(.white)
                )
        }
    }

    private var previewText: String {
        if let last = lastMessage {
            // Truncate long messages
            let text = last.content.prefix(100)
            return String(text)
        }
        return conversation.chatType == .ai ? "AI Assistant ready to help" : "No messages yet"
    }

    private func formatDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else if let daysAgo = calendar.dateComponents([.day], from: date, to: Date()).day, daysAgo < 7 {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            return formatter.string(from: date)
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "M/d/yy"
            return formatter.string(from: date)
        }
    }
}

// MARK: - Keyboard Height Publisher

private extension Publishers {
    static var keyboardHeight: AnyPublisher<CGFloat, Never> {
        let willShow = NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            .map { notification -> CGFloat in
                (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect)?.height ?? 0
            }

        let willHide = NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            .map { _ -> CGFloat in 0 }

        return willShow.merge(with: willHide)
            .eraseToAnyPublisher()
    }
}

// MARK: - Message Thread View

private struct MessageThreadView: View {
    @ObservedObject var chatStore: ChatStore
    let conversation: ChatConversation
    @EnvironmentObject private var session: SessionObserver
    @FocusState private var isInputFocused: Bool
    @State private var keyboardHeight: CGFloat = 0

    var body: some View {
        messagesScrollView
            .safeAreaInset(edge: .bottom, spacing: 0) {
                MessageInputBar(
                    chatStore: chatStore,
                    isInputFocused: $isInputFocused,
                    onSend: {}
                )
            }
            .padding(.bottom, keyboardHeight > 0 ? keyboardHeight - SafeArea.bottom : 0)
            .background(Design.Colors.backgroundPrimary)
            .ignoresSafeArea(.keyboard)
            .animation(.easeOut(duration: 0.25), value: keyboardHeight)
            .navigationTitle(conversation.displayTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    conversationHeader
                }
            }
            .onAppear {
                Task { await chatStore.loadAgentsIfNeeded() }
            }
            .onReceive(Publishers.keyboardHeight) { height in
                keyboardHeight = height
            }
    }

    private var conversationHeader: some View {
        Button {
            // Tappable header - could show conversation details
            Haptics.light()
        } label: {
            VStack(spacing: 4) {
                // Store logo above text
                if let logoUrl = session.store?.fullLogoUrl {
                    CachedAsyncImage(url: logoUrl, placeholderLogoUrl: nil, dimAmount: 0)
                        .frame(width: 36, height: 36)
                        .clipShape(Circle())
                }

                // Title and subtitle in liquid glass pill
                VStack(spacing: 0) {
                    Text(conversation.displayTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Design.Colors.Text.primary)

                    HStack(spacing: 4) {
                        if conversation.chatType == .ai {
                            Circle()
                                .fill(Design.Colors.Semantic.success)
                                .frame(width: 5, height: 5)
                            Text("Active")
                                .font(.system(size: 11))
                                .foregroundStyle(Design.Colors.Text.secondary)
                        } else {
                            Text(subtitleText)
                                .font(.system(size: 11))
                                .foregroundStyle(Design.Colors.Text.secondary)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .glassEffect(.regular.interactive(), in: .capsule)
            }
        }
        .buttonStyle(.plain)
    }

    private var subtitleText: String {
        switch conversation.chatType {
        case .team: return "Team"
        case .location: return "Location"
        case .dm: return "Direct Message"
        case .ai: return "AI Assistant"
        case .alerts: return "Alerts"
        case .bugs: return "Bug Reports"
        }
    }

    private var messagesScrollView: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                // Messages grouped by date
                ForEach(groupedMessages, id: \.date) { group in
                    // Date header
                    Text(formatDateHeader(group.date))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Design.Colors.Text.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Design.Colors.Glass.regular.opacity(0.6), in: Capsule())
                        .padding(.vertical, 12)

                    // Messages
                    ForEach(group.messages) { message in
                        messageBubbleView(message: message, group: group)
                    }
                }

                // Thinking indicator
                if chatStore.agentThinkingVisible {
                    TypingIndicator()
                        .padding(.top, 4)
                }

                // Streaming message - use id to prevent re-renders
                if !chatStore.agentStreamingBuffer.text.isEmpty {
                    StreamingBubble(buffer: chatStore.agentStreamingBuffer)
                        .id("streaming")
                }

                // Bottom anchor
                Color.clear
                    .frame(height: 1)
                    .id("bottom")
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .defaultScrollAnchor(.bottom)
        .scrollDismissesKeyboard(.interactively)
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

        for message in chatStore.messages {
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
                    .font(.system(size: 11))
                    .foregroundStyle(Design.Colors.Text.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
            }

            if let tool = toolCallInfo {
                ToolCallBubble(toolName: tool.name, isComplete: tool.done, success: tool.success, summary: tool.summary)
            } else if isFromCurrentUser {
                // User message - right aligned bubble with context menu
                HStack {
                    Spacer(minLength: 60)
                    messageBubble(isUser: true)
                        .contextMenu { messageContextMenu }
                }
            } else {
                // AI/other message - full width with context menu
                messageBubble(isUser: false)
                    .contextMenu { messageContextMenu }
            }
        }
    }

    @ViewBuilder
    private func messageBubble(isUser: Bool) -> some View {
        if isUser {
            MarkdownContentView(message.displayContent, isFromCurrentUser: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Design.Colors.Semantic.accent)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        } else {
            MarkdownContentView(message.displayContent, isFromCurrentUser: false)
                .frame(maxWidth: .infinity, alignment: .leading)
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

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
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
                .font(.system(size: 16))
                .foregroundStyle(isComplete ? (success ? Design.Colors.Semantic.success : Design.Colors.Semantic.error) : Design.Colors.Text.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Design.Colors.Text.primary)

                Text(isComplete ? summary : "Running...")
                    .font(.system(size: 12))
                    .foregroundStyle(Design.Colors.Text.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Design.Colors.Glass.thin)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// Safe array subscript
private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Typing Indicator (simple iMessage style)

private struct TypingIndicator: View {
    var body: some View {
        HStack {
            // Simple dots bubble
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Design.Colors.Text.tertiary)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Design.Colors.Glass.thin)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            Spacer()
        }
    }
}

// MARK: - Streaming Bubble

private struct StreamingBubble: View {
    @ObservedObject var buffer: StreamingTextBuffer

    var body: some View {
        MarkdownContentView(buffer.text, isFromCurrentUser: false)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
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
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(isStreaming ? Design.Colors.Text.tertiary : Design.Colors.Text.primary)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .disabled(isStreaming)

                // Text input
                HStack(alignment: .center, spacing: 0) {
                    TextField("Message", text: $chatStore.composerText, axis: .vertical)
                        .font(.system(size: 17))
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
                                .font(.system(size: 12))
                                .foregroundStyle(Design.Colors.Semantic.accent)
                            Text(agent.displayName)
                                .font(.system(size: 14, weight: .medium))
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
        isInputFocused = false
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
