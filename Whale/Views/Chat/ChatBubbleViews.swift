//
//  ChatBubbleViews.swift
//  Whale
//
//  iMessage-style bubble views, agent progress indicator, streaming detail sheet.
//  Extracted from TeamChatPanel.
//

import SwiftUI

// MARK: - iMessage Bubble

struct iMessageBubble: View {
    let message: ChatMessage
    let previousMessage: ChatMessage?
    let isFromCurrentUser: Bool
    @ObservedObject var chatStore: ChatStore
    @State private var showStreamingDetail = false

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

    private var senderName: String {
        if message.isAssistant {
            return chatStore.defaultAgent?.displayName ?? "Wilson"
        } else if let senderId = message.senderId {
            return chatStore.senderName(for: senderId)
        }
        return "User"
    }

    /// Extra spacing when sender changes (iMessage group break)
    private var senderChanged: Bool {
        guard let prev = previousMessage else { return false }
        if isFromCurrentUser != (prev.senderId == nil && !prev.isAssistant || prev.isUser) {
            return true
        }
        if message.senderId != prev.senderId { return true }
        if message.isAssistant != prev.isAssistant { return true }
        return false
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
                // User message — right-aligned blue bubble
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
                // Incoming message — left-aligned bubble
                VStack(alignment: .leading, spacing: 2) {
                    if shouldShowSender {
                        Text(senderName)
                            .font(Design.Typography.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(Design.Colors.Text.secondary)
                            .padding(.leading, 14)
                    }

                    HStack(alignment: .top) {
                        if isStreamingMessage {
                            // Progress bubble — tap to see live response
                            Button {
                                Haptics.light()
                                showStreamingDetail = true
                            } label: {
                                AgentProgressBubble(chatStore: chatStore, agentName: senderName)
                            }
                            .buttonStyle(.plain)
                        } else {
                            messageBubble(isUser: false)
                                .opacity(isCompleted ? 0.5 : 1.0)
                                .contextMenu { messageContextMenu }
                        }
                        Spacer(minLength: 40)
                    }

                    if isCompleted {
                        completionCaption
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isCompleted)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(isStreamingMessage ? "\(senderName): working on response" : "\(senderName): \(message.displayContent)\(isCompleted ? ", Done" : "")")
                .sheet(isPresented: $showStreamingDetail) {
                    StreamingDetailSheet(
                        chatStore: chatStore,
                        buffer: chatStore.agentStreamingBuffer,
                        agentName: senderName
                    )
                }
            }
        }
        .padding(.top, senderChanged ? 8 : 0)
    }

    // MARK: - Completion Caption

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

    /// Show sender name when the sender changes (iMessage group chat pattern)
    private var shouldShowSender: Bool {
        guard !isFromCurrentUser else { return false }
        guard let prev = previousMessage else { return true }
        if message.isAssistant != prev.isAssistant { return true }
        if message.senderId != prev.senderId { return true }
        return false
    }

    // MARK: - Message Bubble

