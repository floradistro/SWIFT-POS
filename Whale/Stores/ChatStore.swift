//
//  ChatStore.swift
//  Whale
//
//  Observable store for team chat state.
//  Manages conversations, messages, realtime subscriptions, sender cache,
//  AI agent streaming (SSE via agent-chat Edge Function).
//

import Foundation
import SwiftUI
import Supabase
import Combine
import os.log

@MainActor
final class ChatStore: ObservableObject {

    // MARK: - Singleton

    static let shared = ChatStore()

    // MARK: - Published State

    @Published private(set) var conversations: [ChatConversation] = []
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var isLoadingMessages = false
    @Published private(set) var isLoadingConversations = false
    @Published private(set) var error: String?
    @Published var activeConversationId: UUID?
    @Published var composerText = ""

    // MARK: - Composer Attachments & Locked Agent

    /// Attachments pending to send (max 10)
    @Published var composerAttachments: [ChatAttachment] = []

    /// Agent locked in via @ mention (shown as chip in input)
    @Published var lockedAgent: AIAgent?

    static let maxAttachments = 10

    // MARK: - Completed Tasks

    @Published private(set) var completedTasks: [ChatTask] = [] {
        didSet {
            completedMessageIds = Set(completedTasks.map(\.messageId))
        }
    }
    private(set) var completedMessageIds: Set<UUID> = []

    // MARK: - AI Agents (from ai_agent_config)

    @Published private(set) var agents: [AIAgent] = []
    private var agentsLoaded = false

    // MARK: - Agent Streaming State

    enum StreamingPhase: Equatable { case thinking, streaming, complete }

    struct StreamingToolCall: Equatable {
        let name: String
        var isDone: Bool = false
        var success: Bool = false
        var summary: String = ""
    }

    @Published private(set) var isAgentStreaming = false
    @Published private(set) var streamingMessageId: UUID?
    @Published private(set) var streamingPhase: StreamingPhase?
    @Published private(set) var agentCurrentTool: String?
    @Published private(set) var streamingToolCalls: [StreamingToolCall] = []

    let agentStreamingBuffer = StreamingTextBuffer()
    private let agentSSEStream = AgentSSEStream()
    /// Tracks ai_conversations ID per agent (separate from team chat lisa_conversations)
    private var agentConversationIds: [UUID: UUID] = [:]
    /// Agent active in the current team chat channel (persists after first @mention)
    private var activeAgentForChannel: [UUID: AIAgent] = [:]

    // MARK: - Mute & Pin (UserDefaults-persisted)

    private static let mutedKey = "chat_muted_ids"
    private static let pinnedKey = "chat_pinned_ids"

    private(set) var mutedIds: Set<UUID> = [] {
        didSet { Self.persistUUIDs(mutedIds, key: Self.mutedKey) }
    }
    private(set) var pinnedIds: Set<UUID> = [] {
        didSet {
            Self.persistUUIDs(pinnedIds, key: Self.pinnedKey)
            objectWillChange.send()
        }
    }

    func isMuted(_ conversationId: UUID) -> Bool { mutedIds.contains(conversationId) }
    func isPinned(_ conversationId: UUID) -> Bool { pinnedIds.contains(conversationId) }

    func toggleMute(_ conversationId: UUID) {
        if mutedIds.contains(conversationId) {
            mutedIds.remove(conversationId)
        } else {
            mutedIds.insert(conversationId)
        }
    }

    func togglePin(_ conversationId: UUID) {
        if pinnedIds.contains(conversationId) {
            pinnedIds.remove(conversationId)
        } else {
            pinnedIds.insert(conversationId)
        }
        // Re-sort conversations to move pinned to top
        resortConversations()
    }

