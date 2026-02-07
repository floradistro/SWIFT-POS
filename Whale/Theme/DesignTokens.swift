//
//  DesignTokens.swift
//  Whale
//
//  Apple-inspired design system for POS.
//  Single source of truth for all visual styling.
//
//  Philosophy:
//  - Simplicity: One way to do things
//  - Consistency: Same patterns everywhere
//  - Elegance: Every detail matters
//

import SwiftUI

// MARK: - Color Hex Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Design Tokens Namespace

enum Design {

    // MARK: - Colors

    enum Colors {
        // Backgrounds (OLED-optimized)
        static let backgroundPrimary = Color.black
        static let backgroundSecondary = Color.black.opacity(0.4)
        static let backgroundTertiary = Color.black.opacity(0.85)

        // Glass/Blur Effects (iOS liquid glass)
        enum Glass {
            static let ultraThin = Color.white.opacity(0.02)
            static let thin = Color.white.opacity(0.03)
            static let regular = Color.white.opacity(0.08)
            static let thick = Color.white.opacity(0.12)
            static let ultraThick = Color.white.opacity(0.15)
        }

        // Borders
        enum Border {
            static let subtle = Color.white.opacity(0.06)
            static let regular = Color.white.opacity(0.1)
            static let emphasis = Color.white.opacity(0.12)
            static let strong = Color.white.opacity(0.15)
        }

        // Text
        enum Text {
            static let primary = Color.white
            static let secondary = Color.white.opacity(0.95)
            static let tertiary = Color.white.opacity(0.8)
            static let quaternary = Color.white.opacity(0.7)
            static let disabled = Color.white.opacity(0.5)
            static let subtle = Color.white.opacity(0.4)
            static let ghost = Color.white.opacity(0.25)
            static let placeholder = Color.white.opacity(0.3)
        }

        // Semantic Colors
        enum Semantic {
            static let success = Color(red: 16/255, green: 185/255, blue: 129/255)
            static let successBackground = success.opacity(0.08)
            static let successBorder = success.opacity(0.3)

            static let error = Color(red: 255/255, green: 60/255, blue: 60/255)
            static let errorBackground = error.opacity(0.1)
            static let errorBorder = error.opacity(0.3)

            static let warning = Color(red: 251/255, green: 191/255, blue: 36/255)
            static let warningBackground = warning.opacity(0.1)
            static let warningBorder = warning.opacity(0.3)

            static let info = Color(red: 100/255, green: 200/255, blue: 255/255)
            static let infoBackground = info.opacity(0.15)
            static let infoBorder = info.opacity(0.3)

            static let accent = Color(red: 59/255, green: 130/255, blue: 246/255)
            static let accentBackground = accent.opacity(0.3)
        }

        // Interactive States
        enum Interactive {
            static let `default` = Color.white.opacity(0.08)
            static let hover = Color.white.opacity(0.12)
            static let active = Color.white.opacity(0.15)
            static let disabled = Color.white.opacity(0.03)
        }
    }

    // MARK: - Typography (Dynamic Type enabled)
    //
    // All tokens use Font.system(.textStyle) which automatically scales
    // with the user's Dynamic Type setting. Weights are applied at call
    // sites via .fontWeight() to keep tokens composable.

    enum Typography {
        // MARK: - Core scale
        static let largeTitle = Font.system(.largeTitle)        // 34pt default
        static let title1     = Font.system(.title)             // 28pt
        static let title2     = Font.system(.title2)            // 22pt
        static let title3     = Font.system(.title3)            // 20pt
        static let headline   = Font.system(.headline)          // 17pt semibold
        static let body       = Font.system(.body)              // 17pt
        static let callout    = Font.system(.callout)           // 16pt
        static let subhead    = Font.system(.subheadline)       // 15pt
        static let footnote   = Font.system(.footnote)          // 13pt
        static let caption1   = Font.system(.caption)           // 12pt
        static let caption2   = Font.system(.caption2)          // 11pt

        // MARK: - Rounded variants (prices, quantities, badges)
        static let largeTitleRounded = Font.system(.largeTitle, design: .rounded)
        static let title2Rounded     = Font.system(.title2, design: .rounded)
        static let title3Rounded     = Font.system(.title3, design: .rounded)
        static let headlineRounded   = Font.system(.headline, design: .rounded)
        static let calloutRounded    = Font.system(.callout, design: .rounded)
        static let subheadRounded    = Font.system(.subheadline, design: .rounded)
        static let footnoteRounded   = Font.system(.footnote, design: .rounded)
        static let caption1Rounded   = Font.system(.caption, design: .rounded)
        static let caption2Rounded   = Font.system(.caption2, design: .rounded)

        // MARK: - Monospaced variants (QR codes, IDs, transfer numbers)
        static let footnoteMono = Font.system(.footnote, design: .monospaced)
        static let caption1Mono = Font.system(.caption, design: .monospaced)
        static let caption2Mono = Font.system(.caption2, design: .monospaced)

        // MARK: - Financial display
        static let priceHero    = Font.system(.largeTitle, design: .rounded)
        static let priceLarge   = Font.system(.title3, design: .rounded)
        static let priceRegular = Font.system(.subheadline)

        // MARK: - Semantic aliases
        static let uppercaseLabel = Font.system(.caption2)
        static let button         = Font.system(.subheadline)
        static let buttonLarge    = Font.system(.headline)

        // MARK: - Tracking values
        static let largeTitleTracking: CGFloat = -0.5
    }

    // MARK: - Spacing (4px base unit)

    enum Spacing {
        static let xxxs: CGFloat = 2
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let xxxl: CGFloat = 40
        static let huge: CGFloat = 48
    }

    // MARK: - Border Radius

