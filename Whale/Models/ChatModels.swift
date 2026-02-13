//
//  ChatModels.swift
//  Whale
//
//  Data models for lisa_conversations and lisa_messages tables.
//  Team chat, location channels, AI conversations, alerts, bugs.
//

import Foundation
import Combine

// MARK: - Chat Type

enum ChatType: String, Codable, CaseIterable, Sendable {
    case team
    case dm
    case location
    case ai
    case alerts
    case bugs

    var icon: String {
        switch self {
        case .team: return "person.3"
        case .dm: return "bubble.left.and.bubble.right"
        case .location: return "mappin.circle"
        case .ai: return "cpu"
        case .alerts: return "bell"
        case .bugs: return "ladybug"
        }
    }
}

// MARK: - Chat Conversation

struct ChatConversation: Identifiable, Hashable, Sendable {
    let id: UUID
    let storeId: UUID?
    let userId: UUID?
    let title: String?
    let status: String?
    let messageCount: Int
    let chatType: ChatType
    let locationId: UUID?
    let createdAt: Date
    let updatedAt: Date

    var displayTitle: String { title ?? chatType.rawValue.capitalized }
    var typeIcon: String { chatType.icon }
}

extension ChatConversation: Decodable {
    enum CodingKeys: String, CodingKey {
        case id, title, status, metadata
        case storeId = "store_id"
        case userId = "user_id"
        case messageCount = "message_count"
        case chatType = "chat_type"
        case locationId = "location_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        storeId = try c.decodeIfPresent(UUID.self, forKey: .storeId)
        userId = try c.decodeIfPresent(UUID.self, forKey: .userId)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        messageCount = (try? c.decode(Int.self, forKey: .messageCount)) ?? 0
        chatType = (try? c.decode(ChatType.self, forKey: .chatType)) ?? .team
        locationId = try c.decodeIfPresent(UUID.self, forKey: .locationId)
        createdAt = Self.parseDate(c, .createdAt) ?? Date()
        updatedAt = Self.parseDate(c, .updatedAt) ?? Date()
    }

