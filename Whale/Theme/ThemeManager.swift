//
//  ThemeManager.swift
//  Whale
//
//  Observable singleton that resolves ThemePalette into SwiftUI Colors.
//  DesignTokens.swift reads from this — zero view-code changes needed.
//

import SwiftUI
import Combine
import Supabase
import os.log

final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @Published var palette: ThemePalette {
        didSet { rebuildColors() }
    }

    /// Incremented on every palette change. Views use `.id(themeVersion)` to
    /// force recreation, since `Design.Colors.*` static properties can't be
    /// tracked by SwiftUI's dependency system.
    @Published private(set) var themeVersion = 0

    // MARK: - Resolved Colors (rebuilt on palette change)

    // Backgrounds
    private(set) var backgroundPrimary: Color = .black
    private(set) var backgroundSecondary: Color = .black.opacity(0.4)
    private(set) var backgroundTertiary: Color = .black.opacity(0.85)

    // Glass
    private(set) var glassUltraThin: Color = .white.opacity(0.02)
    private(set) var glassThin: Color = .white.opacity(0.03)
    private(set) var glassRegular: Color = .white.opacity(0.08)
    private(set) var glassThick: Color = .white.opacity(0.12)
    private(set) var glassUltraThick: Color = .white.opacity(0.15)

    // Borders
    private(set) var borderSubtle: Color = .white.opacity(0.06)
    private(set) var borderRegular: Color = .white.opacity(0.1)
    private(set) var borderEmphasis: Color = .white.opacity(0.12)
    private(set) var borderStrong: Color = .white.opacity(0.15)

    // Text
    private(set) var textPrimary: Color = .white
    private(set) var textSecondary: Color = .white.opacity(0.95)
    private(set) var textTertiary: Color = .white.opacity(0.8)
    private(set) var textQuaternary: Color = .white.opacity(0.7)
    private(set) var textDisabled: Color = .white.opacity(0.5)
    private(set) var textSubtle: Color = .white.opacity(0.4)
    private(set) var textGhost: Color = .white.opacity(0.25)
    private(set) var textPlaceholder: Color = .white.opacity(0.3)

    // Semantic
    private(set) var semanticSuccess: Color = .clear
    private(set) var semanticSuccessBackground: Color = .clear
    private(set) var semanticSuccessBorder: Color = .clear
    private(set) var semanticError: Color = .clear
    private(set) var semanticErrorBackground: Color = .clear
    private(set) var semanticErrorBorder: Color = .clear
    private(set) var semanticWarning: Color = .clear
    private(set) var semanticWarningBackground: Color = .clear
    private(set) var semanticWarningBorder: Color = .clear
    private(set) var semanticInfo: Color = .clear
    private(set) var semanticInfoBackground: Color = .clear
    private(set) var semanticInfoBorder: Color = .clear
    private(set) var semanticAccent: Color = .clear
    private(set) var semanticAccentBackground: Color = .clear
    private(set) var semanticAccentForeground: Color = .white

    // Interactive
    private(set) var interactiveDefault: Color = .white.opacity(0.08)
    private(set) var interactiveHover: Color = .white.opacity(0.12)
    private(set) var interactiveActive: Color = .white.opacity(0.15)
    private(set) var interactiveDisabled: Color = .white.opacity(0.03)

    // Derived
    var preferredColorScheme: ColorScheme {
        palette.baseMode == .dark ? .dark : .light
    }

    // MARK: - Init

    private init() {
        self.palette = Self.loadLocal() ?? .defaultDark
        rebuildColors()
    }

    // MARK: - Public API

    func setBaseMode(_ mode: ThemeBaseMode) {
        switch mode {
        case .dark:
            var p = ThemePalette.defaultDark
            p.accent = palette.accent
            p.wallpaperImageName = palette.wallpaperImageName
            p.wallpaperOpacity = palette.wallpaperOpacity
            p.wallpaperBlur = palette.wallpaperBlur
            p.highContrast = palette.highContrast
            palette = p
        case .light:
            var p = ThemePalette.defaultLight
            p.accent = palette.accent
            p.wallpaperImageName = palette.wallpaperImageName
            p.wallpaperOpacity = palette.wallpaperOpacity
            p.wallpaperBlur = palette.wallpaperBlur
            p.highContrast = palette.highContrast
            palette = p
        }
        saveLocal()
    }

    func setAccentColor(_ color: Color) {
        palette.accent = ThemeColor(color)
        saveLocal()
    }

    func setHighContrast(_ enabled: Bool) {
        palette.highContrast = enabled
        saveLocal()
    }

    func setWallpaper(imageData: Data?) {
        guard let data = imageData else {
            removeWallpaperFile()
            palette.wallpaperImageName = nil
            saveLocal()
            return
        }

        let fileName = "theme_wallpaper.jpg"
        let url = Self.documentsDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: url)
            palette.wallpaperImageName = fileName
            saveLocal()
            Log.ui.info("Wallpaper saved: \(fileName)")
        } catch {
            Log.ui.error("Failed to save wallpaper: \(error.localizedDescription)")
        }
    }

    func setWallpaperOpacity(_ opacity: Double) {
        palette.wallpaperOpacity = opacity
        saveLocal()
    }

    func setWallpaperBlur(_ blur: Double) {
        palette.wallpaperBlur = blur
        saveLocal()
    }

    func resetToDefault() {
        removeWallpaperFile()
        palette = .defaultDark
        saveLocal()
    }

    func applyPalette(_ newPalette: ThemePalette) {
        palette = newPalette
        saveLocal()
    }

    // MARK: - Wallpaper Image

    var wallpaperImage: UIImage? {
        guard let name = palette.wallpaperImageName else { return nil }
        let url = Self.documentsDirectory.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    // MARK: - High Contrast Boost

    /// Boosts low opacity values when high contrast is on.
    /// Maps: 0.25→0.6, 0.3→0.6, 0.4→0.65, 0.5→0.7
    func boosted(_ opacity: Double) -> Double {
        guard palette.highContrast else { return opacity }
        if opacity <= 0.3 { return max(opacity, 0.6) }
        if opacity <= 0.5 { return max(opacity, opacity + 0.2) }
        return opacity
    }

    // MARK: - Supabase Sync

    func loadFromSupabase(userId: UUID) async {
        do {
            let client = await supabaseAsync()
            struct ThemeRow: Decodable {
                let palette: ThemePalette
            }
            let rows: [ThemeRow] = try await client
                .from("user_themes")
                .select("palette")
                .eq("user_id", value: userId.uuidString)
                .limit(1)
                .execute()
                .value

            if let remote = rows.first?.palette {
                palette = remote
                saveLocal()
                Log.ui.info("Theme loaded from Supabase")
            }
        } catch {
            Log.ui.debug("No remote theme found, using local: \(error.localizedDescription)")
        }
    }

    func saveToSupabase(userId: UUID) async {
        do {
            let client = await supabaseAsync()
            struct ThemeUpsert: Encodable {
                let user_id: String
                let palette: ThemePalette
                let updated_at: String
            }
            let row = ThemeUpsert(
                user_id: userId.uuidString,
                palette: palette,
                updated_at: ISO8601DateFormatter().string(from: Date())
            )
            try await client
                .from("user_themes")
                .upsert(row, onConflict: "user_id")
                .execute()
            Log.ui.info("Theme saved to Supabase")
        } catch {
            Log.ui.warning("Failed to save theme to Supabase: \(error.localizedDescription)")
        }
    }

    // MARK: - Local Persistence

    private static let userDefaultsKey = "whale_theme_palette"

    private func saveLocal() {
        guard let data = try? JSONEncoder().encode(palette) else { return }
        UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
    }

    private static func loadLocal() -> ThemePalette? {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let palette = try? JSONDecoder().decode(ThemePalette.self, from: data) else {
            return nil
        }
        return palette
    }

    private static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private func removeWallpaperFile() {
        guard let name = palette.wallpaperImageName else { return }
        let url = Self.documentsDirectory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Neutral Accent Detection

    /// Whether the accent is the "None" neutral gray (no tinting).
    var isNeutralAccent: Bool {
        let a = palette.accent
        return abs(a.red - 0.5) < 0.02 && abs(a.green - 0.5) < 0.02 && abs(a.blue - 0.5) < 0.02
    }

    // MARK: - Color Rebuild

    private func rebuildColors() {
        let p = palette
        let text = p.textBase
        let isLight = p.baseMode == .light
        let accent = p.accent
        let neutral = isNeutralAccent
        let overlay = p.glassOverlay  // white for dark, black for light

        // Backgrounds — skip accent wash when neutral
        if neutral {
            backgroundPrimary = p.backgroundPrimary.color
            backgroundSecondary = p.backgroundSecondary.color
            backgroundTertiary = p.backgroundTertiary.color
        } else {
            // More vibrant background tinting (was 5-6%, now 10-12%)
            let bgTintPrimary = isLight ? 0.08 : 0.10
            let bgTintSecondary = isLight ? 0.10 : 0.12
            let bgTintTertiary = isLight ? 0.12 : 0.14
            backgroundPrimary = accentBlend(p.backgroundPrimary, accent: accent, amount: bgTintPrimary)
            backgroundSecondary = accentBlend(p.backgroundSecondary, accent: accent, amount: bgTintSecondary)
            backgroundTertiary = accentBlend(p.backgroundTertiary, accent: accent, amount: bgTintTertiary)
        }

        // Glass — neutral uses white/black overlay, accent uses vibrant tinted overlay
        let glassBase = neutral ? overlay : accent
        glassUltraThin = glassBase.withOpacity(isLight ? 0.06 : 0.05)
        glassThin = glassBase.withOpacity(isLight ? 0.10 : 0.08)
        glassRegular = glassBase.withOpacity(isLight ? 0.16 : 0.14)
        glassThick = glassBase.withOpacity(isLight ? 0.24 : 0.20)
        glassUltraThick = glassBase.withOpacity(isLight ? 0.32 : 0.26)

        // Borders — neutral uses overlay, accent uses vibrant tint
        let borderBase = neutral ? overlay : accent
        borderSubtle = borderBase.withOpacity(isLight ? 0.14 : 0.12)
        borderRegular = borderBase.withOpacity(isLight ? 0.22 : 0.18)
        borderEmphasis = borderBase.withOpacity(isLight ? 0.30 : 0.24)
        borderStrong = borderBase.withOpacity(isLight ? 0.38 : 0.30)

        // Text (using text base with high contrast boost)
        textPrimary = text.color
        textSecondary = text.withOpacity(boosted(0.95))
        textTertiary = text.withOpacity(boosted(0.8))
        textQuaternary = text.withOpacity(boosted(0.7))
        textDisabled = text.withOpacity(boosted(0.5))
        textSubtle = text.withOpacity(boosted(0.4))
        textGhost = text.withOpacity(boosted(0.25))
        textPlaceholder = text.withOpacity(boosted(0.3))

        // Semantic — more vibrant background fills
        semanticSuccess = p.success.color
        semanticSuccessBackground = p.success.withOpacity(0.14)
        semanticSuccessBorder = p.success.withOpacity(0.4)
        semanticError = p.error.color
        semanticErrorBackground = p.error.withOpacity(0.16)
        semanticErrorBorder = p.error.withOpacity(0.4)
        semanticWarning = p.warning.color
        semanticWarningBackground = p.warning.withOpacity(0.16)
        semanticWarningBorder = p.warning.withOpacity(0.4)
        semanticInfo = p.info.color
        semanticInfoBackground = p.info.withOpacity(0.20)
        semanticInfoBorder = p.info.withOpacity(0.4)
        if neutral {
            // When no accent color: use a visible glass-like overlay so selected states
            // still read clearly (matching the original monochrome glass design).
            semanticAccent = overlay.withOpacity(isLight ? 0.32 : 0.26)
            semanticAccentBackground = overlay.withOpacity(isLight ? 0.14 : 0.12)
            semanticAccentForeground = text.color  // Text.primary — adapts to light/dark
        } else {
            semanticAccent = accent.color
            semanticAccentBackground = accent.withOpacity(0.45)  // More vibrant (was 0.3)
            semanticAccentForeground = .white      // Always white on colored accent
        }

        // Interactive — neutral uses overlay, accent uses vibrant tint
        let interactiveBase = neutral ? overlay : accent
        interactiveDefault = interactiveBase.withOpacity(isLight ? 0.16 : 0.14)
        interactiveHover = interactiveBase.withOpacity(isLight ? 0.24 : 0.20)
        interactiveActive = interactiveBase.withOpacity(isLight ? 0.32 : 0.26)
        interactiveDisabled = interactiveBase.withOpacity(isLight ? 0.06 : 0.05)

        themeVersion += 1
    }

    // MARK: - Accent Blending

    /// Blends a base palette color toward the accent color by `amount` (0–1).
    private func accentBlend(_ base: ThemeColor, accent: ThemeColor, amount: Double) -> Color {
        let r = base.red * (1 - amount) + accent.red * amount
        let g = base.green * (1 - amount) + accent.green * amount
        let b = base.blue * (1 - amount) + accent.blue * amount
        return Color(.sRGB, red: r, green: g, blue: b, opacity: base.opacity)
    }
}
