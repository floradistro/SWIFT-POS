//
//  ClaudeClientSlim.swift
//  Whale
//
//  Thin client that streams from agentic-loop Edge Function.
//  All orchestration, tool execution, and context management happens server-side.
//
//  This replaces the 4000-line ClaudeClient.swift with ~150 lines.
//
//  Architecture:
//  - Client sends message + history + attachments to Edge Function
//  - Edge Function runs the agentic loop (Claude + tools)
//  - Client receives SSE stream and renders events
//  - NO business logic in client
//

import Foundation
import os.log

// MARK: - Slim Claude Client

actor ClaudeClientSlim {
    static let shared = ClaudeClientSlim()

    private var agenticLoopURL: String { "\(SupabaseConfig.baseURL)/functions/v1/agentic-loop" }

    // MARK: - Public API

    /// Stream a chat response from the agentic loop
    /// All orchestration happens server-side - this just streams the result
    func chat(
        message: String,
        attachments: [ChatAttachment] = [],
        conversationHistory: [ClaudeMessage] = [],
        context: SessionContext,
        modelOverride: String? = nil
    ) -> AsyncThrowingStream<String, Error> {
        // Capture values needed for the stream before creating the AsyncThrowingStream
        let agenticURL = self.agenticLoopURL

        return AsyncThrowingStream { continuation in
            // Use Task.detached to avoid actor isolation issues with URLSession streaming
            Task.detached {
                do {
                    try await Self.streamFromAgenticLoopStatic(
                        agenticLoopURL: agenticURL,
                        message: message,
                        attachments: attachments,
                        conversationHistory: conversationHistory,
                        context: context,
                        modelOverride: modelOverride,
                        continuation: continuation
                    )
                } catch {
                    Log.agent.error("Chat stream error: \(error.localizedDescription)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Non-streaming version for simple queries
    func query(message: String, context: SessionContext) async throws -> String {
        var fullResponse = ""
        for try await chunk in chat(message: message, context: context) {
            fullResponse += chunk
        }
        return fullResponse
    }

    // MARK: - Private Implementation

    /// Static version to avoid actor isolation issues with URLSession streaming
    private static func streamFromAgenticLoopStatic(
        agenticLoopURL: String,
        message: String,
        attachments: [ChatAttachment],
        conversationHistory: [ClaudeMessage],
        context: SessionContext,
        modelOverride: String?,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        // Build request body with full session context
        var body: [String: Any] = [
            "store_id": context.storeId.uuidString,
            "message": message
        ]

        // Add full session context for personalization
        if let storeName = context.storeName {
            body["store_name"] = storeName
        }
        if let userId = context.userId {
            body["user_id"] = userId.uuidString
        }
        if let userEmail = context.userEmail {
            body["user_email"] = userEmail
        }
        if let locationId = context.locationId {
            body["location_id"] = locationId.uuidString
        }
        if let locationName = context.locationName {
            body["location_name"] = locationName
        }
        if let registerId = context.registerId {
            body["register_id"] = registerId.uuidString
        }
        if let registerName = context.registerName {
            body["register_name"] = registerName
        }
        if let conversationId = context.conversationId {
            body["conversation_id"] = conversationId.uuidString
        }

        // Add active creation context (when user has a creation window open)
        if let creationId = context.activeCreationId {
            body["active_creation_id"] = creationId
            Log.agent.info("ClaudeClientSlim: Sending active_creation_id=\(creationId)")
        }
        if let creationName = context.activeCreationName {
            body["active_creation_name"] = creationName
            Log.agent.info("ClaudeClientSlim: Sending active_creation_name=\(creationName)")
        }
        if let creationUrl = context.activeCreationUrl {
            body["active_creation_url"] = creationUrl
        }

        // Add conversation history
        if !conversationHistory.isEmpty {
            body["history"] = conversationHistory.map { msg -> [String: Any] in
                return ["role": msg.role.rawValue, "content": msg.content]
            }
        }

        // Add attachments
        if !attachments.isEmpty {
            body["attachments"] = attachments.map { att -> [String: Any] in
                var attDict: [String: Any] = [
                    "type": att.type.rawValue,
                    "file_name": att.fileName
                ]
                attDict["base64_data"] = att.base64Data
                attDict["mime_type"] = att.mimeType
                if let text = att.extractedText {
                    attDict["extracted_text"] = text
                }
                if let url = att.publicUrl {
                    attDict["public_url"] = url
                }
                return attDict
            }
        }

        // Add optional model override
        if let model = modelOverride {
            body["model_override"] = model
        }

        // Create request
        guard let url = URL(string: agenticLoopURL) else {
            throw ClaudeError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 300  // 5 minute timeout for long operations
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let bodySize = request.httpBody?.count ?? 0
        Log.agent.info("Streaming from agentic-loop... (body: \(bodySize) bytes)")

        // Stream the response
        Log.agent.info("Awaiting agentic-loop response...")
        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            Log.agent.error("Invalid response type from agentic-loop")
            throw ClaudeError.invalidResponse
        }

        Log.agent.info("Agentic-loop responded with status: \(httpResponse.statusCode)")

        if httpResponse.statusCode != 200 {
            Log.agent.error("Agentic-loop error: HTTP \(httpResponse.statusCode)")
            throw ClaudeError.apiError("HTTP \(httpResponse.statusCode)")
        }

        // Parse SSE stream
        var buffer = ""
        var byteCount = 0

        for try await byte in bytes {
            byteCount += 1
            if byteCount == 1 {
                Log.agent.info("First byte received from agentic-loop stream")
            }
            buffer.append(Character(UnicodeScalar(byte)))

            // Check for complete SSE event (ends with double newline)
            // Also check for \r\n\r\n in case server uses Windows line endings
            let delimiter = buffer.contains("\r\n\r\n") ? "\r\n\r\n" : "\n\n"
            while let range = buffer.range(of: delimiter) {
                var eventText = String(buffer[..<range.lowerBound])
                buffer = String(buffer[range.upperBound...])

                // Normalize line endings (remove \r that might interfere with parsing)
                eventText = eventText.replacingOccurrences(of: "\r", with: "")

                // DEBUG: Log every raw SSE event
                if eventText.contains("code_") {
                    Log.agent.info("🔍 RAW SSE EVENT (byte \(byteCount)): \(eventText.prefix(200))")
                }

                // Parse SSE event
                guard let event = parseSSEEvent(eventText) else {
                    if eventText.contains("code_") {
                        Log.agent.error("❌ FAILED TO PARSE code event: \(eventText.prefix(300))")
                    }
                    continue
                }

                // DEBUG: Log all parsed event types
                if event.type.contains("code") {
                    Log.agent.info("✅ PARSED event type=\(event.type), content=\(event.content?.prefix(50) ?? "nil")")
                }

                switch event.type {
                    case "text":
                        // Stream text content to UI
                        if let content = event.content {
                            continuation.yield(content)
                        }

                    case "tool_start":
                        // Just log - don't emit to avoid duplicate action blocks
                        // The tool_result will show the completed action
                        if let toolName = event.toolName {
                            Log.agent.debug("Tool starting: \(toolName)")
                        }

                    case "code_start":
                        // Start streaming code block
                        if let toolName = event.toolName {
                            Log.agent.info("💻 Code streaming started for: \(toolName)")
                            continuation.yield("\n<streaming-code tool=\"\(toolName)\">\n")
                        }

                    case "code_delta":
                        // Stream code content chunk
                        if let content = event.content, !content.isEmpty {
                            Log.agent.debug("📥 code_delta received: \(content.count) chars")
                            continuation.yield(content)
                        } else {
                            Log.agent.warning("📥 code_delta EMPTY!")
                        }

                    case "code_end":
                        // End streaming code block
                        if let toolName = event.toolName {
                            Log.agent.info("💻 Code streaming ended for: \(toolName)")
                            continuation.yield("\n</streaming-code>\n")
                        }

                    case "tool_result":
                        // Emit completed action block (raw tool name - ActionCardView formats it)
                        if let toolName = event.toolName {
                            Log.agent.info("🔧 Tool result received: \(toolName), hasResult: \(event.result != nil)")
                            continuation.yield("\n<action status=\"success\">\n\(toolName)\n</action>\n")

                            // Special handling for creation_save - emit creation data for auto-opening
                            if toolName == "creation_save", let result = event.result {
                                Log.agent.info("📦 Emitting creation-saved marker (result length: \(result.count))")
                                continuation.yield("\n<creation-saved>\(result)</creation-saved>\n")
                            }

                            // Special handling for creation_edit - emit for hot reload
                            if toolName == "creation_edit", let result = event.result {
                                Log.agent.info("🔥 Emitting creation-edited marker (result length: \(result.count))")
                                continuation.yield("\n<creation-edited>\(result)</creation-edited>\n")
                            } else if toolName == "creation_edit" {
                                Log.agent.warning("🔥 creation_edit received but NO RESULT - hot reload will fail!")
                            }
                        }

                    case "images":
                        // Emit images block for direct rendering (bypasses markdown parsing issues)
                        if let images = event.images, !images.isEmpty {
                            if let jsonData = try? JSONSerialization.data(withJSONObject: images),
                               let jsonString = String(data: jsonData, encoding: .utf8) {
                                continuation.yield("\n<images-block>\(jsonString)</images-block>\n")
                            }
                        }

                    case "tool_error":
                        if let error = event.error {
                            continuation.yield("\n**Tool Error:** \(error)\n")
                        }

                    case "thinking":
                        // Extended thinking - stream thinking content
                        if let content = event.content {
                            continuation.yield(content)
                        }

                    case "error":
                        if let error = event.error {
                            throw ClaudeError.apiError(error)
                        }

                    case "done":
                        Log.agent.info("Agentic loop completed in \(event.elapsedMs ?? 0)ms")
                        // Stream is complete - finish immediately
                        Log.agent.info("Stream finished - received \(byteCount) bytes total")
                        continuation.finish()
                        return  // Exit the function immediately

                    default:
                        break
                    }
                }
            }

        Log.agent.info("Stream finished naturally - received \(byteCount) bytes total")
        continuation.finish()
    }

    // MARK: - SSE Parsing

    private struct SSEEvent {
        let type: String
        var content: String?
        var toolName: String?
        var toolId: String?
        var result: String?
        var error: String?
        var elapsedMs: Int?
        var images: [[String: String]]?
    }

    private static func parseSSEEvent(_ text: String) -> SSEEvent? {
        // SSE format: "data: {json}\n"
        guard text.hasPrefix("data: ") else { return nil }

        let jsonString = String(text.dropFirst(6))
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            Log.agent.warning("Failed to parse SSE: \(text.prefix(200))")
            return nil
        }

        var event = SSEEvent(type: type)
        event.content = json["content"] as? String
        event.toolName = json["tool_name"] as? String
        event.toolId = json["tool_id"] as? String
        event.result = json["result"] as? String
        event.error = json["error"] as? String
        event.elapsedMs = json["elapsed_ms"] as? Int
        event.images = json["images"] as? [[String: String]]


        return event
    }
}

// MARK: - Errors
// ClaudeError is defined in AgentModels.swift
