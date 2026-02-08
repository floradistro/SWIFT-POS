//
//  ThemeWallpaper.swift
//  Whale
//
//  Root background view that replaces Color.black.ignoresSafeArea().
//  Shows background color + optional wallpaper with opacity/blur + darkening overlay.
//

import SwiftUI

struct ThemeWallpaper: View {
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        ZStack {
            // Base background color
            theme.backgroundPrimary
                .ignoresSafeArea()

            // Wallpaper image (if set)
            if let image = theme.wallpaperImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .opacity(theme.palette.wallpaperOpacity)
                    .blur(radius: theme.palette.wallpaperBlur)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                // Mode-adaptive overlay for text readability
                Group {
                    if theme.palette.baseMode == .light {
                        Color.white.opacity(0.15)
                    } else {
                        Color.black.opacity(0.3)
                    }
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }
        }
    }
}
