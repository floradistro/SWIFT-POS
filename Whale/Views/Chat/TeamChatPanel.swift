//
//  TeamChatPanel.swift
//  Whale
//
//  iMessage-style chat interface.
//  iPad: Split view with conversation list + messages
//  iPhone: Navigation stack with list → detail push
//

import SwiftUI

// MARK: - Main Chat Panel (Adaptive Layout)

struct TeamChatPanel: View {
    @ObservedObject var chatStore: ChatStore
    @EnvironmentObject private var session: SessionObserver
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        Group {
            if sizeClass == .regular {
                // iPad: Split view like iMessage
                iPadChatSplitView(chatStore: chatStore)
            } else {
                // iPhone: Navigation stack
                iPhoneChatStackView(chatStore: chatStore)
            }
        }
        // Notification setup + permission is handled in RootView + POSMainView
    }
}

// MARK: - iPad Split View

private struct iPadChatSplitView: View {
    @ObservedObject var chatStore: ChatStore
    @State private var selectedConversation: ChatConversation?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            ConversationListView(
                chatStore: chatStore,
                selectedConversation: $selectedConversation
            )
            .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 400)
        } detail: {
            if let conversation = selectedConversation ?? chatStore.activeConversation {
                MessageThreadView(chatStore: chatStore, conversation: conversation)
            } else {
                emptyDetailView
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: selectedConversation) { _, newValue in
            if let conv = newValue {
                chatStore.selectChannel(conv.id)
            }
        }
        .onAppear {
            // Auto-select first conversation if none selected
            if selectedConversation == nil, let first = chatStore.conversations.first {
                selectedConversation = first
            }
        }
        .onChange(of: chatStore.conversations) { _, convs in
            if selectedConversation == nil, let first = convs.first {
                selectedConversation = first
            }
        }
    }

    private var emptyDetailView: some View {
        VStack(spacing: 16) {
            // Simple icon like iMessage
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 64, weight: .thin))
                .foregroundStyle(Design.Colors.Text.tertiary)

            VStack(spacing: 4) {
                Text("No Conversation Selected")
                    .font(Design.Typography.title3).fontWeight(.semibold)
                    .foregroundStyle(Design.Colors.Text.primary)

                Text("Choose a conversation from the sidebar")
                    .font(Design.Typography.subhead)
                    .foregroundStyle(Design.Colors.Text.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Design.Colors.backgroundPrimary)
    }
}

// MARK: - iPhone Navigation Stack

private struct iPhoneChatStackView: View {
    @ObservedObject var chatStore: ChatStore
    @State private var selectedConversation: ChatConversation?

    var body: some View {
        ZStack {
            // Conversation list (always rendered, hidden when thread is shown)
            ConversationListView(
                chatStore: chatStore,
                selectedConversation: $selectedConversation,
                onSelect: { conversation in
                    chatStore.selectChannel(conversation.id)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                        selectedConversation = conversation
                    }
                }
            )
            .navigationTitle("Messages")
            .navigationBarTitleDisplayMode(.large)
            .opacity(selectedConversation == nil ? 1 : 0)

            // Message thread (slides in from right)
            if let conversation = selectedConversation {
                MessageThreadView(
                    chatStore: chatStore,
                    conversation: conversation,
                    onBack: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                            selectedConversation = nil
                        }
                    }
                )
                .transition(.move(edge: .trailing))
            }
        }
    }
}
