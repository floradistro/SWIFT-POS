//
//  UnifiedModal.swift
//  Whale
//
//  Native iOS 26 sheet-based modal system.
//  Uses presentationDetents for Liquid Glass styling.
//
//  USAGE: The modal content is presented as a native sheet.
//  Wrap your content in UnifiedModal and it handles the sheet presentation.
//

import SwiftUI
import Combine

// MARK: - Modal Manager

@MainActor
final class ModalManager: ObservableObject {
    static let shared = ModalManager()

    @Published private(set) var activeModalId: String?
    @Published private(set) var isModalOpen: Bool = false

    private init() {}

    func canOpen(id: String) -> Bool {
        activeModalId == nil || activeModalId == id
    }

    func open(id: String) {
        activeModalId = id
        isModalOpen = true
    }

    func close(id: String) {
        if activeModalId == id {
            activeModalId = nil
            isModalOpen = false
        }
    }
}

// MARK: - Unified Modal

/// A modal that presents content as a native iOS sheet.
/// Content fills naturally - NO ScrollView wrapper to avoid gesture conflicts.
/// Uses .large detent by default so content is visible without expansion.
struct UnifiedModal<Content: View>: View {
    @Binding var isPresented: Bool
    let modalId: String
    let maxWidth: CGFloat
    let dismissOnTapOutside: Bool
    let content: () -> Content

    @Environment(\.dismiss) private var dismiss

    init(
        isPresented: Binding<Bool>,
        id: String = UUID().uuidString,
        dismissOnTapOutside: Bool = true,
        maxWidth: CGFloat = 420,
        hidesDock: Bool = true,
        keyboardAvoidance: ModalKeyboardAvoidance = .standard,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self._isPresented = isPresented
        self.modalId = id
        self.maxWidth = maxWidth
        self.dismissOnTapOutside = dismissOnTapOutside
        self.content = content
    }

    var body: some View {
        // Direct content - no ScrollView wrapper to avoid gesture interception
        content()
            .frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // Use .large as default so content shows fully
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .interactiveDismissDisabled(!dismissOnTapOutside)
            .onAppear {
                ModalManager.shared.open(id: modalId)
            }
            .onDisappear {
                ModalManager.shared.close(id: modalId)
            }
    }
}

// MARK: - Keyboard Avoidance (API Compatibility)

enum ModalKeyboardAvoidance {
    case standard
    case high
}

// MARK: - Modal Close Button

struct ModalCloseButton: View {
    let action: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button {
            Haptics.light()
            action()
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
    }
}

// MARK: - Modal Back Button

struct ModalBackButton: View {
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.light()
            action()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
    }
}

// MARK: - Modal Header

struct ModalHeader<Trailing: View>: View {
    let title: String
    let subtitle: String?
    let onClose: () -> Void
    let trailing: () -> Trailing

    @Environment(\.dismiss) private var dismiss