    private func resortConversations() {
        let locId = self.locationId
        let pinned = self.pinnedIds
        conversations.sort { a, b in
            let aPinned = pinned.contains(a.id)
            let bPinned = pinned.contains(b.id)
            if aPinned != bPinned { return aPinned }
            let aOrder = Self.channelSortOrder(a, locationId: locId)
            let bOrder = Self.channelSortOrder(b, locationId: locId)
            if aOrder != bOrder { return aOrder < bOrder }
            return a.updatedAt > b.updatedAt
        }
    }

    private nonisolated static func persistUUIDs(_ ids: Set<UUID>, key: String) {
        let strings = ids.map(\.uuidString)
        UserDefaults.standard.set(strings, forKey: key)
    }

    private nonisolated static func loadUUIDs(key: String) -> Set<UUID> {
        guard let strings = UserDefaults.standard.stringArray(forKey: key) else { return [] }
        return Set(strings.compactMap { UUID(uuidString: $0) })
    }

    // MARK: - Sender Cache

    private(set) var senderCache: [UUID: ChatSender] = [:]

    // MARK: - Realtime

    private var realtimeChannel: RealtimeChannelV2?
    private var realtimeTask: Task<Void, Never>?
    private var isSubscribed = false
    private(set) var storeId: UUID?
    private var locationId: UUID?
    private var currentUserId: UUID?
    private var currentUserEmail: String?

    // MARK: - Init

    private init() {
        mutedIds = Self.loadUUIDs(key: Self.mutedKey)
        pinnedIds = Self.loadUUIDs(key: Self.pinnedKey)
    }

    // MARK: - Configuration

    func configure(storeId: UUID, locationId: UUID?, userId: UUID?, userEmail: String? = nil) {
        let storeChanged = self.storeId != storeId
        let locationChanged = self.locationId != locationId
        self.storeId = storeId
        self.locationId = locationId
        self.currentUserId = userId
        self.currentUserEmail = userEmail

        if storeChanged || locationChanged {
            conversations = []
            messages = []
            activeConversationId = nil
            error = nil
            agents = []
            agentsLoaded = false
            agentConversationIds = [:]
            activeAgentForChannel = [:]
        }
    }

    // MARK: - Load Agents

    func loadAgentsIfNeeded() async {
        guard let storeId, !agentsLoaded else { return }
        agentsLoaded = true

        do {
            agents = try await ChatService.fetchAgents(storeId: storeId)
            Log.network.info("ChatStore: Loaded \(self.agents.count) agents")
        } catch {
            Log.network.error("ChatStore: Failed to load agents: \(error)")
        }
    }

    /// Find an agent by @mention (e.g. "@Wilson", "@Whale Code")
    func agentForMention(_ text: String) -> AIAgent? {
        agents.first { agent in
            text.localizedCaseInsensitiveContains("@\(agent.displayName)")
        }
    }

    /// Default agent (Wilson) or first available
    var defaultAgent: AIAgent? {
        agents.first { $0.displayName.lowercased() == "wilson" } ?? agents.first
    }

    // MARK: - Attachment Management

    /// Add attachment if under limit
    func addAttachment(_ attachment: ChatAttachment) {
        guard composerAttachments.count < Self.maxAttachments else { return }
        composerAttachments.append(attachment)
    }

    /// Remove attachment by ID
    func removeAttachment(_ id: UUID) {
        composerAttachments.removeAll { $0.id == id }
    }

    /// Clear all attachments
    func clearAttachments() {
        composerAttachments.removeAll()
    }

    /// Whether vision is available (has image attachments)
    var hasVisionContent: Bool {
        composerAttachments.contains { $0.type == .image }
    }

    // MARK: - Agent Locking

    /// Lock an agent from @ mention
    func lockAgent(_ agent: AIAgent) {
        lockedAgent = agent
    }

    /// Unlock/clear the locked agent
    func unlockAgent() {
        lockedAgent = nil
    }

    // MARK: - Load Conversations

