//
//  ChatListStore.swift
//  Whale
//
//  Manages multiple chat conversations - AI agents, staff messaging, etc.
//  iMessage-style multi-conversation support.
//

import Foundation
import SwiftUI
import Combine
import Supabase
import os.log

// MARK: - Conversation Type

enum ConversationType: String, Codable, Equatable {
    case aiAgent = "ai_agent"
    case staffChat = "staff_chat"
    case teamChannel = "team_channel"

    var icon: String {
        switch self {
        case .aiAgent: return "sparkles"
        case .staffChat: return "person.fill"
        case .teamChannel: return "person.3.fill"
        }
    }

    var label: String {
        switch self {
        case .aiAgent: return "AI Agent"
        case .staffChat: return "Staff"
        case .teamChannel: return "Team"
        }
    }
}

// MARK: - Agent Status

enum AgentStatus: String, Codable, Equatable {
    case idle
    case thinking
    case working
    case completed
    case error

    var color: Color {
        switch self {
        case .idle: return .gray
        case .thinking: return .orange
        case .working: return .blue
        case .completed: return .green
        case .error: return .red
        }
    }

    /// Default label - use statusDetail for contextual messages
    var label: String {
        switch self {
        case .idle: return "Ready to help"
        case .thinking: return "Thinking"
        case .working: return "Working on it"
        case .completed: return "Completed"
        case .error: return "Something went wrong"
        }
    }

    /// Whether to show as active (pulsing indicator)
    var isActive: Bool {
        self == .thinking || self == .working
    }
}

// MARK: - Chat Conversation

struct ChatConversation: Identifiable, Equatable {
    let id: UUID
    var type: ConversationType
    var title: String
    var subtitle: String?
    var lastMessage: String?
    var lastMessageTime: Date?
    var unreadCount: Int
    var isPinned: Bool
    var agentStatus: AgentStatus?
    var avatarUrl: String?
    var participantIds: [UUID]
    var databaseId: UUID?

    // For AI chats
    var taskDescription: String?
    var progress: Double? // 0.0 - 1.0

    /// Contextual status message (e.g., "Generating your sales report...")
    /// Falls back to agentStatus.label if nil
    var statusDetail: String?

    init(
        id: UUID = UUID(),
        type: ConversationType,
        title: String,
        subtitle: String? = nil,
        lastMessage: String? = nil,
        lastMessageTime: Date? = nil,
        unreadCount: Int = 0,
        isPinned: Bool = false,
        agentStatus: AgentStatus? = nil,
        avatarUrl: String? = nil,
        participantIds: [UUID] = [],
        databaseId: UUID? = nil,
        taskDescription: String? = nil,
        progress: Double? = nil,
        statusDetail: String? = nil
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.subtitle = subtitle
        self.lastMessage = lastMessage
        self.lastMessageTime = lastMessageTime
        self.unreadCount = unreadCount
        self.isPinned = isPinned
        self.agentStatus = agentStatus
        self.avatarUrl = avatarUrl
        self.participantIds = participantIds
        self.databaseId = databaseId
        self.taskDescription = taskDescription
        self.progress = progress
        self.statusDetail = statusDetail
    }

    /// Display-ready status text - uses detail if available, falls back to status label
    var displayStatus: String? {
        if let detail = statusDetail, !detail.isEmpty {
            return detail
        }
        return agentStatus?.label
    }

    static func == (lhs: ChatConversation, rhs: ChatConversation) -> Bool {
        lhs.id == rhs.id &&
        lhs.lastMessage == rhs.lastMessage &&
        lhs.unreadCount == rhs.unreadCount &&
        lhs.agentStatus == rhs.agentStatus &&
        lhs.progress == rhs.progress &&
        lhs.statusDetail == rhs.statusDetail
    }
}

// MARK: - Chat List Store

@MainActor
final class ChatListStore: ObservableObject {

    static let shared = ChatListStore()

    // MARK: - Published State

    @Published private(set) var conversations: [ChatConversation] = []
    @Published private(set) var isLoading = false
    @Published var selectedConversationId: UUID?

    /// Navigation state - persists across dock open/close
    /// When true, user is in a chat view; when false, in list view
    @Published var isInChatView: Bool = false

    // MARK: - Computed Properties

    var selectedConversation: ChatConversation? {
        conversations.first { $0.id == selectedConversationId }
    }

