//
//  GlassCard.swift
//  Whale
//
//  Legacy compatibility layer for glass-morphism styling.
//  All components now use the unified LiquidGlass.swift system.
//
//  DEPRECATED: Use LiquidGlass components directly:
//  - .glassBackground() instead of .glassCard()
//  - .glassCapsule() instead of .glassPill()
//  - GlassCard {} instead of custom modifiers
//

import SwiftUI

// MARK: - Legacy Glass Card Modifier (Compatibility)

/// Applies glass-morphism card styling - now uses unified GlassBackground
struct GlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    let opacity: CGFloat
    let borderOpacity: CGFloat
    let includeShadow: Bool

    init(
        cornerRadius: CGFloat = Design.Radius.lg,
        opacity: CGFloat = 0.3,
        borderOpacity: CGFloat = 0.1,
        includeShadow: Bool = true
    ) {
        self.cornerRadius = cornerRadius
        self.opacity = opacity
        self.borderOpacity = borderOpacity
        self.includeShadow = includeShadow
    }

    func body(content: Content) -> some View {
        content
            .glassBackground(intensity: intensityFromOpacity, cornerRadius: cornerRadius)
            .if(includeShadow) { view in
                view.shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
            }
    }

    private var intensityFromOpacity: GlassIntensity {
        switch opacity {
        case 0..<0.05: return .subtle
        case 0.05..<0.08: return .light
        case 0.08..<0.12: return .medium
        case 0.12..<0.18: return .strong
        default: return .solid
        }
    }
}

// MARK: - Legacy Glass Input Modifier (Compatibility)

/// Applies glass-morphism styling for input fields
struct GlassInputModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Design.Spacing.md)
            .glassBackground(intensity: .medium, cornerRadius: Design.Radius.md)
    }
}

// MARK: - Legacy Glass Pill Modifier (Compatibility)

/// Applies glass-morphism styling for pill/capsule shapes
struct GlassPillModifier: ViewModifier {
    let opacity: CGFloat
    let borderOpacity: CGFloat

    init(opacity: CGFloat = 0.3, borderOpacity: CGFloat = 0.1) {
        self.opacity = opacity
        self.borderOpacity = borderOpacity
    }

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, Design.Spacing.md)
            .padding(.vertical, Design.Spacing.xs)
            .glassCapsule(intensity: intensityFromOpacity)
    }

    private var intensityFromOpacity: GlassIntensity {
        switch opacity {
        case 0..<0.05: return .subtle
        case 0.05..<0.08: return .light
        case 0.08..<0.12: return .medium
        case 0.12..<0.18: return .strong
        default: return .solid
        }
    }
}

// MARK: - Legacy Glass Badge Modifier (Compatibility)

/// Applies glass-morphism styling for small badges
struct GlassBadgeModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(Design.Typography.caption2)
            .foregroundStyle(Design.Colors.Text.disabled)
            .padding(.horizontal, Design.Spacing.xs)
            .padding(.vertical, Design.Spacing.xxxs)
            .glassCapsule(intensity: .light)
    }
}

// MARK: - View Extensions (Legacy Compatibility)

extension View {
    /// Applies glass card styling (legacy - use .glassBackground() instead)
    func glassCard(
        cornerRadius: CGFloat = Design.Radius.lg,
        opacity: CGFloat = 0.3,
        borderOpacity: CGFloat = 0.1,
        includeShadow: Bool = true
    ) -> some View {
        modifier(GlassCardModifier(
            cornerRadius: cornerRadius,
            opacity: opacity,
            borderOpacity: borderOpacity,
            includeShadow: includeShadow
        ))
    }

    /// Applies glass input field styling (legacy - use GlassTextField instead)
    func glassInput() -> some View {
        modifier(GlassInputModifier())
    }

    /// Applies glass pill styling (legacy - use .glassCapsule() instead)
    func glassPill(opacity: CGFloat = 0.3, borderOpacity: CGFloat = 0.1) -> some View {
        modifier(GlassPillModifier(opacity: opacity, borderOpacity: borderOpacity))
    }

    /// Applies glass badge styling (legacy - use GlassChip instead)
    func glassBadge() -> some View {
        modifier(GlassBadgeModifier())
    }

    /// Conditional modifier helper
    @ViewBuilder
    func `if`<Transform: View>(_ condition: Bool, transform: (Self) -> Transform) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Design.Colors.backgroundPrimary.ignoresSafeArea()

        VStack(spacing: Design.Spacing.lg) {
            // Glass Card (legacy)
            VStack {
                Text("Legacy Glass Card")
                    .font(Design.Typography.headline)
                    .foregroundStyle(Design.Colors.Text.primary)
            }
            .padding(Design.Spacing.lg)
            .frame(maxWidth: .infinity)
            .glassCard()
            .padding(.horizontal)

            // Glass Input (legacy)
            HStack {
                Image(systemName: "envelope.fill")
                    .foregroundStyle(Design.Colors.Text.subtle)
                Text("Legacy glass input")
                    .foregroundStyle(Design.Colors.Text.primary)
            }
            .glassInput()
            .padding(.horizontal)

            // Glass Pill (legacy)
            Text("Legacy Pill")
                .font(Design.Typography.subhead)
                .foregroundStyle(Design.Colors.Text.secondary)
                .glassPill()

            // Glass Badge (legacy)
            Text("Badge")
                .glassBadge()
        }
    }
    .preferredColorScheme(.dark)
}