    func loadConversations() async {
        guard let storeId else { return }
        isLoadingConversations = true
        defer { isLoadingConversations = false }

        // Load agents in parallel with conversations
        async let agentsFetch: () = loadAgentsIfNeeded()

        do {
            let all = try await ChatService.fetchConversations(storeId: storeId)
            _ = await agentsFetch
            let locId = self.locationId

            let pinned = self.pinnedIds
            let sorted = all.sorted { a, b in
                let aPinned = pinned.contains(a.id)
                let bPinned = pinned.contains(b.id)
                if aPinned != bPinned { return aPinned }
                let aOrder = Self.channelSortOrder(a, locationId: locId)
                let bOrder = Self.channelSortOrder(b, locationId: locId)
                if aOrder != bOrder { return aOrder < bOrder }
                return a.updatedAt > b.updatedAt
            }

            conversations = sorted

            if activeConversationId == nil {
                activeConversationId = locationConversation?.id ?? conversations.first?.id
            }
        } catch {
            Log.network.error("ChatStore: Failed to load conversations: \(error)")
            self.error = error.localizedDescription
        }
    }

    var locationConversation: ChatConversation? {
        guard let locationId else { return nil }
        return conversations.first { $0.locationId == locationId && $0.chatType == .location }
    }

    var activeConversation: ChatConversation? {
        guard let id = activeConversationId else { return nil }
        return conversations.first { $0.id == id }
    }

    private nonisolated static func channelSortOrder(_ conv: ChatConversation, locationId: UUID?) -> Int {
        if conv.chatType == .location && conv.locationId == locationId { return 0 }
        switch conv.chatType {
        case .location: return 1
        case .team: return 2
        case .ai: return 3
        case .alerts: return 4
        case .bugs: return 5
        case .dm: return 6
        }
    }

    // MARK: - Load Messages

    func loadMessages() async {
        guard let conversationId = activeConversationId else { return }
        isLoadingMessages = true

        do {
            async let messagesFetch = ChatService.fetchMessages(conversationId: conversationId)
            async let tasksFetch: () = loadCompletedTasks()

            let fetched = try await messagesFetch
            _ = await tasksFetch
            messages = fetched
            isLoadingMessages = false

            Task { await resolveSenders() }
            Task { await subscribeToMessages(conversationId: conversationId) }
        } catch {
            isLoadingMessages = false
            Log.network.error("ChatStore: Failed to load messages: \(error)")
            self.error = error.localizedDescription
        }
    }

    // MARK: - Send Message

    func sendMessage() async {
        let text = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !composerAttachments.isEmpty,
              let conversationId = activeConversationId,
              let userId = currentUserId else { return }

        // Capture and clear composer state
        let messageText = text
        let attachments = composerAttachments
        let targetAgent = lockedAgent

        composerText = ""
        composerAttachments = []
        lockedAgent = nil

        // Load agents on-demand if not yet loaded
        if agents.isEmpty {
            await loadAgentsIfNeeded()
        }

        // Determine agent: explicit lock or @mention always wins.
        // Only auto-continue agent sessions in AI channels — team/location channels require explicit @mention.
        let isAIChannel = activeConversation?.chatType == .ai
        let mentionedAgent: AIAgent?
        if let target = targetAgent {
            mentionedAgent = target
        } else if let mentioned = agentForMention(messageText) {
            mentionedAgent = mentioned
        } else if isAIChannel {
            mentionedAgent = activeAgentForChannel[conversationId] ?? defaultAgent
        } else {
            mentionedAgent = nil
        }
        let isAiInvocation = mentionedAgent != nil

        do {
            let message = try await ChatService.sendMessage(
                conversationId: conversationId,
                content: messageText,
                senderId: userId,
                isAiInvocation: isAiInvocation
            )
            if !messages.contains(where: { $0.id == message.id }) {
                messages.append(message)
            }

            // Invoke AI agent via SSE streaming
            if isAiInvocation {
                let agent = mentionedAgent ?? defaultAgent
                if let agent {
                    invokeAgent(text: messageText, agent: agent, attachments: attachments)
                }
            }
        } catch {
            Log.network.error("ChatStore: Failed to send message: \(error)")
            composerText = messageText
            composerAttachments = attachments
            lockedAgent = targetAgent
            self.error = error.localizedDescription
        }
    }