    var pinnedConversations: [ChatConversation] {
        conversations.filter { $0.isPinned }.sorted { ($0.lastMessageTime ?? .distantPast) > ($1.lastMessageTime ?? .distantPast) }
    }

    var unpinnedConversations: [ChatConversation] {
        conversations.filter { !$0.isPinned }.sorted { ($0.lastMessageTime ?? .distantPast) > ($1.lastMessageTime ?? .distantPast) }
    }

    var aiAgentConversations: [ChatConversation] {
        conversations.filter { $0.type == .aiAgent }
    }

    var activeAgents: [ChatConversation] {
        conversations.filter { $0.type == .aiAgent && ($0.agentStatus == .working || $0.agentStatus == .thinking) }
    }

    var totalUnread: Int {
        conversations.reduce(0) { $0 + $1.unreadCount }
    }

    // MARK: - Initialization

    private init() {
        // Add default Lisa conversation
        addDefaultConversations()
    }

    private func addDefaultConversations() {
        // Always have a main Lisa chat available
        let lisaChat = ChatConversation(
            type: .aiAgent,
            title: "Lisa",
            subtitle: "AI Assistant",
            lastMessage: "How can I help you today?",
            lastMessageTime: Date(),
            isPinned: true,
            agentStatus: .idle
        )
        conversations.append(lisaChat)
    }

    // MARK: - Public API

    func loadConversations() async {
        guard !isLoading else { return }
        isLoading = true

        // Load from database
        await loadFromDatabase()

        isLoading = false
    }

    func createNewAIChat(title: String? = nil, taskDescription: String? = nil) -> ChatConversation {
        let chatNumber = aiAgentConversations.count + 1
        let defaultTitle = title ?? "New Chat \(chatNumber)"

        let conversation = ChatConversation(
            type: .aiAgent,
            title: defaultTitle,
            subtitle: taskDescription ?? "AI Assistant",
            lastMessageTime: Date(),
            agentStatus: .idle,
            taskDescription: taskDescription
        )

        conversations.insert(conversation, at: 0)
        selectedConversationId = conversation.id

        return conversation
    }

    func createStaffChat(with userId: UUID, userName: String, avatarUrl: String? = nil) -> ChatConversation {
        // Check if chat already exists
        if let existing = conversations.first(where: { $0.type == .staffChat && $0.participantIds.contains(userId) }) {
            selectedConversationId = existing.id
            return existing
        }

        let conversation = ChatConversation(
            type: .staffChat,
            title: userName,
            lastMessageTime: Date(),
            avatarUrl: avatarUrl,
            participantIds: [userId]
        )

        conversations.insert(conversation, at: 0)
        selectedConversationId = conversation.id

        return conversation
    }

    func selectConversation(_ id: UUID) {
        selectedConversationId = id
        markAsRead(id)
    }

    func deselectConversation() {
        selectedConversationId = nil
    }