    private static func parseDate(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Date? {
        if let d = try? c.decode(Date.self, forKey: key) { return d }
        guard let s = try? c.decode(String.self, forKey: key) else { return nil }
        return parseISO(s)
    }

    private static func parseISO(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}

// MARK: - Chat Message

struct ChatMessage: Identifiable, Hashable, Sendable {
    let id: UUID
    let conversationId: UUID
    let role: String
    let content: String
    let senderId: UUID?
    let isAiInvocation: Bool
    let replyToMessageId: UUID?
    let createdAt: Date

    /// Memberwise init for creating transient/streaming messages
    init(id: UUID = UUID(), conversationId: UUID, role: String, content: String,
         senderId: UUID? = nil, isAiInvocation: Bool = false,
         replyToMessageId: UUID? = nil, createdAt: Date = Date()) {
        self.id = id
        self.conversationId = conversationId
        self.role = role
        self.content = content
        self.senderId = senderId
        self.isAiInvocation = isAiInvocation
        self.replyToMessageId = replyToMessageId
        self.createdAt = createdAt
    }

    var isUser: Bool { role == "user" }
    var isAssistant: Bool { role == "assistant" }
    var isAI: Bool { isAiInvocation || isAssistant }
    var isError: Bool { content.hasPrefix("[ERROR]") }

    /// Whether this is a transient tool call indicator
    var isToolCall: Bool { content.hasPrefix("tool:") }
    var isToolDone: Bool { content.hasPrefix("tool_done:") }

    var displayContent: String {
        content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension ChatMessage: Codable {
    enum CodingKeys: String, CodingKey {
        case id, role, content
        case conversationId = "conversation_id"
        case senderId = "sender_id"
        case isAiInvocation = "is_ai_invocation"
        case replyToMessageId = "reply_to_message_id"
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        conversationId = try c.decode(UUID.self, forKey: .conversationId)
        role = try c.decode(String.self, forKey: .role)
        content = try c.decode(String.self, forKey: .content)
        senderId = try c.decodeIfPresent(UUID.self, forKey: .senderId)
        isAiInvocation = (try? c.decode(Bool.self, forKey: .isAiInvocation)) ?? false
        replyToMessageId = try c.decodeIfPresent(UUID.self, forKey: .replyToMessageId)
        createdAt = Self.parseDate(c, .createdAt) ?? Date()
    }

    private static func parseDate(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Date? {
        if let d = try? c.decode(Date.self, forKey: key) { return d }
        guard let s = try? c.decode(String.self, forKey: key) else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}

// MARK: - Chat Sender

struct ChatSender: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let firstName: String?
    let lastName: String?
    let email: String?

    enum CodingKeys: String, CodingKey {
        case id = "auth_user_id"
        case firstName = "first_name"
        case lastName = "last_name"
        case email
    }

    var displayName: String {
        let parts = [firstName, lastName].compactMap { $0 }.filter { !$0.isEmpty }
        if !parts.isEmpty { return parts.joined(separator: " ") }
        if let email { return email.components(separatedBy: "@").first ?? email }
        return "Team Member"
    }

    var initials: String {
        let f = firstName?.first.map(String.init) ?? ""
        let l = lastName?.first.map(String.init) ?? ""
        let r = f + l
        return r.isEmpty ? "?" : r.uppercased()
    }
}

// MARK: - AI Agent (from ai_agent_config table — shared with WhaleChat)

struct AIAgent: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let storeId: UUID?
    var name: String?
    var description: String?
    var icon: String?
    var accentColor: String?
    var systemPrompt: String?
    var model: String?
    var maxToolCalls: Int?
    var maxTokens: Int?
    var version: Int?
    var isActive: Bool
    let createdAt: Date?
    var updatedAt: Date?
    var status: String?
    var publishedAt: Date?
    var publishedBy: UUID?
    var enabledTools: [String]?
    var contextConfig: ContextConfig?
    var temperature: Double?
    var tone: String?
    var verbosity: String?
    var canQuery: Bool?
    var canSend: Bool?
    var canModify: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case storeId = "store_id"
        case name, description, icon
        case accentColor = "accent_color"
        case systemPrompt = "system_prompt"
        case model
        case maxToolCalls = "max_tool_calls"
        case maxTokens = "max_tokens"
        case version
        case isActive = "is_active"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case status
        case publishedAt = "published_at"
        case publishedBy = "published_by"
        case enabledTools = "enabled_tools"
        case contextConfig = "context_config"
        case temperature, tone, verbosity
        case canQuery = "can_query"
        case canSend = "can_send"
        case canModify = "can_modify"
    }

    var displayName: String { name?.isEmpty == false ? name! : "AI Agent" }
    var displayIcon: String { icon ?? "cpu" }
    var displayColor: String { accentColor ?? "blue" }
    var shortDescription: String { description ?? "AI Agent" }

    /// Lowercase slug for @mention matching (e.g. "Wilson" → "wilson")
    var mentionSlug: String { displayName.lowercased().replacingOccurrences(of: " ", with: "") }
}

// MARK: - Context Config

struct ContextConfig: Codable, Hashable, Sendable {
    var includeLocations: Bool?
    var locationIds: [String]?
    var includeCustomers: Bool?
    var customerSegments: [String]?
    // Context window management (chars, ~4 chars per token)
    var maxHistoryChars: Int?       // total history budget (default 400K ~100K tokens)
    var maxToolResultChars: Int?    // per tool result (default 40K ~10K tokens)
    var maxMessageChars: Int?       // per history message (default 20K ~5K tokens)
}

// MARK: - Token Usage

struct TokenUsage: Sendable {
    let inputTokens: Int
    let outputTokens: Int
    let totalCost: Double
    var totalTokens: Int { inputTokens + outputTokens }
}

// MARK: - Chat Attachment

enum ChatAttachmentType: String, Codable, Sendable {
    case image
    case pdf
}

struct ChatAttachment: Identifiable, Hashable, Sendable {
    let id: UUID
    let type: ChatAttachmentType
    let fileName: String
    let data: Data
    let thumbnail: Data?  // For preview rendering
    let pageCount: Int?   // For PDFs

    init(id: UUID = UUID(), type: ChatAttachmentType, fileName: String, data: Data, thumbnail: Data? = nil, pageCount: Int? = nil) {
        self.id = id
        self.type = type
        self.fileName = fileName
        self.data = data
        self.thumbnail = thumbnail
        self.pageCount = pageCount
    }

    var icon: String {
        switch type {
        case .image: return "photo"
        case .pdf: return "doc.fill"
        }
    }

    var displayName: String {
        if fileName.count > 12 {
            let ext = (fileName as NSString).pathExtension
            let name = (fileName as NSString).deletingPathExtension
            let truncated = String(name.prefix(8))
            return ext.isEmpty ? "\(truncated)..." : "\(truncated)...\(ext)"
        }
        return fileName
    }

    /// Approximate size in KB/MB
    var sizeLabel: String {
        let bytes = data.count
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024)
        } else {
            return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
        }
    }
}

// MARK: - Chat Completed Task

struct ChatTask: Identifiable, Codable, Sendable {
    let id: UUID
    let messageId: UUID
    let conversationId: UUID
    let storeId: UUID?
    let completedBy: UUID?
    let completedByName: String?
    let originalContent: String
    let originalRole: String
    let senderName: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case messageId = "message_id"
        case conversationId = "conversation_id"
        case storeId = "store_id"
        case completedBy = "completed_by"
        case completedByName = "completed_by_name"
        case originalContent = "original_content"
        case originalRole = "original_role"
        case senderName = "sender_name"
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        messageId = try c.decode(UUID.self, forKey: .messageId)
        conversationId = try c.decode(UUID.self, forKey: .conversationId)
        storeId = try c.decodeIfPresent(UUID.self, forKey: .storeId)
        completedBy = try c.decodeIfPresent(UUID.self, forKey: .completedBy)
        completedByName = try c.decodeIfPresent(String.self, forKey: .completedByName)
        originalContent = try c.decode(String.self, forKey: .originalContent)
        originalRole = (try? c.decode(String.self, forKey: .originalRole)) ?? "assistant"
        senderName = try c.decodeIfPresent(String.self, forKey: .senderName)

