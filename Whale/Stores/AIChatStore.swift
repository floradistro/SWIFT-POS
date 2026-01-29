//
//  AIChatStore.swift
//  Whale
//
//  Manages AI chat state and streams responses from Claude.
//  Persists conversation history per staff member.
//

import Foundation
import SwiftUI
import UIKit
import Combine
import os.log
import Supabase
import PDFKit
import UniformTypeIdentifiers

// MARK: - Chat Attachment

struct ChatAttachment: Identifiable, Equatable {
    let id: UUID
    let type: AttachmentType
    let data: Data
    let fileName: String
    let mimeType: String
    var thumbnail: UIImage?
    var extractedText: String?  // For PDFs
    var publicUrl: String?  // Public URL after upload to storage (for use in emails)
    var caption: String?  // iOS Photos caption (user-defined name for the image)

    enum AttachmentType: String, Equatable {
        case image
        case pdf
        case document
    }

    init(id: UUID = UUID(), type: AttachmentType, data: Data, fileName: String, mimeType: String, thumbnail: UIImage? = nil, extractedText: String? = nil, publicUrl: String? = nil, caption: String? = nil) {
        self.id = id
        self.type = type
        self.data = data
        self.fileName = fileName
        self.mimeType = mimeType
        self.thumbnail = thumbnail
        self.extractedText = extractedText
        self.publicUrl = publicUrl
        self.caption = caption
    }

    /// Display name: caption if available, otherwise filename
    var displayName: String {
        if let caption = caption, !caption.isEmpty {
            return caption
        }
        return fileName
    }

    static func == (lhs: ChatAttachment, rhs: ChatAttachment) -> Bool {
        lhs.id == rhs.id
    }

    /// Create from image data (resized and compressed to stay under Claude's 5MB limit)
    /// - Parameters:
    ///   - image: The UIImage to process
    ///   - fileName: Filename for the attachment
    ///   - caption: iOS Photos caption (user-defined name) - will be used to identify the image to AI
    static func fromImage(_ image: UIImage, fileName: String = "image.jpg", caption: String? = nil) -> ChatAttachment? {
        // Claude has a 5MB limit for images, target 4MB to be safe
        let maxBytes = 4 * 1024 * 1024
        let maxDimension: CGFloat = 2048  // Max dimension to avoid huge images

        // Resize if needed
        var processedImage = image
        let originalSize = image.size
        if originalSize.width > maxDimension || originalSize.height > maxDimension {
            let scale = maxDimension / max(originalSize.width, originalSize.height)
            let newSize = CGSize(width: originalSize.width * scale, height: originalSize.height * scale)
            let renderer = UIGraphicsImageRenderer(size: newSize)
            processedImage = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: newSize))
            }
            Log.agent.info("Resized image from \(Int(originalSize.width))x\(Int(originalSize.height)) to \(Int(newSize.width))x\(Int(newSize.height))")
        }

        // Try progressively lower quality until under limit
        var quality: CGFloat = 0.8
        var data = processedImage.jpegData(compressionQuality: quality)

        while let currentData = data, currentData.count > maxBytes, quality > 0.1 {
            quality -= 0.1
            data = processedImage.jpegData(compressionQuality: quality)
            Log.agent.info("Compressed image to quality \(quality), size: \(currentData.count / 1024)KB")
        }

        guard let finalData = data else { return nil }

        // Use caption as filename if available (sanitized for file system)
        let finalFileName: String
        if let caption = caption, !caption.isEmpty {
            // Sanitize caption for use as filename
            let sanitized = caption
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            finalFileName = sanitized.isEmpty ? fileName : "\(sanitized).jpg"
            Log.agent.info("Image has caption: '\(caption)' -> filename: '\(finalFileName)'")
        } else {
            finalFileName = fileName
        }

        Log.agent.info("Final image size: \(finalData.count / 1024)KB (quality: \(quality))")

        return ChatAttachment(
            type: .image,
            data: finalData,
            fileName: finalFileName,
            mimeType: "image/jpeg",
            thumbnail: processedImage,
            caption: caption
        )
    }

    /// Create from PDF data
    static func fromPDF(_ data: Data, fileName: String) -> ChatAttachment {
        var attachment = ChatAttachment(
            type: .pdf,
            data: data,
            fileName: fileName,
            mimeType: "application/pdf"
        )

        // Extract text and thumbnail from PDF
        if let pdf = PDFDocument(data: data) {
            // Extract text
            var text = ""
            for pageIndex in 0..<min(pdf.pageCount, 10) {  // Limit to first 10 pages
                if let page = pdf.page(at: pageIndex), let pageText = page.string {
                    text += pageText + "\n\n"
                }
            }
            attachment.extractedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

            // Generate thumbnail from first page
            if let firstPage = pdf.page(at: 0) {
                let pageRect = firstPage.bounds(for: .mediaBox)
                let scale: CGFloat = 100 / max(pageRect.width, pageRect.height)
                let thumbnailSize = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)

                let renderer = UIGraphicsImageRenderer(size: thumbnailSize)
                attachment.thumbnail = renderer.image { ctx in
                    UIColor.white.setFill()
                    ctx.fill(CGRect(origin: .zero, size: thumbnailSize))

                    ctx.cgContext.translateBy(x: 0, y: thumbnailSize.height)
                    ctx.cgContext.scaleBy(x: scale, y: -scale)
                    firstPage.draw(with: .mediaBox, to: ctx.cgContext)
                }
            }
        }

        return attachment
    }

    /// Base64 encoded data for API
    var base64Data: String {
        data.base64EncodedString()
    }
}

// MARK: - Chat Message

struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let role: ChatRole
    var content: String
    let timestamp: Date
    var isStreaming: Bool
    var attachments: [ChatAttachment]
    var databaseId: UUID?  // ID from lisa_messages table (for feedback)
    var feedbackRating: Int?  // -1 = negative, 0 = neutral, 1 = positive

    enum ChatRole: String {
        case user
        case assistant
    }

    init(id: UUID = UUID(), role: ChatRole, content: String, timestamp: Date = Date(), isStreaming: Bool = false, attachments: [ChatAttachment] = [], databaseId: UUID? = nil, feedbackRating: Int? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.isStreaming = isStreaming
        self.attachments = attachments
        self.databaseId = databaseId
        self.feedbackRating = feedbackRating
    }

    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id && lhs.content == rhs.content && lhs.isStreaming == rhs.isStreaming && lhs.feedbackRating == rhs.feedbackRating
    }
}

// MARK: - Database Message (for decoding)

private struct DBMessage: Decodable {
    let id: UUID
    let role: String
    let content: String
    let tool_calls: [String: Any]?  // JSON column, can be ignored
    let created_at: Date

    enum CodingKeys: String, CodingKey {
        case id, role, content, created_at
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        role = try container.decode(String.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)
        tool_calls = nil  // We don't need this for display

        // Handle date - try ISO8601 with fractional seconds
        let dateString = try container.decode(String.self, forKey: .created_at)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: dateString) {
            created_at = date
        } else {
            // Fallback without fractional seconds
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: dateString) {
                created_at = date
            } else {
                created_at = Date()
            }
        }
    }
}

// MARK: - Chat Store

@MainActor
final class AIChatStore: ObservableObject {
    static let shared = AIChatStore()

    // MARK: - Workspace (The Core - Each Workspace is Completely Isolated)

    /// All workspaces keyed by ID ("general" or repo ID)
    private var workspaces: [String: WorkspaceState] = [:]

    /// The current active workspace - views observe this directly
    @Published var workspace: WorkspaceState

    /// Forwards workspace changes to store so views update
    private var workspaceSubscription: AnyCancellable?

    // MARK: - Store-Level State (Shared Across Workspaces)

    // CRITICAL: Streaming update counter - changes every chunk to force view updates
    // This is observed by views and changes whenever streaming content updates
    @Published var streamingUpdateCounter: Int = 0

    // Chat visibility
    @Published var isChatVisible: Bool = false
    @Published var isChatInputFocused: Bool = false

    // Action tracking for undo
    @Published var trackedActions: [TrackedAction] = []

    // Conversation history
    @Published var conversations: [ConversationSummary] = []
    @Published var isLoadingHistory: Bool = false

    // Model selection
    @Published var selectedModel: AIModel = .opus

