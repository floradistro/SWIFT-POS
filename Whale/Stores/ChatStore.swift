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

    // MARK: - AI Agents (from ai_agent_config)

    @Published private(set) var agents: [AIAgent] = []
    private var agentsLoaded = false

    // MARK: - Agent Streaming State

    @Published private(set) var isAgentStreaming = false
    @Published private(set) var agentThinkingVisible = false
    @Published private(set) var agentCurrentTool: String?

    let agentStreamingBuffer = StreamingTextBuffer()
    private let agentSSEStream = AgentSSEStream()
    private var agentTransientIds: Set<UUID> = []
    private var agentStreamingActiveId: UUID?
    /// Tracks ai_conversations ID per agent (separate from team chat lisa_conversations)
    private var agentConversationIds: [UUID: UUID] = [:]
    /// Agent active in the current team chat channel (persists after first @mention)
    private var activeAgentForChannel: [UUID: AIAgent] = [:]

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

    private init() {}

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

            let sorted = all.sorted { a, b in
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
            let fetched = try await ChatService.fetchMessages(conversationId: conversationId)
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

        // Use locked agent, detect @mention, or continue active agent session
        let mentionedAgent = targetAgent ?? agentForMention(messageText) ?? activeAgentForChannel[conversationId]
        let isAiInvocation = mentionedAgent != nil || !attachments.isEmpty

        Log.network.debug("ChatStore.sendMessage: agents.count=\(self.agents.count), mentionedAgent=\(mentionedAgent?.displayName ?? "nil"), isAiInvocation=\(isAiInvocation)")

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
                Log.network.debug("ChatStore.sendMessage: Invoking agent=\(agent?.displayName ?? "nil")")
                if let agent {
                    invokeAgent(text: messageText, agent: agent, attachments: attachments)
                } else {
                    Log.network.warning("ChatStore.sendMessage: No agent found for invocation")
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
        Log.network.debug("ChatStore.invokeAgent: Starting with agent=\(agent.displayName), text=\(text.prefix(50))")

        // Strip the @mention from the prompt
        let prompt = stripMention(from: text, agent: agent)
        Log.network.debug("ChatStore.invokeAgent: Stripped prompt=\(prompt.prefix(50))")

        guard !prompt.isEmpty || !attachments.isEmpty else {
            Log.network.warning("ChatStore.invokeAgent: Empty prompt, skipping")
            return
        }
        guard let conversationId = activeConversationId else {
            Log.network.warning("ChatStore.invokeAgent: No active conversation")
            return
        }

        Log.network.debug("ChatStore.invokeAgent: Agent ID=\(agent.id), enabled_tools=\(agent.enabledTools ?? [])")

        // Persist agent for this channel — subsequent messages continue the session
        activeAgentForChannel[conversationId] = agent

        // TODO: Pass attachments to AgentSSEStream for vision support
        _ = attachments // Will be used when SSE endpoint supports multimodal

        let history = buildConversationHistory()

        // Abort any stale stream
        agentSSEStream.abort()

        // Reset transient state
        withAnimation(.easeOut(duration: 0.15)) {
            messages.removeAll { agentTransientIds.contains($0.id) }
        }
        agentTransientIds.removeAll()
        agentStreamingActiveId = nil
        agentStreamingBuffer.clear()
        isAgentStreaming = true
        agentCurrentTool = nil

        // Show thinking dots immediately
        withAnimation(.easeOut(duration: 0.15)) {
            agentThinkingVisible = true
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

                if self.agentStreamingActiveId == nil {
                    // First text chunk — replace thinking with streaming bubble
                    let msgId = UUID()
                    self.agentStreamingActiveId = msgId
                    self.agentTransientIds.insert(msgId)
                    withAnimation(.easeInOut(duration: 0.2)) {
                        self.agentThinkingVisible = false
                        self.messages.append(ChatMessage(
                            id: msgId, conversationId: conversationId,
                            role: "assistant", content: "",
                            isAiInvocation: true
                        ))
                    }
                }
                self.agentStreamingBuffer.append(newText)
            },

            onToolStart: { [weak self] tool in
                guard let self else { return }
                self.agentCurrentTool = tool
                self.finalizeStreamingMessage(channelId: conversationId)

                let toolMsgId = UUID()
                self.agentTransientIds.insert(toolMsgId)
                withAnimation(.easeInOut(duration: 0.2)) {
                    self.agentThinkingVisible = false
                    self.messages.append(ChatMessage(
                        id: toolMsgId, conversationId: conversationId,
                        role: "assistant", content: "tool:\(tool)",
                        isAiInvocation: true
                    ))
                }
            },

            onToolResult: { [weak self] tool, success, errorMsg in
                guard let self else { return }
                self.agentCurrentTool = nil

                // Update tool message status
                let toolPrefix = "tool:\(tool)"
                if let idx = self.messages.lastIndex(where: {
                    $0.content.hasPrefix(toolPrefix) && self.agentTransientIds.contains($0.id)
                }) {
                    let summary = self.toolResultSummary(tool: tool, success: success, error: errorMsg)
                    self.messages[idx] = ChatMessage(
                        id: self.messages[idx].id, conversationId: conversationId,
                        role: "assistant",
                        content: "tool_done:\(success ? "1" : "0"):\(tool):\(summary)",
                        isAiInvocation: true,
                        createdAt: self.messages[idx].createdAt
                    )
                }

                // Show thinking again while agent processes
                withAnimation(.easeOut(duration: 0.15)) {
                    self.agentThinkingVisible = true
                }
            },

            onDone: { [weak self] returnedConvId, _ in
                guard let self else { return }
                // Persist the AI conversation ID for multi-turn continuity
                if let aiConvUUID = UUID(uuidString: returnedConvId) {
                    self.agentConversationIds[agent.id] = aiConvUUID
                }
                self.finalizeStreamingMessage(channelId: conversationId)
                self.agentSSEStream.abort()

                self.agentThinkingVisible = false
                self.isAgentStreaming = false
                self.agentCurrentTool = nil

                // Collect final text from transient text messages
                let finalParts = self.messages
                    .filter { self.agentTransientIds.contains($0.id) && !$0.content.hasPrefix("tool:") && !$0.content.hasPrefix("tool_done:") }
                    .map(\.content)
                let finalText = finalParts.joined(separator: "\n\n")

                // Find the last text message to replace in-place
                let lastTextMsgIndex = self.messages.lastIndex {
                    self.agentTransientIds.contains($0.id) &&
                    !$0.content.hasPrefix("tool:") &&
                    !$0.content.hasPrefix("tool_done:")
                }

                // Remove tool call messages only (keep the text message for now)
                self.messages.removeAll {
                    self.agentTransientIds.contains($0.id) &&
                    ($0.content.hasPrefix("tool:") || $0.content.hasPrefix("tool_done:"))
                }

                guard !finalText.isEmpty else {
                    // No text - remove remaining transient
                    self.messages.removeAll { self.agentTransientIds.contains($0.id) }
                    self.agentTransientIds.removeAll()
                    return
                }

                // Save final response to DB, then swap in-place
                Task {
                    do {
                        let saved = try await ChatService.saveAssistantMessage(
                            conversationId: conversationId,
                            content: finalText
                        )
                        // Replace transient message with saved one at same position (no flicker)
                        if let idx = lastTextMsgIndex, idx < self.messages.count,
                           self.agentTransientIds.contains(self.messages[idx].id) {
                            self.messages[idx] = saved
                        } else if !self.messages.contains(where: { $0.id == saved.id }) {
                            self.messages.append(saved)
                        }
                    } catch {
                        Log.network.error("ChatStore: Failed to save AI response: \(error)")
                        // Keep transient message as-is (already showing the text)
                    }
                    self.agentTransientIds.removeAll()
                }
            },

            onError: { [weak self] errorMessage in
                guard let self else { return }
                self.agentSSEStream.abort()
                self.isAgentStreaming = false
                self.agentCurrentTool = nil
                withAnimation(.easeOut(duration: 0.15)) {
                    self.agentThinkingVisible = false
                    self.messages.removeAll { self.agentTransientIds.contains($0.id) }
                }
                self.agentTransientIds.removeAll()
                self.agentStreamingActiveId = nil
                self.agentStreamingBuffer.clear()
                self.error = errorMessage
                Log.network.error("ChatStore: Agent error: \(errorMessage)")

                // Show error as visible message in chat
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
        if let channelId = activeConversationId {
            finalizeStreamingMessage(channelId: channelId)
        }
        isAgentStreaming = false
        agentCurrentTool = nil
        withAnimation(.easeOut(duration: 0.2)) {
            agentThinkingVisible = false
            messages.removeAll { agentTransientIds.contains($0.id) }
        }
        agentTransientIds.removeAll()
        agentStreamingActiveId = nil
        agentStreamingBuffer.clear()
    }

    private func finalizeStreamingMessage(channelId: UUID) {
        guard let msgId = agentStreamingActiveId else { return }
        agentStreamingBuffer.flush()
        let finalText = agentStreamingBuffer.text
        if let idx = messages.firstIndex(where: { $0.id == msgId }) {
            if !finalText.isEmpty {
                messages[idx] = ChatMessage(
                    id: msgId, conversationId: channelId,
                    role: "assistant", content: finalText,
                    isAiInvocation: true, createdAt: messages[idx].createdAt
                )
            } else {
                messages.remove(at: idx)
                agentTransientIds.remove(msgId)
            }
        }
        agentStreamingActiveId = nil
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
        // Send last 20 non-transient messages as context
        let realMessages = messages.filter { !agentTransientIds.contains($0.id) }
        let recent = realMessages.suffix(20)
        return recent.map { (role: $0.role, content: $0.content) }
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
        while i >= 0 {
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
            // Skip if this is a transient message we already have or if streaming
            if !messages.contains(where: { $0.id == message.id }) {
                messages.append(message)
            }
            if let senderId = message.senderId, senderCache[senderId] == nil {
                await resolveSenders()
            }
        default:
            break
        }
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
        error = nil
        Task { await loadMessages() }
    }
}
