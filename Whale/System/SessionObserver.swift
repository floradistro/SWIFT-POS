//
//  SessionObserver.swift
//  Whale
//
//  SwiftUI bridge for AppSession actor.
//  @MainActor only. No logic. No mutations. Pure bridge.
//
//  See ARCHITECTURE.md Rule 4.
//

import Foundation
import Combine
import os.log
import Supabase

@MainActor
final class SessionObserver: ObservableObject {
    static let shared = SessionObserver()

    // MARK: - State (NOT @Published - we manually control notifications)
    // This prevents cascading updates when multiple properties change at once

    private(set) var isAuthenticated = false
    private(set) var userEmail: String?
    private(set) var userId: UUID?        // auth.users.id
    private(set) var publicUserId: UUID?  // public.users.id (for FK constraints)
    private(set) var userFirstName: String?
    private(set) var userLastName: String?
    private(set) var store: Store?
    private(set) var storeId: UUID?
    private(set) var locations: [Location] = []
    private(set) var registers: [Register] = []
    private(set) var selectedLocation: Location?
    private(set) var selectedRegister: Register?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var activePOSSession: POSSession?
    private(set) var userStoreAssociations: [UserStoreAssociation] = []  // Multi-store support
    private(set) var loyaltyProgram: LoyaltyProgram?  // Store's loyalty program settings

    /// Whether user has access to multiple stores
    var hasMultipleStores: Bool { userStoreAssociations.count > 1 }

    /// Point value for loyalty redemption (from loyalty program or default)
    var loyaltyPointValue: Decimal { loyaltyProgram?.pointValue ?? Decimal(sign: .plus, exponent: -2, significand: 5) }

    // MARK: - Lock Screen State
    private(set) var isLocked = true
    private(set) var hasCheckedSession = false

    // CRITICAL: Use computed property to defer AppSession initialization
    // Using `let session = AppSession.shared` would trigger AppSession.init()
    // during SessionObserver.init(), which happens during @StateObject creation
    // BEFORE the first frame renders.
    private var session: AppSession { AppSession.shared }

    /// Whether start() has been called
    private var hasStarted = false

    private init() {
        // CRITICAL: Do NOTHING here!
        // Any work in init() causes SwiftUI to repeatedly rebuild the view tree
        // which triggers gesture gate timeouts and UI freezes.
        // All initialization happens in start() which is called from .task
        Log.session.debug("SessionObserver.init")

        // Listen for GitHub repo changes from Lisa
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("GitHubRepoChanged"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            Log.session.info("GitHub repo changed notification received")
            Task { @MainActor in
                await self.refreshStore()
            }
        }

        // Listen for general store data changes
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("StoreDataChanged"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            Log.session.info("Store data changed notification received")
            Task { @MainActor in
                await self.refreshStore()
            }
        }
    }

    // MARK: - Deferred Startup

    /// Call this from .task {} AFTER the first frame renders.
    /// This is where ALL initialization work happens.
    func start() async {
        guard !hasStarted else { return }
        hasStarted = true

        Log.session.debug("SessionObserver.start() - AFTER first frame")

        #if DEBUG
        // Clear session persistence between dev builds to ensure clean state
        clearPersistenceIfNewBuild()

        // Skip all warmups and delays in dev mode for faster build/load cycles
        // Set to false to re-enable warmups if debugging gesture gate issues
        let skipWarmupsForSpeed = true

        if !skipWarmupsForSpeed {
            // In debug builds, give Xcode's debugger time to fully attach
            // This prevents the "gesture gate timeout" freeze on fresh builds
            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
        }
        #else
        let skipWarmupsForSpeed = false
        #endif

        // 1. Supabase client (keychain I/O happens in background)
        _ = await supabaseAsync()
        Log.session.debug("Supabase ready")

        // 2. Warmups - run in background, don't block (skipped in dev mode for speed)
        if !skipWarmupsForSpeed {
            SubsystemWarmup.shared.warmIfNeeded()
            BiometricAuthService.warmup()
        } else {
            Log.session.debug("Skipping warmups for dev speed")
        }

        // 3. Check session and restore state
        await checkSession()
        Log.session.info("Session checked, boot complete")
    }

    // MARK: - Manual Change Notification

    /// True during initial boot - suppresses UI updates until boot completes
    private var isBooting = true

    /// Call this ONCE after batch updates to notify SwiftUI
    private func notifyChange() {
        // During boot, suppress notifications to prevent view re-creation cascade
        guard !isBooting else { return }
        objectWillChange.send()
    }

    /// Call this when boot is complete to enable UI updates
    func bootComplete() {
        isBooting = false
        objectWillChange.send()  // Single notification for all boot changes
    }

    // MARK: - Sync

