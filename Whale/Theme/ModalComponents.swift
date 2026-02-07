//
//  ModalComponents.swift
//  Whale
//
//  Reusable modal/sheet component styles.
//  Extracted from the deprecated UnifiedModal system.
//

import SwiftUI

// MARK: - Modal Section

struct ModalSection<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.06)))
    }
}

// MARK: - Modal Header

struct ModalHeader<Trailing: View>: View {
    let title: String
    let subtitle: String?
    let onClose: () -> Void
    @ViewBuilder let trailing: Trailing

    init(_ title: String, subtitle: String? = nil, onClose: @escaping () -> Void, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.onClose = onClose
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center) {
            ModalCloseButton(action: onClose)
            Spacer()
            VStack(spacing: 2) {
                if let subtitle = subtitle {
                    Text(subtitle.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.4))
                        .tracking(0.5)
                }
                Text(title)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            Spacer()
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }
}

extension ModalHeader where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil, onClose: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.onClose = onClose
        self.trailing = EmptyView()
    }
}

// MARK: - Modal Close Button

struct ModalCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.light()
            action()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 44, height: 44)
                .background(Circle().fill(.white.opacity(0.1)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
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
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 44, height: 44)
                .background(Circle().fill(.white.opacity(0.1)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
    }
}

// MARK: - Modal Action Button

struct ModalActionButton: View {
    enum Style {
        case primary
        case success
        case destructive
        case glass

        var backgroundColor: Color {
            switch self {
            case .primary: return .white.opacity(0.15)
            case .success: return Color(red: 0.2, green: 0.78, blue: 0.35).opacity(0.25)
            case .destructive: return Color(red: 0.95, green: 0.3, blue: 0.3).opacity(0.25)
            case .glass: return .white.opacity(0.1)
            }
        }

        var foregroundColor: Color {
            switch self {
            case .primary: return .white
            case .success: return Color(red: 0.3, green: 0.95, blue: 0.5)
            case .destructive: return Color(red: 1.0, green: 0.4, blue: 0.4)
            case .glass: return .white.opacity(0.8)
            }
        }
    }

    let title: String
    var icon: String? = nil
    var isEnabled: Bool = true
    var isLoading: Bool = false
    var style: Style = .primary
    let action: () -> Void

    init(_ title: String, icon: String? = nil, isEnabled: Bool = true, isLoading: Bool = false, style: Style = .primary, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.isEnabled = isEnabled
        self.isLoading = isLoading
        self.style = style
        self.action = action
    }

    var body: some View {
        Button {
            guard !isLoading && isEnabled else { return }
            Haptics.medium()
            action()
        } label: {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView().scaleEffect(0.8).tint(style.foregroundColor)
                } else {
                    if let icon = icon {
                        Image(systemName: icon)
                            .font(.system(size: 14, weight: .semibold))
                    }
                    Text(title)
                        .font(.system(size: 15, weight: .bold))
                }
            }
            .foregroundStyle(style.foregroundColor)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(style.backgroundColor))
            .opacity(isEnabled ? 1.0 : 0.5)
        }
        .buttonStyle(.plain)
        .disabled(isLoading || !isEnabled)
        .accessibilityLabel(isLoading ? "\(title), loading" : title)
    }
}

// MARK: - Modal Secondary Button

struct ModalSecondaryButton: View {
    let title: String
    var icon: String? = nil
    let action: () -> Void

    init(title: String, icon: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.action = action
    }

    var body: some View {
        Button {
            Haptics.light()
            action()
        } label: {
            HStack(spacing: 6) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .medium))
                }
                Text(title)
                    .font(.system(size: 15, weight: .medium))
            }
            .foregroundStyle(.white.opacity(0.6))
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Modal Info Row

struct ModalInfoRow: View {
    let label: String
    let value: String
    var valueColor: Color = .white

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.5))
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(valueColor)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Modal Text Input

struct ModalTextInput: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        TextField(placeholder, text: $text)
            .font(.system(size: 14))
            .foregroundStyle(.white)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.08), lineWidth: 1))
    }
}

// MARK: - Modal Section Label

struct ModalSectionLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white.opacity(0.5))
            .textCase(.uppercase)
            .tracking(0.5)
    }
}

// MARK: - Adaptive Scroll View

struct AdaptiveScrollView<Content: View>: View {
    let maxHeight: CGFloat
    @ViewBuilder let content: Content

    init(maxHeight: CGFloat = 300, @ViewBuilder content: () -> Content) {
        self.maxHeight = maxHeight
        self.content = content()
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            content
        }
        .frame(maxHeight: maxHeight)
    }
}
