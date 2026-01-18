//
//  TerminalWebSocket.swift
//  Whale
//
//  WebSocket-based interactive terminal for full PTY support.
//  Supports multiple concurrent sessions for mini terminal panels.
//

import Foundation
import Combine

// MARK: - Terminal WebSocket Session (Per-Terminal)

@MainActor
final class TerminalWebSocketSession: NSObject, ObservableObject {
    let id: UUID

    // Connection state
    @Published var isConnected = false
    @Published var isConnecting = false
    @Published var connectionError: String?

    // Terminal output buffer
    @Published var outputBuffer: String = ""

    // WebSocket
    private var webSocket: URLSessionWebSocketTask?
    private var session: URLSession?
    private var pingTimer: Timer?

    // Server config
    private var serverURL: String { "\(BuildServerConfig.wsURL)/terminal/ws" }
    private var serverSecret: String { BuildServerConfig.secret }

    init(id: UUID) {
        self.id = id
        super.init()
    }

    deinit {
        pingTimer?.invalidate()
        webSocket?.cancel(with: .normalClosure, reason: nil)
    }

    // MARK: - Connection

    func connect() {
        guard !isConnected && !isConnecting else { return }

        isConnecting = true
        connectionError = nil
        outputBuffer = "Connecting...\n"

        guard let url = URL(string: serverURL) else {
            connectionError = "Invalid server URL"
            isConnecting = false
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(serverSecret)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        session = URLSession(configuration: config, delegate: self, delegateQueue: .main)

        webSocket = session?.webSocketTask(with: request)
        webSocket?.resume()

        receiveMessage()

        pingTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sendPing()
            }
        }
    }

    func disconnect() {
        pingTimer?.invalidate()
        pingTimer = nil

        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        session = nil

        isConnected = false
        isConnecting = false
        hasReceivedFirstOutput = false
        inTUIMode = false
    }

    // MARK: - Send Input

    func send(_ text: String) {
        guard isConnected, let ws = webSocket else { return }

        let message = URLSessionWebSocketTask.Message.string(text)
        ws.send(message) { [weak self] error in
            if let error = error {
                Task { @MainActor in
                    self?.connectionError = error.localizedDescription
                }
            }
        }
    }

    /// Send text with carriage return (for TUI apps like Claude Code)
    func sendLine(_ text: String) {
        send(text + "\r")
    }

    func sendControlC() { send("\u{03}") }
    func sendControlD() { send("\u{04}") }
    func sendControlZ() { send("\u{1A}") }
    func sendTab() { send("\t") }
    func sendArrowUp() { send("\u{1B}[A") }
    func sendArrowDown() { send("\u{1B}[B") }
    func sendArrowRight() { send("\u{1B}[C") }
    func sendArrowLeft() { send("\u{1B}[D") }

    // MARK: - Receive

    private func receiveMessage() {
        webSocket?.receive { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success(let message):
                    switch message {
                    case .string(let text):
                        self?.handleOutput(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            self?.handleOutput(text)
                        }
                    @unknown default:
                        break
                    }
                    self?.receiveMessage()

                case .failure(let error):
                    self?.connectionError = error.localizedDescription
                    self?.isConnected = false
                    self?.isConnecting = false
                }
            }
        }
    }

    private var hasReceivedFirstOutput = false
    private var inTUIMode = false

    private func handleOutput(_ text: String) {
        // Clear "Connecting..." on first real output
        if !hasReceivedFirstOutput {
            hasReceivedFirstOutput = true
            outputBuffer = ""
        }

        // Detect TUI mode entry (Claude Code uses these)
        if text.contains("\u{1B}[?2004h") || text.contains("\u{1B}[?1004h") {
            inTUIMode = true
        }

        // Detect TUI mode exit
        if text.contains("\u{1B}[?2004l") || text.contains("\u{1B}[?1004l") ||
           text.contains("\u{1B}[?1049l") {
            inTUIMode = false
        }

        // Claude Code uses \x1B[2K\x1B[1A pattern to redraw lines
        // When we see this pattern, it's updating in place - replace the buffer
        let isInPlaceRedraw = text.contains("\u{1B}[2K\u{1B}[1A") ||
                               text.contains("\u{1B}[2J") ||
                               text.contains("\u{1B}[H\u{1B}[")

        if inTUIMode && isInPlaceRedraw {
            // TUI is redrawing - we need to process the escape sequences
            // For now, just keep the latest frame
            outputBuffer = processANSIForDisplay(text)
        } else if inTUIMode {
            // TUI mode but not a redraw - might be partial update, append
            outputBuffer += processANSIForDisplay(text)
        } else {
            // Normal shell mode - append
            outputBuffer += text
        }

        // Limit buffer size
        if outputBuffer.count > 100000 {
            outputBuffer = String(outputBuffer.suffix(80000))
        }
    }

    /// Strip cursor movement sequences but keep colors for display
    private func processANSIForDisplay(_ text: String) -> String {
        var result = text

        // Strip cursor movement and screen control, keep SGR (color) codes
        let stripPatterns = [
            "\u{1B}\\[[0-9]*A",           // Cursor up
            "\u{1B}\\[[0-9]*B",           // Cursor down
            "\u{1B}\\[[0-9]*C",           // Cursor forward
            "\u{1B}\\[[0-9]*D",           // Cursor back
            "\u{1B}\\[[0-9]*G",           // Cursor to column
            "\u{1B}\\[[0-9;]*H",          // Cursor position
            "\u{1B}\\[[0-9]*J",           // Clear screen
            "\u{1B}\\[[0-9]*K",           // Clear line
            "\u{1B}\\[\\?[0-9;]*[hl]",    // Private modes
            "\u{1B}\\[[0-9;]*[su]",       // Save/restore cursor
            "\u{1B}\\][^\u{07}]*\u{07}",  // OSC sequences
            "\u{1B}\\[\\?2026[hl]",       // Synchronized update
        ]

        for pattern in stripPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: ""
                )
            }
        }

        // Normalize line endings
        result = result.replacingOccurrences(of: "\r\n", with: "\n")
        result = result.replacingOccurrences(of: "\r", with: "\n")

        return result
    }

    private func sendPing() {
        webSocket?.sendPing { [weak self] error in
            if let error = error {
                Task { @MainActor in
                    self?.connectionError = "Ping failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func clearBuffer() {
        outputBuffer = ""
    }
}

// MARK: - URLSessionWebSocketDelegate

extension TerminalWebSocketSession: URLSessionWebSocketDelegate {
    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        Task { @MainActor in
            self.isConnected = true
            self.isConnecting = false
            self.connectionError = nil
            // Don't clear buffer - preserve any initial output from the PTY server
            // The welcome message comes after connection opens
        }
    }

    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        Task { @MainActor in
            self.isConnected = false
            self.isConnecting = false
            if let reason = reason, let text = String(data: reason, encoding: .utf8) {
                self.connectionError = text
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        Task { @MainActor in
            self.isConnected = false
            self.isConnecting = false
            if let error = error {
                self.connectionError = error.localizedDescription
            }
        }
    }
}

// MARK: - Terminal WebSocket Manager (Manages Multiple Sessions)

@MainActor
final class TerminalWebSocketManager: ObservableObject {
    static let shared = TerminalWebSocketManager()

    @Published private(set) var sessions: [UUID: TerminalWebSocketSession] = [:]

    private init() {}

    func getOrCreateSession(for id: UUID) -> TerminalWebSocketSession {
        if let existing = sessions[id] {
            return existing
        }

        let session = TerminalWebSocketSession(id: id)
        sessions[id] = session
        return session
    }

    func removeSession(_ id: UUID) {
        if let session = sessions[id] {
            session.disconnect()
            sessions.removeValue(forKey: id)
        }
    }

    func disconnectAll() {
        for session in sessions.values {
            session.disconnect()
        }
        sessions.removeAll()
    }
}

// MARK: - Legacy Shared Instance (For Full Screen Terminal)

@MainActor
final class TerminalWebSocket: NSObject, ObservableObject {
    static let shared = TerminalWebSocket()

    @Published var isConnected = false
    @Published var isConnecting = false
    @Published var connectionError: String?
    @Published var outputBuffer: String = ""

    private var webSocket: URLSessionWebSocketTask?
    private var session: URLSession?
    private var pingTimer: Timer?

    private var serverURL: String { "\(BuildServerConfig.wsURL)/terminal/ws" }
    private var serverSecret: String { BuildServerConfig.secret }

    private override init() {
        super.init()
    }

    func connect() {
        guard !isConnected && !isConnecting else { return }

        isConnecting = true
        connectionError = nil

        guard let url = URL(string: serverURL) else {
            connectionError = "Invalid server URL"
            isConnecting = false
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(serverSecret)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        session = URLSession(configuration: config, delegate: self, delegateQueue: .main)

        webSocket = session?.webSocketTask(with: request)
        webSocket?.resume()

        receiveMessage()

        pingTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.sendPing()
        }
    }

    func disconnect() {
        pingTimer?.invalidate()
        pingTimer = nil
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        session = nil
        isConnected = false
        isConnecting = false
    }

    func send(_ text: String) {
        guard isConnected else { return }
        let message = URLSessionWebSocketTask.Message.string(text)
        webSocket?.send(message) { [weak self] error in
            if let error = error {
                Task { @MainActor in
                    self?.connectionError = error.localizedDescription
                }
            }
        }
    }

    func sendLine(_ text: String) { send(text + "\r") }
    func sendControlC() { send("\u{03}") }
    func sendControlD() { send("\u{04}") }
    func sendControlZ() { send("\u{1A}") }
    func sendTab() { send("\t") }
    func sendArrowUp() { send("\u{1B}[A") }
    func sendArrowDown() { send("\u{1B}[B") }
    func sendArrowRight() { send("\u{1B}[C") }
    func sendArrowLeft() { send("\u{1B}[D") }

    private func receiveMessage() {
        webSocket?.receive { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success(let message):
                    switch message {
                    case .string(let text):
                        self?.handleOutput(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            self?.handleOutput(text)
                        }
                    @unknown default:
                        break
                    }
                    self?.receiveMessage()

                case .failure(let error):
                    self?.connectionError = error.localizedDescription
                    self?.isConnected = false
                    self?.isConnecting = false
                }
            }
        }
    }

    private func handleOutput(_ text: String) {
        outputBuffer += text
        if outputBuffer.count > 50000 {
            outputBuffer = String(outputBuffer.suffix(40000))
        }
    }

    private func sendPing() {
        webSocket?.sendPing { [weak self] error in
            if let error = error {
                Task { @MainActor in
                    self?.connectionError = "Ping failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func clearBuffer() {
        outputBuffer = ""
    }

    func resize(cols: Int, rows: Int) {
        send("{\"type\":\"resize\",\"cols\":\(cols),\"rows\":\(rows)}")
    }
}

extension TerminalWebSocket: URLSessionWebSocketDelegate {
    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        Task { @MainActor in
            self.isConnected = true
            self.isConnecting = false
            self.connectionError = nil
            self.outputBuffer = "Connected to terminal\n"
        }
    }

    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        Task { @MainActor in
            self.isConnected = false
            self.isConnecting = false
            if let reason = reason, let text = String(data: reason, encoding: .utf8) {
                self.connectionError = text
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        Task { @MainActor in
            self.isConnected = false
            self.isConnecting = false
            if let error = error {
                self.connectionError = error.localizedDescription
            }
        }
    }
}
