//
//  BiometricAuthService.swift
//  Whale
//
//  Handles Face ID / Touch ID authentication for app unlock.
//  Manages biometric enrollment and persistent login preferences.
//
//  ARCHITECTURE NOTE:
//  LAContext creation and canEvaluatePolicy() are expensive operations
//  that can block the main thread for 50-200ms. We cache the biometric
//  type at app startup to avoid blocking during SwiftUI view rendering.
//

import Foundation
import LocalAuthentication
import os.log

// MARK: - Biometric Type

enum BiometricType: Sendable {
    case none
    case touchID
    case faceID

    var displayName: String {
        switch self {
        case .none: return "Passcode"
        case .touchID: return "Touch ID"
        case .faceID: return "Face ID"
        }
    }

    var iconName: String {
        switch self {
        case .none: return "lock.fill"
        case .touchID: return "touchid"
        case .faceID: return "faceid"
        }
    }
}

// MARK: - Biometric Auth Service

enum BiometricAuthService {

    // MARK: - Keys

    private enum Keys {
        static let biometricEnabled = "biometric_auth_enabled"
        static let stayLoggedIn = "stay_logged_in"
        static let lastAuthEmail = "last_auth_email"
    }

    // MARK: - Cached State (initialized at app startup)

    /// Cached biometric type - set once at app startup, never changes during runtime
    private static var _cachedBiometricType: BiometricType?

    /// Cached UserDefaults values - refreshed on access but cached to avoid repeated I/O
    private static var _cachedIsBiometricEnabled: Bool?
    private static var _cachedStayLoggedIn: Bool?
    private static var _cachedLastAuthEmail: String??  // Double optional: nil = not cached, .some(nil) = cached nil

    // MARK: - Initialization

    /// Call this ONCE at app startup (from a background thread) to cache biometric type.
    /// This prevents LAContext blocking during SwiftUI view rendering.
    static func warmup() {
        Task.detached(priority: .userInitiated) {
            let type = Self.checkBiometricType()
            Self._cachedBiometricType = type
            Log.session.debug("Biometric type cached: \(type.displayName)")
        }
    }

    /// Actually check biometric type (expensive - only call during warmup)
    private static func checkBiometricType() -> BiometricType {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }

        switch context.biometryType {
        case .faceID:
            return .faceID
        case .touchID:
            return .touchID
        case .opticID:
            return .faceID  // Treat Vision Pro as Face ID
        case .none:
            return .none
        @unknown default:
            return .none
        }
    }

    // MARK: - Biometric Availability

    /// Get cached biometric type - NEVER blocks
    /// Returns .none if warmup hasn't completed (safe default)
    static var availableBiometricType: BiometricType {
        if let cached = _cachedBiometricType {
            return cached
        }
        // Warmup not complete - return safe default
        // This should rarely happen if warmup is called early enough
        Log.session.warning("Biometric type accessed before warmup - returning .none")
        return .none
    }

    /// Check if biometric auth is available
    static var isBiometricAvailable: Bool {
        availableBiometricType != .none
    }

    // MARK: - User Preferences (cached)

    /// Whether user has enabled biometric auth
    static var isBiometricEnabled: Bool {
        get {
            if let cached = _cachedIsBiometricEnabled {
                return cached
            }
            let value = UserDefaults.standard.bool(forKey: Keys.biometricEnabled)
            _cachedIsBiometricEnabled = value
            return value
        }
        set {
            _cachedIsBiometricEnabled = newValue
            UserDefaults.standard.set(newValue, forKey: Keys.biometricEnabled)
        }
    }

    /// Whether user wants to stay logged in
    static var stayLoggedIn: Bool {
        get {
            if let cached = _cachedStayLoggedIn {
                return cached
            }
            let value = UserDefaults.standard.bool(forKey: Keys.stayLoggedIn)
            _cachedStayLoggedIn = value
            return value
        }
        set {
            _cachedStayLoggedIn = newValue
            UserDefaults.standard.set(newValue, forKey: Keys.stayLoggedIn)
        }
    }

    /// Last authenticated email (for display on lock screen)
    static var lastAuthEmail: String? {
        get {
            if let cached = _cachedLastAuthEmail {
                return cached
            }
            let value = UserDefaults.standard.string(forKey: Keys.lastAuthEmail)
            _cachedLastAuthEmail = .some(value)
            return value
        }
        set {
            _cachedLastAuthEmail = .some(newValue)
            UserDefaults.standard.set(newValue, forKey: Keys.lastAuthEmail)
        }
    }

    /// Clear all caches (call on sign out)
    static func invalidateCaches() {
        _cachedIsBiometricEnabled = nil
        _cachedStayLoggedIn = nil
        _cachedLastAuthEmail = nil
    }

    // MARK: - Authentication

    /// Authenticate with biometrics
    /// - Parameter reason: The reason shown to user
    /// - Returns: True if authentication succeeded
    @MainActor
    static func authenticate(reason: String = "Unlock Whale POS") async -> Bool {
        let context = LAContext()
        var error: NSError?

        // Check if biometrics available
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            Log.session.warning("Biometrics not available: \(error?.localizedDescription ?? "Unknown")")

            // Fall back to device passcode
            return await authenticateWithPasscode(reason: reason)
        }

        // Allow fallback to passcode
        context.localizedFallbackTitle = "Use Passcode"

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )

            if success {
                Log.session.info("Biometric authentication successful")
            }

            return success
        } catch let authError as LAError {
            Log.session.warning("Biometric auth failed: \(authError.localizedDescription)")

            // Handle specific errors
            switch authError.code {
            case .userFallback:
                // User tapped "Use Passcode"
                return await authenticateWithPasscode(reason: reason)
            case .userCancel:
                // User cancelled
                return false
            case .biometryLockout:
                // Too many failed attempts, use passcode
                return await authenticateWithPasscode(reason: reason)
            default:
                return false
            }
        } catch {
            Log.session.error("Biometric auth error: \(error.localizedDescription)")
            return false
        }
    }

    /// Authenticate with device passcode
    @MainActor
    static func authenticateWithPasscode(reason: String = "Unlock Whale POS") async -> Bool {
        let context = LAContext()

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,  // This includes passcode
                localizedReason: reason
            )

            if success {
                Log.session.info("Passcode authentication successful")
            }

            return success
        } catch {
            Log.session.error("Passcode auth error: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Setup

    /// Enable biometric auth after successful login
    static func enableBiometric(for email: String) {
        isBiometricEnabled = true
        stayLoggedIn = true
        lastAuthEmail = email
        Log.session.info("Biometric auth enabled for: \(email)")
    }

    /// Disable biometric auth
    static func disableBiometric() {
        isBiometricEnabled = false
        Log.session.info("Biometric auth disabled")
    }

    /// Clear all auth preferences (on sign out)
    static func clearPreferences() {
        UserDefaults.standard.removeObject(forKey: Keys.biometricEnabled)
        UserDefaults.standard.removeObject(forKey: Keys.stayLoggedIn)
        UserDefaults.standard.removeObject(forKey: Keys.lastAuthEmail)
        Log.session.info("Cleared biometric preferences")
    }

    // MARK: - Session Management

    /// Check if we should show lock screen vs login screen
    /// Returns true if user has valid session + biometric enabled
    static func shouldShowLockScreen(hasSession: Bool) -> Bool {
        return hasSession && isBiometricEnabled && stayLoggedIn
    }
}
