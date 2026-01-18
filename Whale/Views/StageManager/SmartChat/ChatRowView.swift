//
//  ChatRowView.swift
//  Whale
//
//  Individual conversation row for the chat list.
//  iMessage-style design with avatar, preview, timestamp, and status indicators.
//  Native iOS 26 Liquid Glass design.
//

import SwiftUI

// MARK: - Chat Row View

struct ChatRowView: View {
    let conversation: ChatConversation
    let onTap: () -> Void

    /// Get linked window if this conversation is associated with a Stage Manager window
    private var linkedWindow: StageManagerStore.StageWindow? {
        guard let dbId = conversation.databaseId else { return nil }
        return StageManagerStore.shared.window(forConversation: dbId)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            avatarView
                .frame(width: 52, height: 52)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                // Top row: Name + Time
                HStack {
                    // Title with pin indicator
                    HStack(spacing: 6) {
                        if conversation.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.orange)
                        }

                        Text(conversation.title)
                            .font(.system(size: 16, weight: .semibold))
                            .lineLimit(1)

                        // Window link indicator
                        if let window = linkedWindow {
                            HStack(spacing: 3) {
                                Image(systemName: window.icon)
                                    .font(.system(size: 9))
                                Text(window.name)
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.white.opacity(0.1), in: Capsule())
                        }
                    }

                    Spacer()

                    // Timestamp
                    if let time = conversation.lastMessageTime {
                        Text(formatTime(time))
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }

                    // Chevron
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }

                // Bottom row: Preview + Unread badge
                HStack(alignment: .center, spacing: 8) {
                    // Agent status indicator (for AI chats)
                    if conversation.type == .aiAgent, let status = conversation.agentStatus {
                        agentStatusIndicator(status)
                    }

                    // Last message preview
                    Text(conversation.lastMessage ?? "No messages yet")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Spacer()

                    // Unread badge
                    if conversation.unreadCount > 0 {
                        unreadBadge
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        // Use highPriorityGesture to ensure this tap is processed before backdrop
        .highPriorityGesture(
            TapGesture()
                .onEnded {
                    Haptics.light()
                    onTap()
                }
        )
        .contextMenu {
            contextMenuItems
        }
    }

    // MARK: - Avatar View

    /// Store logo URL for AI agent avatars
    private var storeLogoUrl: URL? {
        SessionObserver.shared.store?.fullLogoUrl
    }

    @ViewBuilder
    private var avatarView: some View {
        ZStack {
            // Background
            Circle()
                .fill(avatarGradient)

            // Icon or image - AI agents use store logo, others use avatar or icon
            if conversation.type == .aiAgent, let logoUrl = storeLogoUrl {
                // Lisa uses store logo
                CachedAsyncImage(url: logoUrl)
                    .clipShape(Circle())
            } else if let urlString = conversation.avatarUrl,
               let url = URL(string: urlString) {
                // Staff/team use their avatar
                CachedAsyncImage(url: url)
                    .clipShape(Circle())
            } else {
                // Fallback to icon
                Image(systemName: conversation.type.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
            }

            // Online/Working indicator - uses isActive for cleaner check
            if conversation.type == .aiAgent,
               let status = conversation.agentStatus,
               status.isActive {
                Circle()
                    .fill(status.color)
                    .frame(width: 14, height: 14)
                    .overlay(
                        Circle().stroke(.black, lineWidth: 2)
                    )
                    .offset(x: 18, y: 18)
            }
        }
    }

    private var avatarGradient: LinearGradient {
        switch conversation.type {
        case .aiAgent:
            return LinearGradient(
                colors: [.purple.opacity(0.8), .blue.opacity(0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .staffChat:
            return LinearGradient(
                colors: [.blue.opacity(0.7), .cyan.opacity(0.5)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .teamChannel:
            return LinearGradient(
                colors: [.green.opacity(0.7), .teal.opacity(0.5)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    // MARK: - Agent Status Indicator (Simple Pulsing Dot)

    @ViewBuilder
    private func agentStatusIndicator(_ status: AgentStatus) -> some View {
        // Only show when actively working - just a pulsing dot, no text
        if status.isActive {
            PulsingDot(color: status.color, isActive: true)
                .padding(6)
                .glassEffect(.regular, in: .circle)
        }
    }

    // MARK: - Unread Badge (Native iOS)

    private var unreadBadge: some View {
        Text(conversation.unreadCount > 99 ? "99+" : "\(conversation.unreadCount)")
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, conversation.unreadCount > 9 ? 8 : 0)
            .frame(minWidth: 22, minHeight: 22)
            .background(.blue, in: Capsule())
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var contextMenuItems: some View {
        Button {
            ChatListStore.shared.togglePinned(conversation.id)
        } label: {
            Label(
                conversation.isPinned ? "Unpin" : "Pin",
                systemImage: conversation.isPinned ? "pin.slash" : "pin"
            )
        }

        Button {
            ChatListStore.shared.markAsRead(conversation.id)
        } label: {
            Label("Mark as Read", systemImage: "envelope.open")
        }

        Divider()

        Button(role: .destructive) {
            ChatListStore.shared.deleteConversation(conversation.id)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: - Helpers

    private func formatTime(_ date: Date) -> String {
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            // Today: show time
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else if let daysAgo = calendar.dateComponents([.day], from: date, to: Date()).day, daysAgo < 7 {
            // This week: show day name
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            return formatter.string(from: date)
        } else {
            // Older: show date
            let formatter = DateFormatter()
            formatter.dateFormat = "M/d/yy"
            return formatter.string(from: date)
        }
    }
}

// MARK: - Pulsing Dot

private struct PulsingDot: View {
    let color: Color
    let isActive: Bool

    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .shadow(color: color.opacity(isPulsing ? 0.8 : 0.4), radius: isPulsing ? 6 : 3)
            .scaleEffect(isPulsing ? 1.15 : 1.0)
            .animation(
                isActive ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default,
                value: isPulsing
            )
            .onAppear {
                if isActive { isPulsing = true }
            }
            .onChange(of: isActive) { _, active in
                isPulsing = active
            }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack(spacing: 0) {
            ChatRowView(
                conversation: ChatConversation(
                    type: .aiAgent,
                    title: "Lisa",
                    subtitle: "AI Assistant",
                    lastMessage: "Here's the sales report you requested. Total revenue for today is $12,450.",
                    lastMessageTime: Date(),
                    unreadCount: 3,
                    isPinned: true,
                    agentStatus: .working
                ),
                onTap: { }
            )

            ChatRowView(
                conversation: ChatConversation(
                    type: .staffChat,
                    title: "John Smith",
                    lastMessage: "Can you check the inventory for Blue Dream?",
                    lastMessageTime: Date().addingTimeInterval(-3600),
                    unreadCount: 0
                ),
                onTap: { }
            )

            ChatRowView(
                conversation: ChatConversation(
                    type: .aiAgent,
                    title: "Menu Generator",
                    subtitle: "Creating displays",
                    lastMessage: "Generating holiday menu displays...",
                    lastMessageTime: Date().addingTimeInterval(-86400),
                    agentStatus: .thinking,
                    progress: 0.45
                ),
                onTap: { }
            )
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.regularMaterial)
        )
    }
}
