//
//  SheetCoordinator.swift
//  Whale
//
//  Centralized sheet presentation manager.
//  Single source of truth for all sheet state in the app.
//
//  Usage:
//    SheetCoordinator.shared.present(.orderDetail(order))
//    SheetCoordinator.shared.dismiss()
//

import SwiftUI
import Combine

@MainActor
final class SheetCoordinator: ObservableObject {
    static let shared = SheetCoordinator()

    // MARK: - Published State

    /// Currently presented sheet (nil = no sheet)
    @Published private(set) var activeSheet: SheetType?

    /// Currently presented full-screen cover (nil = none)
    @Published private(set) var activeFullScreen: SheetType?

    // MARK: - Sheet Queue (for stacking)

    /// Queue of sheets to present after current one dismisses
    private var sheetQueue: [SheetType] = []

    // MARK: - Callbacks

    /// Optional callback when sheet dismisses
    private var onDismissCallbacks: [String: () -> Void] = [:]

    // MARK: - Init

    private init() {}

    // MARK: - Present

    /// Present a sheet. If a sheet is already visible, queues this one.
    func present(_ sheet: SheetType, onDismiss: (() -> Void)? = nil) {
        if let callback = onDismiss {
            onDismissCallbacks[sheet.id] = callback
        }

        if sheet.isFullScreen {
            // Full screen presentations
            if activeFullScreen != nil {
                // Queue it
                sheetQueue.append(sheet)
            } else {
                activeFullScreen = sheet
            }
        } else {
            // Regular sheet presentations
            if activeSheet != nil {
                // Queue it
                sheetQueue.append(sheet)
            } else {
                activeSheet = sheet
            }
        }
    }

    /// Present a sheet immediately, dismissing any current sheet
    func presentImmediately(_ sheet: SheetType, onDismiss: (() -> Void)? = nil) {
        // Clear queue
        sheetQueue.removeAll()
        onDismissCallbacks.removeAll()

        if let callback = onDismiss {
            onDismissCallbacks[sheet.id] = callback
        }

        if sheet.isFullScreen {
            activeSheet = nil
            activeFullScreen = sheet
        } else {
            activeFullScreen = nil
            activeSheet = sheet
        }
    }

    // MARK: - Dismiss

    /// Dismiss current sheet
    func dismiss() {
        if let sheet = activeSheet {
            // Fire callback if exists
            if let callback = onDismissCallbacks[sheet.id] {
                callback()
                onDismissCallbacks.removeValue(forKey: sheet.id)
            }
            activeSheet = nil
            presentNextInQueue()
        } else if let sheet = activeFullScreen {
            if let callback = onDismissCallbacks[sheet.id] {
                callback()
                onDismissCallbacks.removeValue(forKey: sheet.id)
            }
            activeFullScreen = nil
            presentNextInQueue()
        }
    }

    /// Dismiss all sheets and clear queue
    func dismissAll() {
        sheetQueue.removeAll()
        onDismissCallbacks.removeAll()
        activeSheet = nil
        activeFullScreen = nil
    }

    // MARK: - Query

    /// Whether any sheet is currently presented
    var isPresenting: Bool {
        activeSheet != nil || activeFullScreen != nil
    }

    /// Whether a specific sheet type is currently presented
    func isPresenting(_ sheetType: SheetType) -> Bool {
        activeSheet?.id == sheetType.id || activeFullScreen?.id == sheetType.id
    }

    // MARK: - Private

    private func presentNextInQueue() {
        guard !sheetQueue.isEmpty else { return }

        // Small delay to allow dismiss animation to complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self, let next = self.sheetQueue.first else { return }
            self.sheetQueue.removeFirst()

            if next.isFullScreen {
                self.activeFullScreen = next
            } else {
                self.activeSheet = next
            }
        }
    }
}

// MARK: - SwiftUI Bindings

extension SheetCoordinator {
    /// Binding for .sheet(item:) modifier
    var sheetBinding: Binding<SheetType?> {
        Binding(
            get: { self.activeSheet },
            set: { newValue in
                if newValue == nil {
                    self.dismiss()
                }
            }
        )
    }

    /// Binding for .fullScreenCover(item:) modifier
    var fullScreenBinding: Binding<SheetType?> {
        Binding(
            get: { self.activeFullScreen },
            set: { newValue in
                if newValue == nil {
                    self.dismiss()
                }
            }
        )
    }
}