    enum Radius {
        static let none: CGFloat = 0
        static let xs: CGFloat = 6
        static let sm: CGFloat = 10
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 32
        static let pill: CGFloat = 100
    }

    // MARK: - Animation

    enum Animation {
        // Durations
        static let instant: Double = 0
        static let fast: Double = 0.15
        static let normal: Double = 0.2
        static let slow: Double = 0.3
        static let slower: Double = 0.4

        // Spring Configs
        static let springGentle = SwiftUI.Animation.spring(response: 0.5, dampingFraction: 0.7)
        static let springSnappy = SwiftUI.Animation.spring(response: 0.35, dampingFraction: 0.7)
        static let springBouncy = SwiftUI.Animation.spring(response: 0.3, dampingFraction: 0.6)

        // Modal spring (tension: 300, friction: 26)
        static let modalSpring = SwiftUI.Animation.spring(response: 0.35, dampingFraction: 0.82)
    }

    // MARK: - Layout

    enum Layout {
        // Component Heights
        static let inputHeight: CGFloat = 48
        static let inputHeightLarge: CGFloat = 60
        static let buttonHeight: CGFloat = 44
        static let buttonHeightLarge: CGFloat = 56

        // POS Layout
        static let cartWidth: CGFloat = 320
        static let productGridGap: CGFloat = 16
        static let searchBarHeight: CGFloat = 48
    }

    // MARK: - Blur Intensities

    enum Blur {
        static let ultraThin: CGFloat = 20
        static let thin: CGFloat = 30
        static let regular: CGFloat = 40
        static let thick: CGFloat = 50
        static let ultraThick: CGFloat = 60
    }
}

// MARK: - View Extensions

extension View {
    /// Apply uppercase label style
    func uppercaseLabel() -> some View {
        self
            .font(Design.Typography.uppercaseLabel)
            .fontWeight(.semibold)
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(Design.Colors.Text.disabled)
    }

    /// Apply price hero style
    func priceHero() -> some View {
        self
            .font(Design.Typography.priceHero)
            .fontWeight(.bold)
            .tracking(-1)
            .foregroundStyle(Design.Colors.Text.primary)
    }

    /// Apply section title style
    func sectionTitle() -> some View {
        self
            .font(Design.Typography.title3)
            .fontWeight(.semibold)
            .foregroundStyle(Design.Colors.Text.primary)
    }

    /// Cap Dynamic Type scaling for POS interface density.
    /// Applied once at the root view; all descendants inherit the limit.
    func posDynamicTypeRange() -> some View {
        self.dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

// MARK: - Currency Formatting

enum CurrencyFormatter {
    /// Shared USD currency formatter - use this instead of creating new formatters
    static let usd: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter
    }()

    /// Format a Decimal as USD currency
    static func format(_ value: Decimal) -> String {
        usd.string(from: value as NSDecimalNumber) ?? "$0.00"
    }

    /// Format a Double as USD currency
    static func format(_ value: Double) -> String {
        usd.string(from: NSNumber(value: value)) ?? "$0.00"
    }
}

// MARK: - Haptic Feedback
//
// Apple's haptic philosophy: Less is more. Use haptics sparingly for:
// - Confirming actions (checkout, delete, significant state changes)
// - Long press recognition
// - Success/error feedback
// - Selection changes in pickers
//
// DON'T use haptics for:
// - Every tap/button press (too noisy)
// - Scrolling or swiping
// - Minor UI interactions

enum Haptics {
    private static let isPhone = UIDevice.current.userInterfaceIdiom == .phone

    private static let softGenerator = UIImpactFeedbackGenerator(style: .soft)
    private static let lightGenerator = UIImpactFeedbackGenerator(style: .light)
    private static let mediumGenerator = UIImpactFeedbackGenerator(style: .medium)
    private static let heavyGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private static let notificationGenerator = UINotificationFeedbackGenerator()
    private static let selectionGenerator = UISelectionFeedbackGenerator()

    /// Subtle tap - for selection changes, minor interactions
    /// Use sparingly - most taps don't need haptics
    static func soft() {
        guard isPhone else { return }
        softGenerator.impactOccurred(intensity: 0.5)
    }

    /// Light tap - for button presses that need confirmation
    /// Still subtle, use for filter toggles, tab switches
    static func light() {
        guard isPhone else { return }
        lightGenerator.impactOccurred(intensity: 0.6)
    }

    /// Medium tap - for significant actions
    /// Use for: long press recognition, adding to cart, confirming dialogs
    static func medium() {
        guard isPhone else { return }
        mediumGenerator.impactOccurred(intensity: 0.7)
    }

    /// Heavy tap - for major actions
    /// Use for: checkout complete, delete confirmation
    static func heavy() {
        guard isPhone else { return }
        heavyGenerator.impactOccurred()
    }

    /// Success notification - for completed transactions
    static func success() {
        guard isPhone else { return }
        notificationGenerator.notificationOccurred(.success)
    }

    /// Error notification - for failed actions
    static func error() {
        guard isPhone else { return }
        notificationGenerator.notificationOccurred(.error)
    }

    /// Warning notification - for alerts
    static func warning() {
        guard isPhone else { return }
        notificationGenerator.notificationOccurred(.warning)
    }

    /// Selection change - for pickers, segmented controls
    static func selection() {
        guard isPhone else { return }
        selectionGenerator.selectionChanged()
    }

    /// Prepare generators for immediate response
    static func prepare() {
        guard isPhone else { return }
        softGenerator.prepare()
        lightGenerator.prepare()
        mediumGenerator.prepare()
    }
}

// MARK: - Safe Area Helper

enum SafeArea {
    static var top: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .safeAreaInsets.top ?? 0
    }

    static var bottom: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .safeAreaInsets.bottom ?? 0
    }
}

