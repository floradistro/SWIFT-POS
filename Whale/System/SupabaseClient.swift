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
        lock.lock()
        defer { lock.unlock() }
        storage[key] = value
    }

    func retrieve(key: String) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }

    func remove(key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        storage.removeValue(forKey: key)
    }
}

// MARK: - Configuration

enum SupabaseConfig {
    // Production: floradistro.com
    static let projectRef = "uaednwpxursknmwdeejn"
    static let baseURL = "https://\(projectRef).supabase.co"
    static let functionsBaseURL = "https://\(projectRef).functions.supabase.co"
    static let url = URL(string: baseURL)!

    // Anon key - safe for client-side use (RLS protects data)
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVhZWRud3B4dXJza25td2RlZWpuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjA5OTcyMzMsImV4cCI6MjA3NjU3MzIzM30.N8jPwlyCBB5KJB5I-XaK6m-mq88rSR445AWFJJmwRCg"

    // Service role key for edge functions (build-runner)
    static let serviceKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVhZWRud3B4dXJza25td2RlZWpuIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTczMjE1NDU0NywiZXhwIjoyMDQ3NzMwNTQ3fQ.zdHSMFVu8X3BBK3R4d9zg_fY-rCVNqXyYItE3659xyY"
}

// MARK: - Build Server Configuration

enum BuildServerConfig {
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
final class SupabaseClientWrapper: @unchecked Sendable {
    static let shared = SupabaseClientWrapper()

    /// The cached client - nil until initialization completes
    private var _cachedClient: SupabaseClient?
    private let lock = NSLock()

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
        lock.lock()
        if let cached = _cachedClient {
            lock.unlock()
            return cached
        }
        lock.unlock()

        // Wait for initialization and cache result
        let client = await initTask.value

        lock.lock()
        _cachedClient = client
        lock.unlock()

        return client
    }

    /// Synchronous access - returns cached client or nil if not ready.
    /// NEVER blocks. Returns nil if initialization hasn't completed.
    var clientIfReady: SupabaseClient? {
        lock.lock()
        defer { lock.unlock() }
        return _cachedClient
    }
}

/// Async global accessor - use this in async contexts
/// Waits for initialization without blocking main thread
func supabaseAsync() async -> SupabaseClient {
    await SupabaseClientWrapper.shared.client()
}

/// Sync global accessor - returns cached client or triggers async initialization.
/// IMPORTANT: Prefer `await supabaseAsync()` in async contexts.
/// This accessor is safe to use after app initialization (e.g., in realtime subscriptions).
var supabase: SupabaseClient {
    // Fast path: return cached client immediately (no blocking)
    if let cached = SupabaseClientWrapper.shared.clientIfReady {
        return cached
    }

    // Client not ready - this should only happen during early app startup
    // Instead of blocking with RunLoop, trigger background init and return placeholder
    Log.network.warning("⚠️ Supabase accessed before init - triggering async initialization")

    // Trigger the async initialization in background (doesn't block)
    Task.detached {
        _ = await SupabaseClientWrapper.shared.client()
    }

    // Check once more after triggering - may have completed
    if let cached = SupabaseClientWrapper.shared.clientIfReady {
        return cached
    }

    // Last resort: create a fresh client synchronously
    // This is expensive but won't deadlock - only happens if accessed very early
    Log.network.error("⚠️ Creating emergency Supabase client - investigate early access pattern")
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