    init(
        _ title: String,
        subtitle: String? = nil,
        onClose: @escaping () -> Void,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.onClose = onClose
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center) {
            Button {
                Haptics.light()
                onClose()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)

            Spacer()

            VStack(spacing: 4) {
                if let subtitle = subtitle {
                    Text(subtitle.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .tracking(0.5)
                }

                Text(title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Spacer()

            trailing()
                .frame(width: 44, height: 44, alignment: .center)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }
}

// MARK: - Modal Section

struct ModalSection<Content: View>: View {
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        content()
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Modal Action Button

struct ModalActionButton: View {
    let title: String
    let icon: String?
    var isEnabled: Bool = true
    var isLoading: Bool = false
    var style: ActionStyle = .primary
    let action: () -> Void

    enum ActionStyle {
        case primary
        case success
        case danger
        case glass
    }

    init(
        _ title: String,
        icon: String? = nil,
        isEnabled: Bool = true,
        isLoading: Bool = false,
        style: ActionStyle = .primary,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.isEnabled = isEnabled
        self.isLoading = isLoading
        self.style = style
        self.action = action
    }

    private var backgroundColor: Color {
        guard isEnabled else { return .gray.opacity(0.3) }
        switch style {
        case .primary: return .white
        case .success: return Color(red: 34/255, green: 197/255, blue: 94/255)
        case .danger: return Color(red: 239/255, green: 68/255, blue: 68/255)
        case .glass: return .clear
        }
    }

    private var foregroundColor: Color {
        guard isEnabled else { return .secondary }
        switch style {
        case .primary: return .black
        case .success, .danger: return .white
        case .glass: return .primary
        }
    }

    var body: some View {
        Button {
            guard isEnabled, !isLoading else { return }
            Haptics.medium()
            action()
        } label: {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView()
                        .tint(style == .primary ? .black : .white)
                        .scaleEffect(0.8)
                } else {
                    if let icon = icon {
                        Image(systemName: icon)
                            .font(.system(size: 14, weight: .semibold))
                    }
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                }
            }
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .contentShape(RoundedRectangle(cornerRadius: 14))
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(style == .glass ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(backgroundColor))
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isLoading)
    }
}

// MARK: - Modal Secondary Button

struct ModalSecondaryButton: View {
    let title: String
    var icon: String? = nil
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.light()
            action()
        } label: {
            HStack(spacing: 6) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        // iOS 26: .glassEffect provides proper interactive hit testing in sheets
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
    }
}

// MARK: - Modal Text Input

struct ModalTextInput: View {
    let placeholder: String
    @Binding var text: String
    var icon: String? = nil
    var keyboardType: UIKeyboardType = .default
    var autocapitalization: TextInputAutocapitalization = .sentences

    var body: some View {
        HStack(spacing: 10) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
            }

            TextField("", text: $text, prompt: Text(placeholder).foregroundColor(.secondary))
                .font(.system(size: 14, weight: .medium))
                .keyboardType(keyboardType)
                .textInputAutocapitalization(autocapitalization)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Modal Currency Input

struct ModalCurrencyInput: View {
    @Binding var amount: String
    var size: InputSize = .large

    enum InputSize {
        case medium, large
    }

    var body: some View {
        HStack(spacing: 4) {
            Text("$")
                .font(.system(size: size == .large ? 24 : 18, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)

            TextField("0.00", text: $amount)
                .font(.system(size: size == .large ? 24 : 18, weight: .bold, design: .rounded))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(size == .large ? .center : .leading)
        }
        .padding(.horizontal, 16)
        .frame(height: size == .large ? 56 : 44)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Modal Quick Buttons

struct ModalQuickButtons: View {
    let options: [String]
    var selected: String? = nil
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(options, id: \.self) { option in
                let isSelected = selected == option
                Button {
                    Haptics.light()
                    onSelect(option)
                } label: {
                    Text(option)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isSelected ? .black : .primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .contentShape(Capsule())
                        .background(
                            Capsule().fill(isSelected ? .white : .clear)
                        )
                        .background(.regularMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Modal Section Label

struct ModalSectionLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .tracking(0.5)
    }
}

// MARK: - Modal Info Row

struct ModalInfoRow: View {
    let label: String
    let value: String
    var valueColor: Color = .primary
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
            }

            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(valueColor)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Modal Divider

struct ModalDivider: View {
    var body: some View {
        Rectangle()
            .fill(.separator)
            .frame(height: 1)
    }
}

// MARK: - Adaptive Scroll View

struct AdaptiveScrollView<Content: View>: View {
    let maxHeight: CGFloat?
    let showsIndicators: Bool
    @ViewBuilder let content: () -> Content

    init(
        maxHeight: CGFloat? = nil,
        showsIndicators: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.maxHeight = maxHeight
        self.showsIndicators = showsIndicators
        self.content = content
    }

    var body: some View {
        ScrollView(showsIndicators: showsIndicators) {
            content()
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: maxHeight)
    }
}
