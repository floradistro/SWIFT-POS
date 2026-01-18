//
//  CashDrop.swift
//  Whale
//
//  Cash drop model - represents cash moved from register to safe.
//  Used to track safe deposits during a shift.
//

import Foundation

// MARK: - Cash Drop

struct CashDrop: Codable, Identifiable, Sendable {
    let id: UUID
    let sessionId: UUID
    let locationId: UUID
    let registerId: UUID
    let userId: UUID?
    let amount: Decimal
    let notes: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case sessionId = "session_id"
        case locationId = "location_id"
        case registerId = "register_id"
        case userId = "user_id"
        case amount
        case notes
        case createdAt = "created_at"
    }

    /// Create a new cash drop
    static func create(
        sessionId: UUID,
        locationId: UUID,
        registerId: UUID,
        userId: UUID?,
        amount: Decimal,
        notes: String?
    ) -> CashDrop {
        CashDrop(
            id: UUID(),
            sessionId: sessionId,
            locationId: locationId,
            registerId: registerId,
            userId: userId,
            amount: amount,
            notes: notes,
            createdAt: Date()
        )
    }
}

// MARK: - Cash Drop Summary

/// Summary of drops for a session
struct CashDropSummary: Sendable {
    let drops: [CashDrop]
    let totalDropped: Decimal

    var dropCount: Int {
        drops.count
    }

    static let empty = CashDropSummary(drops: [], totalDropped: 0)
}