    func updateLastMessage(_ conversationId: UUID, message: String, time: Date = Date()) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        conversations[index].lastMessage = sanitizeMessagePreview(message)
        conversations[index].lastMessageTime = time
    }

    /// Clean up message content for display in chat list preview
    /// Strips XML-style tags, status markers, and other technical content
    private func sanitizeMessagePreview(_ message: String) -> String {
        var cleaned = message

        // Remove XML-style action/status tags completely
        cleaned = cleaned.replacingOccurrences(
            of: #"<[^>]+>"#,
            with: "",
            options: .regularExpression
        )

        // Remove markdown-style formatting that looks technical
        cleaned = cleaned.replacingOccurrences(
            of: #"\*\*[^*]+\*\*"#,
            with: "",
            options: .regularExpression
        )

        // Trim whitespace and newlines
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        // If empty after cleaning, provide a default
        if cleaned.isEmpty {
            return "Task completed"
        }

        // Take first meaningful line if multi-line
        if let firstLine = cleaned.components(separatedBy: .newlines).first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            cleaned = firstLine.trimmingCharacters(in: .whitespaces)
        }

        return cleaned
    }

    /// Update agent status with optional contextual detail message
    /// - Parameters:
    ///   - conversationId: The conversation to update
    ///   - status: The new status (idle, thinking, working, completed, error)
    ///   - detail: Optional contextual message (e.g., "Generating your sales report...")
    ///   - progress: Optional progress value (0.0 - 1.0)
    func updateAgentStatus(_ conversationId: UUID, status: AgentStatus, detail: String? = nil, progress: Double? = nil) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        conversations[index].agentStatus = status
        conversations[index].statusDetail = detail
        if let progress = progress {
            conversations[index].progress = progress
        }
        // Clear detail when completed or idle (unless explicitly provided)
        if (status == .completed || status == .idle) && detail == nil {
            conversations[index].statusDetail = nil
        }
    }

    func incrementUnread(_ conversationId: UUID) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        if conversationId != selectedConversationId {
            conversations[index].unreadCount += 1
        }
    }

    func markAsRead(_ conversationId: UUID) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        conversations[index].unreadCount = 0
    }

    func togglePinned(_ conversationId: UUID) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        conversations[index].isPinned.toggle()
    }

    func deleteConversation(_ conversationId: UUID) {
        conversations.removeAll { $0.id == conversationId }
        if selectedConversationId == conversationId {
            selectedConversationId = nil
        }
    }

    func renameConversation(_ conversationId: UUID, to newTitle: String) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        conversations[index].title = newTitle
    }

    /// Link a local conversation to its database ID
    func linkToDatabase(_ localId: UUID, databaseId: UUID) {
        guard let index = conversations.firstIndex(where: { $0.id == localId }) else { return }
        conversations[index].databaseId = databaseId
    }

    /// Get conversation by local ID
    func conversation(withId id: UUID) -> ChatConversation? {
        conversations.first { $0.id == id }
    }

    // MARK: - Database Operations

    private func loadFromDatabase() async {
        let session = SessionObserver.shared
        guard let storeId = session.storeId,
              let userId = session.userId else { return }

        do {
            let client = await supabaseAsync()

            // Load AI conversations with last message preview
            struct DBConversation: Decodable {
                let id: UUID
                let title: String?
                let updated_at: String
            }

            let dbConversations: [DBConversation] = try await client
                .from("lisa_conversations")
                .select("id, title, updated_at")
                .eq("store_id", value: storeId.uuidString)
                .eq("user_id", value: userId.uuidString)
                .order("updated_at", ascending: false)
                .limit(20)
                .execute()
                .value

            Log.agent.info("ChatListStore: Loaded \(dbConversations.count) conversations from database")

            // Fetch last message for each conversation as preview
            var previews: [UUID: String] = [:]
            for dbConv in dbConversations {
                struct MessageRow: Decodable {
                    let content: String
                }

                // Get the last user message from this conversation
                if let lastMsg: MessageRow = try? await client
                    .from("lisa_messages")
                    .select("content")
                    .eq("conversation_id", value: dbConv.id.uuidString)
                    .eq("role", value: "user")
                    .order("created_at", ascending: false)
                    .limit(1)
                    .single()
                    .execute()
                    .value {
                    previews[dbConv.id] = String(lastMsg.content.prefix(80))
                }
            }

            // Merge database conversations with local list
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            for dbConv in dbConversations {
                let date = formatter.date(from: dbConv.updated_at) ?? Date()
                let preview = previews[dbConv.id]

                // Check if already exists (by databaseId)
                if let index = conversations.firstIndex(where: { $0.databaseId == dbConv.id }) {
                    // Update existing
                    conversations[index].lastMessageTime = date
                    if let title = dbConv.title {
                        conversations[index].title = title
                    }
                    if let preview = preview {
                        conversations[index].lastMessage = preview
                    }
                } else {
                    // Add new conversation from database
                    let newConv = ChatConversation(
                        type: .aiAgent,
                        title: dbConv.title ?? "Chat",
                        subtitle: "AI Assistant",
                        lastMessage: preview ?? "Tap to continue...",
                        lastMessageTime: date,
                        isPinned: false,
                        agentStatus: .idle,
                        databaseId: dbConv.id
                    )
                    conversations.append(newConv)
                    Log.agent.info("ChatListStore: Added conversation from DB - \(dbConv.title ?? "untitled")")
                }
            }

            // Sort by last message time (most recent first)
            conversations.sort { ($0.lastMessageTime ?? .distantPast) > ($1.lastMessageTime ?? .distantPast) }

        } catch {
            Log.agent.error("Failed to load conversations: \(error.localizedDescription)")
        }
    }
}
