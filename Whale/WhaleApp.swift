//
//  WhaleApp.swift
//  Whale
//
//  Created by Fahad Khan on 12/14/25.
//

import SwiftUI
import UIKit
import AVFoundation
import Combine
import os.log

@main
struct WhaleApp: App {
    // CRITICAL: App struct must be PURE and STATIC
    // No @StateObject, no observers, no mutable state
    // Any observed state here causes the entire view tree to rebuild on mutations

    init() {
        Log.session.debug("WhaleApp.init START")
        Log.session.debug("WhaleApp.init END")
    }

    var body: some Scene {
        Log.session.debug("WhaleApp.body START")
        return WindowGroup {
            RootView()
            // NOTE: .environmentObject moved to RootView to prevent App-level rebuilds
        }
    }
}

// MARK: - Subsystem Warmup Manager

/// Pre-warms iPadOS subsystems to prevent gesture gate freezes.
/// On fresh install, iPadOS initializes these on first access which blocks touch input.
/// By warming them at launch (async, non-blocking), first modal open is instant.
///
/// All warmups run asynchronously with small delays to avoid blocking the UI.
/// The delays are staggered so they don't all compete at once.
@MainActor
final class SubsystemWarmup: ObservableObject {
    static let shared = SubsystemWarmup()

    /// True once all subsystems have been warmed - modals can now open instantly
    @Published private(set) var isWarm = false

    private var hasWarmedKeyboard = false
    private var hasWarmedCamera = false
    private var hasWarmedListInteraction = false
    private var hasWarmedPasteboard = false
    private var hasWarmedBlurEffects = false

    private init() {}

    /// Warm all subsystems - BLOCKS until complete.
    /// Call this during splash screen, before allowing user interaction.
    func warmAllSubsystems() async {
        guard !isWarm else { return }
        isWarm = true

        Log.session.debug("Subsystem warmup starting (blocking)")

        // Run ALL warmups concurrently but wait for them to complete
        // This ensures everything is ready BEFORE user can interact
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.warmKeyboardAsync() }
            group.addTask { await self.warmListInteractionAsync() }
            group.addTask { await self.warmPasteboardAsync() }
            group.addTask { await self.warmBlurEffectsAsync() }
            // NOTE: Schema loading removed - Anthropic-style on-demand via database_schema tool
            // Lisa will fetch schema when she needs it, not pre-loaded
        }

        // Camera is slower - start in background, don't block
        if !hasWarmedCamera {
            hasWarmedCamera = true
            warmCameraBackground()
        }

        // Clean up any first responder
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )

        Log.session.debug("Subsystem warmup complete - app ready for interaction")
    }

    /// Legacy fire-and-forget method - redirects to blocking version
    func warmIfNeeded() {
        Task { await warmAllSubsystems() }
    }

    // MARK: - Async Warmup Functions (awaitable)

    @MainActor
    private func warmKeyboardAsync() async {
        guard !hasWarmedKeyboard else { return }
        hasWarmedKeyboard = true

        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?.windows.first else { return }

        let hiddenField = UITextField(frame: CGRect(x: -100, y: -100, width: 1, height: 1))
        hiddenField.alpha = 0
        hiddenField.isUserInteractionEnabled = false
        window.addSubview(hiddenField)

        _ = hiddenField.becomeFirstResponder()
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        _ = hiddenField.resignFirstResponder()
        hiddenField.removeFromSuperview()

        Log.session.debug("Keyboard subsystem warmed")
    }

    @MainActor
    private func warmListInteractionAsync() async {
        guard !hasWarmedListInteraction else { return }
        hasWarmedListInteraction = true

        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?.windows.first else { return }

        let hiddenTable = UITableView(frame: CGRect(x: -100, y: -100, width: 1, height: 1))
        hiddenTable.alpha = 0
        hiddenTable.isUserInteractionEnabled = false
        window.addSubview(hiddenTable)

        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        hiddenTable.removeFromSuperview()

        Log.session.debug("List interaction subsystem warmed")
    }

    private func warmPasteboardAsync() async {
        guard !hasWarmedPasteboard else { return }
        hasWarmedPasteboard = true

        _ = await Task.detached(priority: .userInitiated) {
            _ = UIPasteboard.general.hasStrings
        }.value

        Log.session.debug("Pasteboard subsystem warmed")
    }

    @MainActor
    private func warmBlurEffectsAsync() async {
        guard !hasWarmedBlurEffects else { return }
        hasWarmedBlurEffects = true

        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?.windows.first else { return }

        let blurEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        let blurView = UIVisualEffectView(effect: blurEffect)
        blurView.frame = CGRect(x: -100, y: -100, width: 1, height: 1)
        blurView.alpha = 0.01
        window.addSubview(blurView)

        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        blurView.removeFromSuperview()

        Log.session.debug("Blur effects subsystem warmed")
    }

    // Camera runs in background - don't block on it
    private nonisolated func warmCameraBackground() {
        Task.detached(priority: .utility) {
            AVCaptureDevice.requestAccess(for: .video) { _ in }
            _ = AVCaptureSession()
            Log.session.debug("Camera subsystem warmed")
        }
    }

    // Track camera warmup separately since it's nonisolated
    @MainActor
    private func markCameraWarmed() {
        hasWarmedCamera = true
    }
}

// MARK: - App State (for stable routing)

/// Enum for routing to prevent constant view recreation
enum AppRoute: Equatable {
    case loading
    case locked
    case selectLocation
    case selectRegister
    case home
    case login
}

// MARK: - Root View (routing)

struct RootView: View {
    // Session observed HERE, not at App level
    // This prevents App.body from being invalidated on state changes
    @StateObject private var session = SessionObserver.shared
    @StateObject private var sheetCoordinator = SheetCoordinator.shared
    @ObservedObject private var themeManager = ThemeManager.shared

    init() {
        Log.session.debug("RootView.init")
    }

    var body: some View {
        let _ = Log.session.debug("RootView.body")
        // BootSheet handles the entire flow:
        // splash → login → Face ID verify → location → register → start shift → POS
        BootSheet()
            .posDynamicTypeRange()
            .environmentObject(session)
            .environmentObject(themeManager)
            .preferredColorScheme(themeManager.preferredColorScheme)
            .task {
                // CRITICAL: Run startup ONLY after first frame renders
                // This prevents state mutations during view creation
                await session.start()
            }
            // MARK: - Unified Sheet System
            // All sheets in the app flow through this single attachment point
            .sheet(item: sheetCoordinator.sheetBinding) { sheetType in
                SheetContainer(sheetType: sheetType)
                    .environmentObject(session)
                    .environmentObject(themeManager)
                    .applyDetents(sheetType.detents)
            }
            .fullScreenCover(item: sheetCoordinator.fullScreenBinding) { sheetType in
                SheetContainer(sheetType: sheetType)
                    .environmentObject(session)
                    .environmentObject(themeManager)
            }
    }
}

