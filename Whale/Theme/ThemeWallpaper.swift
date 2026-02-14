//
//  ThemeWallpaper.swift
//  Whale
//
//  Root background view. Shows the theme's primary background color.
//

import SwiftUI

struct ThemeWallpaper: View {
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        theme.backgroundPrimary
            .ignoresSafeArea()
    }
}