    func sync() async {
        let snapshot = await session.snapshot()

        // Check if store changed (need to reload loyalty program)
        let storeChanged = storeId != snapshot.storeId

        // Update all properties silently
        isAuthenticated = snapshot.isAuthenticated
        userEmail = snapshot.userEmail
        userId = snapshot.userId
        publicUserId = snapshot.publicUserId
        userFirstName = snapshot.userFirstName
        userLastName = snapshot.userLastName
        store = snapshot.store
        storeId = snapshot.storeId
        locations = snapshot.locations
        registers = snapshot.registers
        selectedLocation = snapshot.selectedLocation
        selectedRegister = snapshot.selectedRegister
        activePOSSession = snapshot.activePOSSession
        userStoreAssociations = snapshot.userStoreAssociations

        // Load loyalty program if store changed or not yet loaded
        if storeChanged || (storeId != nil && loyaltyProgram == nil) {
            await loadLoyaltyProgram()
        }

        // Single notification for all changes (suppressed during boot)
        notifyChange()
    }

    // MARK: - Error Handling

    private func handleError(_ error: Error, context: String) {
        let appError = error.toAppError()
        Log.session.error("\(context): \(appError.errorDescription ?? "Unknown error")")
        errorMessage = appError.userMessage
        notifyChange()
    }

    func clearError() {
        errorMessage = nil
        notifyChange()
    }

    // MARK: - Auth

    func checkSession() async {
        errorMessage = nil

        do {
            try await session.checkSession()
            await sync()
            Log.session.info("Session restored successfully")

            // Determine if we should show lock screen or unlock directly
            if isAuthenticated {
                if BiometricAuthService.isBiometricEnabled && BiometricAuthService.stayLoggedIn {
                    isLocked = true
                    Log.session.info("Session valid, showing lock screen for biometric auth")
                } else {
                    isLocked = false
                    Log.session.info("Session valid, no biometric - unlocking")
                }

                // Load saved selections and theme - await them so boot completes with full state
                await loadSavedLocation()
                await loadSavedRegister()
                await loadSavedPOSSession()
                if let uid = publicUserId {
                    await ThemeManager.shared.loadFromSupabase(userId: uid)
                }
            } else {
                isLocked = false
            }
        } catch {
            Log.session.info("No existing session found")
            isLocked = false
            await sync()
        }

        hasCheckedSession = true

        // Boot complete - now enable UI updates with single notification
        bootComplete()
    }

    func signIn(email: String, password: String) async -> Bool {
        isLoading = true
        errorMessage = nil
        notifyChange()

        do {
            try await session.signIn(email: email, password: password)
            await sync()
            Log.session.info("User signed in: \(email)")

            BiometricAuthService.lastAuthEmail = email
            isLocked = false
            isLoading = false
            notifyChange()

            // Load saved selections and theme in background
            Task {
                await loadSavedLocation()
                await loadSavedRegister()
                if let uid = publicUserId {
                    await ThemeManager.shared.loadFromSupabase(userId: uid)
                }
            }

            return true
        } catch {
            handleError(error, context: "Sign in failed")
            isLoading = false
            notifyChange()
            return false
        }
    }

    func signOut() async {
        isLoading = true
        errorMessage = nil
        notifyChange()

        do {
            BiometricAuthService.clearPreferences()
            try await session.signOut()
            await sync()

            isLocked = false
            hasCheckedSession = true
            isLoading = false
            notifyChange()

            Log.session.info("User signed out")
        } catch {
            handleError(error, context: "Sign out failed")
            isLoading = false
            notifyChange()
        }
    }

    // MARK: - Biometric Unlock

    func unlockWithBiometric() async -> Bool {
        guard isAuthenticated else {
            Log.session.warning("Cannot unlock - no authenticated session")
            return false
        }

        let success = await BiometricAuthService.authenticate(reason: "Unlock Whale POS")

        if success {
            isLocked = false
            notifyChange()
            Log.session.info("Unlocked with biometric")
        } else {
            Log.session.info("Biometric unlock failed or cancelled")
        }

        return success
    }

    func enableBiometric() {
        guard let email = userEmail else { return }
        BiometricAuthService.enableBiometric(for: email)
        Log.session.info("Biometric enabled for \(email)")
    }

    func disableBiometric() {
        BiometricAuthService.disableBiometric()
        Log.session.info("Biometric disabled")
    }

    func lock() {
        guard isAuthenticated && BiometricAuthService.isBiometricEnabled else { return }
        isLocked = true
        notifyChange()
        Log.session.info("App locked")
    }

    // MARK: - Locations

    func fetchLocations() async {
        isLoading = true
        notifyChange()

        do {
            try await session.fetchLocations()
            await sync()
            Log.session.info("Fetched \(self.locations.count) locations")
        } catch {
            handleError(error, context: "Failed to fetch locations")
        }

        isLoading = false
        notifyChange()
    }

