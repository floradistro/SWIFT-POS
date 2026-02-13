//
//  StreamingTextView.swift
//  Whale
//
//  Streaming text renderer — plain Text() during streaming for performance.
//  Markdown parsing happens once on completion when ChatStore replaces the
//  transient message with a real ChatMessage rendered via MarkdownContentView.
//

import SwiftUI

struct StreamingTextView: View {
    @ObservedObject var buffer: StreamingTextBuffer

    var body: some View {
        if !buffer.text.isEmpty {
            Text(buffer.text)
                .font(Design.Typography.subhead)
                .foregroundStyle(Design.Colors.Text.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