        // Date parsing with fractional seconds fallback
        if let d = try? c.decode(Date.self, forKey: .createdAt) {
            createdAt = d
        } else if let s = try? c.decode(String.self, forKey: .createdAt) {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = f.date(from: s) {
                createdAt = d
            } else {
                f.formatOptions = [.withInternetDateTime]
                createdAt = f.date(from: s) ?? Date()
            }
        } else {
            createdAt = Date()
        }
    }
}

// MARK: - Streaming Text Buffer

@MainActor
final class StreamingTextBuffer: ObservableObject {
    @Published private(set) var text: String = ""
    @Published private(set) var version: UInt = 0
    private var pendingText: String = ""
    private var updateTask: Task<Void, Never>?
    private var lastUpdate: Date = .distantPast
    private let minInterval: TimeInterval = 0.033 // ~30fps

    func append(_ newText: String) {
        pendingText += newText
        if Date().timeIntervalSince(lastUpdate) >= minInterval {
            flushPending()
        } else if updateTask == nil {
            updateTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(33))
                guard !Task.isCancelled else { return }
                self?.flushPending()
            }
        }
    }

    private func flushPending() {
        guard !pendingText.isEmpty else { return }
        text += pendingText
        pendingText = ""
        version &+= 1
        lastUpdate = Date()
        updateTask = nil
    }

    func clear() {
        updateTask?.cancel()
        updateTask = nil
        pendingText = ""
        text = ""
        version = 0
        lastUpdate = .distantPast
    }

    func flush() {
        updateTask?.cancel()
        updateTask = nil
        flushPending()
    }
}
