//
//  ThemePalette.swift
//  Whale
//
//  Codable color data structure for user-customizable themes.
//  Persisted to UserDefaults (local) and Supabase user_themes (remote).
//

import SwiftUI

// MARK: - Theme Color (Codable bridge)

struct ThemeColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var opacity: Double

    init(red: Double, green: Double, blue: Double, opacity: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.opacity = opacity
    }

    init(_ color: Color) {
        let resolved = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        self.red = Double(r)
        self.green = Double(g)
        self.blue = Double(b)
        self.opacity = Double(a)
    }

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }

    func withOpacity(_ opacity: Double) -> Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }
}

// MARK: - Base Mode

enum ThemeBaseMode: String, Codable, CaseIterable {
    case dark
    case light
}

// MARK: - Theme Palette

struct ThemePalette: Codable, Equatable {
    var baseMode: ThemeBaseMode

    // Background
    var backgroundPrimary: ThemeColor
    var backgroundSecondary: ThemeColor
    var backgroundTertiary: ThemeColor

    // Glass overlay base (white for dark mode, black for light mode)
    var glassOverlay: ThemeColor

    // Text base (white for dark, black for light)
    var textBase: ThemeColor

    // Semantic
    var accent: ThemeColor
    var success: ThemeColor
    var error: ThemeColor
    var warning: ThemeColor
    var info: ThemeColor

    // Wallpaper
    var wallpaperImageName: String?
    var wallpaperOpacity: Double
    var wallpaperBlur: Double

    // Accessibility
    var highContrast: Bool

    // MARK: - Factory Presets

    static let defaultDark = ThemePalette(
        baseMode: .dark,
        backgroundPrimary: ThemeColor(red: 0, green: 0, blue: 0),
        backgroundSecondary: ThemeColor(red: 0, green: 0, blue: 0, opacity: 0.4),
        backgroundTertiary: ThemeColor(red: 0, green: 0, blue: 0, opacity: 0.85),
        glassOverlay: ThemeColor(red: 1, green: 1, blue: 1),
        textBase: ThemeColor(red: 1, green: 1, blue: 1),
        accent: ThemeColor(red: 59/255, green: 130/255, blue: 246/255),
        success: ThemeColor(red: 16/255, green: 185/255, blue: 129/255),
        error: ThemeColor(red: 1, green: 60/255, blue: 60/255),
        warning: ThemeColor(red: 251/255, green: 191/255, blue: 36/255),
        info: ThemeColor(red: 100/255, green: 200/255, blue: 1),
        wallpaperImageName: nil,
        wallpaperOpacity: 0.3,
        wallpaperBlur: 20,
        highContrast: false
    )

    static let defaultLight = ThemePalette(
        baseMode: .light,
        backgroundPrimary: ThemeColor(red: 0.96, green: 0.96, blue: 0.97),
        backgroundSecondary: ThemeColor(red: 1, green: 1, blue: 1, opacity: 0.6),
        backgroundTertiary: ThemeColor(red: 0.95, green: 0.95, blue: 0.96, opacity: 0.85),
        glassOverlay: ThemeColor(red: 0, green: 0, blue: 0),
        textBase: ThemeColor(red: 0, green: 0, blue: 0),
        accent: ThemeColor(red: 59/255, green: 130/255, blue: 246/255),
        success: ThemeColor(red: 16/255, green: 185/255, blue: 129/255),
        error: ThemeColor(red: 1, green: 60/255, blue: 60/255),
        warning: ThemeColor(red: 251/255, green: 191/255, blue: 36/255),
        info: ThemeColor(red: 100/255, green: 200/255, blue: 1),
        wallpaperImageName: nil,
        wallpaperOpacity: 0.2,
        wallpaperBlur: 30,
        highContrast: false
    )
}
