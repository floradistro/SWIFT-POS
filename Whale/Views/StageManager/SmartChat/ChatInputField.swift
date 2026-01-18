//
//  ChatInputField.swift
//  Whale
//
//  Clean, polished input field for Smart AI Dock.
//  Native iOS 26 Liquid Glass design.
//

import SwiftUI

// MARK: - Smart Chat Input (Native iOS 26 Glass)

struct SmartChatInput: View {
    @Binding var text: String
    let isStreaming: Bool
    let onSend: () -> Void
    let onCancel: () -> Void

    @FocusState private var isFocused: Bool

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            // Text field - native iOS 26 interactive glass
            TextField("Message Lisa...", text: $text, axis: .vertical)
                .font(.system(size: 15, weight: .regular))
                .lineLimit(1...6)
                .focused($isFocused)
                .onSubmit {
                    if canSend && !isStreaming {
                        onSend()
                    }
                }
                .submitLabel(.send)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))

            // Send / Stop button - native glass circle
            SmartSendButton(
                canSend: canSend,
                isStreaming: isStreaming,
                onTap: {
                    if isStreaming {
                        onCancel()
                    } else if canSend {
                        Haptics.medium()
                        onSend()
                    }
                }
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Smart Send Button (Liquid Glass)

struct SmartSendButton: View {
    let canSend: Bool
    let isStreaming: Bool
    let onTap: () -> Void

    private var isActive: Bool { canSend || isStreaming }

    var body: some View {
        Button {
            Haptics.medium()
            onTap()
        } label: {
            ZStack {
                // Stop icon (visible when streaming)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(.white)
                    .frame(width: 12, height: 12)
                    .opacity(isStreaming ? 1 : 0)
                    .scaleEffect(isStreaming ? 1 : 0.5)

                // Arrow icon (visible when not streaming)
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(canSend ? .white : .secondary)
                    .opacity(isStreaming ? 0 : 1)
                    .scaleEffect(isStreaming ? 0.5 : 1)
            }
            .frame(width: 40, height: 40)
            .background(
                Circle()
                    .fill(isActive ? .blue : .clear)
            )
            .glassEffect(.regular, in: .circle)
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isStreaming)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: canSend)
        }
        .buttonStyle(LiquidPressStyle())
        .disabled(!canSend && !isStreaming)
    }
}

// MARK: - Compact Chat Input (For Collapsed State)

struct CompactChatTrigger: View {
    let logoUrl: URL?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                // Lisa avatar (store logo or fallback)
                avatarView
                    .frame(width: 36, height: 36)

                Text("Ask Lisa anything...")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))

                Spacer()

                // Mic hint
                Image(systemName: "mic.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.3))
                    .frame(width: 28, height: 28)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(.white.opacity(0.06))
            )
            .overlay(
                Capsule()
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(ChatTriggerButtonStyle())
    }

    @ViewBuilder
    private var avatarView: some View {
        if let url = logoUrl {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipShape(Circle())
                default:
                    fallbackAvatar
                }
            }
        } else {
            fallbackAvatar
        }
    }

    private var fallbackAvatar: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.purple.opacity(0.8), .blue.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

private struct ChatTriggerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Quick Suggestions

struct SmartSuggestions: View {
    let suggestions: [Suggestion]
    let onSelect: (String) -> Void

    struct Suggestion: Identifiable {
        let id = UUID()
        let text: String
        let icon: String
    }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(suggestions) { suggestion in
                SuggestionButton(
                    text: suggestion.text,
                    icon: suggestion.icon,
                    onTap: { onSelect(suggestion.text) }
                )
            }
        }
    }
}

// MARK: - Suggestion Button (Liquid Glass)

struct SuggestionButton: View {
    let text: String
    let icon: String
    let onTap: () -> Void

    var body: some View {
        Button {
            Haptics.light()
            onTap()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)

                Text(text)
                    .font(.system(size: 14, weight: .regular))

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .glassEffect(.regular, in: .rect(cornerRadius: 12))
        }
        .buttonStyle(LiquidPressStyle())
    }
}

// MARK: - Default Suggestions

extension SmartSuggestions {
    static var defaultSuggestions: [Suggestion] {
        [
            Suggestion(text: "Create a menu board", icon: "tv"),
            Suggestion(text: "Design an email template", icon: "envelope"),
            Suggestion(text: "Show me today's sales", icon: "chart.bar")
        ]
    }

    static var creationSuggestions: [Suggestion] {
        [
            Suggestion(text: "Create a menu board", icon: "tv"),
            Suggestion(text: "Design an email template", icon: "envelope"),
            Suggestion(text: "Build a landing page", icon: "globe"),
            Suggestion(text: "Make a dashboard", icon: "chart.bar")
        ]
    }
}
