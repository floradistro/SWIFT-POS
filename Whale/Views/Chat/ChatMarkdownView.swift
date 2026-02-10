//
//  ChatMarkdownView.swift
//  Whale
//
//  Cached markdown parser, syntax-highlighted code blocks, rich tables.
//  Tables and code render outside bubbles on the main background.
//  All parsing is cached per message ID to avoid main-thread blocking.
//

import SwiftUI

// MARK: - Block Types

enum ChatMarkdownBlock {
    case text(String)
    case heading(String, Int)
    case table(headers: [String], rows: [[String]])
    case codeBlock(code: String, language: String?)
}

/// Grouped blocks for rendering: text goes in bubbles, rich content goes standalone.
enum ChatBlockGroup {
    case textBubble(String)
    case heading(String, Int)
    case table(headers: [String], rows: [[String]])
    case codeBlock(code: String, language: String?)
}

// MARK: - Parser (cached)

struct ChatMarkdownParser {

    // Block cache keyed by message UUID — only parsed once
    private static var blockCache: [UUID: [ChatMarkdownBlock]] = [:]
    private static let maxBlockCacheSize = 200

    static func blocks(for messageId: UUID, content: String) -> [ChatMarkdownBlock] {
        if let cached = blockCache[messageId] { return cached }
        let parsed = parse(content)
        if blockCache.count >= maxBlockCacheSize { blockCache.removeAll(keepingCapacity: true) }
        blockCache[messageId] = parsed
        return parsed
    }

    /// Group adjacent text blocks into single bubbles. Tables/code stand alone.
    static func grouped(for messageId: UUID, content: String) -> [ChatBlockGroup] {
        let blocks = self.blocks(for: messageId, content: content)
        var groups: [ChatBlockGroup] = []
        var currentText = ""

        for block in blocks {
            switch block {
            case .text(let text):
                if !currentText.isEmpty { currentText += "\n\n" }
                currentText += text
            case .heading(let text, let level):
                flushGroupText(&currentText, into: &groups)
                groups.append(.heading(text, level))
            case .table(let headers, let rows):
                flushGroupText(&currentText, into: &groups)
                groups.append(.table(headers: headers, rows: rows))
            case .codeBlock(let code, let lang):
                flushGroupText(&currentText, into: &groups)
                groups.append(.codeBlock(code: code, language: lang))
            }
        }

        flushGroupText(&currentText, into: &groups)
        return groups
    }

    // MARK: - Parse

    static func parse(_ content: String) -> [ChatMarkdownBlock] {
        var blocks: [ChatMarkdownBlock] = []
        var currentText = ""
        let lines = content.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)

