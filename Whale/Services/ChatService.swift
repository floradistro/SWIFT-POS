//
//  ChatService.swift
//  Whale
//
//  Stateless service for lisa_conversations and lisa_messages.
//  Follows the same patterns as OrderService / ProductService.
//

import Foundation
import Supabase
import os.log

enum ChatService {

    // MARK: - Conversations

    static func fetchConversations(storeId: UUID) async throws -> [ChatConversation] {
        let client = await supabaseAsync()
        let response = try await client
            .from("lisa_conversations")
            .select()
            .eq("store_id", value: storeId.uuidString)
            .eq("status", value: "active")
            .order("updated_at", ascending: false)
            .execute()

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode([ChatConversation].self, from: response.data)
        } catch {
            Log.network.error("ChatService: Failed to decode conversations: \(error)")
            return []
        }
    }

    // MARK: - Messages

    static func fetchMessages(conversationId: UUID, limit: Int = 50) async throws -> [ChatMessage] {
        let client = await supabaseAsync()
        let response = try await client
            .from("lisa_messages")
            .select()
            .eq("conversation_id", value: conversationId.uuidString)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let messages: [ChatMessage]
        do {
            messages = try decoder.decode([ChatMessage].self, from: response.data)
        } catch {
            Log.network.error("ChatService: Failed to decode messages: \(error)")
            messages = []
        }
        return messages.reversed() // Oldest first for display
    }

    // MARK: - Send Message

    static func sendMessage(
        conversationId: UUID,
        content: String,
        senderId: UUID,
        isAiInvocation: Bool = false
    ) async throws -> ChatMessage {
        let client = await supabaseAsync()

        struct Payload: Encodable {
            let conversation_id: String
            let role: String
            let content: String
            let sender_id: String
            let is_ai_invocation: Bool
        }

        let response = try await client
            .from("lisa_messages")
            .insert(Payload(
                conversation_id: conversationId.uuidString,
                role: "user",
                content: content,
                sender_id: senderId.uuidString,
                is_ai_invocation: isAiInvocation
            ))
            .select()
            .single()
            .execute()

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ChatMessage.self, from: response.data)
    }

    // MARK: - Save Assistant Response

    static func saveAssistantMessage(
        conversationId: UUID,
        content: String
    ) async throws -> ChatMessage {
        let client = await supabaseAsync()

        struct Payload: Encodable {
            let conversation_id: String
            let role: String
            let content: String
            let is_ai_invocation: Bool
        }

        let response = try await client
            .from("lisa_messages")
            .insert(Payload(
                conversation_id: conversationId.uuidString,
                role: "assistant",
                content: content,
                is_ai_invocation: false
            ))
            .select()
            .single()
            .execute()

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ChatMessage.self, from: response.data)
    }

    // MARK: - AI Agents (from ai_agent_config)

    static func fetchAgents(storeId: UUID) async throws -> [AIAgent] {
        let client = await supabaseAsync()
        // Include store-specific agents AND global agents (store_id is null)
        let response = try await client
            .from("ai_agent_config")
            .select("id, store_id, name, description, icon, accent_color, model, max_tokens, is_active, enabled_tools")
            .eq("is_active", value: true)
            .or("store_id.eq.\(storeId.uuidString),store_id.is.null")
            .execute()

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode([AIAgent].self, from: response.data)
        } catch {
            Log.network.error("ChatService: Failed to decode agents: \(error)")
            return []
        }
    }

    // MARK: - Task Completion

    static func completeTask(
        messageId: UUID,
        conversationId: UUID,
        storeId: UUID?,
        completedBy: UUID?,
        completedByName: String?,
        content: String,
        role: String,
        senderName: String?
    ) async throws -> ChatTask {
        let client = await supabaseAsync()

        struct Payload: Encodable {
            let message_id: String
            let conversation_id: String
            let store_id: String?
            let completed_by: String?
            let completed_by_name: String?
            let original_content: String
            let original_role: String
            let sender_name: String?
        }

        let response = try await client
            .from("chat_completed_tasks")
            .insert(Payload(
                message_id: messageId.uuidString,
                conversation_id: conversationId.uuidString,
                store_id: storeId?.uuidString,
                completed_by: completedBy?.uuidString,
                completed_by_name: completedByName,
                original_content: content,
                original_role: role,
                sender_name: senderName
            ))
            .select()
            .single()
            .execute()

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ChatTask.self, from: response.data)
    }

    static func fetchCompletedTasks(conversationId: UUID) async throws -> [ChatTask] {
        let client = await supabaseAsync()
        let response = try await client
            .from("chat_completed_tasks")
            .select()
            .eq("conversation_id", value: conversationId.uuidString)
            .order("created_at", ascending: false)
            .execute()

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode([ChatTask].self, from: response.data)
        } catch {
            Log.network.error("ChatService: Failed to decode completed tasks: \(error)")
            return []
        }
    }

    static func restoreTask(_ task: ChatTask) async throws {
        let client = await supabaseAsync()
        try await client
            .from("chat_completed_tasks")
            .delete()
            .eq("id", value: task.id.uuidString)
            .execute()
    }

    // MARK: - Sender Resolution

    static func fetchSenders(authUserIds: Set<UUID>) async throws -> [UUID: ChatSender] {
        guard !authUserIds.isEmpty else { return [:] }
        let client = await supabaseAsync()
        let ids = authUserIds.map { $0.uuidString }

        let response = try await client
            .from("users")
            .select("auth_user_id, first_name, last_name, email")
            .in("auth_user_id", values: ids)
            .execute()

        let senders: [ChatSender]
        do {
            senders = try JSONDecoder().decode([ChatSender].self, from: response.data)
        } catch {
            Log.network.error("ChatService: Failed to decode senders: \(error)")
            senders = []
        }
        var result: [UUID: ChatSender] = [:]
        for s in senders { result[s.id] = s }
        return result
    }
}
