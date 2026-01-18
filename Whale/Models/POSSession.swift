//
//  POSSession.swift
//  Whale
//
//  POS session model - represents an active cash drawer session.
//  A session starts when cash drawer is opened and ends when closed.
//

import Foundation

// MARK: - POS Session

struct POSSession: Codable, Identifiable, Sendable {
    let id: UUID
    let locationId: UUID
    let registerId: UUID
    let userId: UUID?
    let openingCash: Decimal
    let openingNotes: String?
    let openedAt: Date
    var closingCash: Decimal?
    var closingNotes: String?
    var closedAt: Date?
    var status: SessionStatus

    enum SessionStatus: String, Codable, Sendable {
        case open
        case closed
    }

    enum CodingKeys: String, CodingKey {
        case id
        case locationId = "location_id"
        case registerId = "register_id"
        case userId = "user_id"
        case openingCash = "opening_cash"
        case openingNotes = "opening_notes"
        case openedAt = "opened_at"
        case closingCash = "closing_cash"
        case closingNotes = "closing_notes"
        case closedAt = "closed_at"
        case status
    }

    var isOpen: Bool {
        status == .open
    }

    var duration: TimeInterval? {
        guard let closedAt = closedAt else {
            return Date().timeIntervalSince(openedAt)
        }
        return closedAt.timeIntervalSince(openedAt)
    }

    var formattedDuration: String {
        guard let duration = duration else { return "--" }

        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    /// Create a new session for opening the cash drawer
    static func create(
        locationId: UUID,
        registerId: UUID,
        userId: UUID?,
        openingCash: Decimal,
        notes: String?
    ) -> POSSession {
        POSSession(
            id: UUID(),
            locationId: locationId,
            registerId: registerId,
            userId: userId,
            openingCash: openingCash,
            openingNotes: notes,
            openedAt: Date(),
            closingCash: nil,
            closingNotes: nil,
            closedAt: nil,
            status: .open
        )
    }
}

// MARK: - Session Summary

/// Summary of session for closing modal
struct SessionSummary: Sendable {
    let totalSales: Decimal
    let cashSales: Decimal
    let cardSales: Decimal
    let refunds: Decimal
    let expectedCash: Decimal
    let transactionCount: Int

    var netCash: Decimal {
        cashSales - refunds
    }

    static let empty = SessionSummary(
        totalSales: 0,
        cashSales: 0,
        cardSales: 0,
        refunds: 0,
        expectedCash: 0,
        transactionCount: 0
    )
}
