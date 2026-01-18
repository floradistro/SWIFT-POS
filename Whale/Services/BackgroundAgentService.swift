//
//  BackgroundAgentService.swift
//  Whale
//
//  Enables Lisa AI to continue running when app is backgrounded.
//  Uses URLSession background configuration + local notifications for progress.
//

import Foundation
import BackgroundTasks
import UserNotifications
import Combine
import os.log

// MARK: - Agent Task State

struct AgentTaskState: Codable {
    let taskId: UUID
    let conversationId: UUID
    let storeId: UUID
    let startTime: Date
    var lastUpdate: Date
    var status: AgentStatus
    var currentAction: String?
    var toolCallCount: Int
    var error: String?

    enum AgentStatus: String, Codable {
        case running
        case paused
        case completed
        case failed
    }
}

// MARK: - Background Agent Service

@MainActor
final class BackgroundAgentService: ObservableObject {
    static let shared = BackgroundAgentService()

    // Background task identifiers
    static let backgroundTaskId = "com.whale.lisa.agent"
    static let backgroundRefreshId = "com.whale.lisa.refresh"

    // Published state
    @Published var activeTask: AgentTaskState?
    @Published var isRunningInBackground = false

    // Background URL session for network requests
    private lazy var backgroundSession: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "com.whale.lisa.background")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.shouldUseExtendedBackgroundIdleMode = true
        return URLSession(configuration: config, delegate: nil, delegateQueue: nil)
    }()

    // Persistence
    private let stateKey = "BackgroundAgentState"

    private init() {
        // Load any persisted state
        loadPersistedState()

        // Request notification permission
        requestNotificationPermission()
    }

    // MARK: - Notification Permission

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                Log.agent.info("Notification permission granted for background agent updates")
            }
        }
    }

    // MARK: - Task Management

    /// Start tracking a background agent task
    func startTask(conversationId: UUID, storeId: UUID, initialAction: String) -> UUID {
        let taskId = UUID()

        // Humanize the action for display
        let humanizedAction = humanizeAction(initialAction)

        let state = AgentTaskState(
            taskId: taskId,
            conversationId: conversationId,
            storeId: storeId,
            startTime: Date(),
            lastUpdate: Date(),
            status: .running,
            currentAction: humanizedAction,
            toolCallCount: 0,
            error: nil
        )

        activeTask = state
        persistState()

        // Show initial notification
        showProgressNotification(title: "Lisa is working", body: humanizedAction)

        Log.agent.info("Started background agent task: \(taskId)")
        return taskId
    }

    /// Update task progress
    func updateTask(taskId: UUID, action: String, toolCallCount: Int) {
        guard var task = activeTask, task.taskId == taskId else { return }

        // Humanize the action for display
        let humanizedAction = humanizeAction(action)

        task.lastUpdate = Date()
        task.currentAction = humanizedAction
        task.toolCallCount = toolCallCount
        activeTask = task
        persistState()

        // Update notification every 3 tool calls to avoid spam
        if toolCallCount % 3 == 0 {
            showProgressNotification(
                title: "Lisa is working",
                body: humanizedAction
            )
        }
    }

    /// Transform technical action names into polished, user-friendly messages
    private func humanizeAction(_ action: String) -> String {
        let lower = action.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip any remaining XML-style tags
        var cleaned = lower.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        // Common technical terms -> friendly messages
        let mappings: [(pattern: String, replacement: String)] = [
            ("querying database", "Looking up information..."),
            ("executing sql", "Retrieving data..."),
            ("query.*products", "Checking product catalog..."),
            ("query.*inventory", "Checking inventory levels..."),
            ("query.*sales", "Analyzing sales data..."),
            ("query.*customers", "Looking up customer info..."),
            ("query.*orders", "Checking orders..."),
            ("insert.*", "Saving changes..."),
            ("update.*", "Updating records..."),
            ("delete.*", "Removing data..."),
            ("generating.*report", "Creating your report..."),
            ("generating.*menu", "Building menu display..."),
            ("creating.*", "Setting things up..."),
            ("fetching.*", "Getting information..."),
            ("calculating.*", "Crunching the numbers..."),
            ("processing.*", "Working on it..."),
            ("searching.*", "Searching..."),
            ("analyzing.*", "Analyzing..."),
            ("status.*success", "Done"),
            ("status.*error", "Encountered an issue"),
            ("working", "Working on it..."),
        ]

        for (pattern, replacement) in mappings {
            if cleaned.range(of: pattern, options: .regularExpression) != nil {
                return replacement
            }
        }

        // If it's already a reasonable message (starts with capital, ends properly), use as-is
        if action.first?.isUppercase == true && (action.hasSuffix("...") || action.hasSuffix(".")) {
            return action
        }

        // Default: capitalize first letter and add ellipsis if needed
        let formatted = action.prefix(1).uppercased() + action.dropFirst()
        return formatted.hasSuffix("...") || formatted.hasSuffix(".") ? formatted : "\(formatted)..."
    }

    /// Complete task successfully
    func completeTask(taskId: UUID, summary: String) {
        guard var task = activeTask, task.taskId == taskId else { return }

        task.lastUpdate = Date()
        task.status = .completed
        task.currentAction = summary
        activeTask = task
        persistState()

        // Show completion notification
        showCompletionNotification(title: "Lisa finished", body: summary)

        // Clear task after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.activeTask = nil
            self?.clearPersistedState()
        }

        Log.agent.info("Completed background agent task: \(taskId)")
    }

    /// Fail task with error
    func failTask(taskId: UUID, error: String) {
        guard var task = activeTask, task.taskId == taskId else { return }

        task.lastUpdate = Date()
        task.status = .failed
        task.error = error
        activeTask = task
        persistState()

        // Show error notification
        showErrorNotification(title: "Lisa encountered an issue", body: error)

        Log.agent.info("Failed background agent task: \(taskId) - \(error)")
    }

    /// Pause task when entering background
    func pauseTask(taskId: UUID) {
        guard var task = activeTask, task.taskId == taskId else { return }

        task.lastUpdate = Date()
        task.status = .paused
        activeTask = task
        isRunningInBackground = true
        persistState()

        // Schedule background task to resume
        scheduleBackgroundRefresh()

        Log.agent.info("Paused background agent task: \(taskId)")
    }

    /// Resume task when returning to foreground
    func resumeTask(taskId: UUID) -> AgentTaskState? {
        guard var task = activeTask, task.taskId == taskId else { return nil }

        task.lastUpdate = Date()
        task.status = .running
        activeTask = task
        isRunningInBackground = false
        persistState()

        Log.agent.info("Resumed background agent task: \(taskId)")
        return task
    }

    // MARK: - Background Task Scheduling

    /// Register background task handlers (call from AppDelegate)
    static func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: backgroundTaskId, using: nil) { task in
            Task { @MainActor in
                BackgroundAgentService.shared.handleBackgroundTask(task as! BGProcessingTask)
            }
        }

        BGTaskScheduler.shared.register(forTaskWithIdentifier: backgroundRefreshId, using: nil) { task in
            Task { @MainActor in
                BackgroundAgentService.shared.handleBackgroundRefresh(task as! BGAppRefreshTask)
            }
        }
    }

    /// Schedule a background refresh
    private func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundRefreshId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 minutes

        do {
            try BGTaskScheduler.shared.submit(request)
            Log.agent.info("Scheduled background refresh task")
        } catch {
            Log.agent.error("Failed to schedule background refresh: \(error)")
        }
    }

    /// Handle background processing task
    private func handleBackgroundTask(_ task: BGProcessingTask) {
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        // Resume agent work if there's a paused task
        if let agentTask = activeTask, agentTask.status == .paused {
            showProgressNotification(
                title: "Lisa continuing in background",
                body: agentTask.currentAction ?? "Working..."
            )
        }

        task.setTaskCompleted(success: true)
    }

    /// Handle background refresh task
    private func handleBackgroundRefresh(_ task: BGAppRefreshTask) {
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        // Check if agent task is still running
        if let agentTask = activeTask {
            let elapsed = Date().timeIntervalSince(agentTask.lastUpdate)
            if elapsed > 300 { // 5 minutes without update
                showProgressNotification(
                    title: "Lisa waiting for you",
                    body: "Tap to continue: \(agentTask.currentAction ?? "Task paused")"
                )
            }
        }

        // Schedule next refresh
        scheduleBackgroundRefresh()

        task.setTaskCompleted(success: true)
    }

    // MARK: - Notifications

    private func showProgressNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = nil // Silent for progress updates
        content.interruptionLevel = .passive

        let request = UNNotificationRequest(
            identifier: "lisa-progress",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    private func showCompletionNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.interruptionLevel = .active

        let request = UNNotificationRequest(
            identifier: "lisa-complete-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    private func showErrorNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        let request = UNNotificationRequest(
            identifier: "lisa-error-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Persistence

    private func persistState() {
        guard let task = activeTask else {
            clearPersistedState()
            return
        }

        if let data = try? JSONEncoder().encode(task) {
            UserDefaults.standard.set(data, forKey: stateKey)
        }
    }

    private func loadPersistedState() {
        guard let data = UserDefaults.standard.data(forKey: stateKey),
              let task = try? JSONDecoder().decode(AgentTaskState.self, from: data) else {
            return
        }

        // Only restore if task was running/paused and not too old (< 1 hour)
        let elapsed = Date().timeIntervalSince(task.lastUpdate)
        if elapsed < 3600 && (task.status == .running || task.status == .paused) {
            activeTask = task
            isRunningInBackground = true
            Log.agent.info("Restored background agent task: \(task.taskId)")
        } else {
            clearPersistedState()
        }
    }

    private func clearPersistedState() {
        UserDefaults.standard.removeObject(forKey: stateKey)
    }
}
