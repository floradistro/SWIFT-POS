//
//  ChatInputBar.swift
//  Whale
//
//  iMessage-style message input bar with @mentions, attachments, and image picker.
//  Extracted from TeamChatPanel.
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers
import os.log

// MARK: - Message Input Bar (iMessage style with @mentions)

struct MessageInputBar: View {
    @ObservedObject var chatStore: ChatStore
    @FocusState.Binding var isInputFocused: Bool
    var onSend: () -> Void

    @State private var showImagePicker = false
    @State private var showFilePicker = false

    private var canSend: Bool {
        let hasText = !chatStore.composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasAttachments = !chatStore.composerAttachments.isEmpty
        return (hasText || hasAttachments) && !chatStore.isAgentStreaming
    }

    private var isStreaming: Bool { chatStore.isAgentStreaming }

    // Check if typing @mention and get filtered agents
    private var mentionQuery: String? {
        let text = chatStore.composerText
        guard let atIndex = text.lastIndex(of: "@") else { return nil }
        let afterAt = String(text[text.index(after: atIndex)...])
        // Only show if no space yet (still typing the name)
        guard !afterAt.contains(" ") else { return nil }
        return afterAt.lowercased()
    }

    private var filteredAgents: [AIAgent] {
        guard let query = mentionQuery else { return [] }
        if query.isEmpty {
            return chatStore.agents
        }
        // Filter by prefix first, then contains
        let prefixMatches = chatStore.agents.filter { $0.displayName.lowercased().hasPrefix(query) }
        if !prefixMatches.isEmpty { return prefixMatches }
        return chatStore.agents.filter { $0.displayName.lowercased().contains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Agent suggestions (appears above input when typing @)
            if mentionQuery != nil && !filteredAgents.isEmpty {
                agentSuggestions
            }

            // Attachments preview
            if !chatStore.composerAttachments.isEmpty {
                attachmentsPreview
            }

            // Input row
            HStack(alignment: .center, spacing: 8) {
                // Plus button
                Menu {
                    // Agents section
                    Section("Agents") {
                        ForEach(chatStore.agents) { agent in
                            Button {
                                chatStore.composerText += "@\(agent.displayName) "
                                Haptics.selection()
                            } label: {
                                Label(agent.displayName, systemImage: agent.displayIcon)
                            }
                        }
                    }

                    Section("Attachments") {
                        Button {
                            showImagePicker = true
                        } label: {
                            Label("Photo Library", systemImage: "photo.on.rectangle")
                        }
                        Button {
                            showFilePicker = true
                        } label: {
                            Label("Document", systemImage: "doc")
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(Design.Typography.title3)
                        .fontWeight(.medium)
                        .foregroundStyle(isStreaming ? Design.Colors.Text.tertiary : Design.Colors.Text.primary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .disabled(isStreaming)
                .accessibilityLabel("Add attachment or mention agent")

                // Text input
                HStack(alignment: .center, spacing: 0) {
                    TextField("Message", text: $chatStore.composerText, axis: .vertical)
                        .font(Design.Typography.body)
                        .lineLimit(1...6)
                        .focused($isInputFocused)
                        .disabled(isStreaming)
                        .onSubmit {
                            // If showing suggestions, select first one on Enter
                            if mentionQuery != nil, let first = filteredAgents.first {
                                selectAgent(first)
                            } else if canSend {
                                send()
                            }
                        }

                    // Send button
                    if canSend {
                        Button { send() } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(Design.Colors.Semantic.accent)
                        }
                        .buttonStyle(.plain)
                        .transition(.scale.combined(with: .opacity))
                        .padding(.leading, 8)
                        .accessibilityLabel("Send message")
                    }
                }
                .padding(.leading, 16)
                .padding(.trailing, canSend ? 6 : 16)
                .padding(.vertical, 8)
                .glassEffect(.regular.interactive(), in: .capsule)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: canSend)
        }
        .background(Design.Colors.backgroundPrimary.opacity(0.001))
        .sheet(isPresented: $showImagePicker) {
            ChatImagePicker(chatStore: chatStore, onComplete: {})
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.pdf, .image],
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result)
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusChatInput)) { _ in
            isInputFocused = true
        }
    }

    // MARK: - Agent Suggestions (compact row above input)

