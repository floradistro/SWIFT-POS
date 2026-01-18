//
//  AppSession.swift
//  Whale
//
//  Session state actor.
//  Owns: auth, active location, active register, store info.
//  Does NOT own: business logic, computations, decisions.
//
//  See ARCHITECTURE.md Rule 2.
//

import Foundation
import Supabase
import Auth
import os.log

// MARK: - Session Actor

actor AppSession {
    static let shared = AppSession()

    // MARK: - State
    private(set) var currentUser: User?
    private(set) var store: Store?
    private(set) var locations: [Location] = []
    private(set) var registers: [Register] = []
    private(set) var selectedLocation: Location?
    private(set) var selectedRegister: Register?
    private(set) var activePOSSession: POSSession?

    // Multi-store support: user can have access to multiple stores
    private(set) var userStoreAssociations: [UserStoreAssociation] = []

    // Currently selected store (from userStoreAssociations)
    private(set) var _storeId: UUID?
    private(set) var _publicUserId: UUID?  // public.users.id for current store

    // Prevent concurrent store fetches
    private var storeFetchTask: Task<Void, Error>?

    // MARK: - Computed
    var isAuthenticated: Bool { currentUser != nil }

    var storeId: UUID? { _storeId }

    private init() {
        // CRITICAL: Do NOTHING here - not even logging!
        // This init runs when SessionObserver.session computed property is first accessed.
        // Any work here delays the first frame.
    }

    // MARK: - Auth

    func checkSession() async throws {
        // Get Supabase client asynchronously - this waits for background initialization
        // to complete without blocking the main thread
        let client = await supabaseAsync()

        // Try to get cached session first (should be instant with emitLocalSessionAsInitialSession)
        do {
            let session = try await client.auth.session
            self.currentUser = session.user

            // Only fetch store_id if we have a session
            if session.user != nil {
                // Fetch store_id from users table (required for edge function auth)
                // Do this quickly without waiting for store details
                do {
                    try await fetchUserStoreId()
                } catch {
                    Log.session.error("Failed to fetch store ID during session check: \(error.localizedDescription)")
                    // Don't throw - allow user to continue even if store fetch fails
                }
            }
        } catch {
            // No session - that's fine, user will sign in
            Log.session.debug("No session available: \(error.localizedDescription)")
            throw error
        }
    }

    func signIn(email: String, password: String) async throws {
        let session = try await supabase.auth.signIn(email: email, password: password)
        self.currentUser = session.user
        // Fetch store_id from users table (required for edge function auth)
        // Do this quickly without waiting for store details
        do {
            try await fetchUserStoreId()
        } catch {
            Log.session.error("Failed to fetch store ID during sign in: \(error.localizedDescription)")
            // Don't throw - allow user to sign in even if store fetch fails
        }
    }

    /// Fetch ALL store associations for this user (multi-store support)
    private func fetchUserStoreId() async throws {
        guard let authUserId = currentUser?.id else { return }

        struct UserStoreRow: Decodable {
            let id: UUID  // The public.users row ID (for FK constraints)
            let store_id: UUID
            let first_name: String?
            let last_name: String?
            let stores: StoreInfo?

            struct StoreInfo: Decodable {
                let store_name: String
            }
        }

        // Fetch ALL stores user has access to (not just one) with store name
        let rows: [UserStoreRow] = try await supabase
            .from("users")
            .select("id, store_id, first_name, last_name, stores(store_name)")
            .eq("auth_user_id", value: authUserId.uuidString)
            .execute()
            .value

        // Convert to associations
        self.userStoreAssociations = rows.map { row in
            UserStoreAssociation(
                publicUserId: row.id,
                storeId: row.store_id,
                storeName: row.stores?.store_name,
                firstName: row.first_name,
                lastName: row.last_name
            )
        }

        Log.session.info("User has access to \(self.userStoreAssociations.count) store(s)")

        // Auto-select: use saved preference or first store
        if let savedStoreId = UserDefaults.standard.string(forKey: "selectedStoreId"),
           let uuid = UUID(uuidString: savedStoreId),
           let association = userStoreAssociations.first(where: { $0.storeId == uuid }) {
            selectStoreAssociation(association)
        } else if let first = userStoreAssociations.first {
            selectStoreAssociation(first)
        }
    }

    /// Select a store from user's available stores
    func selectStore(_ storeId: UUID) {
        guard let association = userStoreAssociations.first(where: { $0.storeId == storeId }) else {
            Log.session.error("Store \(storeId) not in user's available stores")
            return
        }
        selectStoreAssociation(association)

        // Clear location/register when switching stores
        selectedLocation = nil
        selectedRegister = nil
        locations = []
        registers = []
        store = nil
        UserDefaults.standard.removeObject(forKey: "selectedLocationId")
        UserDefaults.standard.removeObject(forKey: "selectedRegisterId")
    }

    private func selectStoreAssociation(_ association: UserStoreAssociation) {
        self._publicUserId = association.publicUserId
        self._storeId = association.storeId
        self._userFirstName = association.firstName
        self._userLastName = association.lastName
        UserDefaults.standard.set(association.storeId.uuidString, forKey: "selectedStoreId")
        Log.session.info("Selected store: \(association.storeId)")
    }

    // User ID from public.users table (for FK constraints like pos_sessions)
    var publicUserId: UUID? { _publicUserId }

    // User name storage
    private var _userFirstName: String?
    private var _userLastName: String?

    var userFirstName: String? { _userFirstName }
    var userLastName: String? { _userLastName }

    func signOut() async throws {
        try await supabase.auth.signOut()
        currentUser = nil
        _storeId = nil
        _publicUserId = nil
        store = nil
        locations = []
        registers = []
        selectedLocation = nil
        selectedRegister = nil
        userStoreAssociations = []
        UserDefaults.standard.removeObject(forKey: "selectedLocationId")
        UserDefaults.standard.removeObject(forKey: "selectedRegisterId")
        UserDefaults.standard.removeObject(forKey: "selectedStoreId")
    }

    // MARK: - Store

    func fetchStore() async throws {
        guard let storeId = storeId else { return }

        // If already fetching, wait for existing task
        if let existingTask = storeFetchTask {
            try await existingTask.value
            return
        }

        // If already have store data, skip
        if store != nil {
            return
        }

        // Create new fetch task
        let task = Task<Void, Error> {
            let response: Store = try await supabase
                .from("stores")
                .select()
                .eq("id", value: storeId.uuidString)
                .single()
                .execute()
                .value
            self.store = response
            Log.session.info("Fetched store: \(response.businessName ?? "Unknown")")
        }

        storeFetchTask = task

        do {
            try await task.value
        } catch {
            storeFetchTask = nil
            throw error
        }

        storeFetchTask = nil
    }

    // MARK: - Locations

    func fetchLocations() async throws {
        guard let storeId = storeId else { throw AppSessionError.noStore }
        let response: [Location] = try await supabase
            .from("locations")
            .select()
            .eq("store_id", value: storeId.uuidString)
            .eq("is_active", value: true)
            .eq("pos_enabled", value: true)
            .order("name")
            .execute()
            .value
        self.locations = response
    }

    func selectLocation(_ location: Location) {
        selectedLocation = location
        selectedRegister = nil
        registers = []
        UserDefaults.standard.set(location.id.uuidString, forKey: "selectedLocationId")
        UserDefaults.standard.removeObject(forKey: "selectedRegisterId")
    }

    func loadSavedLocation() async {
        guard let savedId = UserDefaults.standard.string(forKey: "selectedLocationId"),
              let uuid = UUID(uuidString: savedId) else { return }
        if locations.isEmpty {
            do {
                try await fetchLocations()
            } catch {
                Log.session.error("Failed to fetch locations while loading saved location: \(error.localizedDescription)")
                return
            }
        }
        selectedLocation = locations.first { $0.id == uuid }
    }

    func clearLocationSelection() {
        selectedLocation = nil
        selectedRegister = nil
        registers = []
        UserDefaults.standard.removeObject(forKey: "selectedLocationId")
        UserDefaults.standard.removeObject(forKey: "selectedRegisterId")
    }

    /// Sync selectedLocation to match a POS session's location
    /// This ensures there's never a mismatch between session location and cached selectedLocation
    private func syncSelectedLocationToSession(_ sessionLocationId: UUID) {
        // Find the location matching the session
        if let matchingLocation = locations.first(where: { $0.id == sessionLocationId }) {
            if selectedLocation?.id != sessionLocationId {
                Log.session.info("Syncing selectedLocation to match POS session: \(matchingLocation.name)")
                selectedLocation = matchingLocation
                UserDefaults.standard.set(sessionLocationId.uuidString, forKey: "selectedLocationId")
            }
        } else {
            Log.session.warning("Could not find location \(sessionLocationId) to sync with session")
        }
    }

    // MARK: - Registers

    func fetchRegisters() async throws {
        guard let locationId = selectedLocation?.id else { throw AppSessionError.noLocation }
        let response: [Register] = try await supabase
            .from("pos_registers")
            .select()
            .eq("location_id", value: locationId.uuidString.lowercased())
            .eq("status", value: "active")
            .order("register_name")
            .execute()
            .value
        self.registers = response
    }

    func selectRegister(_ register: Register) {
        selectedRegister = register
        UserDefaults.standard.set(register.id.uuidString, forKey: "selectedRegisterId")
    }

    func loadSavedRegister() async {
        guard let savedId = UserDefaults.standard.string(forKey: "selectedRegisterId"),
              let uuid = UUID(uuidString: savedId) else { return }
        if registers.isEmpty, selectedLocation != nil {
            do {
                try await fetchRegisters()
            } catch {
                Log.session.error("Failed to fetch registers while loading saved register: \(error.localizedDescription)")
                return
            }
        }
        selectedRegister = registers.first { $0.id == uuid }
    }

    func clearRegisterSelection() {
        selectedRegister = nil
        UserDefaults.standard.removeObject(forKey: "selectedRegisterId")
    }

    // MARK: - POS Session

    /// Start a new POS session and save to database
    func startPOSSession(_ posSession: POSSession) async throws {
        let client = await supabaseAsync()

        // Check if there's already an open session for this register
        struct ExistingSession: Decodable {
            let id: UUID
            let opening_cash: Double
            let opened_at: String
            let opening_notes: String?
        }

        let existingResults: [ExistingSession] = try await client
            .from("pos_sessions")
            .select("id, opening_cash, opened_at, opening_notes")
            .eq("register_id", value: posSession.registerId.uuidString.lowercased())
            .eq("status", value: "open")
            .execute()
            .value

        if let existing = existingResults.first {
            // Reuse existing open session
            let dateFormatter = ISO8601DateFormatter()
            let openedAt = dateFormatter.date(from: existing.opened_at) ?? Date()

            let restoredSession = POSSession(
                id: existing.id,
                locationId: posSession.locationId,
                registerId: posSession.registerId,
                userId: posSession.userId,
                openingCash: Decimal(existing.opening_cash),
                openingNotes: existing.opening_notes,
                openedAt: openedAt,
                closingCash: nil,
                closingNotes: nil,
                closedAt: nil,
                status: .open
            )

            activePOSSession = restoredSession
            savePOSSessionToDefaults(restoredSession)

            // IMPORTANT: Sync selectedLocation to match the session's location
            // This prevents stale cached location from being used for cart creation
            syncSelectedLocationToSession(restoredSession.locationId)

            Log.session.info("Reusing existing open session: \(existing.id)")
            return
        }

        // No existing session - create new one
        // Save locally first so UI updates immediately
        activePOSSession = posSession
        savePOSSessionToDefaults(posSession)

        // IMPORTANT: Sync selectedLocation to match the session's location
        syncSelectedLocationToSession(posSession.locationId)

        // Generate session number: S-YYYYMMDD-HHMMSS
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd-HHmmss"
        let sessionNumber = "S-\(dateFormatter.string(from: posSession.openedAt))"

        // Save to database
        var sessionData: [String: AnyJSON] = [
            "id": .string(posSession.id.uuidString.lowercased()),
            "location_id": .string(posSession.locationId.uuidString.lowercased()),
            "register_id": .string(posSession.registerId.uuidString.lowercased()),
            "session_number": .string(sessionNumber),
            "opening_cash": .double(NSDecimalNumber(decimal: posSession.openingCash).doubleValue),
            "opened_at": .string(ISO8601DateFormatter().string(from: posSession.openedAt)),
            "status": .string("open")
        ]

        if let userId = posSession.userId {
            sessionData["user_id"] = .string(userId.uuidString.lowercased())
        }
        if let storeId = storeId {
            sessionData["store_id"] = .string(storeId.uuidString.lowercased())
        }
        if let notes = posSession.openingNotes {
            sessionData["opening_notes"] = .string(notes)
        }

        try await client
            .from("pos_sessions")
            .insert(sessionData)
            .execute()

        Log.session.info("POS session saved to database: \(posSession.id)")
    }

    /// End the current POS session
    func endPOSSession() async {
        guard let posSession = activePOSSession else { return }

        // Clear locally first so UI updates immediately
        activePOSSession = nil
        UserDefaults.standard.removeObject(forKey: "activePOSSessionData")

        // Update database to mark session as closed
        do {
            let client = await supabaseAsync()
            try await client
                .from("pos_sessions")
                .update(["status": "closed", "closed_at": ISO8601DateFormatter().string(from: Date())])
                .eq("id", value: posSession.id.uuidString.lowercased())
                .execute()

            Log.session.info("POS session closed in database: \(posSession.id)")
        } catch {
            Log.session.error("Failed to close POS session in database: \(error.localizedDescription)")
        }
    }

    /// Load saved POS session from UserDefaults and verify it's still valid
    func loadSavedPOSSession() async {
        guard let data = UserDefaults.standard.data(forKey: "activePOSSessionData"),
              let posSession = try? JSONDecoder().decode(POSSession.self, from: data) else {
            return
        }

        // Verify session is still open in database
        do {
            struct SessionStatus: Decodable {
                let status: String
            }

            let client = await supabaseAsync()
            let result: [SessionStatus] = try await client
                .from("pos_sessions")
                .select("status")
                .eq("id", value: posSession.id.uuidString.lowercased())
                .execute()
                .value

            if let dbSession = result.first, dbSession.status == "open" {
                activePOSSession = posSession
                // Sync selectedLocation to match restored session
                syncSelectedLocationToSession(posSession.locationId)
                Log.session.info("Restored active POS session: \(posSession.id)")
            } else {
                // Session was closed or doesn't exist - clear local storage
                UserDefaults.standard.removeObject(forKey: "activePOSSessionData")
                Log.session.info("Saved POS session is no longer active, cleared")
            }
        } catch {
            Log.session.error("Failed to verify POS session: \(error.localizedDescription)")
            // Keep local session as fallback
            activePOSSession = posSession
            // Sync selectedLocation to match restored session
            syncSelectedLocationToSession(posSession.locationId)
        }
    }

    private func savePOSSessionToDefaults(_ session: POSSession) {
        if let data = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(data, forKey: "activePOSSessionData")
        }
    }

    // MARK: - Snapshot

    func snapshot() -> SessionSnapshot {
        SessionSnapshot(
            isAuthenticated: isAuthenticated,
            userEmail: currentUser?.email,
            userId: currentUser?.id,
            publicUserId: publicUserId,  // The public.users.id for FK constraints
            userFirstName: userFirstName,
            userLastName: userLastName,
            store: store,
            storeId: storeId,
            locations: locations,
            registers: registers,
            selectedLocation: selectedLocation,
            selectedRegister: selectedRegister,
            activePOSSession: activePOSSession,
            userStoreAssociations: userStoreAssociations
        )
    }
}

