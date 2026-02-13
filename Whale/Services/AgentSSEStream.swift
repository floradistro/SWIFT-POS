//
//  AgentSSEStream.swift
//  Whale
//
//  SSE streaming client for agent-chat Edge Function.
//  Ported from WhaleChat — same SSE protocol, adapted to Whale POS SupabaseConfig.
//  Each ChatStore owns one instance for independent concurrent execution.
//

import Foundation
import Supabase
import Auth
import os.log

// MARK: - Request Payload (Encodable — avoids __SwiftValue JSON crash)

private struct AgentChatPayload: Encodable {
    let message: String
    let agentId: String
    var storeId: String?
    var conversationId: String?
    var source: String? = "whale_pos"
    var userId: String?
    var userEmail: String?
    var conversationHistory: [HistoryMessage]?

    struct HistoryMessage: Encodable {
        let role: String
        let content: String
    }
}

@MainActor
final class AgentSSEStream {
    private(set) var isRunning = false
    private(set) var currentTool: String?
    private var currentTask: Task<Void, Never>?
    private var pendingUsage: TokenUsage?
    private var accumulatedText: String = ""
    private var receivedDone = false

    func run(
        prompt: String,
        storeId: UUID?,
        agentId: UUID,
        conversationId: UUID? = nil,
        userId: UUID? = nil,
        userEmail: String? = nil,
        conversationHistory: [(role: String, content: String)]? = nil,
        onText: @escaping @MainActor (String) -> Void,
        onToolStart: @escaping @MainActor (String) -> Void,
        onToolResult: @escaping @MainActor (String, Bool, String?) -> Void,
        onDone: @escaping @MainActor (String, TokenUsage) -> Void,
        onError: @escaping @MainActor (String) -> Void
    ) {
        guard !isRunning else { onError("Already running"); return }
        isRunning = true
        currentTool = nil
        pendingUsage = nil
        accumulatedText = ""
        receivedDone = false

        currentTask = Task { [weak self] in
            await self?.executeQuery(
                prompt: prompt, storeId: storeId, agentId: agentId,
                conversationId: conversationId, userId: userId, userEmail: userEmail,
                conversationHistory: conversationHistory,
                onText: onText, onToolStart: onToolStart, onToolResult: onToolResult,
                onDone: onDone, onError: onError
            )
        }
    }

    func abort() {
        currentTask?.cancel()
        currentTask = nil
        isRunning = false
        currentTool = nil
    }

    // MARK: - SSE Query Execution

    private func executeQuery(
        prompt: String,
        storeId: UUID?,
        agentId: UUID,
        conversationId: UUID?,
        userId: UUID?,
        userEmail: String?,
        conversationHistory: [(role: String, content: String)]?,
        onText: @escaping @MainActor (String) -> Void,
        onToolStart: @escaping @MainActor (String) -> Void,
        onToolResult: @escaping @MainActor (String, Bool, String?) -> Void,
        onDone: @escaping @MainActor (String, TokenUsage) -> Void,
        onError: @escaping @MainActor (String) -> Void
    ) async {
        let url = SupabaseConfig.url.appendingPathComponent("functions/v1/agent-chat")

        var payload = AgentChatPayload(
            message: prompt,
            agentId: agentId.uuidString,
            storeId: storeId?.uuidString,
            conversationId: conversationId?.uuidString,
            userId: userId?.uuidString,
            userEmail: userEmail
        )
        if let history = conversationHistory, !history.isEmpty {
            payload.conversationHistory = history.map {
                AgentChatPayload.HistoryMessage(role: $0.role, content: $0.content)
            }
        }

        guard let bodyData = try? JSONEncoder().encode(payload) else {
            onError("Failed to encode request")
            finishRun()
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 3600  // 1 hour — long tool chains can run 10-30+ min
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Use user's session token if available, fall back to service key
        var authToken = SupabaseConfig.serviceKey
        if let client = try? await SupabaseClientWrapper.shared.client(),
           let session = try? await client.auth.session {
            authToken = session.accessToken
        }
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = bodyData

        Log.network.debug("AgentSSEStream: Starting request to \(url.absoluteString)")

        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                var errorBody = ""
                var lineCount = 0
                for try await line in bytes.lines {
                    errorBody += line
                    lineCount += 1
                    if lineCount > 10 || errorBody.count > 1000 { break }
                }
                onError("Server error \(httpResponse.statusCode): \(errorBody.prefix(500))")
                finishRun()
                return
            }

            var lineCount = 0
            for try await line in bytes.lines {
                if Task.isCancelled {
                    Log.network.debug("AgentSSEStream: Cancelled after \(lineCount) lines")
                    break
                }
                lineCount += 1

                if line.hasPrefix("data: ") {
                    let data = String(line.dropFirst(6))
                    processSSEEvent(
                        data, onText: onText, onToolStart: onToolStart,
                        onToolResult: onToolResult, onDone: onDone, onError: onError
                    )
                }
            }

            Log.network.debug("AgentSSEStream: Stream ended after \(lineCount) lines, receivedDone=\(self.receivedDone)")

            // If stream ended without explicit "done" event but we have text, call onDone
            if !receivedDone && !accumulatedText.isEmpty {
                Log.network.warning("AgentSSEStream: Stream ended without 'done' event, calling onDone with accumulated text")
                let usage = pendingUsage ?? TokenUsage(inputTokens: 0, outputTokens: 0, totalCost: 0)
                onDone("", usage)
            }
        } catch is CancellationError {
            Log.network.debug("AgentSSEStream: Cancelled")
            // Aborted — not an error
        } catch {
            Log.network.error("AgentSSEStream: Connection error: \(error.localizedDescription)")
            onError("Connection error: \(error.localizedDescription)")
        }

