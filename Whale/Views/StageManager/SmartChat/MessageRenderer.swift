//
//  MessageRenderer.swift
//  Whale
//
//  Clean message rendering for Smart AI Dock.
//  Handles parsing of XML action tags from Claude streaming responses.
//

import SwiftUI

// MARK: - Content Parser

/// Parses Claude's streaming output to extract displayable content
/// Converts internal XML tags to user-friendly status indicators
struct MessageContentParser {

    /// Parse result with clean text and extracted actions
    struct ParseResult {
        let displayText: String
        let actions: [String]  // Tool names that were called
        let isWorking: Bool    // True if there's an unclosed action tag
    }

    /// Parse content and return clean displayable text with action indicators
    static func parse(_ content: String) -> ParseResult {
        var result = content
        var actions: [String] = []
        var isWorking = false

        // Extract action tool names before removing them
        // Pattern: <action status="success">\ntool_name\n</action>
        let actionPattern = #"<action[^>]*>\s*(\w+)\s*</action>"#
        if let regex = try? NSRegularExpression(pattern: actionPattern, options: []) {
            let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
            for match in matches {
                if let toolRange = Range(match.range(at: 1), in: result) {
                    let toolName = String(result[toolRange])
                    actions.append(toolName)
                }
            }
        }

        // Check for unclosed action tag (still working)
        if result.contains("<action") && !result.contains("</action>") {
            isWorking = true
        }

        // Remove action tags
        result = removeTagPairs(from: result, tagName: "action")

        // Remove streaming-code tags
        result = removeTagPairs(from: result, tagName: "streaming-code")

        // Remove internal data tags (keep these hidden)
        result = removeTagPairs(from: result, tagName: "creation-saved")
        result = removeTagPairs(from: result, tagName: "creation-edited")
        result = removeTagPairs(from: result, tagName: "images-block")

        // Clean up multiple newlines
        while result.contains("\n\n\n") {
            result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }

        return ParseResult(
            displayText: result.trimmingCharacters(in: .whitespacesAndNewlines),
            actions: actions,
            isWorking: isWorking
        )
    }

    /// Simple version that just returns display text
    static func parseForDisplay(_ content: String) -> String {
        return parse(content).displayText
    }

    /// Remove XML tag pairs and their content
    private static func removeTagPairs(from text: String, tagName: String) -> String {
        var result = text

        // Pattern to match opening tag with optional attributes
        let openPattern = "<\(tagName)[^>]*>"
        let closePattern = "</\(tagName)>"

        // Keep removing while we find pairs
        while let openRange = result.range(of: openPattern, options: .regularExpression) {
            let searchStart = openRange.upperBound
            if let closeRange = result.range(of: closePattern, range: searchStart..<result.endIndex) {
                result.removeSubrange(openRange.lowerBound..<closeRange.upperBound)
            } else {
                // No closing tag yet (streaming) - remove from opening tag to end
                result.removeSubrange(openRange.lowerBound..<result.endIndex)
                break
            }
        }

        return result
    }

    /// Convert tool name to user-friendly display
    static func formatToolName(_ toolName: String) -> String {
        switch toolName {
        case "creation_get": return "Reading creation..."
        case "creation_edit": return "Editing..."
        case "creation_save": return "Saving..."
        case "database_query": return "Querying database..."
        case "products_find": return "Finding products..."
        case "inventory_adjust": return "Adjusting inventory..."
        default:
            // Convert snake_case to Title Case
            return toolName
                .replacingOccurrences(of: "_", with: " ")
                .capitalized + "..."
        }
    }
}

// MARK: - Monochrome Message Content (simple markdown rendering)

struct MonochromeMessageContent: View {
    let content: String
    let isStreaming: Bool

    /// Parsed content with actions extracted
    private var parsed: MessageContentParser.ParseResult {
        MessageContentParser.parse(content)
    }

    init(content: String, isStreaming: Bool = false) {
        self.content = content
        self.isStreaming = isStreaming
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Show completed actions as subtle status chips
            if !parsed.actions.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(parsed.actions, id: \.self) { action in
                        ActionChip(toolName: action, isComplete: true)
                    }
                }
            }

            // Show main text content
            if !parsed.displayText.isEmpty {
                Text(LocalizedStringKey(parsed.displayText))
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.white.opacity(0.9))
                    .textSelection(.enabled)
                    .lineSpacing(4)
            }

            // Show working indicator when streaming with no text yet
            if isStreaming && parsed.displayText.isEmpty {
                WorkingIndicator(isWorking: parsed.isWorking || parsed.actions.isEmpty)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }
}