// MARK: - Errors

enum AppSessionError: LocalizedError, Sendable {
    case noStore
    case noLocation

    var errorDescription: String? {
        switch self {
        case .noStore: return "No store associated with this account"
        case .noLocation: return "No location selected"
        }
    }
}

// MARK: - Snapshot

/// Thread-safe snapshot of session state for SwiftUI bridge.
/// Contains only Sendable types - no raw User reference.
struct SessionSnapshot: Sendable {
    let isAuthenticated: Bool
    let userEmail: String?
    let userId: UUID?           // auth.users.id (for Supabase auth)
    let publicUserId: UUID?     // public.users.id (for FK constraints)
    let userFirstName: String?
    let userLastName: String?
    let store: Store?
    let storeId: UUID?
    let locations: [Location]
    let registers: [Register]
    let selectedLocation: Location?
    let selectedRegister: Register?
    let activePOSSession: POSSession?
    let userStoreAssociations: [UserStoreAssociation]  // Multi-store support
}

// MARK: - User Info (Sendable extraction from Auth.User)

/// Sendable user information extracted from Auth.User
struct UserInfo: Sendable {
    let id: UUID
    let email: String?
    let createdAt: Date
}

// MARK: - Multi-Store Support

/// Represents a user's association with a store (multi-store accounts)
struct UserStoreAssociation: Identifiable, Sendable, Hashable {
    let publicUserId: UUID  // public.users.id for this store association
    let storeId: UUID
    let storeName: String?
    let firstName: String?
    let lastName: String?

    var id: UUID { storeId }

    var displayName: String {
        storeName ?? "Store \(storeId.uuidString.prefix(8))..."
    }
}
