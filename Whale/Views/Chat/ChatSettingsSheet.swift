//
//  ChatSettingsSheet.swift
//  Whale
//
//  iMessage-style conversation info/settings sheet.
//  Opens when tapping the conversation header (iPad toolbar or iPhone title).
//

import SwiftUI

struct ChatSettingsSheet: View {
    let conversation: ChatConversation
    @ObservedObject var chatStore: ChatStore
    var onSearch: (() -> Void)?
    @EnvironmentObject private var session: SessionObserver
    @Environment(\.dismiss) private var dismiss

    private var isMuted: Bool { chatStore.isMuted(conversation.id) }
    private var isPinned: Bool { chatStore.isPinned(conversation.id) }

    private var members: [ChatSender] {
        Array(chatStore.senderCache.values).sorted { $0.displayName < $1.displayName }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                    quickActions
                    infoSection

                    if conversation.chatType == .team || conversation.chatType == .location {
                        membersSection
                    }

                    if conversation.chatType == .ai, let agent = chatStore.defaultAgent {
                        agentSection(agent)
                    }

                    if !chatStore.completedTasks.isEmpty {
                        completedTasksSection
                    }
                }
                .padding(.top, 24)
                .padding(.bottom, 40)
            }
            .background(Design.Colors.backgroundPrimary)
            .navigationBarTitleDisplayMode(.inline)
            .task { await chatStore.loadCompletedTasks() }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            ConversationAvatar(
                conversation: conversation,
                size: 80,
                iconSize: 34,
                logoUrl: session.store?.fullLogoUrl
            )
            .accessibilityHidden(true)

            VStack(spacing: 4) {
                Text(conversation.displayTitle)
                    .font(Design.Typography.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(Design.Colors.Text.primary)

                if conversation.chatType == .ai {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Design.Colors.Semantic.success)
                            .frame(width: 6, height: 6)
                        Text("Active")
                            .font(Design.Typography.subhead)
                            .foregroundStyle(Design.Colors.Text.secondary)
                    }
                } else if conversation.chatType == .team || conversation.chatType == .location {
                    Text("\(members.count) member\(members.count == 1 ? "" : "s")")
                        .font(Design.Typography.subhead)
                        .foregroundStyle(Design.Colors.Text.secondary)
                }
            }
        }
    }

    // MARK: - Quick Actions

    private var quickActions: some View {
        HStack(spacing: 16) {
            quickActionButton(
                icon: isMuted ? "bell.slash.fill" : "bell.fill",
                label: isMuted ? "Unmute" : "Mute",
                isActive: isMuted
            ) {
                chatStore.toggleMute(conversation.id)
                Haptics.selection()
            }

            quickActionButton(
                icon: isPinned ? "pin.slash.fill" : "pin.fill",
                label: isPinned ? "Unpin" : "Pin",
                isActive: isPinned
            ) {
                chatStore.togglePin(conversation.id)
                Haptics.selection()
            }

            quickActionButton(
                icon: "magnifyingglass",
                label: "Search",
                isActive: false
            ) {
                dismiss()
                // Small delay so sheet finishes dismissing before focusing search
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    onSearch?()
                }
            }
        }
        .padding(.horizontal, 32)
    }

    private func quickActionButton(icon: String, label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(isActive ? Design.Colors.Semantic.accent : Design.Colors.Text.primary)
                    .frame(width: 52, height: 52)
                    .glassEffect(.regular.interactive(), in: .circle)

                Text(label)
                    .font(Design.Typography.caption1)
                    .foregroundStyle(isActive ? Design.Colors.Semantic.accent : Design.Colors.Text.secondary)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(label)
    }

    // MARK: - Info Section

    private var infoSection: some View {
        VStack(spacing: 0) {
            infoRow(icon: "bubble.left.and.bubble.right", label: "Messages", value: "\(conversation.messageCount)")

            Divider().padding(.leading, 52)

            infoRow(icon: "calendar", label: "Created", value: formatFullDate(conversation.createdAt))

            Divider().padding(.leading, 52)

            infoRow(icon: "tag", label: "Type", value: conversation.chatType.rawValue.capitalized)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 16)
        .background(Design.Colors.Glass.thin, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 16)
    }

    private func infoRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(Design.Typography.callout)
                .foregroundStyle(Design.Colors.Text.secondary)
                .frame(width: 28)
                .accessibilityHidden(true)

            Text(label)
                .font(Design.Typography.body)
                .foregroundStyle(Design.Colors.Text.primary)

            Spacer()

            Text(value)
                .font(Design.Typography.body)
                .foregroundStyle(Design.Colors.Text.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Members Section

    private var membersSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Members")
                .font(Design.Typography.subhead)
                .fontWeight(.semibold)
                .foregroundStyle(Design.Colors.Text.secondary)
                .padding(.horizontal, 28)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                ForEach(members, id: \.id) { sender in
                    memberRow(sender)

                    if sender.id != members.last?.id {
                        Divider().padding(.leading, 64)
                    }
                }

                if members.isEmpty {
                    HStack(spacing: 12) {
                        Image(systemName: "person.2")
                            .font(Design.Typography.callout)
                            .foregroundStyle(Design.Colors.Text.tertiary)
                            .frame(width: 28)
                        Text("No members loaded")
                            .font(Design.Typography.body)
                            .foregroundStyle(Design.Colors.Text.tertiary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 16)
            .background(Design.Colors.Glass.thin, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 16)
        }
    }

    private func memberRow(_ sender: ChatSender) -> some View {
        let color = SenderColor.forId(sender.id)
        return HStack(spacing: 12) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.8), color],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .frame(width: 36, height: 36)
                .overlay(
                    Text(sender.initials)
                        .font(Design.Typography.caption1)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(sender.displayName)
                    .font(Design.Typography.body)
                    .foregroundStyle(Design.Colors.Text.primary)

                if let email = sender.email {
                    Text(email)
                        .font(Design.Typography.caption1)
                        .foregroundStyle(Design.Colors.Text.tertiary)
                }
            }

            Spacer()

            if sender.id == session.userId {
                Text("You")
                    .font(Design.Typography.caption1)
                    .fontWeight(.medium)
                    .foregroundStyle(Design.Colors.Semantic.accent)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    // MARK: - AI Agent Section

    private func agentSection(_ agent: AIAgent) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("AI Agent")
                .font(Design.Typography.subhead)
                .fontWeight(.semibold)
                .foregroundStyle(Design.Colors.Text.secondary)
                .padding(.horizontal, 28)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Design.Colors.Semantic.accent.opacity(0.8), Design.Colors.Semantic.accent],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 36, height: 36)
                        .overlay(
                            Image(systemName: agent.displayIcon)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(Design.Colors.Semantic.accentForeground)
                        )
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(agent.displayName)
                            .font(Design.Typography.body)
                            .fontWeight(.medium)
                            .foregroundStyle(Design.Colors.Text.primary)

                        Text(agent.shortDescription)
                            .font(Design.Typography.caption1)
                            .foregroundStyle(Design.Colors.Text.secondary)
                            .lineLimit(2)
                    }

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)

                if let model = agent.model {
                    Divider().padding(.leading, 64)
                    infoRow(icon: "cpu", label: "Model", value: model)
                }

                if let tools = agent.enabledTools, !tools.isEmpty {
                    Divider().padding(.leading, 64)
                    infoRow(icon: "wrench", label: "Tools", value: "\(tools.count) enabled")
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 16)
            .background(Design.Colors.Glass.thin, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Completed Tasks Section

    private var completedTasksSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Completed Tasks")
                    .font(Design.Typography.subhead)
                    .fontWeight(.semibold)
                    .foregroundStyle(Design.Colors.Text.secondary)

                Text("\(chatStore.completedTasks.count)")
                    .font(Design.Typography.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Design.Colors.Semantic.success, in: Capsule())
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 8)

            VStack(spacing: 0) {
                ForEach(chatStore.completedTasks) { task in
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(Design.Typography.callout)
                            .foregroundStyle(Design.Colors.Semantic.success)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.originalContent)
                                .font(Design.Typography.body)
                                .foregroundStyle(Design.Colors.Text.primary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)

                            HStack(spacing: 4) {
                                if let name = task.completedByName {
                                    Text(name)
                                        .fontWeight(.medium)
                                }
                                Text(relativeTime(task.createdAt))
                            }
                            .font(Design.Typography.caption2)
                            .foregroundStyle(Design.Colors.Text.tertiary)
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .accessibilityElement(children: .combine)

                    if task.id != chatStore.completedTasks.last?.id {
                        Divider().padding(.leading, 48)
                    }
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 16)
            .background(Design.Colors.Glass.thin, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 16)
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "Just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        let days = Int(interval / 86400)
        if days == 1 { return "Yesterday" }
        if days < 7 { return "\(days)d ago" }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter.string(from: date)
    }

    // MARK: - Helpers

    private static let fullDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private func formatFullDate(_ date: Date) -> String {
        Self.fullDateFormatter.string(from: date)
    }
}

