//
//  MarkdownComponents.swift
//  Whale
//
//  WhaleChat-style markdown rendering components.
//  Exact port from WhaleChat with Design.Colors theming.
//

import SwiftUI
import UIKit

// MARK: - Block Types

enum MarkdownBlock: Identifiable {
    case text(content: String)
    case code(content: String, lang: String?, incomplete: Bool)
    case table(headers: [String], rows: [[String]])

    var id: String {
        switch self {
        case .text(let c): return "text-\(c.hashValue)"
        case .code(let c, let l, _): return "code-\(l ?? "")-\(c.hashValue)"
        case .table(let h, _): return "table-\(h.joined())"
        }
    }
}

// MARK: - Parser

struct MarkdownBlockParser {
    static func parse(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let cleaned = text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)

        let lines = cleaned.components(separatedBy: "\n")
        var buf: [String] = []
        var inCode = false
        var codeLang = ""
        var inTable = false
        var tableHeaders: [String] = []
        var tableRows: [[String]] = []

        for line in lines {
            if line.hasPrefix("```") {
                if inTable && !tableHeaders.isEmpty {
                    blocks.append(.table(headers: tableHeaders, rows: tableRows))
                    inTable = false; tableHeaders = []; tableRows = []
                }
                if !inCode {
                    if !buf.isEmpty { blocks.append(.text(content: buf.joined(separator: "\n"))); buf = [] }
                    inCode = true; codeLang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                } else {
                    blocks.append(.code(content: buf.joined(separator: "\n"), lang: codeLang.isEmpty ? nil : codeLang, incomplete: false))
                    inCode = false; codeLang = ""; buf = []
                }
                continue
            }
            if inCode { buf.append(line); continue }

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let pipeCount = trimmed.filter { $0 == "|" }.count
            let isTableLine = pipeCount >= 2 && !trimmed.hasPrefix("```")
            let isSeparator = isTableLine && (trimmed.contains("---") || trimmed.contains("|-"))

            if isTableLine {
                if !inTable && !buf.isEmpty { blocks.append(.text(content: buf.joined(separator: "\n"))); buf = [] }
                let cells = parseTableRow(trimmed)
                if !inTable { tableHeaders = cells; inTable = true }
                else if isSeparator { continue }
                else { tableRows.append(cells) }
                continue
            }

            if inTable && !tableHeaders.isEmpty {
                blocks.append(.table(headers: tableHeaders, rows: tableRows))
                inTable = false; tableHeaders = []; tableRows = []
            }
            buf.append(line)
        }

        if inTable && !tableHeaders.isEmpty { blocks.append(.table(headers: tableHeaders, rows: tableRows)) }
        if !buf.isEmpty {
            if inCode { blocks.append(.code(content: buf.joined(separator: "\n"), lang: codeLang.isEmpty ? nil : codeLang, incomplete: true)) }
            else { blocks.append(.text(content: buf.joined(separator: "\n"))) }
        }
        return blocks
    }

    private static func parseTableRow(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") { trimmed = String(trimmed.dropFirst()) }
        if trimmed.hasSuffix("|") { trimmed = String(trimmed.dropLast()) }
        return trimmed.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

// MARK: - Main Markdown View

struct MarkdownContentView: View, Equatable {
    let content: String
    let isFromCurrentUser: Bool
    private let blocks: [MarkdownBlock]

    init(_ content: String, isFromCurrentUser: Bool = false) {
        self.content = content
        self.isFromCurrentUser = isFromCurrentUser
        self.blocks = MarkdownBlockParser.parse(content)
    }

    static func == (lhs: MarkdownContentView, rhs: MarkdownContentView) -> Bool { lhs.content == rhs.content }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(blocks) { block in
                blockView(for: block)
            }
        }
    }

    @ViewBuilder
    private func blockView(for block: MarkdownBlock) -> some View {
        switch block {
        case .text(let content):
            TextBlockView(content: content, isFromCurrentUser: isFromCurrentUser)
        case .code(let content, let lang, let incomplete):
            CodeBlockView(code: content, language: lang, incomplete: incomplete)
        case .table(let headers, let rows):
            TableBlockView(headers: headers, rows: rows)
        }
    }
}

// MARK: - Text Block View

struct TextBlockView: View, Equatable {
    let content: String
    let isFromCurrentUser: Bool
    private let parsedLines: [[String]]

