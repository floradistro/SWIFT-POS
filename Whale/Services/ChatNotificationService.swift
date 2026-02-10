//
//  ChatNotificationService.swift
//  Whale
//
//  Handles local notifications for chat messages.
//  Requests permission and posts notifications when app is backgrounded.
//

import Foundation
import UserNotifications
import UIKit
import Combine
import os.log

@MainActor
final class ChatNotificationService: ObservableObject {

    static let shared = ChatNotificationService()

    @Published private(set) var isAuthorized = false
    private var hasRequestedPermission = false

    private init() {}

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
        // Only notify when app is not active
        guard UIApplication.shared.applicationState != .active else { return }
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body.prefix(200).description
        content.sound = .default
        content.threadIdentifier = conversationId.uuidString
        content.userInfo = [
            "conversationId": conversationId.uuidString,
            "messageId": messageId.uuidString
        ]

        // Category for actions
        content.categoryIdentifier = "CHAT_MESSAGE"

        let request = UNNotificationRequest(
            identifier: messageId.uuidString,
            content: content,
            trigger: nil // Deliver immediately
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            Log.network.debug("ChatNotificationService: Posted notification for message \(messageId)")
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

    func incrementBadge() async {
        let current = await UNUserNotificationCenter.current().deliveredNotifications().count
        try? await UNUserNotificationCenter.current().setBadgeCount(current + 1)
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
}