    // Repo selection (for coding mode)
    @Published var selectedRepo: GitHubRepo? = nil

    // MARK: - GitHub Repo Model

    struct GitHubRepo: Identifiable, Equatable, Codable {
        var id: String { fullName }
        let fullName: String   // e.g. "floradistro/flora-distro-storefront"
        let owner: String      // e.g. "floradistro"
        let name: String       // e.g. "flora-distro-storefront"

        init(fullName: String) {
            self.fullName = fullName
            let parts = fullName.split(separator: "/")
            self.owner = parts.count > 0 ? String(parts[0]) : ""
            self.name = parts.count > 1 ? String(parts[1]) : fullName
        }
    }

    // Recently used repos (persisted)
    @Published var recentRepos: [GitHubRepo] = []

    // Store's connected repo (from stores table)
    @Published var storeRepo: GitHubRepo? = nil

    // All available GitHub repos from user's account
    @Published var availableRepos: [GitHubRepo] = []
    @Published var isLoadingRepos: Bool = false

    private let recentReposKey = "ai_chat_recent_repos"

    func loadRecentRepos() {
        if let data = UserDefaults.standard.data(forKey: recentReposKey),
           let repos = try? JSONDecoder().decode([GitHubRepo].self, from: data) {
            recentRepos = repos
        }
    }

    /// Load the store's connected GitHub repo from AppSession
    func loadStoreRepo() {
        Task {
            let store = await AppSession.shared.store
            await MainActor.run {
                if let repoFullName = store?.githubRepoFullName,
                   !repoFullName.isEmpty {
                    storeRepo = GitHubRepo(fullName: repoFullName)
                }
            }
        }
    }

    /// Fetch all GitHub repos from user's connected GitHub account
    func fetchGitHubRepos() {
        guard !isLoadingRepos else { return }
        isLoadingRepos = true

        Task {
            do {
                let storeId = await AppSession.shared.storeId
                guard let storeId = storeId else {
                    await MainActor.run { isLoadingRepos = false }
                    return
                }

                // Call the github-repos edge function
                guard let url = URL(string: "\(SupabaseConfig.baseURL)/functions/v1/github-repos") else {
                    await MainActor.run { isLoadingRepos = false }
                    return
                }

                let body: [String: Any] = [
                    "store_id": storeId.uuidString.lowercased()
                ]

                let jsonData = try JSONSerialization.data(withJSONObject: body)

                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                // Use anon key from SupabaseConfig
                request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
                request.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
                request.httpBody = jsonData

                let (data, _) = try await URLSession.shared.data(for: request)

                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let success = json["success"] as? Bool, success,
                   let reposData = json["repos"] as? [[String: Any]] {

                    let repos = reposData.compactMap { repoDict -> GitHubRepo? in
                        guard let fullName = repoDict["full_name"] as? String else { return nil }
                        return GitHubRepo(fullName: fullName)
                    }

                    await MainActor.run {
                        self.availableRepos = repos
                        self.isLoadingRepos = false
                    }
                } else {
                    // Check for error message
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let errorMsg = json["error"] as? String {
                        Log.agent.warning("GitHub repos: \(errorMsg)")
                    }
                    await MainActor.run { isLoadingRepos = false }
                }
            } catch {
                Log.agent.error("Failed to fetch GitHub repos: \(error.localizedDescription)")
                await MainActor.run { isLoadingRepos = false }
            }
        }
    }

    func selectRepo(_ repo: GitHubRepo?) {
        selectedRepo = repo
        if let repo = repo {
            // Add to recent, keeping max 5
            recentRepos.removeAll { $0.fullName == repo.fullName }
            recentRepos.insert(repo, at: 0)
            if recentRepos.count > 5 {
                recentRepos = Array(recentRepos.prefix(5))
            }
            // Persist
            if let data = try? JSONEncoder().encode(recentRepos) {
                UserDefaults.standard.set(data, forKey: recentReposKey)
            }
        }
    }

    func clearRepo() {
        selectedRepo = nil
    }

    // MARK: - Context Caching (Anthropic-style: load once, use many)
    // These are pre-loaded when chat opens and refreshed on location change

    /// Cached displays for current location
    private var cachedDisplays: [DisplayInfo] = []

    /// Cached in-stock products for current location
    private var cachedProducts: [ProductSummary] = []

    /// Location ID when cache was loaded (invalidate if changed)
    private var cachedLocationId: UUID?

    /// Last cache refresh time
    private var cacheLoadedAt: Date?

    // MARK: - AI Models