    // MARK: - Agent Invocation (SSE streaming)

    func invokeAgent(text: String, agent: AIAgent, attachments: [ChatAttachment] = []) {
        // Strip the @mention from the prompt
        let prompt = stripMention(from: text, agent: agent)

        guard !prompt.isEmpty || !attachments.isEmpty else { return }
        guard let conversationId = activeConversationId else { return }

        // Only persist agent session in AI channels — team channels require explicit @mention each time
        if activeConversation?.chatType == .ai {
            activeAgentForChannel[conversationId] = agent
        }

        // TODO: Pass attachments to AgentSSEStream for vision support
        _ = attachments // Will be used when SSE endpoint supports multimodal

        let history = buildConversationHistory()

        // Abort any stale stream
        agentSSEStream.abort()

        // Reset transient state — remove previous streaming message if any
        if let oldId = streamingMessageId {
            withAnimation(.easeOut(duration: 0.15)) {
                messages.removeAll { $0.id == oldId }
            }
        }
        agentStreamingBuffer.clear()
        streamingToolCalls = []
        isAgentStreaming = true
        agentCurrentTool = nil

        // Insert transient streaming message immediately (thinking phase)
        let streamingId = UUID()
        streamingMessageId = streamingId
        withAnimation(.easeOut(duration: 0.15)) {
            streamingPhase = .thinking
            messages.append(ChatMessage(
                id: streamingId, conversationId: conversationId,
                role: "assistant", content: "",
                isAiInvocation: true
            ))
        }

        // Use the AI conversation ID for this agent (not the team chat conversation)
        let aiConversationId = agentConversationIds[agent.id]

        agentSSEStream.run(
            prompt: prompt,
            storeId: storeId,
            agentId: agent.id,
            conversationId: aiConversationId,
            userId: currentUserId,
            userEmail: currentUserEmail,
            conversationHistory: history.isEmpty ? nil : history,

            onText: { [weak self] newText in
                guard let self else { return }

                if self.streamingPhase != .streaming {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        self.streamingPhase = .streaming
                    }
                }
                self.agentStreamingBuffer.append(newText)
            },

            onToolStart: { [weak self] tool in
                guard let self else { return }
                self.agentCurrentTool = tool
                withAnimation(.easeInOut(duration: 0.2)) {
                    self.streamingToolCalls.append(StreamingToolCall(name: tool))
                    self.streamingPhase = .thinking
                }
            },

            onToolResult: { [weak self] tool, success, errorMsg in
                guard let self else { return }
                self.agentCurrentTool = nil

                // Update the matching tool call entry
                if let idx = self.streamingToolCalls.lastIndex(where: { $0.name == tool && !$0.isDone }) {
                    let summary = self.toolResultSummary(tool: tool, success: success, error: errorMsg)
                    self.streamingToolCalls[idx].isDone = true
                    self.streamingToolCalls[idx].success = success
                    self.streamingToolCalls[idx].summary = summary
                }
            },

            onDone: { [weak self] returnedConvId, _ in
                guard let self else { return }
                // Persist the AI conversation ID for multi-turn continuity
                if let aiConvUUID = UUID(uuidString: returnedConvId) {
                    self.agentConversationIds[agent.id] = aiConvUUID
                }

                // Flush buffer — it has ALL text across the entire response
                self.agentStreamingBuffer.flush()
                let finalText = self.agentStreamingBuffer.text

                self.agentSSEStream.abort()
                self.isAgentStreaming = false
                self.agentCurrentTool = nil
                self.streamingToolCalls = []

                guard !finalText.isEmpty, let smId = self.streamingMessageId else {
                    // No text — remove streaming message
                    if let smId = self.streamingMessageId {
                        self.messages.removeAll { $0.id == smId }
                    }
                    self.streamingMessageId = nil
                    self.streamingPhase = nil
                    self.agentStreamingBuffer.clear()
                    return
                }

                // Update streaming message content in-place, mark complete
                if let idx = self.messages.firstIndex(where: { $0.id == smId }) {
                    self.messages[idx] = ChatMessage(
                        id: smId, conversationId: conversationId,
                        role: "assistant", content: finalText,
                        isAiInvocation: true,
                        createdAt: self.messages[idx].createdAt
                    )
                }
                withAnimation(.easeInOut(duration: 0.15)) {
                    self.streamingPhase = .complete
                }

                // Save to DB, then swap transient for saved message
                let capturedSmId = smId
                Task {
                    defer {
                        self.streamingMessageId = nil
                        self.streamingPhase = nil
                        self.agentStreamingBuffer.clear()
                    }
                    do {
                        let saved = try await ChatService.saveAssistantMessage(
                            conversationId: conversationId,
                            content: finalText
                        )
                        if let idx = self.messages.firstIndex(where: { $0.id == capturedSmId }) {
                            self.messages[idx] = saved
                        } else if !self.messages.contains(where: { $0.id == saved.id }) {
                            self.messages.append(saved)
                        }
                    } catch {
                        Log.network.error("ChatStore: Failed to save AI response: \(error)")
                    }
                }
            },

            onError: { [weak self] errorMessage in
                guard let self else { return }
                self.agentSSEStream.abort()
                self.isAgentStreaming = false
                self.agentCurrentTool = nil
                self.streamingToolCalls = []
                withAnimation(.easeOut(duration: 0.15)) {
                    self.streamingPhase = nil
                    if let smId = self.streamingMessageId {
                        self.messages.removeAll { $0.id == smId }
                    }
                }
                self.streamingMessageId = nil
                self.agentStreamingBuffer.clear()
                self.error = errorMessage
                Log.network.error("ChatStore: Agent error: \(errorMessage)")

                self.messages.append(ChatMessage(
                    conversationId: conversationId,
                    role: "assistant",
                    content: "[ERROR] \(errorMessage)"
                ))
            }
        )
    }

    func abortAgent() {
        agentSSEStream.abort()
        isAgentStreaming = false
        agentCurrentTool = nil
        streamingToolCalls = []
        withAnimation(.easeOut(duration: 0.2)) {
            streamingPhase = nil
            if let smId = streamingMessageId {
                messages.removeAll { $0.id == smId }
            }
        }
        streamingMessageId = nil
        agentStreamingBuffer.clear()
    }

    private func stripMention(from text: String, agent: AIAgent) -> String {
        var result = text
        // Remove @AgentName from text (match by displayName, case-insensitive)
        if let range = result.range(of: "@\(agent.displayName)", options: .caseInsensitive) {
            result.removeSubrange(range)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func buildConversationHistory() -> [(role: String, content: String)] {
        // Only include messages from the active conversation (scoped per channel)
        guard let convId = activeConversationId else { return [] }
        let realMessages = messages.filter {
            $0.id != streamingMessageId && $0.conversationId == convId
        }

        // Work backwards, keep messages that fit within ~80K chars (~20K tokens)
        let maxTotalChars = 80_000
        let maxPerMessage = 8_000
        var totalChars = 0
        var result: [(role: String, content: String)] = []

        for msg in realMessages.reversed() {
            let content = msg.content.count > maxPerMessage
                ? String(msg.content.prefix(maxPerMessage)) + "\n...[earlier content trimmed]"
                : msg.content
            if totalChars + content.count > maxTotalChars { break }
            totalChars += content.count
            result.insert((role: msg.role, content: content), at: 0)
        }

        // Ensure history starts with "user" role (API requirement)
        while let first = result.first, first.role != "user" {
            result.removeFirst()
        }
        return result
    }

    private func toolResultSummary(tool: String, success: Bool, error: String?) -> String {
        if let error { return error }
        return success ? "Done" : "Failed"
    }

    // MARK: - Sender Resolution

    private func resolveSenders() async {
        let unknownIds = Set(messages.compactMap(\.senderId)).subtracting(senderCache.keys)
        guard !unknownIds.isEmpty else { return }

        do {
            let newSenders = try await ChatService.fetchSenders(authUserIds: unknownIds)
            for (id, sender) in newSenders {
                senderCache[id] = sender
            }
            objectWillChange.send()
        } catch {
            Log.network.error("ChatStore: Failed to resolve senders: \(error)")
        }
    }

    func senderName(for userId: UUID?) -> String {
        guard let userId else { return "Team Member" }
        return senderCache[userId]?.displayName ?? "Team Member"
    }

    func senderInitials(for userId: UUID?) -> String {
        guard let userId else { return "?" }
        return senderCache[userId]?.initials ?? "?"
    }

    // MARK: - Agent Resolution

    /// Resolve which AI agent responded by scanning backwards for the triggering @mention.
    func resolvedAgent(forMessageAt index: Int) -> AIAgent? {
        var i = index - 1
        // Bounds check to prevent crash if messages modified during iteration
        while i >= 0 && i < messages.count {
            let prev = messages[i]
            if prev.isAiInvocation {
                if let agent = agentForMention(prev.content) {
                    return agent
                }
                return defaultAgent
            }
            if prev.isAssistant { break }
            i -= 1
        }
        return defaultAgent
    }

    // MARK: - Task Completion

    func completeTask(message: ChatMessage) {
        guard !completedMessageIds.contains(message.id) else { return }
        let conversationId = message.conversationId

        // Determine sender name
        let msgSenderName: String?
        if message.isAssistant {
            msgSenderName = defaultAgent?.displayName ?? "Wilson"
        } else if let sid = message.senderId {
            msgSenderName = senderName(for: sid)
        } else {
            msgSenderName = nil
        }

        // Determine who is completing
        let completedById = currentUserId
        let completedByName: String?
        if let uid = currentUserId {
            completedByName = senderName(for: uid)
        } else {
            completedByName = nil
        }

        Task {
            do {
                let task = try await ChatService.completeTask(
                    messageId: message.id,
                    conversationId: conversationId,
                    storeId: storeId,
                    completedBy: completedById,
                    completedByName: completedByName,
                    content: message.content,
                    role: message.role,
                    senderName: msgSenderName
                )
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    completedTasks.insert(task, at: 0)
                }
                Haptics.success()
            } catch {
                Log.network.error("ChatStore: Failed to complete task: \(error)")
                self.error = error.localizedDescription
            }
        }
    }

    func undoComplete(messageId: UUID) {
        guard let task = completedTasks.first(where: { $0.messageId == messageId }) else { return }
        Task {
            do {
                try await ChatService.restoreTask(task)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    completedTasks.removeAll { $0.id == task.id }
                }
                Haptics.success()
            } catch {
                Log.network.error("ChatStore: Failed to undo complete: \(error)")
                self.error = error.localizedDescription
            }
        }
    }

    func loadCompletedTasks() async {
        guard let conversationId = activeConversationId else { return }
        do {
            completedTasks = try await ChatService.fetchCompletedTasks(conversationId: conversationId)
        } catch {
            Log.network.error("ChatStore: Failed to load completed tasks: \(error)")
        }
    }

    // MARK: - Realtime Subscription

    private func subscribeToMessages(conversationId: UUID) async {
        await cleanupRealtime()

        let client = await supabaseAsync()
        let channelName = "chat-\(conversationId.uuidString.prefix(8))-\(UInt64(Date().timeIntervalSince1970 * 1000))"
        let channel = client.realtimeV2.channel(channelName)

        let changes = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "lisa_messages",
            filter: "conversation_id=eq.\(conversationId.uuidString)"
        )

        self.realtimeChannel = channel

        do {
            try await channel.subscribeWithError()
        } catch {
            Log.network.error("ChatStore: Failed to subscribe to realtime: \(error)")
            return
        }

        self.isSubscribed = true

        realtimeTask = Task { [weak self] in
            for await change in changes {
                guard let self, !Task.isCancelled else { break }
                await self.handleRealtimeChange(change)
            }
            await MainActor.run { [weak self] in
                self?.isSubscribed = false
            }
        }
    }

    private func handleRealtimeChange(_ change: AnyAction) async {
        switch change {
        case .insert(let action):
            let decoded: ChatMessage? = await Task.detached {
                Self.decodeRealtimeMessage(from: action.record)
            }.value
            guard let message = decoded else { return }

            // Skip if this is a transient message we already have
            guard !messages.contains(where: { $0.id == message.id }) else { return }
            guard message.id != streamingMessageId else { return }

            // Append message
            messages.append(message)

            // Resolve sender if needed
            if let senderId = message.senderId, senderCache[senderId] == nil {
                await resolveSenders()
            }

            // Post notification if message is from someone else
            let isFromCurrentUser = message.senderId == currentUserId
            if !isFromCurrentUser && !message.isUser {
                await postNotificationForMessage(message)
            }

        case .update(let action):
            // Handle message updates (e.g., reactions, edits)
            let decoded: ChatMessage? = await Task.detached {
                Self.decodeRealtimeMessage(from: action.record)
            }.value
            guard let message = decoded else { return }
            if let idx = messages.firstIndex(where: { $0.id == message.id }) {
                messages[idx] = message
            }

        case .delete(let action):
            // Handle message deletion
            if let idString = action.oldRecord["id"] as? String,
               let id = UUID(uuidString: idString) {
                messages.removeAll { $0.id == id }
            }
        }
    }

    private func postNotificationForMessage(_ message: ChatMessage) async {
        guard let conversationId = activeConversationId else { return }

        // Get sender name
        let senderName: String
        if message.isAssistant {
            senderName = defaultAgent?.displayName ?? "Wilson"
        } else if let senderId = message.senderId, let sender = senderCache[senderId] {
            senderName = sender.displayName
        } else {
            senderName = "Team"
        }

        // Get conversation title
        let conversationTitle = activeConversation?.displayTitle ?? senderName

        // Skip notification if conversation is muted
        guard !mutedIds.contains(conversationId) else { return }

        await ChatNotificationService.shared.postMessageNotification(
            title: conversationTitle,
            body: "\(senderName): \(message.content)",
            conversationId: conversationId,
            messageId: message.id
        )
    }

    private nonisolated static func decodeRealtimeMessage(from record: [String: Any]) -> ChatMessage? {
        guard JSONSerialization.isValidJSONObject(record) else {
            Log.network.error("ChatStore: Invalid JSON object in realtime record")
            return nil
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: record)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(ChatMessage.self, from: data)
        } catch {
            Log.network.error("ChatStore: Failed to decode realtime message: \(error)")
            return nil
        }
    }

    // MARK: - Cleanup

    private func cleanupRealtime() async {
        realtimeTask?.cancel()
        realtimeTask = nil

        if let channel = realtimeChannel {
            realtimeChannel = nil
            Task.detached {
                await channel.unsubscribe()
                let client = await supabaseAsync()
                await client.removeChannel(channel)
            }
        }

        isSubscribed = false
    }

    func disconnect() async {
        abortAgent()
        await cleanupRealtime()
    }

    // MARK: - Select Channel

    func selectChannel(_ conversationId: UUID) {
        guard conversationId != activeConversationId else { return }
        abortAgent()
        activeConversationId = conversationId
        messages = []
        completedTasks = []
        error = nil
        Task { await loadMessages() }
    }
}