// MARK: - Shared Conversation Avatar (reusable across list + settings)

struct ConversationAvatar: View {
    let conversation: ChatConversation
    var size: CGFloat = 52
    var iconSize: CGFloat = 22
    var logoUrl: URL?

    private var colors: (primary: Color, secondary: Color) {
        ConversationColor.forConversation(conversation)
    }

    /// Use store logo as the icon for team/location/dm chats
    private var useLogoAsIcon: Bool {
        guard logoUrl != nil else { return false }
        switch conversation.chatType {
        case .team, .location, .dm: return true
        case .ai, .alerts, .bugs: return false
        }
    }

    var body: some View {
        if useLogoAsIcon, let logoUrl {
            CachedAsyncImage(url: logoUrl, placeholderLogoUrl: nil, dimAmount: 0)
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [colors.primary.opacity(0.85), colors.secondary],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
                .overlay(
                    Image(systemName: conversation.typeIcon)
                        .font(.system(size: iconSize, weight: .medium))
                        .foregroundStyle(.white)
                )
        }
    }
}

// MARK: - Deterministic Color Palette (conversation-level)

enum ConversationColor {
    /// Vibrant, distinct color pairs for conversation avatars.
    /// Each tuple is (primary gradient start, secondary gradient end).
    private static let palette: [(Color, Color)] = [
        // Teal
        (Color(red: 0.18, green: 0.72, blue: 0.68), Color(red: 0.12, green: 0.55, blue: 0.58)),
        // Indigo
        (Color(red: 0.35, green: 0.34, blue: 0.84), Color(red: 0.28, green: 0.24, blue: 0.70)),
        // Coral
        (Color(red: 0.95, green: 0.45, blue: 0.38), Color(red: 0.82, green: 0.30, blue: 0.32)),
        // Violet
        (Color(red: 0.58, green: 0.34, blue: 0.82), Color(red: 0.45, green: 0.22, blue: 0.72)),
        // Ocean
        (Color(red: 0.22, green: 0.56, blue: 0.92), Color(red: 0.16, green: 0.40, blue: 0.78)),
        // Amber
        (Color(red: 0.92, green: 0.65, blue: 0.20), Color(red: 0.80, green: 0.50, blue: 0.15)),
        // Rose
        (Color(red: 0.88, green: 0.36, blue: 0.56), Color(red: 0.72, green: 0.24, blue: 0.46)),
        // Emerald
        (Color(red: 0.16, green: 0.70, blue: 0.46), Color(red: 0.10, green: 0.54, blue: 0.38)),
        // Slate blue
        (Color(red: 0.42, green: 0.50, blue: 0.78), Color(red: 0.32, green: 0.38, blue: 0.68)),
        // Crimson
        (Color(red: 0.82, green: 0.22, blue: 0.28), Color(red: 0.65, green: 0.14, blue: 0.22)),
    ]

