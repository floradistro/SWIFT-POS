//
//  StageManagerStore.swift
//  Whale
//
//  State for Stage Manager - iPad-style window switching.
//

import SwiftUI
import UIKit
import Combine
import Supabase

@MainActor
final class StageManagerStore: ObservableObject {
    static let shared = StageManagerStore()

    @Published var isVisible = false
    @Published var windows: [StageWindow] = []
    @Published var activeWindowId: UUID?
    @Published var refreshTrigger: [UUID: UUID] = [:]  // windowId -> trigger UUID

    // Screen lock state - keeps screen on and disables pinch gestures
    @Published var isScreenLocked = false {
        didSet {
            UIApplication.shared.isIdleTimerDisabled = isScreenLocked
        }
    }

    // Realtime subscriptions for creation hot reload
    private var creationChannels: [String: RealtimeChannelV2] = [:]  // creationId -> channel
    private var realtimeTasks: [String: Task<Void, Never>] = [:]  // creationId -> listening task

    struct StageWindow: Identifiable, Equatable, Hashable {
        let id: UUID
        let type: WindowType
        var name: String
        var snapshot: UIImage?
        var conversationId: UUID?  // Each window has its own chat conversation

        enum WindowType: Equatable, Hashable {
            case app(sessionId: UUID)
            case creation(id: String, url: String?, reactCode: String?)
        }

        // Custom hash - exclude snapshot (UIImage isn't Hashable)
        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
            hasher.combine(type)
            hasher.combine(name)
        }

        // Custom equality - exclude snapshot to ensure reactCode changes are detected
        static func == (lhs: StageWindow, rhs: StageWindow) -> Bool {
            lhs.id == rhs.id && lhs.type == rhs.type && lhs.name == rhs.name
        }

        var icon: String {
            switch type {
            case .app: return "app.fill"
            case .creation: return "tv"
            }
        }

        var sessionId: UUID? {
            if case .app(let sid) = type { return sid }
            return nil
        }

