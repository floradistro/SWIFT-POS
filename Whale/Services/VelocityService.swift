//
//  VelocityService.swift
//  Whale
//
//  Sales velocity service for product analytics.
//  Fetches and caches 7-day sales velocity data for products.
//  Used by ProductInsightsPanel to show what's selling vs stale.
//

import Foundation
import Combine
import Supabase
import os.log

// MARK: - Velocity Data Models

struct ProductVelocity: Codable, Sendable {
    let productId: String
    let categoryId: String?
    let daily: [DailyVelocity]
    let totalUnits: Double
    let avgPerDay: Double
    let categoryAvgPerDay: Double
    let percentile: Int
    let trend: VelocityTrend
    let velocityScore: Int
    let health: VelocityHealth

    enum CodingKeys: String, CodingKey {
        case productId = "product_id"
        case categoryId = "category_id"
        case daily
        case totalUnits = "total_units"
        case avgPerDay = "avg_per_day"
        case categoryAvgPerDay = "category_avg_per_day"
        case percentile
        case trend
        case velocityScore = "velocity_score"
        case health
    }

    /// Normalized values for chart display (0-1 range)
    var normalizedDaily: [Double] {
        guard !daily.isEmpty else { return [] }
        let maxUnits = daily.map { $0.units }.max() ?? 1
        guard maxUnits > 0 else { return daily.map { _ in 0.0 } }
        return daily.map { $0.units / maxUnits }
    }

    /// Comparison to category average
    var vsCategory: String {
        guard categoryAvgPerDay > 0 else { return "" }
        let ratio = avgPerDay / categoryAvgPerDay
        if ratio >= 1.5 { return "+\(Int((ratio - 1) * 100))%" }
        if ratio >= 1.1 { return "+\(Int((ratio - 1) * 100))%" }
        if ratio <= 0.5 { return "\(Int((ratio - 1) * 100))%" }
        if ratio <= 0.9 { return "\(Int((ratio - 1) * 100))%" }
        return "avg"
    }
}

struct DailyVelocity: Codable, Sendable {
    let day: String
    let units: Double
}

enum VelocityTrend: String, Codable, Sendable {
    case rising
    case steady
    case falling

    var icon: String {
        switch self {
        case .rising: return "arrow.up.right"
        case .steady: return "arrow.right"
        case .falling: return "arrow.down.right"
        }
    }
}

enum VelocityHealth: String, Codable, Sendable {
    case hot, good, slow, stale

    var label: String {
        switch self {
        case .hot: return "Hot"
        case .good: return "Good"
        case .slow: return "Slow"
        case .stale: return "Stale"
        }
    }
}

// MARK: - API Response

private struct BatchVelocityResponse: Codable {
    let success: Bool
    let velocities: [String: ProductVelocity]?
    let error: String?
}

// MARK: - Velocity Service

@MainActor
final class VelocityService: ObservableObject {
    static let shared = VelocityService()

    private let logger = Logger(subsystem: "com.whale", category: "VelocityService")

    // Cache with TTL
    @Published private(set) var velocityCache: [UUID: ProductVelocity] = [:]
    private var cacheTimestamp: Date?
    private let cacheTTL: TimeInterval = 300 // 5 minutes

    // Loading state
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?

    // Edge function URL
    private var functionURL: String {
        "\(SupabaseConfig.baseURL)/functions/v1/product-velocity"
    }

    private init() {}

    // MARK: - Public API

    /// Get velocity for a product (from cache or fetch if needed)
    func velocity(for productId: UUID) -> ProductVelocity? {
        return velocityCache[productId]
    }

    /// Check if cache is valid
    var isCacheValid: Bool {
        guard let timestamp = cacheTimestamp else { return false }
        return Date().timeIntervalSince(timestamp) < cacheTTL
    }

    /// Fetch velocity for multiple products (batch)
    func fetchVelocity(for productIds: [UUID], storeId: UUID, forceRefresh: Bool = false) async {
        print("📊 VelocityService.fetchVelocity called with \(productIds.count) products")

        // Skip if cache is valid and not forcing refresh
        if !forceRefresh && isCacheValid {
            // Check if all requested products are in cache
            let allCached = productIds.allSatisfy { velocityCache[$0] != nil }
            if allCached {
                print("📊 VelocityService: Using cached data")
                return
            }
        }

        guard !isLoading else {
            print("📊 VelocityService: Already loading, skipping")
            return
        }

        isLoading = true
        lastError = nil

        do {
            print("📊 VelocityService: Calling fetchBatch...")
            let velocities = try await fetchBatch(productIds: productIds, storeId: storeId)
            print("📊 VelocityService: Got \(velocities.count) velocities from API")

            // Update cache
            for (idString, velocity) in velocities {
                if let uuid = UUID(uuidString: idString) {
                    velocityCache[uuid] = velocity
                    print("📊 Cached: \(idString.prefix(8)) -> \(velocity.health.rawValue), \(velocity.totalUnits) sold")
                }
            }
            cacheTimestamp = Date()

            print("📊 VelocityService: Cache now has \(velocityCache.count) items")
        } catch {
            print("📊 VelocityService ERROR: \(error.localizedDescription)")
            lastError = error.localizedDescription
        }

        isLoading = false
    }

    /// Clear cache (e.g., on store change)
    func clearCache() {
        velocityCache.removeAll()
        cacheTimestamp = nil
        logger.debug("Velocity cache cleared")
    }

    // MARK: - Private

    private func fetchBatch(productIds: [UUID], storeId: UUID) async throws -> [String: ProductVelocity] {
        guard let url = URL(string: functionURL) else {
            throw VelocityError.invalidURL
        }

        logger.info("📊 Fetching velocity for \(productIds.count) products, store: \(storeId.uuidString)")

        let body: [String: Any] = [
            "action": "batch",
            "store_id": storeId.uuidString,
            "product_ids": productIds.map { $0.uuidString },
            "days": 7
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Auth token
        if let session = try? await supabase.auth.session {
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        }

        // API key
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw VelocityError.invalidResponse
        }

        // Debug: log raw response
        if let rawResponse = String(data: data, encoding: .utf8) {
            logger.debug("📊 Raw velocity response: \(rawResponse.prefix(500))")
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            logger.error("Velocity API error (\(httpResponse.statusCode)): \(errorMessage)")
            throw VelocityError.apiError(httpResponse.statusCode, errorMessage)
        }

        let decoder = JSONDecoder()
        let result = try decoder.decode(BatchVelocityResponse.self, from: data)

        guard result.success else {
            throw VelocityError.apiError(0, result.error ?? "Unknown error")
        }

        // Debug: log parsed velocities
        if let velocities = result.velocities {
            for (id, vel) in velocities.prefix(3) {
                logger.info("📊 Product \(id): health=\(vel.health.rawValue), total=\(vel.totalUnits), percentile=\(vel.percentile)")
            }
        }

        return result.velocities ?? [:]
    }
}

// MARK: - Errors

enum VelocityError: LocalizedError {
    case invalidURL
    case invalidResponse
    case apiError(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid velocity service URL"
        case .invalidResponse:
            return "Invalid response from velocity service"
        case .apiError(let code, let message):
            return "Velocity API error (\(code)): \(message)"
        }
    }
}
