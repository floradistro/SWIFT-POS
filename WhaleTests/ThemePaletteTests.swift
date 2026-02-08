//
//  ThemePaletteTests.swift
//  WhaleTests
//
//  Tests for ThemePalette Codable round-trips, presets, and high contrast.
//

import Foundation
import Testing
@testable import Whale

struct ThemePaletteTests {

    // MARK: - Codable Round-Trip

    @Test func defaultDarkRoundTrips() throws {
        let original = ThemePalette.defaultDark
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ThemePalette.self, from: data)

        #expect(decoded.baseMode == original.baseMode)
        #expect(decoded.accent.red == original.accent.red)
        #expect(decoded.accent.green == original.accent.green)
        #expect(decoded.accent.blue == original.accent.blue)
        #expect(decoded.highContrast == original.highContrast)
    }

    @Test func defaultLightRoundTrips() throws {
        let original = ThemePalette.defaultLight
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ThemePalette.self, from: data)

        #expect(decoded.baseMode == .light)
        #expect(decoded.highContrast == false)
    }

    // MARK: - Presets

    @Test func darkPresetIsDefault() {
        let palette = ThemePalette.defaultDark
        #expect(palette.baseMode == .dark)
        #expect(palette.highContrast == false)
        #expect(palette.wallpaperImageName == nil)
    }

    @Test func lightPresetHasCorrectMode() {
        let palette = ThemePalette.defaultLight
        #expect(palette.baseMode == .light)
    }

    // MARK: - ThemeColor

    @Test func themeColorCodableRoundTrip() throws {
        let color = ThemeColor(red: 0.5, green: 0.3, blue: 0.8, opacity: 0.9)
        let data = try JSONEncoder().encode(color)
        let decoded = try JSONDecoder().decode(ThemeColor.self, from: data)

        #expect(decoded.red == 0.5)
        #expect(decoded.green == 0.3)
        #expect(decoded.blue == 0.8)
        #expect(decoded.opacity == 0.9)
    }

    @Test func themeColorDefaultOpacity() {
        let color = ThemeColor(red: 1, green: 1, blue: 1)
        #expect(color.opacity == 1.0)
    }

    // MARK: - Base Mode

    @Test func baseModeEnumCodable() throws {
        let dark = ThemeBaseMode.dark
        let light = ThemeBaseMode.light

        let darkData = try JSONEncoder().encode(dark)
        let lightData = try JSONEncoder().encode(light)

        let decodedDark = try JSONDecoder().decode(ThemeBaseMode.self, from: darkData)
        let decodedLight = try JSONDecoder().decode(ThemeBaseMode.self, from: lightData)

        #expect(decodedDark == .dark)
        #expect(decodedLight == .light)
    }

    // MARK: - Custom Palette

    @Test func customPalettePreservesValues() throws {
        var palette = ThemePalette.defaultDark
        palette.accent = ThemeColor(red: 1, green: 0, blue: 0)
        palette.highContrast = true
        palette.wallpaperImageName = "custom_bg.jpg"
        palette.wallpaperOpacity = 0.5
        palette.wallpaperBlur = 10

        let data = try JSONEncoder().encode(palette)
        let decoded = try JSONDecoder().decode(ThemePalette.self, from: data)

        #expect(decoded.accent.red == 1)
        #expect(decoded.accent.green == 0)
        #expect(decoded.accent.blue == 0)
        #expect(decoded.highContrast == true)
        #expect(decoded.wallpaperImageName == "custom_bg.jpg")
        #expect(decoded.wallpaperOpacity == 0.5)
        #expect(decoded.wallpaperBlur == 10)
    }
}
