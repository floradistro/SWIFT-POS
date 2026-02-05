//
//  LiquidGlass.swift
//  Whale
//
//  iOS 26 Native Liquid Glass
//  Uses the real .glassEffect() modifier for authentic liquid glass.
//

import SwiftUI

// MARK: - Glass Intensity (for compatibility)

enum GlassIntensity {
    case subtle, light, medium, strong, solid

    var baseOpacity: CGFloat {
        switch self {
        case .subtle: return 0.02
        case .light: return 0.04
        case .medium: return 0.06
        case .strong: return 0.10
        case .solid: return 0.15
        }
    }

    var selectedOpacity: CGFloat { baseOpacity * 2 }
    var backgroundOpacity: CGFloat { baseOpacity }
    var borderOpacity: CGFloat { baseOpacity * 1.5 }
}

// MARK: - View Extensions for Native Liquid Glass

extension View {
    /// Native iOS 26 liquid glass effect
    func liquidGlass(
        cornerRadius: CGFloat = 16,
        intensity: GlassIntensity = .medium,
        isSelected: Bool = false,
        borderWidth: CGFloat = 1.5
    ) -> some View {
        self
            .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    }

    /// Native iOS 26 liquid glass capsule
    func liquidGlassCapsule(
        intensity: GlassIntensity = .medium,
        isSelected: Bool = false,
        borderWidth: CGFloat = 1.5
    ) -> some View {
        self
            .glassEffect(.regular, in: .capsule)
    }

    /// Native iOS 26 liquid glass circle
    func liquidGlassCircle(
        intensity: GlassIntensity = .medium,
        isSelected: Bool = false,
        borderWidth: CGFloat = 1.5
    ) -> some View {
        self
            .glassEffect(.regular, in: .circle)
    }

    // Legacy compatibility
    func glassBackground(intensity: GlassIntensity = .medium, cornerRadius: CGFloat = 16) -> some View {
        liquidGlass(cornerRadius: cornerRadius, intensity: intensity)
    }

    func glassCapsule(intensity: GlassIntensity = .medium) -> some View {
        liquidGlassCapsule(intensity: intensity)
    }

    func glassCircle(intensity: GlassIntensity = .medium) -> some View {
        liquidGlassCircle(intensity: intensity)
    }
}

// MARK: - Liquid Press Style

struct LiquidPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Liquid Glass Search Bar

struct LiquidGlassSearchBar: View {
    let placeholder: String
    @Binding var text: String
    var onClear: (() -> Void)?

    @FocusState private var isFocused: Bool

    init(
        _ placeholder: String = "Search...",
        text: Binding<String>,
        onClear: (() -> Void)? = nil
    ) {
        self.placeholder = placeholder
        self._text = text
        self.onClear = onClear
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(isFocused ? .white : .white.opacity(0.5))

            TextField(placeholder, text: $text)
                .font(.system(size: 17))
                .foregroundStyle(.white)
                .focused($isFocused)
                .submitLabel(.search)

            if !text.isEmpty {
                Button {
                    Haptics.light()
                    text = ""
                    onClear?()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, text.isEmpty ? 14 : 4)
        .frame(height: 44)
        .glassEffect(.regular.interactive(), in: .capsule)
    }
}

// MARK: - Liquid Glass Pill (Filter Chip)

struct LiquidGlassPill: View {
    let label: String
    var icon: String?
    var count: Int?
    var color: Color?
    let isSelected: Bool
    let action: () -> Void

    init(
        _ label: String,
        icon: String? = nil,
        count: Int? = nil,
        color: Color? = nil,
        isSelected: Bool = false,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.icon = icon
        self.count = count
        self.color = color
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button {
            Haptics.light()
            action()
        } label: {
            HStack(spacing: 4) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .semibold))
                }

                if let color = color {
                    Circle()
                        .fill(color)
                        .frame(width: 6, height: 6)
                }

                Text(label)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))

                if let count = count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.fill.tertiary, in: .capsule)
                }
            }
            .foregroundStyle(isSelected ? .white : .white.opacity(0.5))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                isSelected ? .white.opacity(0.15) : Color.clear,
                in: .capsule
            )
        }
        .tint(.white)
        .glassEffect(.regular.interactive(), in: .capsule)
    }
}

// MARK: - Liquid Glass Icon Button
//
// IMPORTANT: Apple HIG requires 44×44pt minimum touch targets
// Reference: https://developer.apple.com/design/human-interface-guidelines/buttons
//
// CRITICAL: .glassEffect() has a touch target bug - only the content (icon) is tappable,
// not the full glass circle. The fix is adding .contentShape() to define the full tap area.
// Reference: https://juniperphoton.substack.com/p/adopting-liquid-glass-experiences

struct LiquidGlassIconButton: View {
    let icon: String
    var size: CGFloat = 44  // Apple HIG minimum: 44pt
    var iconSize: CGFloat?
    var badge: Int?
    var badgeColor: Color = Design.Colors.Semantic.accent
    var isSelected: Bool = false
    var tintColor: Color = .white
    let action: () -> Void

    // Computed icon size: ~40% of button size looks balanced
    private var computedIconSize: CGFloat {
        iconSize ?? (size * 0.40)
    }