        finishRun()
    }

    private func processSSEEvent(
        _ data: String,
        onText: @escaping @MainActor (String) -> Void,
        onToolStart: @escaping @MainActor (String) -> Void,
        onToolResult: @escaping @MainActor (String, Bool, String?) -> Void,
        onDone: @escaping @MainActor (String, TokenUsage) -> Void,
        onError: @escaping @MainActor (String) -> Void
    ) {
        guard let jsonData = data.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let type = json["type"] as? String else { return }

        switch type {
        case "text":
            if let text = json["text"] as? String {
                accumulatedText += text
                onText(text)
            }

        case "tool_start":
            if let tool = json["name"] as? String ?? json["tool"] as? String {
                currentTool = tool
                Log.network.debug("AgentSSEStream: Tool started: \(tool)")
                onToolStart(tool)
            }

        case "tool_result":
            if let tool = json["name"] as? String ?? json["tool"] as? String {
                let success = json["success"] as? Bool ?? true  // Default to true if not specified
                let errorMsg = json["error"] as? String
                Log.network.debug("AgentSSEStream: Tool result: \(tool) success=\(success)")
                onToolResult(tool, success, errorMsg)
            }
            currentTool = nil

        case "usage":
            if let u = json["usage"] as? [String: Any] {
                pendingUsage = TokenUsage(
                    inputTokens: u["input_tokens"] as? Int ?? u["inputTokens"] as? Int ?? 0,
                    outputTokens: u["output_tokens"] as? Int ?? u["outputTokens"] as? Int ?? 0,
                    totalCost: u["totalCost"] as? Double ?? 0
                )
            }

        case "done":
            receivedDone = true
            let convId = json["conversationId"] as? String ?? ""
            var usage = pendingUsage ?? TokenUsage(inputTokens: 0, outputTokens: 0, totalCost: 0)
            if let u = json["usage"] as? [String: Any] {
                usage = TokenUsage(
                    inputTokens: u["input_tokens"] as? Int ?? u["inputTokens"] as? Int ?? 0,
                    outputTokens: u["output_tokens"] as? Int ?? u["outputTokens"] as? Int ?? 0,
                    totalCost: u["totalCost"] as? Double ?? 0
                )
            }
            pendingUsage = nil
            Log.network.debug("AgentSSEStream: Received 'done' event, accumulated \(self.accumulatedText.count) chars")
            onDone(convId, usage)

        case "error":
            let errorMsg = json["error"] as? String ?? json["message"] as? String ?? "Unknown error"
            Log.network.error("AgentSSEStream: Received error event: \(errorMsg)")
            onError(errorMsg)

        default:
            Log.network.debug("AgentSSEStream: Unknown event type: \(type)")
        }
    }

    private func finishRun() {
        isRunning = false
        currentTool = nil
        currentTask = nil
        accumulatedText = ""
        receivedDone = false
    }
}