    init(content: String, isFromCurrentUser: Bool) {
        self.content = content
        self.isFromCurrentUser = isFromCurrentUser
        let paragraphs = content.split(separator: "\n\n", omittingEmptySubsequences: true)
        self.parsedLines = paragraphs.map { $0.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) }
    }

    static func == (lhs: TextBlockView, rhs: TextBlockView) -> Bool { lhs.content == rhs.content }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(parsedLines.indices, id: \.self) { pIdx in
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(parsedLines[pIdx].indices, id: \.self) { lIdx in
                        renderLine(parsedLines[pIdx][lIdx])
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func renderLine(_ line: String) -> some View {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let textColor = isFromCurrentUser ? Design.Colors.Semantic.accentForeground : Design.Colors.Text.primary

        if trimmed.isEmpty {
            EmptyView()
        } else if trimmed.hasPrefix("### ") {
            Text(String(trimmed.dropFirst(4)))
                .font(Design.Typography.subhead).fontWeight(.semibold)
                .foregroundStyle(textColor)
                .padding(.top, 4)
        } else if trimmed.hasPrefix("## ") {
            Text(String(trimmed.dropFirst(3)))
                .font(Design.Typography.headline)
                .foregroundStyle(textColor)
                .padding(.top, 6)
        } else if trimmed.hasPrefix("# ") {
            Text(String(trimmed.dropFirst(2)))
                .font(Design.Typography.title3).fontWeight(.bold)
                .foregroundStyle(textColor)
                .padding(.top, 8)
        } else if trimmed.hasPrefix("> ") {
            HStack(spacing: 8) {
                Rectangle()
                    .fill(Design.Colors.Text.tertiary)
                    .frame(width: 3)
                Text(renderInlineText(String(trimmed.dropFirst(2))))
                    .font(Design.Typography.subhead).italic()
                    .foregroundStyle(Design.Colors.Text.secondary)
            }
            .padding(.leading, 8)
        } else if let listContent = parseUnorderedListItem(trimmed) {
            HStack(alignment: .top, spacing: 8) {
                Text("•")
                    .font(Design.Typography.subhead).fontWeight(.bold)
                    .foregroundStyle(isFromCurrentUser ? Design.Colors.Semantic.accentForeground : Design.Colors.Semantic.accent)
                Text(renderInlineText(listContent))
                    .font(Design.Typography.subhead)
                    .foregroundStyle(textColor)
            }
            .padding(.leading, 8)
        } else if let (num, listContent) = parseOrderedListItem(trimmed) {
            HStack(alignment: .top, spacing: 8) {
                Text("\(num).")
                    .font(Design.Typography.subhead).fontWeight(.medium)
                    .foregroundStyle(Design.Colors.Text.secondary)
                    .frame(minWidth: 20, alignment: .trailing)
                Text(renderInlineText(listContent))
                    .font(Design.Typography.subhead)
                    .foregroundStyle(textColor)
            }
            .padding(.leading, 8)
        } else if trimmed.allSatisfy({ $0 == "-" || $0 == "*" || $0 == "_" }) && trimmed.count >= 3 {
            Rectangle()
                .fill(Design.Colors.Border.subtle)
                .frame(height: 1)
                .padding(.vertical, 8)
        } else {
            Text(renderInlineText(trimmed))
                .font(Design.Typography.subhead)
                .foregroundStyle(textColor)
        }
    }

    private func renderInlineText(_ text: String) -> AttributedString {
        var result = AttributedString()
        var remaining = text[...]

        while !remaining.isEmpty {
            // Bold: **text**
            if remaining.hasPrefix("**") {
                let afterStars = remaining.dropFirst(2)
                if let endIdx = afterStars.range(of: "**") {
                    let boldText = String(afterStars[afterStars.startIndex..<endIdx.lowerBound])
                    var attr = AttributedString(boldText)
                    attr.font = .system(size: 15, weight: .bold)
                    result += attr
                    remaining = afterStars[endIdx.upperBound...]
                    continue
                }
            }
            // Inline code: `text`
            if remaining.hasPrefix("`") {
                if let endIdx = remaining.dropFirst().firstIndex(of: "`") {
                    let code = String(remaining[remaining.index(after: remaining.startIndex)..<endIdx])
                    var codeAttr = AttributedString(code)
                    codeAttr.foregroundColor = Design.Colors.Semantic.accent
                    codeAttr.font = .system(size: 14, design: .monospaced)
                    result += codeAttr
                    remaining = remaining[remaining.index(after: endIdx)...]
                    continue
                }
            }
            // Currency: $123.45
            if remaining.hasPrefix("$") {
                var currency = "$"
                var idx = remaining.index(after: remaining.startIndex)
                while idx < remaining.endIndex && (remaining[idx].isNumber || remaining[idx] == "," || remaining[idx] == ".") {
                    currency.append(remaining[idx])
                    idx = remaining.index(after: idx)
                }
                if currency.count > 1 {
                    var attr = AttributedString(currency)
                    attr.foregroundColor = Design.Colors.Semantic.success
                    attr.font = .system(size: 15, weight: .bold)
                    result += attr
                    remaining = remaining[idx...]
                    continue
                }
            }
            result += AttributedString(String(remaining.prefix(1)))
            remaining = remaining.dropFirst()
        }
        return result
    }

    private func parseUnorderedListItem(_ line: String) -> String? {
        for prefix in ["- ", "* ", "+ "] {
            if line.hasPrefix(prefix) { return String(line.dropFirst(2)) }
        }
        return nil
    }

    private func parseOrderedListItem(_ line: String) -> (String, String)? {
        var idx = line.startIndex
        var numStr = ""
        while idx < line.endIndex && line[idx].isNumber {
            numStr.append(line[idx])
            idx = line.index(after: idx)
        }
        guard !numStr.isEmpty, idx < line.endIndex, line[idx] == "." else { return nil }
        let afterDot = line.index(after: idx)
        guard afterDot < line.endIndex, line[afterDot] == " " else { return nil }
        return (numStr, String(line[line.index(after: afterDot)...]))
    }
}

// MARK: - Code Block View

struct CodeBlockView: View {
    let code: String
    let language: String?
    let incomplete: Bool

    @State private var copied = false

    private var lines: [String] { code.components(separatedBy: "\n") }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                if let lang = language, !lang.isEmpty {
                    Text(lang)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Design.Colors.Text.secondary)
                }
                if incomplete {
                    Text("streaming...")
                        .font(Design.Typography.caption2)
                        .foregroundStyle(Design.Colors.Semantic.warning)
                }
                Spacer()
                Button {
                    UIPasteboard.general.string = code
                    Haptics.light()
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(Design.Typography.caption2)
                        .foregroundStyle(copied ? Design.Colors.Semantic.success : Design.Colors.Text.tertiary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copy code")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Design.Colors.Glass.regular)

            // Code lines
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                    HStack(spacing: 0) {
                        Text(String(format: "%3d", idx + 1))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Design.Colors.Text.tertiary)
                            .frame(width: 32)
                            .accessibilityHidden(true)

                        Text(line.isEmpty ? " " : line)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Design.Colors.Text.primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity)
        .background(Design.Colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - Table Block View

struct TableBlockView: View {
    let headers: [String]
    let rows: [[String]]

    private var displayRows: [[String]] { Array(rows.prefix(20)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(spacing: 0) {
                ForEach(Array(headers.enumerated()), id: \.offset) { idx, header in
                    Text(header.uppercased())
                        .font(Design.Typography.caption2).fontWeight(.semibold)
                        .foregroundStyle(Design.Colors.Text.secondary)
                        .frame(maxWidth: .infinity, alignment: alignment(for: idx))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                }
            }
            .background(Design.Colors.Glass.regular)

            Divider()

            // Data rows
            ForEach(Array(displayRows.enumerated()), id: \.offset) { rowIdx, row in
                HStack(spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.offset) { colIdx, cell in
                        cellView(cell, column: colIdx)
                            .frame(maxWidth: .infinity, alignment: alignment(for: colIdx))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                    }
                }
                .background(rowIdx % 2 == 1 ? Design.Colors.Glass.ultraThin : Color.clear)
            }

            if rows.count > 20 {
                Text("\(rows.count - 20) more rows")
                    .font(Design.Typography.caption2)
                    .foregroundStyle(Design.Colors.Text.tertiary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
            }
        }
        .frame(maxWidth: .infinity)
        .background(Design.Colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Design.Colors.Border.subtle, lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func cellView(_ text: String, column: Int) -> some View {
        if isCurrency(text) {
            Text(text)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Design.Colors.Semantic.success)
        } else if isNumeric(text) {
            Text(text)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Design.Colors.Text.primary)
        } else if isStatusBadge(text) {
            Text(text)
                .font(Design.Typography.caption2).fontWeight(.medium)
                .foregroundStyle(statusColor(text))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(statusColor(text).opacity(0.12)))
        } else {
            Text(text)
                .font(Design.Typography.caption2)
                .foregroundStyle(column == 0 ? Design.Colors.Text.primary : Design.Colors.Text.secondary)
                .lineLimit(2)
        }
    }

    private func alignment(for column: Int) -> Alignment {
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
            return Design.Colors.Text.tertiary
        }
    }
}