    /// AI conversations always use accent blue
    private static let aiColors: (Color, Color) = (
        Color(red: 0.35, green: 0.34, blue: 0.84),
        Color(red: 0.22, green: 0.56, blue: 0.92)
    )

    static func forConversation(_ conversation: ChatConversation) -> (primary: Color, secondary: Color) {
        switch conversation.chatType {
        case .ai:
            return aiColors
        case .alerts:
            return (Color(red: 0.95, green: 0.60, blue: 0.18), Color(red: 0.85, green: 0.42, blue: 0.12))
        case .bugs:
            return (Color(red: 0.82, green: 0.22, blue: 0.28), Color(red: 0.65, green: 0.14, blue: 0.22))
        default:
            // Hash-based for team, location, dm
            let hash = abs(conversation.id.hashValue)
            let index = hash % palette.count
            return palette[index]
        }
    }
}

// MARK: - Deterministic Sender Colors

enum SenderColor {
    private static let palette: [Color] = [
        Color(red: 0.18, green: 0.72, blue: 0.68), // Teal
        Color(red: 0.35, green: 0.34, blue: 0.84), // Indigo
        Color(red: 0.95, green: 0.45, blue: 0.38), // Coral
        Color(red: 0.58, green: 0.34, blue: 0.82), // Violet
        Color(red: 0.22, green: 0.56, blue: 0.92), // Ocean
        Color(red: 0.92, green: 0.65, blue: 0.20), // Amber
        Color(red: 0.88, green: 0.36, blue: 0.56), // Rose
        Color(red: 0.16, green: 0.70, blue: 0.46), // Emerald
    ]

    static func forId(_ id: UUID) -> Color {
        let hash = abs(id.hashValue)
        return palette[hash % palette.count]
    }
}
