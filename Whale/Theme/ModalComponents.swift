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
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Design.Colors.Border.subtle))
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
                        .font(Design.Typography.caption2).fontWeight(.bold)
                        .foregroundStyle(Design.Colors.Text.subtle)
                        .tracking(0.5)
                }
                Text(title)
                    .font(Design.Typography.title3Rounded).fontWeight(.bold)
                    .foregroundStyle(Design.Colors.Text.primary)
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
                .font(Design.Typography.footnote).fontWeight(.semibold)
                .foregroundStyle(Design.Colors.Text.quaternary)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Design.Colors.Glass.thick))
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
                .font(Design.Typography.footnote).fontWeight(.semibold)
                .foregroundStyle(Design.Colors.Text.quaternary)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Design.Colors.Glass.thick))
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
            case .primary: return Design.Colors.Glass.ultraThick
            case .success: return Color(red: 0.2, green: 0.78, blue: 0.35).opacity(0.25)
            case .destructive: return Color(red: 0.95, green: 0.3, blue: 0.3).opacity(0.25)
            case .glass: return Design.Colors.Glass.thick
            }
        }

        var foregroundColor: Color {
            switch self {
            case .primary: return Design.Colors.Text.primary
            case .success: return Color(red: 0.3, green: 0.95, blue: 0.5)
            case .destructive: return Color(red: 1.0, green: 0.4, blue: 0.4)
            case .glass: return Design.Colors.Text.tertiary
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
                            .font(Design.Typography.footnote).fontWeight(.semibold)
                    }
                    Text(title)
                        .font(Design.Typography.subhead).fontWeight(.bold)
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
                        .font(Design.Typography.footnote).fontWeight(.medium)
                }
                Text(title)
                    .font(Design.Typography.subhead).fontWeight(.medium)
            }
            .foregroundStyle(Design.Colors.Text.quaternary)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(Design.Colors.Glass.regular, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Modal Info Row

struct ModalInfoRow: View {
    let label: String
    let value: String
    var valueColor: Color = Design.Colors.Text.primary

    var body: some View {
        HStack {
            Text(label)
                .font(Design.Typography.footnote)
                .foregroundStyle(Design.Colors.Text.disabled)
            Spacer()
            Text(value)
                .font(Design.Typography.footnote).fontWeight(.medium)
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
            .font(Design.Typography.footnote)
            .foregroundStyle(Design.Colors.Text.primary)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Design.Colors.Border.subtle))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Design.Colors.Border.regular, lineWidth: 1))
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
            .font(Design.Typography.caption1).fontWeight(.semibold)
            .foregroundStyle(Design.Colors.Text.disabled)
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
