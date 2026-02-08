//
//  LiquidGlassInputs.swift
//  Whale
//
//  Input components, currency fields, and fade mask modifiers
//  extracted from LiquidGlass.swift.
//

import SwiftUI

// MARK: - Liquid Glass Text Field

struct LiquidGlassTextField: View {
    let placeholder: String
    @Binding var text: String
    var icon: String?
    var keyboardType: UIKeyboardType = .default
    @FocusState private var isFocused: Bool

    init(
        _ placeholder: String,
        text: Binding<String>,
        icon: String? = nil,
        keyboardType: UIKeyboardType = .default
    ) {
        self.placeholder = placeholder
        self._text = text
        self.icon = icon
        self.keyboardType = keyboardType
    }

    var body: some View {
        HStack(spacing: 12) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(Design.Typography.callout).fontWeight(.medium)
                    .foregroundStyle(isFocused ? .primary : .secondary)
                    .frame(width: 24)
                    .accessibilityHidden(true)
            }

            TextField(placeholder, text: $text)
                .font(Design.Typography.callout)
                .keyboardType(keyboardType)
                .focused($isFocused)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
    }
}

// MARK: - Glass Dock Container
// Per Apple docs: "Glass cannot sample other glass"
// Solution: Use .regularMaterial for container, .glassEffect for buttons inside
// GlassEffectContainer groups the glass buttons for shared sampling region

struct GlassDockContainer<Content: View>: View {
    let cornerRadius: CGFloat
    let content: Content

    init(
        cornerRadius: CGFloat = 28,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        // Simplified: GlassEffectContainer enables glass buttons inside
        // Removed expensive gradient overlay for better performance
        GlassEffectContainer(spacing: 8) {
            content
                .background(
                    .regularMaterial,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Design.Colors.Border.strong, lineWidth: 0.5)
                )
        }
        .compositingGroup()  // Flatten layers for GPU efficiency
        .shadow(color: .black.opacity(0.35), radius: 20, y: 10)
    }
}

// MARK: - Additional Components

struct GlassChip: View {
    let text: String
    let color: Color?

    init(_ text: String, color: Color? = nil) {
        self.text = text
        self.color = color
    }

    var body: some View {
        HStack(spacing: 5) {
            if let color = color {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(Design.Typography.caption2).fontWeight(.semibold)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .combine)
    }
}

struct GlassQuickAmount: View {
    let amount: Int
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.light()
            action()
        } label: {
            Text("$\(amount)")
                .font(Design.Typography.subhead).fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .glassEffect(.regular.interactive(), in: .capsule)
        .accessibilityLabel("Add \(amount) dollars")
    }
}

struct GlassCurrencyField: View {
    @Binding var amount: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text("$")
                .font(Design.Typography.priceHero).fontWeight(.bold)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField("0.00", text: $amount)
                .font(Design.Typography.priceHero).fontWeight(.bold)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.leading)
                .focused($isFocused)
                .accessibilityLabel("Dollar amount")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
    }
}

// MARK: - Top Fade Gradient (Overlay approach)

/// Reusable top fade gradient that fades content scrolling behind headers
/// Place this in a ZStack BETWEEN scrolling content and header for correct z-ordering
struct TopFadeGradient: View {
    var fadeHeight: CGFloat = 80

    var body: some View {
        GeometryReader { geo in
            let safeTop = geo.safeAreaInsets.top

            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black.opacity(0.85), location: 0.4),
                    .init(color: .black.opacity(0.5), location: 0.7),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: geo.size.width, height: safeTop + fadeHeight)
            .position(x: geo.size.width / 2, y: (safeTop + fadeHeight) / 2)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Top Fade Mask (Apple's approach)

/// Apply this to ScrollView to fade content at the top edge of screen
/// This is how Apple achieves the effect - content fades behind status bar, headers stay visible
struct TopFadeMask: ViewModifier {
    var fadeHeight: CGFloat = 60  // Height of fade zone from top of screen

    func body(content: Content) -> some View {
        content
            .mask(
                GeometryReader { geo in
                    let safeTop = geo.safeAreaInsets.top

                    VStack(spacing: 0) {
                        // Fade zone starting from very top of screen (behind status bar)
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .black.opacity(0.3), location: 0.4),
                                .init(color: .black, location: 1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: safeTop + fadeHeight)

                        // Rest is fully visible
                        Color.black
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .ignoresSafeArea()
            )
    }
}

struct BottomFadeMask: ViewModifier {
    var fadeHeight: CGFloat = 60  // Height of fade zone from bottom of screen

    func body(content: Content) -> some View {
        content
            .mask(
                GeometryReader { geo in
                    let safeBottom = geo.safeAreaInsets.bottom

                    VStack(spacing: 0) {
                        // Rest is fully visible
                        Color.black

                        // Fade zone at bottom of screen
                        LinearGradient(
                            stops: [
                                .init(color: .black, location: 0),
                                .init(color: .black.opacity(0.3), location: 0.6),
                                .init(color: .clear, location: 1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: safeBottom + fadeHeight)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
                .ignoresSafeArea()
            )
    }
}

struct TopBottomFadeMask: ViewModifier {
    var topFadeHeight: CGFloat = 60
    var bottomFadeHeight: CGFloat = 60

    func body(content: Content) -> some View {
        content
            .mask(
                GeometryReader { geo in
                    let safeTop = geo.safeAreaInsets.top
                    let safeBottom = geo.safeAreaInsets.bottom

                    VStack(spacing: 0) {
                        // Top fade zone
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .black.opacity(0.3), location: 0.4),
                                .init(color: .black, location: 1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: safeTop + topFadeHeight)

                        // Middle is fully visible
                        Color.black

                        // Bottom fade zone
                        LinearGradient(
                            stops: [
                                .init(color: .black, location: 0),
                                .init(color: .black.opacity(0.3), location: 0.6),
                                .init(color: .clear, location: 1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: safeBottom + bottomFadeHeight)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .ignoresSafeArea()
            )
    }
}

extension View {
    /// Apple-style top fade mask for ScrollViews
    /// Content fades at the very top edge of screen (behind status bar)
    func topFadeMask(fadeHeight: CGFloat = 60) -> some View {
        modifier(TopFadeMask(fadeHeight: fadeHeight))
    }

    /// Apple-style bottom fade mask for ScrollViews
    /// Content fades at the very bottom edge of screen
    func bottomFadeMask(fadeHeight: CGFloat = 60) -> some View {
        modifier(BottomFadeMask(fadeHeight: fadeHeight))
    }

    /// Apple-style top and bottom fade mask for ScrollViews
    /// Content fades at both top and bottom edges
    func topBottomFadeMask(topFadeHeight: CGFloat = 60, bottomFadeHeight: CGFloat = 60) -> some View {
        modifier(TopBottomFadeMask(topFadeHeight: topFadeHeight, bottomFadeHeight: bottomFadeHeight))
    }
}
