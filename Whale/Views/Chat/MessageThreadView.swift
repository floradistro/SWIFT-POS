//
//  MessageThreadView.swift
//  Whale
//
//  Message thread view with native scroll tracking and manual keyboard handling.
//  Uses ScrollPosition + onScrollGeometryChange (iOS 18+) for smooth auto-follow.
//

import SwiftUI
import UIKit
import Combine

// MARK: - Message Thread View

struct MessageThreadView: View {
    @ObservedObject var chatStore: ChatStore
    let conversation: ChatConversation
    var onBack: (() -> Void)?
    @EnvironmentObject private var session: SessionObserver
    @Environment(\.horizontalSizeClass) private var sizeClass
    @FocusState private var isInputFocused: Bool
    @State private var showSettings = false
    @State private var showMessageSearch = false
    @State private var messageSearchText = ""
    @State private var scrollPosition = ScrollPosition(edge: .bottom)
    @State private var keyboardHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            // iPhone back bar — padded below status bar / Dynamic Island
            if sizeClass == .compact, let onBack {
                HStack(spacing: 8) {
                    Button { onBack() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(Design.Typography.body).fontWeight(.semibold)
                            Text("Back")
                                .font(Design.Typography.body)
                        }
                        .foregroundStyle(Design.Colors.Semantic.accent)
                    }
                    Spacer()
                    Button {
                        Haptics.light()
                        showSettings = true
                    } label: {
                        Text(conversation.displayTitle)
                            .font(Design.Typography.headline)
                            .foregroundStyle(Design.Colors.Text.primary)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Color.clear.frame(width: 60)
                }
                .padding(.horizontal, 16)
                .padding(.top, SafeArea.top + 6)
                .padding(.bottom, 10)
                .background(.ultraThinMaterial)
            }

            // In-thread search bar
            if showMessageSearch {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(Design.Typography.callout)
                        .foregroundStyle(Design.Colors.Text.secondary)
                        .accessibilityHidden(true)

                    TextField("Search messages...", text: $messageSearchText)
                        .font(Design.Typography.body)
                        .textFieldStyle(.plain)

                    if !messageSearchText.isEmpty {
                        Button {
                            messageSearchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(Design.Typography.callout)
                                .foregroundStyle(Design.Colors.Text.tertiary)
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            showMessageSearch = false
                            messageSearchText = ""
                        }
                    } label: {
                        Text("Cancel")
                            .font(Design.Typography.callout)
                            .foregroundStyle(Design.Colors.Semantic.accent)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Design.Colors.Glass.thin)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            messagesScrollView

            MessageInputBar(
                chatStore: chatStore,
                isInputFocused: $isInputFocused,
                onSend: {}
            )
        }
        .padding(.bottom, adjustedKeyboardHeight)
        .ignoresSafeArea(.keyboard)
        .background(Design.Colors.backgroundPrimary)
        .navigationTitle(conversation.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if sizeClass == .regular {
                ToolbarItem(placement: .principal) {
                    conversationHeader
                }
            }
        }
        .onAppear {
            Task { await chatStore.loadAgentsIfNeeded() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
            guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            // Only adjust for docked keyboard (not iPad floating keyboard)
            guard frame.maxY >= UIScreen.main.bounds.height - 1 else { return }
            let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
            withAnimation(.easeOut(duration: duration)) {
                keyboardHeight = frame.height
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { notification in
            let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
            withAnimation(.easeOut(duration: duration)) {
                keyboardHeight = 0
            }
        }
        .sheet(isPresented: $showSettings) {
            ChatSettingsSheet(conversation: conversation, chatStore: chatStore, onSearch: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    showMessageSearch = true
                }
            })
        }
    }

    // MARK: - Keyboard

    private var adjustedKeyboardHeight: CGFloat {
        guard keyboardHeight > 0 else { return 0 }
        return max(keyboardHeight - SafeArea.bottom, 0)
    }

    // MARK: - Conversation Header (iPad toolbar)