            // Code block
            if trimmed.hasPrefix("```") {
                flushText(&currentText, into: &blocks)
                let langStr = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                let language: String? = langStr.isEmpty ? nil : langStr
                var code = ""
                i += 1
                while i < lines.count {
                    if lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        i += 1; break
                    }
                    if !code.isEmpty { code += "\n" }
                    code += lines[i]
                    i += 1
                }
                blocks.append(.codeBlock(code: code, language: language))
                continue
            }

            // Table
            if trimmed.hasPrefix("|") {
                var tableLines: [String] = []
                var j = i
                while j < lines.count {
                    let tl = lines[j].trimmingCharacters(in: .whitespaces)
                    guard tl.hasPrefix("|") else { break }
                    tableLines.append(tl)
                    j += 1
                }
                if tableLines.count >= 2, let table = parseTable(tableLines) {
                    flushText(&currentText, into: &blocks)
                    blocks.append(.table(headers: table.headers, rows: table.rows))
                    i = j
                    continue
                }
            }

            // Heading
            if trimmed.hasPrefix("#") {
                let level = trimmed.prefix(while: { $0 == "#" }).count
                if level >= 1 && level <= 6 {
                    let text = String(trimmed.dropFirst(level)).trimmingCharacters(in: .whitespaces)
                    if !text.isEmpty {
                        flushText(&currentText, into: &blocks)
                        blocks.append(.heading(text, level))
                        i += 1
                        continue
                    }
                }
            }

            if !currentText.isEmpty { currentText += "\n" }
            currentText += lines[i]
            i += 1
        }

        flushText(&currentText, into: &blocks)
        return blocks
    }

    // MARK: Helpers

    private static func flushText(_ text: inout String, into blocks: inout [ChatMarkdownBlock]) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { blocks.append(.text(trimmed)) }
        text = ""
    }

    private static func flushGroupText(_ text: inout String, into groups: inout [ChatBlockGroup]) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { groups.append(.textBubble(trimmed)) }
        text = ""
    }

    private static func parseTable(_ lines: [String]) -> (headers: [String], rows: [[String]])? {
        guard lines.count >= 2 else { return nil }
        let headers = parseCells(lines[0])
        guard !headers.isEmpty else { return nil }
        let isSeparator = lines[1]
            .replacingOccurrences(of: "|", with: "")
            .trimmingCharacters(in: .whitespaces)
            .allSatisfy { $0 == "-" || $0 == ":" || $0 == " " }
        let dataStart = isSeparator ? 2 : 1
        var rows: [[String]] = []
        for idx in dataStart..<lines.count {
            let cells = parseCells(lines[idx])
            if !cells.isEmpty { rows.append(cells) }
        }
        return rows.isEmpty ? nil : (headers, rows)
    }

    private static func parseCells(_ line: String) -> [String] {
        line.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

// MARK: - Syntax Highlighter

/// Thread-safe syntax highlighter. Cache accessed from @MainActor only.
/// `compute()` is a pure function safe to call from any thread.
struct SyntaxHighlighter {

    // Cache keyed by code+language hash — only touched from @MainActor views
    private static var cache: [Int: AttributedString] = [:]
    private static let maxCacheSize = 100

    static func cacheKey(_ code: String, language: String?) -> Int {
        code.hashValue &+ (language?.hashValue ?? 0)
    }

    static func cached(key: Int) -> AttributedString? { cache[key] }
    static func store(key: Int, value: AttributedString) {
        if cache.count >= maxCacheSize { cache.removeAll(keepingCapacity: true) }
        cache[key] = value
    }

    /// Pure computation — no shared mutable state. Safe from any thread.
    static func compute(_ code: String, language: String?) -> AttributedString {
        let nsStr = code as NSString
        let full = NSRange(location: 0, length: nsStr.length)
        let mutable = NSMutableAttributedString(string: code)

        mutable.addAttribute(.font, value: UIFont.monospacedSystemFont(ofSize: 13, weight: .regular), range: full)
        mutable.addAttribute(.foregroundColor, value: UIColor.label, range: full)

        let lang = (language ?? "").lowercased()

        for kw in keywords(for: lang) {
            applyPattern(mutable, "\\b\(NSRegularExpression.escapedPattern(for: kw))\\b", keywordColor)
        }
        applyPattern(mutable, "\\b\\d+(\\.\\d+)?\\b", numberColor)
        applyPattern(mutable, "\"[^\"\\\\]*(\\\\.[^\"\\\\]*)*\"", stringColor)
        applyPattern(mutable, "'[^'\\\\]*(\\\\.[^'\\\\]*)*'", stringColor)
        applyPattern(mutable, "//[^\n]*", commentColor)
        if ["python", "py", "bash", "sh", "shell", "ruby", "yaml", "yml"].contains(lang) {
            applyPattern(mutable, "#[^\n]*", commentColor)
        }
        applyPattern(mutable, "/\\*[\\s\\S]*?\\*/", commentColor)

        return AttributedString(mutable)
    }

    private static func applyPattern(_ str: NSMutableAttributedString, _ pattern: String, _ color: UIColor) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return }
        for match in regex.matches(in: str.string, range: NSRange(location: 0, length: str.length)) {
            str.addAttribute(.foregroundColor, value: color, range: match.range)
        }
    }

    private static let keywordColor  = UIColor(red: 0.69, green: 0.52, blue: 0.92, alpha: 1.0)
    private static let stringColor   = UIColor(red: 0.43, green: 0.78, blue: 0.40, alpha: 1.0)
    private static let numberColor   = UIColor(red: 0.83, green: 0.60, blue: 0.35, alpha: 1.0)
    private static let commentColor  = UIColor.secondaryLabel

    private static func keywords(for lang: String) -> [String] {
        switch lang {
        case "swift":
            return ["let", "var", "func", "struct", "class", "enum", "if", "else", "for", "while", "return", "import", "guard", "switch", "case", "true", "false", "nil", "self", "async", "await", "try", "catch", "throw", "private", "public", "static", "protocol", "extension", "override", "init", "where", "in", "do"]
        case "python", "py":
            return ["def", "class", "if", "else", "elif", "for", "while", "return", "import", "from", "as", "try", "except", "with", "True", "False", "None", "self", "async", "await", "yield", "lambda", "pass", "raise", "in", "not", "and", "or"]
        case "javascript", "js", "typescript", "ts":
            return ["const", "let", "var", "function", "if", "else", "for", "while", "return", "import", "export", "from", "class", "async", "await", "try", "catch", "true", "false", "null", "undefined", "new", "this"]
        case "sql":
            return ["SELECT", "FROM", "WHERE", "INSERT", "UPDATE", "DELETE", "CREATE", "ALTER", "DROP", "TABLE", "JOIN", "LEFT", "RIGHT", "INNER", "ON", "AND", "OR", "NOT", "NULL", "AS", "ORDER", "BY", "GROUP", "HAVING", "LIMIT", "INTO", "VALUES", "SET", "COUNT", "SUM", "AVG", "MAX", "MIN"]
        case "bash", "sh", "shell", "zsh":
            return ["if", "then", "else", "fi", "for", "do", "done", "while", "case", "esac", "function", "return", "echo", "exit", "export", "local"]
        default:
            return ["if", "else", "for", "while", "return", "true", "false", "null", "nil", "func", "def", "class", "import", "let", "var", "const"]
        }
    }
}