    private var agentSuggestions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(filteredAgents.prefix(5)) { agent in
                    Button {
                        selectAgent(agent)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: agent.displayIcon)
                                .font(Design.Typography.caption2)
                                .foregroundStyle(Design.Colors.Semantic.accent)
                                .accessibilityHidden(true)
                            Text(agent.displayName)
                                .font(Design.Typography.caption1)
                                .fontWeight(.medium)
                                .foregroundStyle(Design.Colors.Text.primary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Design.Colors.Glass.regular)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private func selectAgent(_ agent: AIAgent) {
        // Replace @partial with @AgentName
        if let atIndex = chatStore.composerText.lastIndex(of: "@") {
            let beforeAt = String(chatStore.composerText[..<atIndex])
            chatStore.composerText = beforeAt + "@\(agent.displayName) "
        } else {
            chatStore.composerText += "@\(agent.displayName) "
        }
        Haptics.selection()
    }

    private var attachmentsPreview: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chatStore.composerAttachments) { attachment in
                    attachmentThumbnail(attachment)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private func attachmentThumbnail(_ attachment: ChatAttachment) -> some View {
        ZStack(alignment: .topTrailing) {
            if let data = attachment.thumbnail, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Design.Colors.Glass.regular)
                    .frame(width: 60, height: 60)
                    .overlay(
                        Image(systemName: attachment.icon)
                            .foregroundStyle(Design.Colors.Text.secondary)
                    )
            }

            Button {
                chatStore.removeAttachment(attachment.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Design.Colors.Text.primary, Design.Colors.Glass.thick)
            }
            .offset(x: 6, y: -6)
        }
    }

    private func send() {
        Haptics.medium()
        Task {
            await chatStore.sendMessage()
            onSend()
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                guard chatStore.composerAttachments.count < ChatStore.maxAttachments else { break }
                guard url.startAccessingSecurityScopedResource() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }

                do {
                    let data = try Data(contentsOf: url)
                    let fileName = url.lastPathComponent
                    let isPDF = url.pathExtension.lowercased() == "pdf"

                    let attachment = ChatAttachment(
                        type: isPDF ? .pdf : .image,
                        fileName: fileName,
                        data: data,
                        thumbnail: isPDF ? nil : data,
                        pageCount: isPDF ? getPDFPageCount(data) : nil
                    )
                    chatStore.addAttachment(attachment)
                } catch {
                    Log.ui.error("Failed to read file: \(error)")
                }
            }
        case .failure(let error):
            Log.ui.error("File picker error: \(error)")
        }
    }

    private func getPDFPageCount(_ data: Data) -> Int? {
        guard let provider = CGDataProvider(data: data as CFData),
              let pdf = CGPDFDocument(provider) else { return nil }
        return pdf.numberOfPages
    }
}

// MARK: - Chat Attachment Picker

struct ChatAttachmentPicker: View {
    @ObservedObject var chatStore: ChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var showImagePicker = false
    @State private var showFilePicker = false

    var body: some View {
        NavigationStack {
            List {
                Button {
                    showImagePicker = true
                } label: {
                    Label("Photo Library", systemImage: "photo.on.rectangle")
                }

                Button {
                    showFilePicker = true
                } label: {
                    Label("Document", systemImage: "doc")
                }
            }
            .navigationTitle("Attach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showImagePicker) {
                ChatImagePicker(chatStore: chatStore, onComplete: { dismiss() })
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.pdf, .image],
                allowsMultipleSelection: true
            ) { result in
                handleFileImport(result)
            }
        }
        .presentationDetents([.medium])
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                guard chatStore.composerAttachments.count < ChatStore.maxAttachments else { break }
                guard url.startAccessingSecurityScopedResource() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }

                do {
                    let data = try Data(contentsOf: url)
                    let fileName = url.lastPathComponent
                    let isPDF = url.pathExtension.lowercased() == "pdf"

                    let attachment = ChatAttachment(
                        type: isPDF ? .pdf : .image,
                        fileName: fileName,
                        data: data,
                        thumbnail: isPDF ? nil : data,
                        pageCount: isPDF ? getPDFPageCount(data) : nil
                    )
                    chatStore.addAttachment(attachment)
                } catch {
                    Log.ui.error("Failed to read file: \(error)")
                }
            }
            dismiss()
        case .failure(let error):
            Log.ui.error("File picker error: \(error)")
        }
    }

    private func getPDFPageCount(_ data: Data) -> Int? {
        guard let provider = CGDataProvider(data: data as CFData),
              let pdf = CGPDFDocument(provider) else { return nil }
        return pdf.numberOfPages
    }
}

// MARK: - Chat Image Picker

struct ChatImagePicker: UIViewControllerRepresentable {
    @ObservedObject var chatStore: ChatStore
    let onComplete: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ChatImagePicker

        init(_ parent: ChatImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage,
               let data = image.jpegData(compressionQuality: 0.8) {

                let thumbnailSize = CGSize(width: 100, height: 100)
                let thumbnail = image.preparingThumbnail(of: thumbnailSize)
                let thumbnailData = thumbnail?.jpegData(compressionQuality: 0.6)

                let fileName = "image_\(Date().timeIntervalSince1970).jpg"
                let attachment = ChatAttachment(
                    type: .image,
                    fileName: fileName,
                    data: data,
                    thumbnail: thumbnailData
                )
                parent.chatStore.addAttachment(attachment)
            }
            parent.onComplete()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onComplete()
        }
    }
}
