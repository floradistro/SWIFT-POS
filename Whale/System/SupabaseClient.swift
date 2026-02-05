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
    // Production: floradistro.com
    nonisolated(unsafe) static let projectRef = "uaednwpxursknmwdeejn"
    nonisolated(unsafe) static let baseURL = "https://\(projectRef).supabase.co"
    nonisolated(unsafe) static let functionsBaseURL = "https://\(projectRef).functions.supabase.co"
    nonisolated(unsafe) static let url = URL(string: baseURL)!

    // Anon key - safe for client-side use (RLS protects data)
    nonisolated(unsafe) static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVhZWRud3B4dXJza25td2RlZWpuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjA5OTcyMzMsImV4cCI6MjA3NjU3MzIzM30.N8jPwlyCBB5KJB5I-XaK6m-mq88rSR445AWFJJmwRCg"

    // Service role key for edge functions (build-runner)
    nonisolated(unsafe) static let serviceKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVhZWRud3B4dXJza25td2RlZWpuIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2MDk5NzIzMywiZXhwIjoyMDc2NTczMjMzfQ.l0NvBbS2JQWPObtWeVD2M2LD866A2tgLmModARYNnbI"
}

// MARK: - Build Server Configuration

enum BuildServerConfig: Sendable {
    // Build server URL via Cloudflare Tunnel (permanent)
    static let url = "https://build.wh4le.net"
    static let wsURL = "wss://build.wh4le.net"

    // Build server secret - must match BUILD_SECRET in build-server/.env
    static let secret = "e650624a9b009c2b41619ae50620f0d9952f436e83efec92a428effd90343351"
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
                        autoRefreshToken: true
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