// MARK: - Inline Markdown Text

/// Renders inline markdown synchronously with caching.
/// No flash of raw text - content appears formatted immediately.
struct ChatMarkdownText: View {
    let content: String

    private static var cache: [Int: AttributedString] = [:]
    private static let maxCacheSize = 200

    private var formatted: AttributedString {
        let key = content.hashValue
        if let cached = Self.cache[key] {
            return cached
        }
        let result = (try? AttributedString(
            markdown: content,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(content)
        if Self.cache.count >= Self.maxCacheSize { Self.cache.removeAll(keepingCapacity: true) }
        Self.cache[key] = result
        return result
    }

    var body: some View {
        Text(formatted)
    }
}

// MARK: - Rich Table View

struct ChatRichTableView: View {
    let headers: [String]
    let rows: [[String]]

    private let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
    private var displayRows: [[String]] { Array(rows.prefix(20)) }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack(spacing: 0) {
                    ForEach(Array(headers.enumerated()), id: \.offset) { idx, header in
                        Text(header.uppercased())
                            .font(Design.Typography.caption2).fontWeight(.bold)
                            .foregroundStyle(Design.Colors.Text.tertiary)
                            .frame(minWidth: columnWidth(idx), alignment: columnAlignment(idx))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                    }
                }
                .background(Design.Colors.Glass.thin)

                Rectangle().fill(Design.Colors.Border.subtle).frame(height: 0.5)

                // Rows
                ForEach(Array(displayRows.enumerated()), id: \.offset) { rowIdx, row in
                    HStack(spacing: 0) {
                        ForEach(Array(row.prefix(headers.count).enumerated()), id: \.offset) { idx, cell in
                            cellView(cell, column: idx)
                                .frame(minWidth: columnWidth(idx), alignment: columnAlignment(idx))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                        }
                    }
                    .background(rowIdx % 2 == 1 ? Design.Colors.Glass.ultraThin : Color.clear)
                }

                if rows.count > 20 {
                    Text("\(rows.count - 20) more rows")
                        .font(Design.Typography.caption2)
                        .foregroundStyle(Design.Colors.Text.ghost)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                }
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(Design.Colors.Border.subtle, lineWidth: 0.5))
        }
        .accessibilityElement(children: .combine)
    }

    /// Calculate minimum column width based on content
    private func columnWidth(_ column: Int) -> CGFloat {
        // Sample header and first few rows to determine width
        var maxLength = column < headers.count ? headers[column].count : 0
        for row in rows.prefix(10) {
            if column < row.count {
                maxLength = max(maxLength, row[column].count)
            }
        }
        // Estimate width: ~7pt per character + padding, min 50, max 200
        let estimated = CGFloat(maxLength) * 7 + 20
        return min(max(estimated, 50), 200)
    }

    // MARK: - Smart Cell Rendering

    @ViewBuilder
    private func cellView(_ text: String, column: Int) -> some View {
        if isCurrency(text) {
            Text(text)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Design.Colors.Semantic.success)
                .lineLimit(1)
        } else if isNumeric(text) {
            Text(text)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Design.Colors.Text.primary)
                .lineLimit(1)
        } else if isStatusBadge(text) {
            Text(text)
                .font(Design.Typography.caption2).fontWeight(.medium)
                .foregroundStyle(statusColor(text))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(statusColor(text).opacity(0.12)))
        } else {
            Text(text)
                .font(Design.Typography.caption1)
                .foregroundStyle(column == 0 ? Design.Colors.Text.primary : Design.Colors.Text.secondary)
                .lineLimit(2)
        }
    }

    private func columnAlignment(_ column: Int) -> Alignment {
        guard !rows.isEmpty else { return .leading }
        let samples = rows.prefix(5).compactMap { $0.count > column ? $0[column] : nil }
        let numericCount = samples.filter { isNumeric($0) || isCurrency($0) }.count
        return numericCount > samples.count / 2 ? .trailing : .leading
    }

    private func isNumeric(_ text: String) -> Bool {
        let cleaned = text.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
        return !cleaned.isEmpty && Double(cleaned) != nil
    }

    private func isCurrency(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "**", with: "")
        return trimmed.hasPrefix("$") && isNumeric(String(trimmed.dropFirst()))
    }

    private func isStatusBadge(_ text: String) -> Bool {
        let lower = text.lowercased().trimmingCharacters(in: .whitespaces)
        return ["active", "inactive", "pending", "completed", "draft", "published", "archived",
                "approved", "cancelled", "canceled", "shipped", "delivered", "open", "closed",
                "critical", "low", "ok", "overstocked", "out_of_stock", "in_transit", "received"].contains(lower)
    }

    private func statusColor(_ text: String) -> Color {
        switch text.lowercased().trimmingCharacters(in: .whitespaces) {
        case "active", "published", "completed", "delivered", "approved", "ok", "received":
            return Design.Colors.Semantic.success
        case "pending", "draft", "in_transit", "open", "low":
            return Design.Colors.Semantic.warning
        case "critical", "out_of_stock":
            return Design.Colors.Semantic.error
        default:
            return Design.Colors.Text.ghost
        }
    }
}

