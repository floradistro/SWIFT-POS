//
//  LocationQueueService.swift
//  Whale
//
//  Backend-driven location queue service.
//  Manages customer queue shared across all registers at a location.
//
//  BACKEND: /supabase/functions/location-queue/index.ts
//

import Foundation

// MARK: - Queue Models

struct QueueEntry: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let locationId: UUID
    let cartId: UUID
    let customerId: UUID?
    let position: Int
    let addedAt: Date
    let customerFirstName: String?
    let customerLastName: String?
    let customerPhone: String?
    let cartItemCount: Int
    let cartTotal: Decimal

    enum CodingKeys: String, CodingKey {
        case id
        case locationId = "location_id"
        case cartId = "cart_id"
        case customerId = "customer_id"
        case position
        case addedAt = "added_at"
        case customerFirstName = "customer_first_name"
        case customerLastName = "customer_last_name"
        case customerPhone = "customer_phone"
        case cartItemCount = "cart_item_count"
        case cartTotal = "cart_total"
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        locationId = try container.decode(UUID.self, forKey: .locationId)
        cartId = try container.decode(UUID.self, forKey: .cartId)
        customerId = try container.decodeIfPresent(UUID.self, forKey: .customerId)
        position = try container.decode(Int.self, forKey: .position)
        addedAt = try container.decode(Date.self, forKey: .addedAt)
        customerFirstName = try container.decodeIfPresent(String.self, forKey: .customerFirstName)
        customerLastName = try container.decodeIfPresent(String.self, forKey: .customerLastName)
        customerPhone = try container.decodeIfPresent(String.self, forKey: .customerPhone)
        // Default to 0 if not present (new cart has no items yet)
        cartItemCount = try container.decodeIfPresent(Int.self, forKey: .cartItemCount) ?? 0
        cartTotal = try container.decodeIfPresent(Decimal.self, forKey: .cartTotal) ?? 0
    }

    var customerName: String {
        let first = customerFirstName ?? ""
        let last = customerLastName ?? ""
        let name = "\(first) \(last)".trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Guest" : name
    }

    var customerInitials: String {
        let first = customerFirstName?.prefix(1).uppercased() ?? ""
        let last = customerLastName?.prefix(1).uppercased() ?? ""
        let initials = "\(first)\(last)"
        return initials.isEmpty ? "?" : initials
    }

    static func == (lhs: QueueEntry, rhs: QueueEntry) -> Bool {
        lhs.id == rhs.id && lhs.position == rhs.position && lhs.cartItemCount == rhs.cartItemCount
    }
}

struct QueueData: Codable {
    let queue: [QueueEntry]
    let count: Int
}

// MARK: - Location Queue Service

actor LocationQueueService {
    static let shared = LocationQueueService()

    private let baseURL: URL
    private let session: URLSession

    private init() {
        guard let url = URL(string: SupabaseConfig.functionsBaseURL) else {
            fatalError("Invalid Supabase functions URL: \(SupabaseConfig.functionsBaseURL)")
        }
        self.baseURL = url
        self.session = URLSession.shared
    }

    // MARK: - Queue Operations

    /// Get the current queue for a location
    func getQueue(locationId: UUID) async throws -> [QueueEntry] {
        let response: QueueResponse = try await post("location-queue", body: [
            "action": "get",
            "location_id": locationId.uuidString
        ])

        guard let data = response.data else {
            throw QueueError.serverError(response.error ?? "Failed to get queue")
        }

        return data.queue
    }

    /// Add a cart/customer to the queue
    func addToQueue(
        locationId: UUID,
        cartId: UUID,
        customerId: UUID?,
        userId: UUID?
    ) async throws -> [QueueEntry] {
        var body: [String: Any] = [
            "action": "add",
            "location_id": locationId.uuidString,
            "cart_id": cartId.uuidString
        ]

        if let customerId = customerId {
            body["customer_id"] = customerId.uuidString
        }
        if let userId = userId {
            body["user_id"] = userId.uuidString
        }

        let response: QueueResponse = try await post("location-queue", body: body)

        guard let data = response.data else {
            throw QueueError.serverError(response.error ?? "Failed to add to queue")
        }

        return data.queue
    }

    /// Remove a cart from the queue
    func removeFromQueue(locationId: UUID, cartId: UUID) async throws -> [QueueEntry] {
        let response: QueueResponse = try await post("location-queue", body: [
            "action": "remove",
            "location_id": locationId.uuidString,
            "cart_id": cartId.uuidString
        ])

        guard let data = response.data else {
            throw QueueError.serverError(response.error ?? "Failed to remove from queue")
        }

        return data.queue
    }

    /// Clear the entire queue for a location
    func clearQueue(locationId: UUID) async throws {
        let response: QueueResponse = try await post("location-queue", body: [
            "action": "clear",
            "location_id": locationId.uuidString
        ])

        if !response.success {
            throw QueueError.serverError(response.error ?? "Failed to clear queue")
        }
    }

    /// Reorder an item in the queue
    func reorderQueue(locationId: UUID, cartId: UUID, newPosition: Int) async throws -> [QueueEntry] {
        let response: QueueResponse = try await post("location-queue", body: [
            "action": "reorder",
            "location_id": locationId.uuidString,
            "cart_id": cartId.uuidString,
            "new_position": newPosition
        ])

        guard let data = response.data else {
            throw QueueError.serverError(response.error ?? "Failed to reorder queue")
        }

        return data.queue
    }

    // MARK: - HTTP Helpers

    private func post<T: Decodable>(_ path: String, body: [String: Any]) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw QueueError.networkError
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown"
            throw QueueError.serverError("HTTP \(httpResponse.statusCode): \(errorBody)")
        }

        let decoder = JSONDecoder()
        // Use custom ISO8601 date decoding that handles fractional seconds
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            // Try with fractional seconds first
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: dateString) {
                return date
            }
            // Fallback to standard ISO8601
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: dateString) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date: \(dateString)")
        }
        return try decoder.decode(T.self, from: data)
    }
}

// MARK: - Response Types

private struct QueueResponse: Sendable {
    let success: Bool
    let data: QueueData?
    let entry: QueueEntry?
    let error: String?

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decode(Bool.self, forKey: .success)
        data = try container.decodeIfPresent(QueueData.self, forKey: .data)
        entry = try container.decodeIfPresent(QueueEntry.self, forKey: .entry)
        error = try container.decodeIfPresent(String.self, forKey: .error)
    }

    enum CodingKeys: String, CodingKey {
        case success, data, entry, error
    }
}

extension QueueResponse: Decodable {}

// MARK: - Errors

enum QueueError: LocalizedError {
    case serverError(String)
    case networkError
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .serverError(let message): return message
        case .networkError: return "Network error"
        case .httpError(let code): return "HTTP error: \(code)"
        }
    }
}