    @ViewBuilder
    private func messageBubble(isUser: Bool) -> some View {
        if isUser {
            MarkdownContentView(message.displayContent, isFromCurrentUser: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Design.Colors.Semantic.accent)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .accessibilityHidden(true)
        } else {
            MarkdownContentView(message.displayContent, isFromCurrentUser: false)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Design.Colors.Glass.regular)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .accessibilityHidden(true)
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var messageContextMenu: some View {
        Button {
            replyToMessage()
        } label: {
            Label("Reply", systemImage: "arrowshape.turn.up.left")
        }

        Button {
            UIPasteboard.general.string = message.displayContent
            Haptics.light()
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }

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

        Button {
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
        if message.isAssistant {
            if let agent = chatStore.defaultAgent {
                chatStore.composerText = "@\(agent.displayName) "
            }
        }
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

// MARK: - Notification

extension Notification.Name {
    static let focusChatInput = Notification.Name("focusChatInput")
}

// MARK: - Agent Progress Bubble (shown during streaming)

struct AgentProgressBubble: View {
    @ObservedObject var chatStore: ChatStore
    let agentName: String
    @State private var active = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Status with typing dots
            HStack(spacing: 8) {
                TypingDots(active: active)
                Text(statusText)
                    .font(Design.Typography.caption1)
                    .fontWeight(.medium)
                    .foregroundStyle(Design.Colors.Text.secondary)
            }

            // Animated tool call list
            if !chatStore.streamingToolCalls.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(chatStore.streamingToolCalls.enumerated()), id: \.offset) { _, tool in
                        HStack(spacing: 6) {
                            Group {
                                if tool.isDone {
                                    Image(systemName: tool.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundStyle(tool.success ? Design.Colors.Semantic.success : Design.Colors.Semantic.error)
                                } else {
                                    Image(systemName: "circle.dotted")
                                        .foregroundStyle(Design.Colors.Text.tertiary)
                                        .symbolEffect(.rotate, isActive: true)
                                }
                            }
                            .font(.system(size: 12))

                            Text(tool.name.replacingOccurrences(of: "_", with: " ").capitalized)
                                .font(Design.Typography.caption2)
                                .foregroundStyle(Design.Colors.Text.secondary)
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }

            // Tap hint
            HStack(spacing: 4) {
                Image(systemName: "eye")
                    .font(.system(size: 10))
                Text("Tap to view response")
                    .font(Design.Typography.caption2)
            }
            .foregroundStyle(Design.Colors.Text.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Design.Colors.Glass.regular)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onAppear { active = true }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: chatStore.streamingToolCalls.count)
    }

    private var statusText: String {
        switch chatStore.streamingState {
        case .thinking: return "\(agentName) is thinking\u{2026}"
        case .streaming: return "\(agentName) is writing\u{2026}"
        case .toolRunning(_, let tool):
            return tool.replacingOccurrences(of: "_", with: " ").capitalized
        default: return "Working\u{2026}"
        }
    }
}

// MARK: - Streaming Detail Sheet (live response viewer)

struct StreamingDetailSheet: View {
    @ObservedObject var chatStore: ChatStore
    @ObservedObject var buffer: StreamingTextBuffer
    let agentName: String
    @Environment(\.dismiss) private var dismiss
    @State private var scrollPosition = ScrollPosition(edge: .bottom)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Tool calls
                    if !chatStore.streamingToolCalls.isEmpty {
                        toolCallsSection
                    }

                    // Live markdown content
                    if !buffer.text.isEmpty {
                        MarkdownContentView(buffer.text, isFromCurrentUser: false)
                    } else if chatStore.isAgentStreaming {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Thinking\u{2026}")
                                .font(Design.Typography.subhead)
                                .foregroundStyle(Design.Colors.Text.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                    }
                }
                .padding(16)
            }
            .scrollPosition($scrollPosition)
            .defaultScrollAnchor(.bottom)
            // Auto-follow as content grows
            .onScrollGeometryChange(for: SheetScrollMetrics.self) { geo in
                let maxOffset = max(0, geo.contentSize.height - geo.containerSize.height)
                return SheetScrollMetrics(
                    contentHeight: geo.contentSize.height,
                    containerHeight: geo.containerSize.height,
                    nearBottom: geo.contentOffset.y >= maxOffset - 80
                )
            } action: { old, new in
                let layoutChanged = new.contentHeight != old.contentHeight
                    || new.containerHeight != old.containerHeight
                if old.nearBottom && layoutChanged {
                    scrollPosition.scrollTo(edge: .bottom)
                }
            }
            .navigationTitle(agentName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if chatStore.isAgentStreaming {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            chatStore.abortAgent()
                            dismiss()
                        } label: {
                            Text("Stop")
                                .foregroundStyle(Design.Colors.Semantic.error)
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        // Auto-dismiss when streaming completes
        .onChange(of: chatStore.isAgentStreaming) { _, isStreaming in
            if !isStreaming { dismiss() }
        }
    }

    private var toolCallsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(chatStore.streamingToolCalls.enumerated()), id: \.offset) { _, tool in
                HStack(spacing: 8) {
                    Group {
                        if tool.isDone {
                            Image(systemName: tool.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(tool.success ? Design.Colors.Semantic.success : Design.Colors.Semantic.error)
                        } else {
                            Image(systemName: "circle.dotted")
                                .foregroundStyle(Design.Colors.Text.tertiary)
                                .symbolEffect(.rotate, isActive: true)
                        }
                    }
                    .font(Design.Typography.caption1)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(tool.name.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(Design.Typography.caption1)
                            .fontWeight(.medium)
                            .foregroundStyle(Design.Colors.Text.primary)
                        if tool.isDone && !tool.summary.isEmpty {
                            Text(tool.summary)
                                .font(Design.Typography.caption2)
                                .foregroundStyle(Design.Colors.Text.secondary)
                                .lineLimit(2)
                        }
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(12)
        .background(Design.Colors.Glass.thin)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: chatStore.streamingToolCalls.count)
    }
}

private struct SheetScrollMetrics: Equatable {
    let contentHeight: CGFloat
    let containerHeight: CGFloat
    let nearBottom: Bool
}

// MARK: - Tool Call Bubble

struct ToolCallBubble: View {
    let toolName: String
    let isComplete: Bool
    let success: Bool
    let summary: String

    private var displayName: String {
        toolName.replacingOccurrences(of: "_", with: " ").capitalized
    }

    var body: some View {
        HStack(spacing: 10) {
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
extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Typing Dots (iMessage-style)

struct TypingDots: View {
    var active: Bool

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Design.Colors.Text.secondary)
                    .frame(width: 7, height: 7)
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