    enum AIModel: String, CaseIterable, Identifiable {
        case haiku = "claude-haiku-4-5-20251001"
        case sonnet = "claude-sonnet-4-5-20250929"
        case opus = "claude-opus-4-5-20251101"
        case gemini = "gemini-2.5-flash"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .haiku: return "Haiku"
            case .sonnet: return "Sonnet"
            case .opus: return "Opus"
            case .gemini: return "Gemini"
            }
        }

        var icon: String {
            switch self {
            case .haiku: return "hare"
            case .sonnet: return "sparkles"
            case .opus: return "brain.head.profile"
            case .gemini: return "globe.americas"
            }
        }

        var description: String {
            switch self {
            case .haiku: return "Fast & efficient"
            case .sonnet: return "Balanced"
            case .opus: return "Most capable"
            case .gemini: return "Google AI"
            }
        }

        var shortName: String {
            switch self {
            case .haiku: return "Haiku"
            case .sonnet: return "Sonnet"
            case .opus: return "Opus"
            case .gemini: return "Gemini"
            }
        }

        var isGemini: Bool {
            self == .gemini
        }
    }

    // MARK: - Private

    private var hasLoadedHistory = false

    private init() {
        // Create the default "general" workspace
        let generalWorkspace = WorkspaceState(id: "general")
        self.workspace = generalWorkspace
        self.workspaces["general"] = generalWorkspace

        // Forward workspace changes to store so views update
        subscribeToWorkspace(generalWorkspace)
    }

    /// Subscribe to a workspace's changes and forward to store
    private func subscribeToWorkspace(_ ws: WorkspaceState) {
        workspaceSubscription = ws.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
    }

    // MARK: - Conversation Summary

    struct ConversationSummary: Identifiable {
        let id: UUID
        let title: String
        let messageCount: Int
        let updatedAt: Date
        let preview: String?  // First user message for context
    }

    // MARK: - Workspace State

    /// Holds ALL state for the chat workspace
    /// This is an ObservableObject so views can observe it directly
    @MainActor
    final class WorkspaceState: ObservableObject {
        let id: String

        // Chat state - all @Published for direct observation
        @Published var messages: [ChatMessage] = []
        @Published var inputText: String = ""
        @Published var pendingAttachments: [ChatAttachment] = []
        @Published var conversationId: UUID?
        @Published var error: String?

        // Dev mode context - auto-injected into AI messages when set
        @Published var devModeContext: String?
        @Published var devModeCreationId: String?

        // Streaming state
        @Published var isLoading: Bool = false
        @Published var isStreaming: Bool = false
        @Published var streamingTokenCount: Int = 0
        @Published var streamingStartTime: Date?

        // Task tracking (not published - internal use only)
        var streamTask: Task<Void, Never>?

        var displayName: String { "General" }
        var icon: String { "bubble.left.and.bubble.right" }

        init(id: String) {
            self.id = id
        }

        func cancelStream() {
            streamTask?.cancel()
            streamTask = nil
            isLoading = false
            isStreaming = false

            if let lastIndex = messages.indices.last, messages[lastIndex].isStreaming {
                messages[lastIndex].isStreaming = false
                if messages[lastIndex].content.isEmpty {
                    messages[lastIndex].content = "Cancelled."
                }
            }
        }

        func reset() {
            messages = []
            inputText = ""
            pendingAttachments = []
            conversationId = nil
            error = nil
            devModeContext = nil
            devModeCreationId = nil
            isLoading = false
            isStreaming = false
            streamingTokenCount = 0
            streamingStartTime = nil
            streamTask?.cancel()
            streamTask = nil
        }
    }

    // MARK: - Load Conversation History

    /// Load today's conversation or create a new one
    func loadConversation() async {
        let session = SessionObserver.shared
        guard let storeId = session.storeId,
              let userId = session.userId else {
            Log.agent.warning("Cannot load conversation - no session")
            return
        }

        // Prevent double loading
        guard !hasLoadedHistory else { return }
        hasLoadedHistory = true
        isLoadingHistory = true

        do {
            let client = await supabaseAsync()

            // Get or create today's conversation
            let response: UUID = try await client
                .rpc("get_or_create_lisa_conversation", params: [
                    "p_store_id": storeId.uuidString,
                    "p_user_id": userId.uuidString
                ])
                .execute()
                .value

            workspace.conversationId = response
            Log.agent.info("Loaded conversation: \(response.uuidString)")

            // Load messages for this conversation
            await loadMessages(conversationId: response)

            // Load optimized context (includes summary if available)
            await loadOptimizedContext(conversationId: response)

        } catch {
            Log.agent.error("Failed to load conversation: \(error.localizedDescription)")
            // Fall back to welcome message
            updateWelcomeMessage(in: workspace)
        }

        isLoadingHistory = false
    }

    /// Switch to a specific conversation
    func switchConversation(to conversationId: UUID) async {
        Log.agent.info("Switching to conversation: \(conversationId.uuidString)")

        // Store previous conversation ID to detect if we're switching to a different conversation
        let previousConversationId = workspace.conversationId
        let isSameConversation = previousConversationId == conversationId

        workspace.conversationId = conversationId
        workspace.isLoading = true

        // Load messages - the function now handles preserving messages on error
        await loadMessages(conversationId: conversationId)

        workspace.isLoading = false
        Log.agent.info("Switched to conversation \(conversationId.uuidString), now have \(self.workspace.messages.count) messages (same: \(isSameConversation))")
    }

    /// Load or create a conversation for a specific window/creation context
    /// This is used when opening chat from a Stage Manager window
    func loadConversationForWindow(windowId: UUID, creationId: String?, creationName: String?) async -> UUID? {
        let session = SessionObserver.shared
        guard let storeId = session.storeId,
              let userId = session.userId else {
            Log.agent.warning("Cannot load conversation - no session")
            return nil
        }

        isLoadingHistory = true

        do {
            let client = await supabaseAsync()

            // If window already has a conversation, load it
            if let existingConvId = StageManagerStore.shared.conversationId(for: windowId) {
                Log.agent.info("Window already has conversation: \(existingConvId)")
                workspace.conversationId = existingConvId
                await loadMessages(conversationId: existingConvId)

                // Update active creation context if this is a creation window
                if let creationId = creationId {
                    workspace.devModeCreationId = creationId
                }

                isLoadingHistory = false
                return existingConvId
            }

            // Create a new conversation for this window
            let title = creationName ?? "Chat"
            let response: UUID = try await client
                .rpc("get_or_create_lisa_conversation", params: [
                    "p_store_id": storeId.uuidString,
                    "p_user_id": userId.uuidString,
                    "p_title": title
                ])
                .execute()
                .value

            workspace.conversationId = response
            Log.agent.info("Created conversation \(response) for window")

            // Link conversation to window
            await MainActor.run {
                StageManagerStore.shared.setConversation(for: windowId, conversationId: response)
            }

            // Update active creation context if this is a creation window
            if let creationId = creationId {
                workspace.devModeCreationId = creationId
            }

            // Load any existing messages (in case conversation was reused)
            await loadMessages(conversationId: response)

            isLoadingHistory = false
            return response

        } catch {
            Log.agent.error("Failed to load/create window conversation: \(error.localizedDescription)")
            updateWelcomeMessage(in: workspace)
            isLoadingHistory = false
            return nil
        }
    }

    /// Force reload the current conversation's messages (called when chat is shown)
    func reloadCurrentConversation() async {
        guard let conversationId = workspace.conversationId else {
            // No conversation yet - load default
            hasLoadedHistory = false
            await loadConversation()
            return
        }

        await loadMessages(conversationId: conversationId)
    }

    /// Load messages for a conversation
    private func loadMessages(conversationId: UUID) async {
        Log.agent.info("Loading messages for conversation: \(conversationId.uuidString)")

        // Keep existing messages until we successfully load new ones
        let previousMessages = workspace.messages

        do {
            let client = await supabaseAsync()

            let dbMessages: [DBMessage] = try await client
                .rpc("get_lisa_conversation_history", params: [
                    "p_conversation_id": conversationId.uuidString,
                    "p_limit": "50"
                ])
                .execute()
                .value

            Log.agent.info("Fetched \(dbMessages.count) messages from database")

            if dbMessages.isEmpty {
                // New conversation - show welcome (clear previous messages)
                Log.agent.info("No messages found, showing welcome")
                workspace.messages = []
                updateWelcomeMessage(in: workspace)
            } else {
                // Convert DB messages to ChatMessages - update workspace directly
                // Only replace messages after successful fetch
                workspace.messages = dbMessages.map { dbMsg in
                    ChatMessage(
                        id: dbMsg.id,
                        role: dbMsg.role == "user" ? .user : .assistant,
                        content: dbMsg.content,
                        timestamp: dbMsg.created_at,
                        isStreaming: false,
                        databaseId: dbMsg.id  // Store DB ID for feedback
                    )
                }
                Log.agent.info("Loaded \(self.workspace.messages.count) messages into chat")
            }

        } catch {
            Log.agent.error("Failed to load messages: \(error.localizedDescription)")
            // Keep previous messages if we had any, otherwise show welcome
            if previousMessages.isEmpty {
                workspace.messages = []
                updateWelcomeMessage(in: workspace)
            } else {
                Log.agent.info("Keeping \(previousMessages.count) previous messages after load failure")
                // Don't clear - keep previous messages on error
            }
        }
    }

    /// Load list of past conversations with previews
    func loadConversationList() async {
        let session = SessionObserver.shared
        guard let storeId = session.storeId,
              let userId = session.userId else { return }

        do {
            let client = await supabaseAsync()

            struct ConvRow: Decodable {
                let id: UUID
                let title: String?
                let message_count: Int
                let updated_at: Date
            }

            let rows: [ConvRow] = try await client
                .rpc("get_lisa_conversations", params: [
                    "p_store_id": storeId.uuidString,
                    "p_user_id": userId.uuidString,
                    "p_limit": "20"
                ])
                .execute()
                .value

            // Get conversation IDs for preview fetch
            let convIds = rows.map { $0.id.uuidString.lowercased() }

            // Fetch first user message for each conversation as preview
            var previews: [UUID: String] = [:]
            if !convIds.isEmpty {
                struct PreviewRow: Decodable {
                    let conversation_id: UUID
                    let content: String?
                }

                // Get first user message from each conversation
                let previewRows: [PreviewRow] = try await client
                    .from("lisa_messages")
                    .select("conversation_id, content")
                    .in("conversation_id", values: convIds)
                    .eq("role", value: "user")
                    .order("created_at", ascending: true)
                    .execute()
                    .value

                // Take first user message per conversation
                for row in previewRows {
                    if previews[row.conversation_id] == nil, let content = row.content {
                        // Truncate to ~80 chars for preview
                        let preview = content.count > 80 ? String(content.prefix(80)) + "..." : content
                        previews[row.conversation_id] = preview
                    }
                }
            }

            conversations = rows.map { row in
                ConversationSummary(
                    id: row.id,
                    title: row.title ?? "Untitled",
                    messageCount: row.message_count,
                    updatedAt: row.updated_at,
                    preview: previews[row.id]
                )
            }

        } catch {
            Log.agent.error("Failed to load conversation list: \(error.localizedDescription)")
        }
    }

    // MARK: - Location Context Loading (Anthropic-style: load once, use many)

    /// Load displays and in-stock products for the current location
    /// This is called when chat opens and cached for the session
    func loadLocationContext() async {
        let session = SessionObserver.shared
        guard let storeId = session.storeId,
              let locationId = session.selectedLocation?.id else {
            Log.agent.info("Cannot load location context - no store or location selected")
            return
        }

        // Skip if already loaded for this location and cache is fresh (5 min)
        if let cached = cachedLocationId, cached == locationId,
           let loadedAt = cacheLoadedAt,
           Date().timeIntervalSince(loadedAt) < 300 {
            Log.agent.info("Using cached location context (location: \(locationId))")
            return
        }

        Log.agent.info("Loading location context for location: \(locationId)")

        do {
            let client = await supabaseAsync()

            // Load displays and products in parallel for speed
            async let displaysTask = loadDisplays(client: client, storeId: storeId, locationId: locationId)
            async let productsTask = loadInStockProducts(client: client, storeId: storeId, locationId: locationId)

            let (displays, products) = await (try displaysTask, try productsTask)

            // Cache the results
            cachedDisplays = displays
            cachedProducts = products
            cachedLocationId = locationId
            cacheLoadedAt = Date()

            Log.agent.info("Loaded location context: \(displays.count) displays, \(products.count) in-stock products")

        } catch {
            Log.agent.error("Failed to load location context: \(error.localizedDescription)")
            // Clear cache on error
            cachedDisplays = []
            cachedProducts = []
            cachedLocationId = nil
            cacheLoadedAt = nil
        }
    }

    /// Load digital displays for a location (from unified creations table)
    private func loadDisplays(client: SupabaseClient, storeId: UUID, locationId: UUID) async throws -> [DisplayInfo] {
        struct DisplayRow: Decodable {
            let id: UUID
            let name: String
            let live_status: String?
        }

        let rows: [DisplayRow] = try await client
            .from("creations")
            .select("id, name, live_status")
            .eq("store_id", value: storeId.uuidString.lowercased())
            .eq("location_id", value: locationId.uuidString.lowercased())
            .eq("creation_type", value: "display")
            .execute()
            .value

        return rows.map { row in
            DisplayInfo(
                id: row.id.uuidString.lowercased(),
                name: row.name,
                status: row.live_status ?? "offline"
            )
        }
    }

    /// Load in-stock products for a location (products with quantity > 0)
    private func loadInStockProducts(client: SupabaseClient, storeId: UUID, locationId: UUID) async throws -> [ProductSummary] {
        // Query products joined with inventory for this location
        // Using RPC for efficient query with pricing data
        struct ProductRow: Decodable {
            let id: UUID
            let name: String
            let category_name: String?
            let quantity: Int
            let pricing_data: AnyCodable?
        }

        // Use RPC for efficient query
        let rows: [ProductRow] = try await client
            .rpc("get_location_instock_products", params: [
                "p_store_id": storeId.uuidString.lowercased(),
                "p_location_id": locationId.uuidString.lowercased()
            ])
            .execute()
            .value

        return rows.map { row in
            // Parse pricing_data - can be {"tiers": [...]} or just [...]
            var pricingTiers: [[String: Any]]? = nil
            if let pricingValue = row.pricing_data?.value {
                if let dict = pricingValue as? [String: Any],
                   let tiers = dict["tiers"] as? [[String: Any]] {
                    pricingTiers = tiers
                } else if let tiers = pricingValue as? [[String: Any]] {
                    pricingTiers = tiers
                }
            }

            return ProductSummary(
                id: row.id.uuidString.lowercased(),
                name: row.name,
                category: row.category_name,
                quantity: row.quantity,
                pricingData: pricingTiers
            )
        }
    }

    /// Invalidate the location context cache (call when location changes)
    func invalidateLocationContext() {
        cachedDisplays = []
        cachedProducts = []
        cachedLocationId = nil
        cacheLoadedAt = nil
        Log.agent.info("Location context cache invalidated")
    }

    /// Start a new conversation in current workspace
    func startNewConversation() async {
        let session = SessionObserver.shared
        guard let storeId = session.storeId,
              let userId = session.userId else { return }

        // Reset workspace for new conversation
        workspace.reset()

        do {
            let client = await supabaseAsync()

            // Create new conversation using RPC
            let newConvId: UUID = try await client
                .rpc("create_lisa_conversation", params: [
                    "p_store_id": storeId.uuidString,
                    "p_user_id": userId.uuidString
                ])
                .execute()
                .value

            workspace.conversationId = newConvId
            updateWelcomeMessage(in: workspace)

            Log.agent.info("Started new conversation: \(newConvId) in workspace: \(self.workspace.displayName)")

        } catch {
            Log.agent.error("Failed to create new conversation: \(error.localizedDescription)")
        }
    }

    /// Update welcome message in a specific workspace
    func updateWelcomeMessage(in ws: WorkspaceState) {
        let session = SessionObserver.shared
        let userName = session.userFirstName ?? "friend"
        let storeName = session.store?.businessName ?? "the shop"

        // Variety of quirky, sweet greetings
        let greetings = [
            "Hey \(userName)! 👋 It's me, Lisa! Ready to make some magic happen at \(storeName) today? What can I help you with?",
            "Well hello there, \(userName)! ✨ Lisa at your service! Whether it's inventory, orders, or just vibes — I'm here for it. What's up?",
            "Oh hey \(userName)! 💫 Your favorite AI sidekick reporting for duty at \(storeName)! What are we tackling today?",
            "\(userName)! There you are! 🌟 I was just thinking about you. Okay not really, I'm an AI, but still — what do you need?",
            "Heyyy \(userName)! 👋 Lisa here, caffeinated and ready! Well... virtually caffeinated. What can I do for you today?"
        ]

        // Pick a random greeting (seeded by day so it's consistent within the day)
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        let welcomeContent = greetings[dayOfYear % greetings.count]

        if ws.messages.isEmpty {
            ws.messages.append(ChatMessage(role: .assistant, content: welcomeContent))
        } else if ws.messages.count == 1 && ws.messages[0].role == .assistant {
            ws.messages[0] = ChatMessage(role: .assistant, content: welcomeContent)
        }
    }

    // MARK: - Session Context

    /// Get active creation from StageManager if user has a creation window open
    private func getActiveCreationContext() -> (id: String, name: String, url: String?)? {
        let stageManager = StageManagerStore.shared

        // Debug: Log what we're seeing
        Log.agent.info("getActiveCreationContext: activeWindowId=\(stageManager.activeWindowId?.uuidString ?? "nil"), windowCount=\(stageManager.windows.count)")

        guard let activeWindowId = stageManager.activeWindowId else {
            Log.agent.info("getActiveCreationContext: No active window")
            return nil
        }

        guard let activeWindow = stageManager.windows.first(where: { $0.id == activeWindowId }) else {
            Log.agent.info("getActiveCreationContext: Active window not found in windows array")
            return nil
        }

        // Check if it's a creation window
        guard case .creation(let creationId, let url, _) = activeWindow.type else {
            let typeDesc: String = {
                switch activeWindow.type {
                case .app: return "app"
                case .creation: return "creation"
                }
            }()
            Log.agent.info("getActiveCreationContext: Active window is not a creation, type=\(typeDesc)")
            return nil
        }

        Log.agent.info("Active creation context FOUND: id=\(creationId) name=\(activeWindow.name)")
        return (id: creationId, name: activeWindow.name, url: url)
    }

    /// Build session context from SessionObserver
    private func buildSessionContext() -> SessionContext? {
        let session = SessionObserver.shared
        guard let storeId = session.storeId else { return nil }

        // DEBUG: Log what location we're getting
        if let loc = session.selectedLocation {
            Log.agent.info("buildSessionContext: locationId=\(loc.id.uuidString) locationName=\(loc.name)")
        } else {
            Log.agent.info("buildSessionContext: selectedLocation is NIL")
        }

        // Get active creation from StageManager (if user has a creation window open)
        let activeCreation = getActiveCreationContext()
        Log.agent.info("buildSessionContext: activeCreation=\(activeCreation?.name ?? "nil")")

        // Build context with pre-loaded displays and products (Anthropic-style caching)
        var context = SessionContext(
            storeId: storeId,
            storeName: session.store?.businessName,
            storeLogoUrl: session.store?.fullLogoUrl?.absoluteString,
            userId: session.userId,
            userEmail: session.userEmail,
            locationId: session.selectedLocation?.id,
            locationName: session.selectedLocation?.name,
            registerId: session.selectedRegister?.id,
            registerName: session.selectedRegister?.registerName,
            conversationId: workspace.conversationId,
            selectedRepoFullName: selectedRepo?.fullName,
            selectedRepoOwner: selectedRepo?.owner,
            selectedRepoName: selectedRepo?.name,
            activeCreationId: activeCreation?.id,
            activeCreationName: activeCreation?.name,
            activeCreationUrl: activeCreation?.url
        )

        // Inject cached displays and products if available for current location
        if cachedLocationId == session.selectedLocation?.id {
            context.displays = cachedDisplays.isEmpty ? nil : cachedDisplays
            context.inStockProducts = cachedProducts.isEmpty ? nil : cachedProducts
        }

        return context
    }

    // MARK: - Chat Actions

    /// Send a message - simple version that works on current workspace
    func sendMessage() {
        let ws = workspace  // Capture reference to current workspace

        guard !ws.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !ws.pendingAttachments.isEmpty else { return }
        guard let context = buildSessionContext() else {
            ws.error = "Not signed in"
            return
        }

        // Get user's typed message (what they'll see in chat)
        let displayMessage = ws.inputText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Build full message for AI - prepend dev mode context if active
        let userMessage: String
        if let devContext = ws.devModeContext {
            userMessage = "[DEV MODE CONTEXT]\n\(devContext)\n[END DEV MODE CONTEXT]\n\n\(displayMessage)"
        } else {
            userMessage = displayMessage
        }
        let attachments = ws.pendingAttachments

        // Clear input
        ws.inputText = ""
        ws.pendingAttachments = []

        // Add user message (display version only - no dev context in UI)
        ws.messages.append(ChatMessage(role: .user, content: displayMessage, attachments: attachments))

        // Add placeholder for assistant response
        let assistantMessage = ChatMessage(role: .assistant, content: "", isStreaming: true)
        ws.messages.append(assistantMessage)

        // Set loading state
        ws.isLoading = true
        ws.isStreaming = true
        ws.streamingTokenCount = 0
        ws.streamingStartTime = Date()
        ws.error = nil

        // Start background agent tracking
        let backgroundService = BackgroundAgentService.shared
        let taskId = backgroundService.startTask(
            conversationId: ws.conversationId ?? UUID(),
            storeId: context.storeId,
            initialAction: String(displayMessage.prefix(50)) + (displayMessage.count > 50 ? "..." : "")
        )

        // Start streaming task with background execution support
        ws.streamTask = Task {
            // Request extended background execution time from iOS
            // This allows the AI to continue running when app is backgrounded
            var bgTaskId: UIBackgroundTaskIdentifier = .invalid
            bgTaskId = await UIApplication.shared.beginBackgroundTask(withName: "LisaAIStreaming") {
                // Expiration handler - iOS is forcing us to stop
                Log.agent.warning("Background task expired - AI streaming will pause")
                if bgTaskId != .invalid {
                    UIApplication.shared.endBackgroundTask(bgTaskId)
                    bgTaskId = .invalid
                }
            }

            defer {
                // End background task when streaming completes
                if bgTaskId != .invalid {
                    UIApplication.shared.endBackgroundTask(bgTaskId)
                }
            }

            // Ensure conversation exists
            if ws.conversationId == nil {
                ws.conversationId = await self.ensureConversation(for: ws)
            }

            // Save user message to DB (display version, not dev context)
            if let convId = ws.conversationId {
                Task.detached { [weak self] in
                    await self?.saveMessage(role: "user", content: displayMessage, toConversation: convId)
                }
            }

            // Stream response to AI (with dev context injected)
            await self.streamResponse(
                userMessage: userMessage,
                attachments: attachments,
                context: context,
                messageId: assistantMessage.id,
                backgroundTaskId: taskId,
                in: ws
            )
        }
    }

    // MARK: - Attachment Management

    /// Add an image attachment with optional caption and upload to storage for email use
    /// - Parameters:
    ///   - image: The image to attach
    ///   - caption: iOS Photos caption (user-defined name) - AI will see this as the image's name
    func addImageAttachment(_ image: UIImage, caption: String? = nil) {
        guard let attachment = ChatAttachment.fromImage(image, caption: caption) else { return }

        // Add to workspace's pending attachments
        workspace.pendingAttachments.append(attachment)
        Log.agent.info("Added image attachment: \(attachment.fileName)\(caption != nil ? " (caption: \(caption!))" : "")")

        // Upload to storage in background to get public URL
        let ws = workspace
        Task {
            if let publicUrl = await uploadAttachmentToStorage(attachment) {
                await MainActor.run {
                    if let index = ws.pendingAttachments.firstIndex(where: { $0.id == attachment.id }) {
                        ws.pendingAttachments[index].publicUrl = publicUrl
                        Log.agent.info("Image uploaded to storage: \(publicUrl)")
                    }
                }
            }
        }
    }

    /// Upload attachment to Supabase storage and return public URL
    private func uploadAttachmentToStorage(_ attachment: ChatAttachment) async -> String? {
        guard let storeId = SessionObserver.shared.storeId else {
            Log.agent.warning("Cannot upload attachment - no store ID")
            return nil
        }

        do {
            let client = await supabaseAsync()
            let fileName = "chat-attachments/\(storeId.uuidString)/\(attachment.id.uuidString).\(attachment.type == .image ? "jpg" : "pdf")"

            try await client.storage
                .from("product-images")
                .upload(
                    path: fileName,
                    file: attachment.data,
                    options: FileOptions(contentType: attachment.mimeType)
                )

            let publicUrl = try client.storage
                .from("product-images")
                .getPublicURL(path: fileName)

            return publicUrl.absoluteString
        } catch {
            Log.agent.error("Failed to upload attachment: \(error.localizedDescription)")
            return nil
        }
    }

    /// Add a PDF attachment
    func addPDFAttachment(data: Data, fileName: String) {
        let attachment = ChatAttachment.fromPDF(data, fileName: fileName)
        workspace.pendingAttachments.append(attachment)
        Log.agent.info("Added PDF attachment: \(fileName), extracted \(attachment.extractedText?.count ?? 0) chars")
    }

    /// Add attachment from file URL
    func addAttachment(from url: URL) async {
        do {
            guard url.startAccessingSecurityScopedResource() else {
                Log.agent.error("Cannot access file: \(url.lastPathComponent)")
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            let data = try Data(contentsOf: url)
            let fileName = url.lastPathComponent
            let ext = url.pathExtension.lowercased()

            await MainActor.run {
                if ext == "pdf" {
                    addPDFAttachment(data: data, fileName: fileName)
                } else if ["jpg", "jpeg", "png", "heic", "webp"].contains(ext) {
                    if let image = UIImage(data: data) {
                        addImageAttachment(image)
                    }
                } else {
                    Log.agent.warning("Unsupported file type: \(ext)")
                }
            }
        } catch {
            Log.agent.error("Failed to load file: \(error.localizedDescription)")
        }
    }

    /// Remove a pending attachment
    func removeAttachment(_ attachment: ChatAttachment) {
        workspace.pendingAttachments.removeAll { $0.id == attachment.id }
    }

    /// Update caption for a specific attachment
    func updateAttachmentCaption(_ attachment: ChatAttachment, caption: String) {
        if let index = workspace.pendingAttachments.firstIndex(where: { $0.id == attachment.id }) {
            workspace.pendingAttachments[index].caption = caption.isEmpty ? nil : caption

            // Also update filename to match caption
            if !caption.isEmpty {
                let sanitized = caption
                    .replacingOccurrences(of: "/", with: "-")
                    .replacingOccurrences(of: ":", with: "-")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                workspace.pendingAttachments[index] = ChatAttachment(
                    id: workspace.pendingAttachments[index].id,
                    type: workspace.pendingAttachments[index].type,
                    data: workspace.pendingAttachments[index].data,
                    fileName: "\(sanitized).jpg",
                    mimeType: workspace.pendingAttachments[index].mimeType,
                    thumbnail: workspace.pendingAttachments[index].thumbnail,
                    extractedText: workspace.pendingAttachments[index].extractedText,
                    publicUrl: workspace.pendingAttachments[index].publicUrl,
                    caption: caption
                )
            }
        }
    }

    /// Set caption for ALL pending attachments (bulk naming)
    func setAllAttachmentCaptions(_ caption: String) {
        guard !caption.isEmpty else { return }
        for i in workspace.pendingAttachments.indices {
            let suffix = workspace.pendingAttachments.count > 1 ? " \(i + 1)" : ""
            updateAttachmentCaption(workspace.pendingAttachments[i], caption: "\(caption)\(suffix)")
        }
    }

    /// Clear all pending attachments
    func clearAttachments() {
        workspace.pendingAttachments = []
    }

    /// Ensure we have a conversation ID, creating one if needed
    private func ensureConversation(for ws: WorkspaceState) async -> UUID? {
        let session = SessionObserver.shared
        guard let storeId = session.storeId,
              let userId = session.userId else {
            Log.agent.warning("Cannot create conversation - no session")
            return nil
        }

        do {
            let client = await supabaseAsync()

            let response: UUID = try await client
                .rpc("get_or_create_lisa_conversation", params: [
                    "p_store_id": storeId.uuidString,
                    "p_user_id": userId.uuidString
                ])
                .execute()
                .value

            Log.agent.info("Ensured conversation: \(response.uuidString) in workspace: \(ws.displayName)")
            return response

        } catch {
            Log.agent.error("Failed to ensure conversation: \(error.localizedDescription)")
            return nil
        }
    }

    /// Cancel streaming in current workspace
    func cancelStream() {
        workspace.cancelStream()
    }

    func clearChat() {
        // Archive current conversation and start new one
        Task {
            if let convId = workspace.conversationId {
                await archiveConversation(convId)
            }
            await startNewConversation()
        }
    }

    /// Archive a conversation
    private func archiveConversation(_ conversationId: UUID) async {
        do {
            let client = await supabaseAsync()
            let _: Bool = try await client
                .rpc("archive_lisa_conversation", params: [
                    "p_conversation_id": conversationId.uuidString
                ])
                .execute()
                .value
        } catch {
            Log.agent.error("Failed to archive conversation: \(error.localizedDescription)")
        }
    }

    /// Save a message to the database
    /// Takes explicit conversation ID to avoid race conditions when switching workspaces
    /// Returns the database message ID for feedback tracking
    @discardableResult
    private func saveMessage(role: String, content: String, toConversation conversationId: UUID, localMessageId: UUID? = nil) async -> UUID? {
        Log.agent.info("Saving \(role) message to conversation \(conversationId.uuidString)")

        do {
            let client = await supabaseAsync()
            let messageId: UUID = try await client
                .rpc("save_lisa_message", params: [
                    "p_conversation_id": conversationId.uuidString,
                    "p_role": role,
                    "p_content": content
                ])
                .execute()
                .value
            Log.agent.info("Saved message with ID: \(messageId.uuidString)")

            // Update local message with database ID for feedback tracking
            if let localId = localMessageId {
                await MainActor.run {
                    if let index = workspace.messages.firstIndex(where: { $0.id == localId }) {
                        workspace.messages[index].databaseId = messageId
                    }
                }
            }

            return messageId
        } catch {
            Log.agent.error("Failed to save message: \(error)")
            return nil
        }
    }

    // MARK: - Feedback Submission

    /// Submit feedback (thumbs up/down) for a message
    func submitFeedback(for message: ChatMessage, rating: Int, correction: String? = nil) async {
        guard let dbId = message.databaseId else {
            Log.agent.warning("Cannot submit feedback: message has no database ID")
            return
        }

        Log.agent.info("Submitting feedback for message \(dbId): rating=\(rating)")

        do {
            let client = await supabaseAsync()
            var params: [String: String] = [
                "p_message_id": dbId.uuidString,
                "p_rating": String(rating),
                "p_feedback_type": correction != nil ? "correction" : "explicit"
            ]
            if let correction = correction {
                params["p_correction_text"] = correction
            }
            let _: UUID = try await client
                .rpc("submit_lisa_feedback", params: params)
                .execute()
                .value

            // Update local state
            if let index = workspace.messages.firstIndex(where: { $0.id == message.id }) {
                workspace.messages[index].feedbackRating = rating
            }

            Log.agent.info("Feedback submitted successfully")
        } catch {
            Log.agent.error("Failed to submit feedback: \(error)")
        }
    }

    /// Complete a conversation with an outcome
    func completeConversation(outcome: String, category: String = "unknown", effortScore: Int? = nil, notes: String? = nil) async {
        guard let convId = workspace.conversationId else {
            Log.agent.warning("Cannot complete conversation: no active conversation")
            return
        }

        Log.agent.info("Completing conversation \(convId) with outcome: \(outcome)")

        do {
            let client = await supabaseAsync()
            var params: [String: String] = [
                "p_conversation_id": convId.uuidString,
                "p_outcome": outcome,
                "p_task_category": category
            ]
            if let score = effortScore {
                params["p_user_effort_score"] = String(score)
            }
            if let notes = notes {
                params["p_outcome_notes"] = notes
            }
            let _: UUID = try await client
                .rpc("complete_lisa_conversation", params: params)
                .execute()
                .value

            Log.agent.info("Conversation completed successfully")
        } catch {
            Log.agent.error("Failed to complete conversation: \(error)")
        }
    }

    // MARK: - Context Management (Claude Code-quality conversations)

    /// Conversation summary for long context preservation
    @Published private(set) var conversationSummary: String?
    private var summaryMessageCutoffId: UUID?

    /// Check if summarization is needed and trigger it
    private func checkAndTriggerSummarization() async {
        guard let conversationId = workspace.conversationId else { return }

        // Summarize when we have 30+ messages since last summary
        let wsMessages = workspace.messages
        let unsummarizedCount = wsMessages.count - (summaryMessageCutoffId != nil ?
            (wsMessages.firstIndex(where: { $0.id == summaryMessageCutoffId }) ?? 0) : 0)

        if unsummarizedCount >= 30 {
            await triggerSummarization(conversationId: conversationId)
        }
    }

    /// Trigger background summarization
    private func triggerSummarization(conversationId: UUID) async {
        guard let storeId = SessionObserver.shared.storeId else { return }

        Log.agent.info("Triggering conversation summarization...")

        do {
            guard let url = URL(string: "\(SupabaseConfig.baseURL)/functions/v1/conversation-manager") else { return }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(SupabaseConfig.serviceKey)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "store_id": storeId.uuidString.lowercased(),
                "conversation_id": conversationId.uuidString.lowercased(),
                "operation": "summarize"
            ])

            let (data, _) = try await URLSession.shared.data(for: request)

            struct SummarizeResponse: Decodable {
                let success: Bool
                let messages_summarized: Int?
            }

            let response = try JSONDecoder().decode(SummarizeResponse.self, from: data)
            if response.success, let count = response.messages_summarized, count > 0 {
                Log.agent.info("Summarized \(count) messages")
                // Reload optimized context
                await loadOptimizedContext(conversationId: conversationId)
            }
        } catch {
            Log.agent.error("Summarization failed: \(error.localizedDescription)")
        }
    }

    /// Load optimized context with summary
    private func loadOptimizedContext(conversationId: UUID) async {
        guard let storeId = SessionObserver.shared.storeId else { return }

        do {
            guard let url = URL(string: "\(SupabaseConfig.baseURL)/functions/v1/conversation-manager") else { return }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(SupabaseConfig.serviceKey)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "store_id": storeId.uuidString.lowercased(),
                "conversation_id": conversationId.uuidString.lowercased(),
                "operation": "get_context",
                "max_tokens": 100000,
                "recent_message_count": 50
            ])

            let (data, _) = try await URLSession.shared.data(for: request)

            struct ContextResponse: Decodable {
                let success: Bool
                let context: ContextData?

                struct ContextData: Decodable {
                    let summary: String?
                    let messages: [MessageData]
                    let total_messages: Int
                    let included_messages: Int
                }

                struct MessageData: Decodable {
                    let role: String
                    let content: String
                }
            }

            let response = try JSONDecoder().decode(ContextResponse.self, from: data)
            if let context = response.context {
                conversationSummary = context.summary
                Log.agent.info("Loaded context: \(context.included_messages)/\(context.total_messages) messages, has summary: \(context.summary != nil)")
            }
        } catch {
            Log.agent.error("Failed to load optimized context: \(error.localizedDescription)")
        }
    }

    /// Build optimized conversation history for Claude
    /// Uses summary for older messages + full recent messages
    private func buildOptimizedHistory(excludingMessageId: UUID) -> [ClaudeMessage] {
        return buildOptimizedHistory(from: workspace.messages, excludingMessageId: excludingMessageId)
    }

    /// Build optimized conversation history from a specific messages array
    /// Used when streaming to a workspace that may not be the current one
    private func buildOptimizedHistory(from wsMessages: [ChatMessage], excludingMessageId: UUID) -> [ClaudeMessage] {
        var history: [ClaudeMessage] = []

        // If we have a summary, add it as context
        if let summary = conversationSummary, !summary.isEmpty {
            history.append(ClaudeMessage(
                role: .user,
                content: "[CONVERSATION SUMMARY - Previous messages have been summarized to preserve context]\n\n\(summary)\n\n[END SUMMARY - Recent messages follow]"
            ))
            history.append(ClaudeMessage(
                role: .assistant,
                content: "I understand. I have the context from our previous conversation. Let's continue."
            ))
        }

        // Add recent messages (last 50 or all if less)
        let recentMessages = wsMessages
            .filter { $0.id != excludingMessageId && !$0.isStreaming && !$0.content.isEmpty }
            .suffix(50)

        for msg in recentMessages {
            history.append(ClaudeMessage(
                role: msg.role == .user ? .user : .assistant,
                content: msg.content
            ))
        }

        return history
    }

    // MARK: - Streaming

    /// Stream response directly to the workspace - simple and isolated
    private func streamResponse(userMessage: String, attachments: [ChatAttachment] = [], context: SessionContext, messageId: UUID, backgroundTaskId: UUID? = nil, in ws: WorkspaceState) async {
        let backgroundService = BackgroundAgentService.shared
        var toolCallCount = 0

        // CRITICAL: Keep app alive while agent is running
        // 1. Disable screen sleep (foreground protection)
        // 2. Start background audio (background protection)
        UIApplication.shared.isIdleTimerDisabled = true
        BackgroundKeepAlive.shared.start()
        Log.agent.info("Agent keep-alive enabled - screen lock disabled, background audio started")

        // Ensure we clean up when done (in all exit paths)
        defer {
            UIApplication.shared.isIdleTimerDisabled = false
            BackgroundKeepAlive.shared.stop()
            Log.agent.info("Agent keep-alive disabled - agent finished")
        }

        do {
            // Build conversation history from workspace's messages
            let history = buildOptimizedHistory(from: ws.messages, excludingMessageId: messageId)

            Log.agent.info("Sending \(history.count) messages to Claude")

            let stream = await ClaudeClientSlim.shared.chat(
                message: userMessage,
                attachments: attachments,
                conversationHistory: history,
                context: context,
                modelOverride: selectedModel.rawValue
            )

            // Stream directly to workspace
            var chunkCount = 0
            for try await chunk in stream {
                guard !Task.isCancelled else {
                    Log.agent.info("Stream cancelled after \(chunkCount) chunks")
                    break
                }

                chunkCount += 1
                if chunkCount == 1 {
                    Log.agent.info("First chunk received (length: \(chunk.count))")
                }


                if let index = ws.messages.firstIndex(where: { $0.id == messageId }) {
                    ws.messages[index].content += chunk
                    ws.streamingTokenCount = ws.messages[index].content.count / 4

                    // CRITICAL: Force view update by changing store-level counter
                    // This is @Published on AIChatStore and changes every chunk
                    self.streamingUpdateCounter += 1

                    // Track tool calls for background progress
                    if chunk.contains("<action") {
                        toolCallCount += 1
                        if let taskId = backgroundTaskId {
                            // Extract action name from chunk if available
                            let actionName = extractActionName(from: chunk) ?? "working..."
                            backgroundService.updateTask(taskId: taskId, action: actionName, toolCallCount: toolCallCount)
                        }
                    }

                    // Auto-open creations when Lisa creates them
                    if chunk.contains("<creation-saved>") {
                        Log.agent.info("📦 Found creation-saved marker in chunk")
                        self.handleCreationSaved(chunk: chunk)
                    }

                    // Hot reload creations when Lisa edits them
                    if chunk.contains("<creation-edited>") {
                        Log.agent.info("🔥 Found creation-edited marker in chunk (length: \(chunk.count))")
                        self.handleCreationEdited(chunk: chunk)
                    }

                    // Debug: Log chunks that might be related to creation operations
                    if chunk.contains("creation") {
                        Log.agent.debug("📝 Chunk contains 'creation': \(chunk.prefix(100))...")
                    }
                }
            }

            // Done streaming
            Log.agent.info("Stream loop finished - received \(chunkCount) chunks total")
            if let index = ws.messages.firstIndex(where: { $0.id == messageId }) {
                ws.messages[index].isStreaming = false
                let finalContent = ws.messages[index].content
                Log.agent.info("Stream completed - content length: \(finalContent.count), chunks: \(chunkCount)")

                // Save to DB (detached so it won't be cancelled) and capture database ID for feedback
                if let convId = ws.conversationId {
                    let localId = messageId
                    Task.detached { [weak self] in
                        let savedId = await self?.saveMessage(role: "assistant", content: finalContent, toConversation: convId, localMessageId: localId)
                        Log.agent.info("Assistant message saved to DB: \(savedId?.uuidString ?? "failed")")
                    }
                }

                // Complete background task
                if let taskId = backgroundTaskId {
                    let summary = String(finalContent.prefix(100))
                    backgroundService.completeTask(taskId: taskId, summary: summary)
                }
            } else {
                Log.agent.warning("Stream completed but message \(messageId) not found in messages array!")
            }

        } catch {
            Log.agent.error("Stream error: \(error.localizedDescription)")

            // Apple HIG-compliant error handling:
            // - Be specific, not generic
            // - No patronizing language ("Oops!", "Sorry!")
            // - Provide actionable guidance
            let errorMessage = parseStreamError(error)

            ws.error = errorMessage.message

            if let index = ws.messages.firstIndex(where: { $0.id == messageId }) {
                ws.messages[index].isStreaming = false
                if ws.messages[index].content.isEmpty {
                    ws.messages[index].content = errorMessage.displayText
                }
            }

            // Fail background task
            if let taskId = backgroundTaskId {
                backgroundService.failTask(taskId: taskId, error: errorMessage.message)
            }
        }

        // Clean up
        ws.isLoading = false
        ws.isStreaming = false
        ws.streamingStartTime = nil
        ws.streamTask = nil
    }

    /// Extract action name from streaming chunk (e.g., "<action status="running">querying database")
    private func extractActionName(from chunk: String) -> String? {
        // Look for text after "<action status="running">"
        if let range = chunk.range(of: "<action status=\"running\">") {
            let afterAction = String(chunk[range.upperBound...])
            let actionName = afterAction.components(separatedBy: CharacterSet.newlines).first?.trimmingCharacters(in: .whitespaces)
            if let name = actionName, !name.isEmpty {
                return name
            }
        }
        return nil
    }

    // MARK: - Undo Support

    /// Get undoable actions (last 10, most recent first)
    var undoableActions: [TrackedAction] {
        Array(trackedActions.suffix(10).reversed())
    }

    /// Add a tracked action (called from ClaudeClient)
    func addTrackedAction(_ action: TrackedAction) {
        trackedActions.append(action)
        // Keep only last 20 actions
        if trackedActions.count > 20 {
            trackedActions.removeFirst(trackedActions.count - 20)
        }
    }

    /// Request undo - asks Lisa to reverse an action
    func requestUndo(_ action: TrackedAction) {
        // Remove from tracked actions
        trackedActions.removeAll { $0.id == action.id }

        // Ask Lisa to undo it
        workspace.inputText = "Please undo that last action: \(action.description). The SQL was: \(action.sql)"
        sendMessage()
    }

    // MARK: - UI Actions

    func showChat() {
        print("🔧 showChat() called")
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            isChatVisible = true
        }

        // Load conversation history when chat opens
        if !hasLoadedHistory {
            Task {
                await loadConversation()
            }
        }

        // Load location context (displays, products)
        print("🔧 showChat() - spawning context loading task")
        Task {
            await loadLocationContext()
        }
    }

    func hideChat() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            isChatVisible = false
            isChatInputFocused = false
        }
    }

    func toggleChat() {
        if isChatVisible {
            hideChat()
        } else {
            showChat()
        }
    }

    /// Reset state when user logs out
    func reset() {
        hasLoadedHistory = false
        conversations = []
        trackedActions = []

        // Clear location context cache
        invalidateLocationContext()

        // Cancel and clear all workspaces
        for ws in workspaces.values {
            ws.streamTask?.cancel()
        }
        workspaces.removeAll()

        // Create fresh general workspace
        let generalWorkspace = WorkspaceState(id: "general")
        workspaces["general"] = generalWorkspace
        workspace = generalWorkspace
    }

    // MARK: - Apple HIG-Compliant Error Handling

    /// Structured error message following Apple Human Interface Guidelines
    struct AIErrorMessage {
        let message: String      // Short message for error banner
        let displayText: String  // Longer message for chat display
        let isRetryable: Bool    // Whether user should try again
    }

    /// Parse stream errors into user-friendly messages
    /// Per Apple HIG: Be specific, not generic. No patronizing language.
    private func parseStreamError(_ error: Error) -> AIErrorMessage {
        let description = error.localizedDescription.lowercased()
        let nsError = error as NSError

        // Cancelled by user - not an error
        if description.contains("cancelled") || nsError.code == NSURLErrorCancelled {
            return AIErrorMessage(
                message: "Cancelled",
                displayText: "Request cancelled.",
                isRetryable: false
            )
        }

        // Network timeout
        if description.contains("timeout") || nsError.code == NSURLErrorTimedOut {
            return AIErrorMessage(
                message: "Request timed out",
                displayText: "The request took too long to complete. Check your connection and try again.",
                isRetryable: true
            )
        }

        // No network connection
        if description.contains("offline") || description.contains("internet") ||
           nsError.code == NSURLErrorNotConnectedToInternet {
            return AIErrorMessage(
                message: "No connection",
                displayText: "Unable to connect. Check your internet connection.",
                isRetryable: true
            )
        }

        // Network error (general)
        if description.contains("network") || nsError.domain == NSURLErrorDomain {
            return AIErrorMessage(
                message: "Connection issue",
                displayText: "Network request failed. Check your connection and try again.",
                isRetryable: true
            )
        }

        // Rate limiting
        if description.contains("rate limit") || description.contains("429") ||
           description.contains("too many") {
            return AIErrorMessage(
                message: "Too many requests",
                displayText: "Rate limit reached. Wait a moment before trying again.",
                isRetryable: true
            )
        }

        // Authentication error
        if description.contains("unauthorized") || description.contains("401") ||
           description.contains("authentication") {
            return AIErrorMessage(
                message: "Authentication required",
                displayText: "Your session may have expired. Sign in again.",
                isRetryable: false
            )
        }

        // Server error
        if description.contains("500") || description.contains("502") ||
           description.contains("503") || description.contains("server error") {
            return AIErrorMessage(
                message: "Service unavailable",
                displayText: "The AI service is temporarily unavailable. Try again in a moment.",
                isRetryable: true
            )
        }

        // Content policy / refusal
        if description.contains("refusal") || description.contains("policy") ||
           description.contains("content") && description.contains("blocked") {
            return AIErrorMessage(
                message: "Request not processed",
                displayText: "Unable to process this request. Try rephrasing.",
                isRetryable: false
            )
        }

        // Token limit exceeded
        if description.contains("token") || description.contains("context length") ||
           description.contains("too long") {
            return AIErrorMessage(
                message: "Message too long",
                displayText: "The conversation is too long. Start a new conversation or ask a shorter question.",
                isRetryable: false
            )
        }

        // Default - still specific about what happened
        return AIErrorMessage(
            message: "Request failed",
            displayText: "Unable to complete the request. Try again.",
            isRetryable: true
        )
    }

    // MARK: - Auto-Open Creations

    /// Handle creation_save tool result - auto-open the new creation window
    private func handleCreationSaved(chunk: String) {
        // Extract JSON from <creation-saved>{json}</creation-saved>
        guard let startRange = chunk.range(of: "<creation-saved>"),
              let endRange = chunk.range(of: "</creation-saved>") else {
            Log.agent.warning("Could not parse creation-saved marker")
            return
        }

        let jsonString = String(chunk[startRange.upperBound..<endRange.lowerBound])

        guard let jsonData = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            Log.agent.warning("Could not parse creation JSON: \(jsonString)")
            return
        }

        // Tool result format: { success: true, data: { creation_id, render_url, creation: { id, name, ... } } }
        let data = json["data"] as? [String: Any] ?? json  // Fall back to root if no data wrapper

        // Extract creation details - try multiple paths
        var creationId: String?
        var name: String?
        var deployedUrl: String?

        // Try to get from nested creation object first
        if let creation = data["creation"] as? [String: Any] {
            creationId = creation["id"] as? String
            name = creation["name"] as? String
            deployedUrl = creation["render_url"] as? String
        }

        // Fall back to top-level data fields
        if creationId == nil {
            creationId = data["creation_id"] as? String ?? data["id"] as? String
        }
        if name == nil {
            name = data["name"] as? String
        }
        if deployedUrl == nil {
            deployedUrl = data["render_url"] as? String ?? data["deployed_url"] as? String
        }

        guard let finalCreationId = creationId else {
            Log.agent.warning("Missing creation id in: \(json)")
            return
        }

        let finalName = name ?? "New Creation"

        Log.agent.info("Auto-opening creation: \(finalName) (id: \(finalCreationId))")

        // Open the creation window via StageManager
        StageManagerStore.shared.addCreation(
            id: finalCreationId,
            name: finalName,
            url: deployedUrl,
            reactCode: nil  // Code not included in tool result
        )
    }

    // MARK: - Hot Reload Creations

    /// Handle creation_edit tool result - hot reload the creation window
    private func handleCreationEdited(chunk: String) {
        Log.agent.info("🔥 Hot reload triggered - checking for creation-edited marker")

        // Extract JSON from <creation-edited>{json}</creation-edited>
        guard let startRange = chunk.range(of: "<creation-edited>"),
              let endRange = chunk.range(of: "</creation-edited>") else {
            Log.agent.warning("🔥 Could not find creation-edited markers in chunk")
            return
        }

        let jsonString = String(chunk[startRange.upperBound..<endRange.lowerBound])
        Log.agent.info("🔥 Extracted JSON string (length: \(jsonString.count)): \(jsonString.prefix(200))...")

        guard let jsonData = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            Log.agent.warning("🔥 Could not parse creation-edited JSON: \(jsonString.prefix(500))")
            return
        }

        Log.agent.info("🔥 Parsed JSON keys: \(json.keys.joined(separator: ", "))")

        // Extract creation_id from result - check top level first (tools-gateway format)
        var creationId: String?

        // Try top-level creation_id first (this is the tools-gateway format)
        if let cid = json["creation_id"] as? String {
            creationId = cid
            Log.agent.info("🔥 Found creation_id at top level: \(cid)")
        }

        // Try nested creation object
        if creationId == nil, let creation = json["creation"] as? [String: Any] {
            creationId = creation["id"] as? String
            Log.agent.info("🔥 Found creation.id: \(creationId ?? "nil")")
        }

        // Try data wrapper (old format)
        if creationId == nil, let data = json["data"] as? [String: Any] {
            creationId = data["creation_id"] as? String ?? data["id"] as? String
            Log.agent.info("🔥 Found in data wrapper: \(creationId ?? "nil")")
        }

        guard let finalCreationId = creationId else {
            Log.agent.warning("🔥 Missing creation id for hot reload. JSON: \(json)")
            return
        }

        Log.agent.info("🔥 Hot reloading creation: \(finalCreationId)")

        // Check all possible locations for react_code
        var reactCode: String? = nil

        // Try top level
        if let code = json["react_code"] as? String, !code.isEmpty {
            reactCode = code
            Log.agent.info("🔥 Found react_code at top level (length: \(code.count))")
        }
        // Try in creation object
        else if let creation = json["creation"] as? [String: Any],
                let code = creation["react_code"] as? String, !code.isEmpty {
            reactCode = code
            Log.agent.info("🔥 Found react_code in creation object (length: \(code.count))")
        }
        // Try in data wrapper
        else if let data = json["data"] as? [String: Any],
                let code = data["react_code"] as? String, !code.isEmpty {
            reactCode = code
            Log.agent.info("🔥 Found react_code in data wrapper (length: \(code.count))")
        }

        if let reactCode = reactCode {
            let name = (json["creation"] as? [String: Any])?["name"] as? String
            StageManagerStore.shared.updateCreation(creationId: finalCreationId, newReactCode: reactCode, newName: name)
            Log.agent.info("🔥 Hot reload complete - updated creation in Stage Manager")
        } else {
            // Fallback - fetch from database (old path)
            Log.agent.info("🔥 No react_code in response (keys: \(json.keys.joined(separator: ", "))), fetching from database...")
            Task {
                await StageManagerStore.shared.refreshCreationFromDatabase(creationId: finalCreationId)
            }
        }
    }
}