// MARK: - Syntax-Highlighted Code Block (async)

/// Renders code with syntax highlighting computed off the main thread.
/// Shows plain monospaced code instantly, swaps in highlighted version when ready.
struct ChatSyntaxCodeBlock: View {
    let code: String
    let language: String?

    @State private var highlighted: AttributedString?
    @State private var copied = false

    private let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            codeTopBar

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 0) {
                    codeLineNumbers
                    Rectangle().fill(Design.Colors.Glass.ultraThick).frame(width: 0.5)
                    codeContent
                }
            }
        }
        .background(Design.Colors.Glass.thin)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Design.Colors.Border.subtle, lineWidth: 0.5))
        .task(id: SyntaxHighlighter.cacheKey(code, language: language)) {
            let key = SyntaxHighlighter.cacheKey(code, language: language)
            if let cached = SyntaxHighlighter.cached(key: key) {
                highlighted = cached
                return
            }
            let c = code, l = language
            let result = await Task.detached(priority: .userInitiated) {
                SyntaxHighlighter.compute(c, language: l)
            }.value
            guard !Task.isCancelled else { return }
            SyntaxHighlighter.store(key: key, value: result)
            highlighted = result
        }
    }

    private var codeTopBar: some View {
        HStack {
            Text(language ?? "code")
                .font(Design.Typography.caption2).fontWeight(.medium)
                .foregroundStyle(Design.Colors.Text.ghost)

            Spacer()

            Button {
                UIPasteboard.general.string = code
                Haptics.light()
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    copied = false
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(Design.Typography.caption2)
                    if copied {
                        Text("Copied")
                            .font(Design.Typography.caption2)
                    }
                }
                .foregroundStyle(copied ? Design.Colors.Semantic.success : Design.Colors.Text.ghost)
            }
            .accessibilityLabel("Copy code")
            .buttonStyle(.plain)
            .animation(.easeInOut(duration: 0.2), value: copied)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Design.Colors.Glass.regular)
    }

    private var codeLineNumbers: some View {
        VStack(alignment: .trailing, spacing: 0) {
            let lines = code.components(separatedBy: "\n")
            ForEach(1...max(lines.count, 1), id: \.self) { num in
                Text("\(num)")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(Design.Colors.Text.ghost)
                    .frame(height: 18)
            }
        }
        .accessibilityHidden(true)
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .padding(.vertical, 12)
        .background(Design.Colors.Glass.ultraThin)
    }

    private var codeContent: some View {
        Group {
            if let highlighted {
                Text(highlighted)
            } else {
                Text(code)
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .textSelection(.enabled)
    }
}

// MARK: - Full Markdown Content View (for detail sheet)

struct ChatMarkdownContentView: View {
    let content: String
    var messageId: UUID = UUID()

    var body: some View {
        let blocks = ChatMarkdownParser.blocks(for: messageId, content: content)

        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: ChatMarkdownBlock) -> some View {
        switch block {
        case .text(let text):
            if !text.isEmpty { ChatMarkdownText(content: text) }
        case .heading(let text, let level):
            Text(text)
                .font(headingFont(level)).fontWeight(.bold)
                .foregroundStyle(Design.Colors.Text.primary)
                .padding(.top, level <= 2 ? 8 : 4)
        case .table(let headers, let rows):
            ChatRichTableView(headers: headers, rows: rows)
        case .codeBlock(let code, let language):
            ChatSyntaxCodeBlock(code: code, language: language)
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return Design.Typography.title2
        case 2: return Design.Typography.headline
        case 3: return Design.Typography.subhead
        default: return Design.Typography.callout
        }
    }
}

// MARK: - Message Detail Sheet

struct ChatMessageDetailSheet: View {
    let message: ChatMessage
    let senderName: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    senderRow
                    Divider()
                    ChatMarkdownContentView(content: message.displayContent, messageId: message.id)
                        .font(Design.Typography.body)
                        .foregroundStyle(Design.Colors.Text.primary)
                }
                .padding(20)
            }
            .background(Design.Colors.backgroundPrimary)
            .navigationTitle(senderName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(Design.Typography.callout).fontWeight(.semibold)
                }
            }
        }
        .tint(Design.Colors.Semantic.accent)
    }

    private var senderRow: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Design.Colors.Glass.regular)
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: message.isAI ? "cpu" : "person.circle")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Design.Colors.Text.tertiary)
                )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(senderName)
                        .font(Design.Typography.callout).fontWeight(.semibold)
                        .foregroundStyle(Design.Colors.Text.primary)

                    if message.isAI {
                        Text("AI")
                            .font(Design.Typography.caption2).fontWeight(.bold)
                            .foregroundStyle(Design.Colors.Text.tertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Design.Colors.Glass.thin, in: Capsule())
                    }
                }

                Text(Self.formatTimestamp(message.createdAt))
                    .font(Design.Typography.caption1)
                    .foregroundStyle(Design.Colors.Text.ghost)
            }

            Spacer()
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, h:mm a"
        return f
    }()

    private static func formatTimestamp(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }
}
