//
//  ChatNotificationService.swift
//  Whale
//
//  Handles local notifications for chat messages.
//  Posts notifications for non-active conversations (including in foreground).
//  Acts as UNUserNotificationCenterDelegate for banner display + tap handling.
//

import Foundation
import UserNotifications
import UIKit
import Combine
import os.log

@MainActor
final class ChatNotificationService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {

    static let shared = ChatNotificationService()

    @Published private(set) var isAuthorized = false
    private var hasRequestedPermission = false

    private override init() { super.init() }

    // MARK: - Setup

    func setup() {
        UNUserNotificationCenter.current().delegate = self
        setupNotificationCategories()
    }

    // MARK: - Permission

    func requestPermissionIfNeeded() async {
        guard !hasRequestedPermission else { return }
        hasRequestedPermission = true

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .notDetermined:
            do {
                isAuthorized = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                Log.network.info("ChatNotificationService: Permission granted = \(self.isAuthorized)")
            } catch {
                Log.network.error("ChatNotificationService: Permission request failed: \(error)")
            }
        case .authorized, .provisional:
            isAuthorized = true
        case .denied, .ephemeral:
            isAuthorized = false
        @unknown default:
            isAuthorized = false
        }
    }

    // MARK: - Post Notification

    func postMessageNotification(
        title: String,
        body: String,
        conversationId: UUID,
        messageId: UUID
    ) async {
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = String(body.prefix(200))
        content.sound = .default
        content.threadIdentifier = conversationId.uuidString
        content.userInfo = [
            "conversationId": conversationId.uuidString,
            "messageId": messageId.uuidString
        ]
        content.categoryIdentifier = "CHAT_MESSAGE"

        let request = UNNotificationRequest(
            identifier: messageId.uuidString,
            content: content,
            trigger: nil
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            Log.network.error("ChatNotificationService: Failed to post notification: \(error)")
        }
    }

    // MARK: - Badge Management

    func clearBadge() {
        Task {
            try? await UNUserNotificationCenter.current().setBadgeCount(0)
        }
    }

    func updateBadge(_ count: Int) {
        Task {
            try? await UNUserNotificationCenter.current().setBadgeCount(count)
        }
    }

    // MARK: - Clear Notifications for Conversation

    func clearNotifications(for conversationId: UUID) {
        let center = UNUserNotificationCenter.current()
        center.getDeliveredNotifications { notifications in
            let idsToRemove = notifications
                .filter { $0.request.content.threadIdentifier == conversationId.uuidString }
                .map { $0.request.identifier }
            center.removeDeliveredNotifications(withIdentifiers: idsToRemove)
        }
    }

    // MARK: - Setup Categories

    func setupNotificationCategories() {
        let replyAction = UNTextInputNotificationAction(
            identifier: "REPLY_ACTION",
            title: "Reply",
            options: [],
            textInputButtonTitle: "Send",
            textInputPlaceholder: "Message"
        )

        let markReadAction = UNNotificationAction(
            identifier: "MARK_READ_ACTION",
            title: "Mark as Read",
            options: []
        )

        let category = UNNotificationCategory(
            identifier: "CHAT_MESSAGE",
            actions: [replyAction, markReadAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show banner even when app is in foreground (for messages in non-active conversations)
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }

    /// Handle notification tap — post internal notification for navigation
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        guard let conversationIdString = userInfo["conversationId"] as? String,
              let conversationId = UUID(uuidString: conversationIdString) else { return }

        await MainActor.run {
            // Navigate to the tapped conversation
            ChatStore.shared.selectChannel(conversationId)
        }
    }
}