    var body: some View {
        Button {
            Haptics.light()
            action()
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: icon)
                    .font(.system(size: computedIconSize, weight: .semibold))
                    .foregroundStyle(isSelected ? Design.Colors.Semantic.accent : tintColor)
                    .frame(width: size, height: size)

                if let badge = badge, badge > 0 {
                    Text("\(min(badge, 99))")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(badgeColor, in: Circle())
                        .offset(x: 6, y: -6)
                }
            }
            // contentShape inside label for proper hit testing
            .contentShape(Circle())
        }
        .buttonStyle(LiquidPressStyle())
        // CRITICAL: .glassEffect provides both visual appearance AND interactive hit testing
        .glassEffect(.regular.interactive(), in: .circle)
    }
}

// MARK: - Modal Icon Button (Back/Close buttons in modals)
// Standard 44pt size, consistent across all modals

struct ModalIconButton: View {
    let icon: String
    var tintColor: Color = .white.opacity(0.7)
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.light()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tintColor)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(LiquidPressStyle())
        .glassEffect(.regular.interactive(), in: .circle)
    }
}

// MARK: - Glass Button Style (Native iOS 26)

struct GlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Liquid Glass Button (Full Width)

struct LiquidGlassButton: View {
    let title: String
    var icon: String?
    var style: Style = .secondary
    var isFullWidth: Bool = true
    let action: () -> Void

    enum Style {
        case primary
        case secondary
        case ghost
        case destructive
        case success

        var tintColor: Color {
            switch self {
            case .primary: return Design.Colors.Semantic.accent
            case .secondary: return .primary
            case .ghost: return .secondary
            case .destructive: return Design.Colors.Semantic.error
            case .success: return Design.Colors.Semantic.success
            }
        }
    }

    var body: some View {
        Button {
            Haptics.medium()
            action()
        } label: {
            HStack(spacing: 8) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(style.tintColor)
            .frame(maxWidth: isFullWidth ? .infinity : nil)
            .padding(.horizontal, isFullWidth ? 16 : 20)
            .padding(.vertical, 14)
            // contentShape inside label for proper hit testing
            .contentShape(Capsule())
        }
        .buttonStyle(LiquidPressStyle())
        // CRITICAL: .glassEffect provides both visual appearance AND interactive hit testing
        .glassEffect(.regular.interactive(), in: .capsule)
    }
}

// MARK: - Liquid Glass Card

struct LiquidGlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 20
    var padding: CGFloat = 16
    var intensity: GlassIntensity = .medium
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    }
}

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
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isFocused ? .primary : .secondary)
                    .frame(width: 24)
            }

            TextField(placeholder, text: $text)
                .font(.system(size: 16))
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
                        .stroke(.white.opacity(0.15), lineWidth: 0.5)
                )
        }
        .compositingGroup()  // Flatten layers for GPU efficiency
        .shadow(color: .black.opacity(0.35), radius: 20, y: 10)
    }
}

// MARK: - Legacy Compatibility Aliases

typealias GlassPill = LiquidGlassPill
typealias GlassSearchBar = LiquidGlassSearchBar
typealias GlassIconButton = LiquidGlassIconButton
typealias GlassButton = LiquidGlassButton
typealias GlassCard = LiquidGlassCard
typealias GlassTextField = LiquidGlassTextField

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
            }
            Text(text)
                .font(.system(size: 11, weight: .semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .glassEffect(.regular, in: .capsule)
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
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .glassEffect(.regular.interactive(), in: .capsule)
    }
}

struct GlassCurrencyField: View {
    @Binding var amount: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text("$")
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(.secondary)

            TextField("0.00", text: $amount)
                .font(.system(size: 36, weight: .bold))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.leading)
                .focused($isFocused)
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

// MARK: - Preview

#Preview("iOS 26 Native Liquid Glass") {
    ScrollView {
        VStack(spacing: 24) {
            // Search Bar
            VStack(alignment: .leading, spacing: 8) {
                Text("Search Bar")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LiquidGlassSearchBar("Search products...", text: .constant(""))
            }

            // Pills / Filters
            VStack(alignment: .leading, spacing: 8) {
                Text("Filter Pills")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        LiquidGlassPill("All", count: 42, isSelected: true) {}
                        LiquidGlassPill("Active", icon: "clock", count: 12, isSelected: false) {}
                        LiquidGlassPill("Completed", isSelected: false) {}
                    }
                }
            }

            // Icon Buttons
            VStack(alignment: .leading, spacing: 8) {
                Text("Icon Buttons")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    LiquidGlassIconButton(icon: "line.3.horizontal.decrease.circle", badge: 3) {}
                    LiquidGlassIconButton(icon: "plus") {}
                    LiquidGlassIconButton(icon: "qrcode.viewfinder", isSelected: true) {}
                }
            }

            // Buttons
            VStack(alignment: .leading, spacing: 8) {
                Text("Buttons")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LiquidGlassButton(title: "Primary", icon: "checkmark", style: .primary) {}
                LiquidGlassButton(title: "Secondary", style: .secondary) {}
                LiquidGlassButton(title: "Success", icon: "checkmark.circle", style: .success) {}
            }

            // Card
            LiquidGlassCard {
                VStack(spacing: 8) {
                    Text("Liquid Glass Card")
                        .font(.headline)
                    Text("Real iOS 26 glass effect")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(20)
    }
    .background(Color.black)
    .preferredColorScheme(.dark)
}