        /// Creation ID for creation windows
        var creationId: String? {
            if case .creation(let id, _, _) = type { return id }
            return nil
        }
    }

    private init() {
        // Launcher architecture: start empty, user adds windows via "+" button
        windows = []
        activeWindowId = nil
    }

    var activeWindow: StageWindow? {
        windows.first { $0.id == activeWindowId }
    }

    func show() {
        guard !isVisible else { return }
        Haptics.medium()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
            isVisible = true
        }
    }

    func hide() {
        guard isVisible else { return }
        Haptics.light()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
            isVisible = false
        }
    }

    func select(_ window: StageWindow, file: String = #file, line: Int = #line, function: String = #function) {
        let caller = "\(URL(fileURLWithPath: file).lastPathComponent):\(line) \(function)"
        print("🪟 StageManager: select() called from \(caller)")
        print("🪟 StageManager: Selecting window - \(window.name), id: \(window.id)")
        activeWindowId = window.id
        print("🪟 StageManager: Active window set, hiding stage manager")
        hide()
    }

    func addApp(name: String? = nil, location: Location? = nil, register: Register? = nil) {
        let sessionNumber = windows.filter { if case .app = $0.type { return true }; return false }.count + 1
        let locationName = location?.name ?? "POS"
        let windowName = name ?? "\(locationName) \(sessionNumber)"
        let newSessionId = UUID()

        // Pre-create the session with the specified location
        if let location = location {
            _ = POSWindowSessionManager.shared.createSession(
                sessionId: newSessionId,
                location: location,
                register: register
            )
        }

        let window = StageWindow(id: UUID(), type: .app(sessionId: newSessionId), name: windowName, snapshot: nil)
        windows.append(window)
        print("🪟 StageManager: Added new POS session - \(windowName), sessionId: \(newSessionId), location: \(location?.name ?? "nil"), total windows: \(windows.count)")

        // Select the new window and go fullscreen immediately
        activeWindowId = window.id
        isVisible = false  // Hide Stage Manager to show fullscreen window
    }

    func addCreation(id: String, name: String, url: String?, reactCode: String?) {
        print("🪟 StageManager: Adding creation - id: \(id), name: \(name), url: \(url ?? "nil"), hasReactCode: \(reactCode != nil)")

        // Check if already open
        if let existing = windows.first(where: {
            if case .creation(let cid, _, _) = $0.type { return cid == id }
            return false
        }) {
            print("🪟 StageManager: Creation already open, selecting existing")
            select(existing)
            return
        }

        let window = StageWindow(id: UUID(), type: .creation(id: id, url: url, reactCode: reactCode), name: name, snapshot: nil)
        windows.append(window)
        print("🪟 StageManager: Created window, total windows: \(windows.count)")

        // Subscribe to realtime updates for hot reload
        subscribeToCreation(creationId: id)

        // Set as active but keep Stage Manager open so user can see it
        activeWindowId = window.id
        print("🪟 StageManager: Set active window, keeping Stage Manager visible")

        // Show Stage Manager if not already visible
        if !isVisible {
            show()
        }
    }

    /// Select a window and close Stage Manager
    func selectAndClose(_ window: StageWindow) {
        print("🪟 StageManager: Selecting and closing - \(window.name)")
        activeWindowId = window.id
        hide()
    }

    func close(_ window: StageWindow) {
        // In launcher architecture, all windows can be closed
        switch window.type {
        case .app(let sessionId):
            // Clean up POS session
            POSWindowSessionManager.shared.removeSession(sessionId)
        case .creation(let creationId, _, _):
            // Clean up realtime subscription
            unsubscribeFromCreation(creationId: creationId)
        }

        windows.removeAll { $0.id == window.id }
        if activeWindowId == window.id {
            activeWindowId = windows.first?.id
        }
    }

    func updateSnapshot(for windowId: UUID, image: UIImage) {
        if let idx = windows.firstIndex(where: { $0.id == windowId }) {
            windows[idx].snapshot = image
        }
    }

    /// Link a conversation to a window
    func setConversation(for windowId: UUID, conversationId: UUID) {
        if let idx = windows.firstIndex(where: { $0.id == windowId }) {
            windows[idx].conversationId = conversationId
            print("🪟 StageManager: Linked conversation \(conversationId) to window \(windows[idx].name)")
        }
    }

    /// Get conversation ID for a window
    func conversationId(for windowId: UUID) -> UUID? {
        windows.first { $0.id == windowId }?.conversationId
    }

    /// Get window by conversation ID (for chat indicators)
    func window(forConversation conversationId: UUID) -> StageWindow? {
        windows.first { $0.conversationId == conversationId }
    }

    func refresh(_ window: StageWindow) {
        Haptics.light()
        refreshTrigger[window.id] = UUID()
        print("🪟 StageManager: Refreshing window - \(window.name)")
    }

    /// Update a creation's react code and trigger hot reload
    func updateCreation(creationId: String, newReactCode: String, newName: String? = nil) {
        guard let index = windows.firstIndex(where: {
            if case .creation(let cid, _, _) = $0.type { return cid == creationId }
            return false
        }) else {
            print("🪟 StageManager: Creation not found for hot reload - \(creationId)")
            return
        }

        let window = windows[index]
        if case .creation(_, let url, _) = window.type {
            // Create updated window with new react code
            var updatedWindow = StageWindow(
                id: window.id,
                type: .creation(id: creationId, url: url, reactCode: newReactCode),
                name: newName ?? window.name,
                snapshot: nil
            )
            windows[index] = updatedWindow
            print("🪟 StageManager: Hot reload - updated react code for \(window.name)")

            // Trigger refresh
            refreshTrigger[window.id] = UUID()
        }
    }

    /// Refresh a creation by fetching latest code from database
    func refreshCreationFromDatabase(creationId: String) async {
        print("🪟 StageManager: Fetching latest code for creation \(creationId)")

        do {
            let client = await supabaseAsync()

            struct CreationData: Decodable {
                let id: UUID
                let name: String
                let react_code: String?
                let deployed_url: String?
            }

            let creation: CreationData = try await client
                .from("creations")
                .select("id, name, react_code, deployed_url")
                .eq("id", value: creationId)
                .single()
                .execute()
                .value

            if let reactCode = creation.react_code {
                await MainActor.run {
                    updateCreation(creationId: creationId, newReactCode: reactCode, newName: creation.name)
                }
                print("🪟 StageManager: Hot reload complete for \(creation.name)")
            }
        } catch {
            print("🪟 StageManager: Failed to fetch creation for hot reload - \(error.localizedDescription)")
        }
    }

    // MARK: - Supabase Realtime for Hot Reload

    /// Subscribe to realtime updates for a creation (called when creation window is opened)
    func subscribeToCreation(creationId: String) {
        // Skip if already subscribed
        guard creationChannels[creationId] == nil else {
            print("🔴 StageManager: Already subscribed to creation \(creationId)")
            return
        }

        print("🔴 StageManager: Subscribing to realtime for creation \(creationId)")

        // Create channel in background task
        Task.detached { [weak self] in
            guard let self else { return }

            let client = await supabaseAsync()
            let channelName = "creation-\(creationId)"
            let channel = client.channel(channelName)

            // Listen for postgres changes on this specific creation
            let changes = channel.postgresChange(
                AnyAction.self,
                schema: "public",
                table: "creations",
                filter: "id=eq.\(creationId)"
            )

            // Store channel reference
            await MainActor.run { [weak self] in
                self?.creationChannels[creationId] = channel
            }

            // Subscribe to channel
            await channel.subscribe()
            print("🔴 StageManager: Subscribed to realtime for creation \(creationId)")

            // Start listening task
            let listeningTask = Task { [weak self] in
                for await change in changes {
                    guard let self else { break }
                    print("🔥 StageManager: Realtime update for creation \(creationId)")

                    // Handle different change types
                    var record: [String: AnyJSON]? = nil
                    switch change {
                    case .update(let action):
                        record = action.record
                    case .insert(let action):
                        record = action.record
                    default:
                        break
                    }

                    // Extract new react_code from the change
                    if let record = record,
                       let reactCodeJSON = record["react_code"],
                       case .string(let reactCode) = reactCodeJSON,
                       !reactCode.isEmpty {
                        var name: String? = nil
                        if let nameJSON = record["name"], case .string(let n) = nameJSON {
                            name = n
                        }
                        print("🔥 StageManager: Got new react_code (\(reactCode.count) chars)")

                        await MainActor.run { [weak self] in
                            self?.updateCreation(creationId: creationId, newReactCode: reactCode, newName: name)
                        }
                    } else {
                        // Fallback: fetch from database if we couldn't extract from payload
                        print("🔥 StageManager: Falling back to database fetch")
                        await self.refreshCreationFromDatabase(creationId: creationId)
                    }
                }
            }

            await MainActor.run { [weak self] in
                self?.realtimeTasks[creationId] = listeningTask
            }
        }
    }

    /// Unsubscribe from realtime updates for a creation (called when creation window is closed)
    func unsubscribeFromCreation(creationId: String) {
        print("🔴 StageManager: Unsubscribing from creation \(creationId)")

        // Cancel listening task
        realtimeTasks[creationId]?.cancel()
        realtimeTasks.removeValue(forKey: creationId)

        // Unsubscribe and remove channel
        if let channel = creationChannels.removeValue(forKey: creationId) {
            Task.detached {
                await channel.unsubscribe()
                let client = await supabaseAsync()
                await client.removeChannel(channel)
                print("🔴 StageManager: Unsubscribed from creation \(creationId)")
            }
        }
    }
}
