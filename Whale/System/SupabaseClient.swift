//
//  SupabaseClient.swift
//  Whale
//
//  Backend driver configuration.
//  No business logic. Transport + auth only.
//
//  SECURITY NOTE:
//  - The anon key is designed to be public (RLS enforces security)
//  - Never store service_role keys in client code
//  - All data access is filtered by Row Level Security policies
//
//  SESSION PERSISTENCE:
//  - Supabase Swift SDK stores sessions in Keychain by default
//  - emitLocalSessionAsInitialSession: true loads cached session on startup
//  - Sessions persist across app restarts and force closes
//

import Foundation
import Supabase
import Auth
import os.log

// MARK: - In-Memory Storage (No Keychain)

/// In-memory auth storage - no persistence, no Keychain I/O
/// Used to test if Keychain access is causing boot freezes
final class InMemoryLocalStorage: AuthLocalStorage, @unchecked Sendable {
    private var storage: [String: Data] = [:]
    private let lock = NSLock()

    func store(key: String, value: Data) throws {
        lock.withLock {
            storage[key] = value
        }
    }

    func retrieve(key: String) throws -> Data? {
        lock.withLock {
            storage[key]
        }
    }

    func remove(key: String) throws {
        _ = lock.withLock {
            storage.removeValue(forKey: key)
        }
    }
}

// MARK: - Configuration

enum SupabaseConfig: Sendable {
    // Read from Info.plist (populated by .xcconfig at build time)
    // Fallback values are for safety only — xcconfig should always provide real values
    private static let infoPlist = Bundle.main.infoDictionary ?? [:]

    nonisolated(unsafe) static let projectRef: String = {
        guard let ref = infoPlist["SUPABASE_PROJECT_REF"] as? String, !ref.isEmpty else {
            fatalError("SUPABASE_PROJECT_REF not set in xcconfig / Info.plist")
        }
        return ref
    }()

    nonisolated(unsafe) static let baseURL = "https://\(projectRef).supabase.co"
    nonisolated(unsafe) static let functionsBaseURL = "https://\(projectRef).functions.supabase.co"

    nonisolated(unsafe) static let url: URL = {
        guard let url = URL(string: "https://\(projectRef).supabase.co") else {
            fatalError("Invalid Supabase URL for project ref: \(projectRef)")
        }
        return url
    }()

    // Anon key - safe for client-side use (RLS protects data)
    nonisolated(unsafe) static let anonKey: String = {
        guard let key = infoPlist["SUPABASE_ANON_KEY"] as? String, !key.isEmpty else {
            fatalError("SUPABASE_ANON_KEY not set in xcconfig / Info.plist")
        }
        return key
    }()

    // SERVICE ROLE KEY REMOVED — must never be in client code.
    // Use edge functions or server-side calls for privileged operations.
}

// MARK: - Build Server Configuration

enum BuildServerConfig: Sendable {
    private static let infoPlist = Bundle.main.infoDictionary ?? [:]

    static let url: String = {
        guard let u = infoPlist["BUILD_SERVER_URL"] as? String, !u.isEmpty else {
            fatalError("BUILD_SERVER_URL not set in xcconfig / Info.plist")
        }
        return u
    }()

    static var wsURL: String {
        url.replacingOccurrences(of: "https://", with: "wss://")
    }

    static let secret: String = {
        guard let s = infoPlist["BUILD_SERVER_SECRET"] as? String, !s.isEmpty else {
            fatalError("BUILD_SERVER_SECRET not set in xcconfig / Info.plist")
        }
        return s
    }()
}

// MARK: - Client Instance

/// Thread-safe Supabase client with background initialization.
///
/// ARCHITECTURE FIX: SupabaseClient() constructor does synchronous Keychain reads
/// which block the main thread for 200-500ms. This caused:
/// - Splash screen freeze
/// - Modal freezes
/// - ID scanner freezes
/// - All UI blocking on first access
///
/// Solution: Initialize on a background thread at app startup.
/// By the time any code needs the client, it's already ready.
actor SupabaseClientWrapper {
    static let shared = SupabaseClientWrapper()

    /// The cached client - nil until initialization completes
    private var _cachedClient: SupabaseClient?

    /// The initialization task - runs once, can be awaited multiple times
    private let initTask: Task<SupabaseClient, Never>

    private init() {
        // Start initialization immediately on a background thread
        // This runs the Keychain I/O off the main thread
        initTask = Task.detached(priority: .userInitiated) {
            Log.network.info("🚀 Initializing Supabase client (background thread)")

            // Production config with session persistence
            let client = SupabaseClient(
                supabaseURL: SupabaseConfig.url,
                supabaseKey: SupabaseConfig.anonKey,
                options: .init(
                    auth: .init(
                        flowType: .implicit,
                        autoRefreshToken: true,
                        emitLocalSessionAsInitialSession: true
                    )
                )
            )

            Log.network.info("✅ Supabase client initialized")
            return client
        }
    }

    /// Get the Supabase client asynchronously.
    /// First call waits for initialization (off main thread).
    /// Subsequent calls return immediately from cache.
    func client() async -> SupabaseClient {
        // Fast path: already cached
        if let cached = _cachedClient {
            return cached
        }

        // Wait for initialization and cache result
        let client = await initTask.value
        _cachedClient = client

        return client
    }
}

/// Async global accessor - use this in async contexts
/// Waits for initialization without blocking main thread
func supabaseAsync() async -> SupabaseClient {
    await SupabaseClientWrapper.shared.client()
}

/// Sync global accessor - creates a fresh client for non-async contexts.
/// IMPORTANT: Prefer `await supabaseAsync()` in async contexts to reuse the cached client.
/// This accessor is safe but creates a new client each time (not cached).
var supabase: SupabaseClient {
    // For sync contexts, we can't await the actor, so create a fresh client
    // This is expensive but necessary for non-async code paths
    return SupabaseClient(
        supabaseURL: SupabaseConfig.url,
        supabaseKey: SupabaseConfig.anonKey,
        options: .init(
            auth: .init(
                flowType: .implicit,
                autoRefreshToken: true
            )
        )
    )
}