    func selectLocation(_ location: Location) async {
        await session.selectLocation(location)
        await sync()
        Log.session.info("Selected location: \(location.name)")
    }

    func loadSavedLocation() async {
        await session.loadSavedLocation()
        await sync()
    }

    func clearLocationSelection() async {
        await session.clearLocationSelection()
        await sync()
        Log.session.info("Cleared location selection")
    }

    // MARK: - Registers

    func fetchRegisters() async {
        isLoading = true
        notifyChange()

        do {
            try await session.fetchRegisters()
            await sync()
            Log.session.info("Fetched \(self.registers.count) registers")
        } catch {
            handleError(error, context: "Failed to fetch registers")
        }

        isLoading = false
        notifyChange()
    }

    func selectRegister(_ register: Register) async {
        await session.selectRegister(register)
        await sync()
        Log.session.info("Selected register: \(register.displayName)")
    }

    func loadSavedRegister() async {
        await session.loadSavedRegister()
        await sync()
    }

    func clearRegisterSelection() async {
        await session.clearRegisterSelection()
        await sync()
        Log.session.info("Cleared register selection")
    }

    // MARK: - Store

    /// Switch to a different store (multi-store support)
    func selectStore(_ storeId: UUID) async {
        await session.selectStore(storeId)
        await sync()

        // Fetch locations for the new store
        await fetchLocations()

        Log.session.info("Switched to store: \(storeId)")
    }

    func fetchStore() async {
        do {
            try await session.fetchStore()
            await sync()
            Log.session.info("Fetched store: \(self.store?.businessName ?? "Unknown")")
        } catch {
            Log.session.warning("Failed to fetch store: \(error.localizedDescription)")
        }
    }

    /// Refresh store data from database - call when external changes occur (e.g., Lisa creates a repo)
    func refreshStore() async {
        Log.session.info("Refreshing store data...")
        do {
            try await session.fetchStore()
            await sync()
            Log.session.info("Store refreshed - github_repo: \(self.store?.githubRepoFullName ?? "none")")
            // Also refresh loyalty program when store refreshes
            await loadLoyaltyProgram()
        } catch {
            Log.session.warning("Failed to refresh store: \(error.localizedDescription)")
        }
    }

    /// Load the store's loyalty program settings
    func loadLoyaltyProgram() async {
        guard let storeId = self.storeId else { return }
        do {
            let programs: [LoyaltyProgram] = try await supabase
                .from("loyalty_programs")
                .select()
                .eq("store_id", value: storeId.uuidString)
                .eq("is_active", value: true)
                .limit(1)
                .execute()
                .value
            self.loyaltyProgram = programs.first
            self.notifyChange()
            Log.session.info("Loaded loyalty program: point_value=\(self.loyaltyProgram?.pointValue ?? 0)")
        } catch {
            Log.session.warning("Failed to load loyalty program: \(error.localizedDescription)")
            // Use default on error
            self.loyaltyProgram = nil
        }
    }

    // MARK: - POS Session

    func startPOSSession(_ posSession: POSSession) async throws {
        try await session.startPOSSession(posSession)
        await sync()
        Log.session.info("Started POS session: \(posSession.id)")
    }

    func endPOSSession() async {
        await session.endPOSSession()
        await sync()
        Log.session.info("Ended POS session")
    }

    func loadSavedPOSSession() async {
        await session.loadSavedPOSSession()
        await sync()
    }

    // MARK: - Debug Helpers

    #if DEBUG
    /// Clears all session persistence when a new build is detected.
    /// Uses the app binary's modification date to detect Xcode rebuilds.
    private func clearPersistenceIfNewBuild() {
        // Get the app binary's modification date - this changes on every Xcode build
        let executableURL = Bundle.main.executableURL
        let currentBuildDate: Date? = executableURL.flatMap {
            try? FileManager.default.attributesOfItem(atPath: $0.path)[.modificationDate] as? Date
        }

        let lastBuildTimestamp = UserDefaults.standard.double(forKey: "lastDevBuildTimestamp")
        let currentTimestamp = currentBuildDate?.timeIntervalSince1970 ?? 0

        // If timestamps differ (new build), clear persistence
        if abs(currentTimestamp - lastBuildTimestamp) > 1 {
            let keysToReset = [
                "activePOSSessionData",
                "selectedLocationId",
                "selectedRegisterId",
                "BackgroundAgentState"
            ]
            keysToReset.forEach { UserDefaults.standard.removeObject(forKey: $0) }
            UserDefaults.standard.set(currentTimestamp, forKey: "lastDevBuildTimestamp")
            Log.session.debug("Cleared session persistence for new build (binary date: \(currentBuildDate?.description ?? "unknown"))")
        }
    }
    #endif
}