    private var conversationHeader: some View {
        Button {
            Haptics.light()
            showSettings = true
        } label: {
            VStack(spacing: 4) {
                ConversationAvatar(
                    conversation: conversation,
                    size: 36,
                    iconSize: 16,
                    logoUrl: session.store?.fullLogoUrl
                )
                .accessibilityHidden(true)
                .padding(.top, 8)

                VStack(spacing: 0) {
                    Text(conversation.displayTitle)
                        .font(Design.Typography.subhead)
                        .fontWeight(.semibold)
                        .foregroundStyle(Design.Colors.Text.primary)

                    if conversation.chatType == .ai {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Design.Colors.Semantic.success)
                                .frame(width: 5, height: 5)
                                .accessibilityHidden(true)
                            Text("Active")
                                .font(Design.Typography.caption2)
                                .foregroundStyle(Design.Colors.Text.secondary)
                        }
                    } else if !subtitleText.isEmpty {
                        Text(subtitleText)
                            .font(Design.Typography.caption2)
                            .foregroundStyle(Design.Colors.Text.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .glassEffect(.regular.interactive(), in: .capsule)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(conversation.displayTitle), \(conversation.chatType == .ai ? "Active" : subtitleText)")
    }

    private var subtitleText: String {
        switch conversation.chatType {
        case .team: return "Team"
        case .location: return ""
        case .dm: return "Direct Message"
        case .ai: return "AI Assistant"
        case .alerts: return "Alerts"
        case .bugs: return "Bug Reports"
        }
    }

    // MARK: - Messages Scroll View

    private var messagesScrollView: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(groupedMessages, id: \.date) { group in
                    Text(formatDateHeader(group.date))
                        .font(Design.Typography.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(Design.Colors.Text.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Design.Colors.Glass.regular.opacity(0.6), in: Capsule())
                        .padding(.vertical, 12)

                    ForEach(group.messages) { message in
                        let isStreaming = chatStore.streamingMessageId == message.id
                        if !message.displayContent.isEmpty || isStreaming {
                            messageBubbleView(message: message, group: group)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .scrollPosition($scrollPosition)
        .defaultScrollAnchor(.bottom)
        .scrollDismissesKeyboard(.interactively)
        // Auto-scroll to bottom when content grows while already near bottom
        .onScrollGeometryChange(for: ScrollMetrics.self) { geo in
            let maxOffset = max(0, geo.contentSize.height - geo.containerSize.height)
            return ScrollMetrics(
                contentHeight: geo.contentSize.height,
                containerHeight: geo.containerSize.height,
                nearBottom: geo.contentOffset.y >= maxOffset - 60
            )
        } action: { old, new in
            let layoutChanged = new.contentHeight != old.contentHeight
                || new.containerHeight != old.containerHeight
            if old.nearBottom && layoutChanged {
                scrollPosition.scrollTo(edge: .bottom)
            }
        }
        // New message: scroll to bottom
        .onChange(of: chatStore.messages.count) { _, _ in
            withAnimation(.easeOut(duration: 0.15)) {
                scrollPosition.scrollTo(edge: .bottom)
            }
        }
        // Keyboard: scroll to bottom
        .onChange(of: keyboardHeight) { _, newHeight in
            if newHeight > 0 {
                withAnimation(.easeOut(duration: 0.2)) {
                    scrollPosition.scrollTo(edge: .bottom)
                }
            }
        }
    }

    // MARK: - Message Bubble

    private func messageBubbleView(message: ChatMessage, group: MessageGroup) -> some View {
        let index = group.messages.firstIndex(where: { $0.id == message.id }) ?? 0
        let previous = index > 0 ? group.messages[index - 1] : nil

        return iMessageBubble(
            message: message,
            previousMessage: previous,
            isFromCurrentUser: message.senderId == session.userId || message.isUser,
            chatStore: chatStore
        )
    }

    // MARK: - Message Grouping

    private var groupedMessages: [MessageGroup] {
        let calendar = Calendar.current
        var groups: [Date: [ChatMessage]] = [:]

        let source: [ChatMessage]
        if showMessageSearch && !messageSearchText.isEmpty {
            let query = messageSearchText.lowercased()
            source = chatStore.messages.filter { $0.content.localizedCaseInsensitiveContains(query) }
        } else {
            source = chatStore.messages
        }

        for message in source {
            let startOfDay = calendar.startOfDay(for: message.createdAt)
            groups[startOfDay, default: []].append(message)
        }

        return groups.map { MessageGroup(date: $0.key, messages: $0.value) }
            .sorted { $0.date < $1.date }
    }

    private static let dateHeaderFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f
    }()

    private func formatDateHeader(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            return Self.dateHeaderFormatter.string(from: date)
        }
    }
}

// MARK: - Message Group

struct MessageGroup {
    let date: Date
    let messages: [ChatMessage]
}

// MARK: - Scroll Metrics (for onScrollGeometryChange)

private struct ScrollMetrics: Equatable {
    let contentHeight: CGFloat
    let containerHeight: CGFloat
    let nearBottom: Bool
}
