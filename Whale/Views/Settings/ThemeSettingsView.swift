//
//  ThemeSettingsView.swift
//  Whale
//
//  Full appearance customization: base mode, accent color, wallpaper, high contrast.
//  Changes apply instantly via ThemeManager.
//

import SwiftUI
import PhotosUI

struct ThemeSettingsView: View {
    @ObservedObject private var theme = ThemeManager.shared
    @EnvironmentObject private var session: SessionObserver
    @Environment(\.dismiss) private var dismiss

    @State private var showColorPicker = false
    @State private var selectedPhoto: PhotosPickerItem?

    private let presetAccents: [(String, Color)] = [
        ("Blue", Color(red: 59/255, green: 130/255, blue: 246/255)),
        ("Purple", Color(red: 147/255, green: 51/255, blue: 234/255)),
        ("Pink", Color(red: 236/255, green: 72/255, blue: 153/255)),
        ("Red", Color(red: 239/255, green: 68/255, blue: 68/255)),
        ("Orange", Color(red: 249/255, green: 115/255, blue: 22/255)),
        ("Green", Color(red: 16/255, green: 185/255, blue: 129/255)),
        ("Teal", Color(red: 20/255, green: 184/255, blue: 166/255)),
        ("Cyan", Color(red: 6/255, green: 182/255, blue: 212/255)),
    ]

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    baseModeSection
                    accentColorSection
                    wallpaperSection
                    accessibilitySection
                    presetsSection
                    resetButton
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .scrollBounceBehavior(.basedOnSize)
            .navigationTitle("Appearance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .onChange(of: selectedPhoto) { _, newItem in
            loadWallpaperPhoto(newItem)
        }
        .sheet(isPresented: $showColorPicker) {
            ColorPickerSheet(
                currentColor: theme.palette.accent.color,
                onApply: { color in
                    theme.setAccentColor(color)
                    saveToRemote()
                }
            )
        }
    }

    // MARK: - Base Mode

    private var baseModeSection: some View {
        settingsGroup {
            HStack(spacing: 14) {
                settingsIcon("moon.fill")

                Text("Base Mode")
                    .font(Design.Typography.subhead).fontWeight(.medium)
                    .foregroundStyle(Design.Colors.Text.primary)

                Spacer()
            }

            HStack(spacing: 12) {
                modeButton("Dark", mode: .dark, icon: "moon.fill")
                modeButton("Light", mode: .light, icon: "sun.max.fill")
            }
            .padding(.top, 8)
        }
    }

    private func modeButton(_ label: String, mode: ThemeBaseMode, icon: String) -> some View {
        Button {
            Haptics.light()
            theme.setBaseMode(mode)
            saveToRemote()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(Design.Typography.footnote)
                Text(label)
                    .font(Design.Typography.subhead).fontWeight(.medium)
            }
            .foregroundStyle(theme.palette.baseMode == mode ? Design.Colors.Text.primary : Design.Colors.Text.disabled)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(theme.palette.baseMode == mode ? Design.Colors.Glass.ultraThick : Design.Colors.Glass.thin)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(theme.palette.baseMode == mode ? Design.Colors.Border.strong : Design.Colors.Border.subtle, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Accent Color

    private var accentColorSection: some View {
        settingsGroup {
            HStack(spacing: 14) {
                settingsIcon("paintpalette.fill")

                Text("Accent Color")
                    .font(Design.Typography.subhead).fontWeight(.medium)
                    .foregroundStyle(Design.Colors.Text.primary)

                Spacer()
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                ForEach(presetAccents, id: \.0) { name, color in
                    Button {
                        Haptics.light()
                        theme.setAccentColor(color)
                        saveToRemote()
                    } label: {
                        Circle()
                            .fill(color)
                            .frame(width: 40, height: 40)
                            .overlay(
                                Circle()
                                    .stroke(Design.Colors.Border.strong, lineWidth: isAccentSelected(color) ? 3 : 0)
                                    .padding(-3)
                            )
                            .overlay {
                                if isAccentSelected(color) {
                                    Image(systemName: "checkmark")
                                        .font(Design.Typography.caption1).fontWeight(.bold)
                                        .foregroundStyle(.white)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(name) accent color")
                    .accessibilityAddTraits(isAccentSelected(color) ? .isSelected : [])
                }
            }
            .padding(.top, 8)

            Button {
                Haptics.light()
                showColorPicker = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "eyedropper")
                        .font(Design.Typography.footnote)
                    Text("Custom Color…")
                        .font(Design.Typography.subhead).fontWeight(.medium)
                }
                .foregroundStyle(Design.Colors.Text.tertiary)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Design.Colors.Glass.regular)
                )
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
    }

    private func isAccentSelected(_ color: Color) -> Bool {
        let tc = ThemeColor(color)
        let pa = theme.palette.accent
        return abs(tc.red - pa.red) < 0.02 && abs(tc.green - pa.green) < 0.02 && abs(tc.blue - pa.blue) < 0.02
    }

    // MARK: - Wallpaper

    private var wallpaperSection: some View {
        settingsGroup {
            HStack(spacing: 14) {
                settingsIcon("photo.fill")

                Text("Wallpaper")
                    .font(Design.Typography.subhead).fontWeight(.medium)
                    .foregroundStyle(Design.Colors.Text.primary)

                Spacer()
            }

            if let image = theme.wallpaperImage {
                // Preview
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .opacity(theme.palette.wallpaperOpacity)
                    .blur(radius: theme.palette.wallpaperBlur / 5)
                    .padding(.top, 8)

                // Opacity slider
                VStack(alignment: .leading, spacing: 4) {
                    Text("Opacity: \(Int(theme.palette.wallpaperOpacity * 100))%")
                        .font(Design.Typography.caption1)
                        .foregroundStyle(Design.Colors.Text.subtle)
                    Slider(value: Binding(
                        get: { theme.palette.wallpaperOpacity },
                        set: { theme.setWallpaperOpacity($0) }
                    ), in: 0.05...0.8)
                    .tint(Design.Colors.Semantic.accent)
                }
                .padding(.top, 4)

                // Blur slider
                VStack(alignment: .leading, spacing: 4) {
                    Text("Blur: \(Int(theme.palette.wallpaperBlur))")
                        .font(Design.Typography.caption1)
                        .foregroundStyle(Design.Colors.Text.subtle)
                    Slider(value: Binding(
                        get: { theme.palette.wallpaperBlur },
                        set: { theme.setWallpaperBlur($0) }
                    ), in: 0...50)
                    .tint(Design.Colors.Semantic.accent)
                }

                // Remove button
                Button {
                    Haptics.light()
                    theme.setWallpaper(imageData: nil)
                    saveToRemote()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                            .font(Design.Typography.caption1)
                        Text("Remove Wallpaper")
                            .font(Design.Typography.subhead).fontWeight(.medium)
                    }
                    .foregroundStyle(Design.Colors.Semantic.error)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }

            PhotosPicker(
                selection: $selectedPhoto,
                matching: .images,
                photoLibrary: .shared()
            ) {
                HStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(Design.Typography.footnote)
                    Text(theme.wallpaperImage != nil ? "Change Wallpaper" : "Choose Image")
                        .font(Design.Typography.subhead).fontWeight(.medium)
                }
                .foregroundStyle(Design.Colors.Text.tertiary)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Design.Colors.Glass.regular)
                )
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
    }

    // MARK: - Accessibility

    private var accessibilitySection: some View {
        settingsGroup {
            HStack(spacing: 14) {
                settingsIcon("eye.fill")

                VStack(alignment: .leading, spacing: 2) {
                    Text("High Contrast")
                        .font(Design.Typography.subhead).fontWeight(.medium)
                        .foregroundStyle(Design.Colors.Text.primary)
                    Text("Increases text opacity for better readability")
                        .font(Design.Typography.caption1)
                        .foregroundStyle(Design.Colors.Text.subtle)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { theme.palette.highContrast },
                    set: { newVal in
                        theme.setHighContrast(newVal)
                        saveToRemote()
                    }
                ))
                .labelsHidden()
                .tint(Design.Colors.Semantic.success)
            }
        }
    }

    // MARK: - Presets

    private var presetsSection: some View {
        settingsGroup {
            HStack(spacing: 14) {
                settingsIcon("sparkles")

                Text("Presets")
                    .font(Design.Typography.subhead).fontWeight(.medium)
                    .foregroundStyle(Design.Colors.Text.primary)

                Spacer()
            }

            HStack(spacing: 12) {
                presetButton("Default Dark", palette: .defaultDark)
                presetButton("Default Light", palette: .defaultLight)
            }
            .padding(.top, 8)
        }
    }

    private func presetButton(_ label: String, palette: ThemePalette) -> some View {
        Button {
            Haptics.light()
            theme.applyPalette(palette)
            saveToRemote()
        } label: {
            Text(label)
                .font(Design.Typography.caption1).fontWeight(.medium)
                .foregroundStyle(Design.Colors.Text.tertiary)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Design.Colors.Glass.regular)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Design.Colors.Border.subtle, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Reset

    private var resetButton: some View {
        Button {
            Haptics.medium()
            theme.resetToDefault()
            saveToRemote()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.counterclockwise")
                    .font(Design.Typography.subhead).fontWeight(.semibold)
                Text("Reset to Default")
                    .font(Design.Typography.callout).fontWeight(.semibold)
            }
            .foregroundStyle(Design.Colors.Semantic.error)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Design.Colors.Semantic.error.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Design.Colors.Semantic.error.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func settingsGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Design.Colors.Glass.thin)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Design.Colors.Border.subtle, lineWidth: 1)
        )
    }

    private func settingsIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(Design.Typography.footnote).fontWeight(.medium)
            .foregroundStyle(Design.Colors.Text.subtle)
            .frame(width: 32, height: 32)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Design.Colors.Border.regular, lineWidth: 1)
            )
    }

    private func loadWallpaperPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                theme.setWallpaper(imageData: data)
                saveToRemote()
            }
        }
    }

    private func saveToRemote() {
        guard let uid = session.publicUserId else { return }
        Task {
            await theme.saveToSupabase(userId: uid)
        }
    }
}