// MARK: - Action Chip (shows completed tool calls)

private struct ActionChip: View {
    let toolName: String
    let isComplete: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isComplete ? "checkmark.circle.fill" : "circle.dotted")
                .font(.system(size: 10))
            Text(MessageContentParser.formatToolName(toolName).replacingOccurrences(of: "...", with: ""))
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(.white.opacity(0.6))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.08))
        )
    }
}

// MARK: - Working Indicator (animated dots)

private struct WorkingIndicator: View {
    let isWorking: Bool
    @State private var dotIndex = 0

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(.white.opacity(index == dotIndex ? 0.8 : 0.3))
                    .frame(width: 6, height: 6)
            }
        }
        .onAppear {
            startAnimation()
        }
    }

    private func startAnimation() {
        guard isWorking else { return }
        Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { timer in
            withAnimation(.easeInOut(duration: 0.2)) {
                dotIndex = (dotIndex + 1) % 3
            }
        }
    }
}

// MARK: - Flow Layout (for action chips)

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            positions.append(CGPoint(x: currentX, y: currentY))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            totalHeight = currentY + lineHeight
        }

        return (CGSize(width: maxWidth, height: totalHeight), positions)
    }
}

// MARK: - Message Bubble

struct SmartChatBubble: View {
    let message: ChatMessage

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if isUser { Spacer(minLength: 48) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                // Message content
                if message.isStreaming && message.content.isEmpty {
                    streamingIndicator
                } else {
                    messageContent
                }

                // Timestamp
                Text(message.timestamp, style: .time)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.25))
            }

            if !isUser { Spacer(minLength: 48) }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Message Content

    @ViewBuilder
    private var messageContent: some View {
        if isUser {
            // User messages - iMessage-style blue bubble
            Text(message.content)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.white)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedBubbleShape(isUser: true, cornerRadius: 18)
                        .fill(Color.blue)
                )
        } else {
            // Assistant messages - rich content rendering (no bubble for cleaner look)
            MonochromeMessageContent(
                content: message.content,
                isStreaming: message.isStreaming
            )
        }
    }

    // MARK: - Streaming Indicator

    private var streamingIndicator: some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { index in
                StreamingDot(index: index)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }
}

// MARK: - Streaming Dot

private struct StreamingDot: View {
    let index: Int
    @State private var isAnimating = false

    var body: some View {
        Circle()
            .fill(.white.opacity(0.5))
            .frame(width: 7, height: 7)
            .offset(y: isAnimating ? -4 : 0)
            .animation(
                .easeInOut(duration: 0.4)
                .repeatForever()
                .delay(Double(index) * 0.15),
                value: isAnimating
            )
            .onAppear {
                isAnimating = true
            }
    }
}

// MARK: - iMessage Bubble Shape

struct RoundedBubbleShape: Shape {
    let isUser: Bool
    let cornerRadius: CGFloat

    init(isUser: Bool, cornerRadius: CGFloat = 18) {
        self.isUser = isUser
        self.cornerRadius = cornerRadius
    }

    func path(in rect: CGRect) -> Path {
        let corners: UIRectCorner = isUser
            ? [.topLeft, .topRight, .bottomLeft]
            : [.topLeft, .topRight, .bottomRight]

        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: cornerRadius, height: cornerRadius)
        )
        return Path(path.cgPath)
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack(spacing: 16) {
            SmartChatBubble(message: ChatMessage(
                role: .user,
                content: "Show me today's sales"
            ))

            SmartChatBubble(message: ChatMessage(
                role: .assistant,
                content: "**Today's Sales Summary**\n\n| Product | Qty | Revenue |\n|---------|-----|--------|\n| OG Kush | 28 | $420 |\n| Blue Dream | 14 | $210 |"
            ))

            SmartChatBubble(message: ChatMessage(
                role: .assistant,
                content: "",
                isStreaming: true
            ))
        }
        .padding()
    }
}
