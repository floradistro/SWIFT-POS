//
//  POSWindowSessionDrawer.swift
//  Whale
//
//  Cash drawer management extension for POSWindowSession.
//  SafeDrop, DrawerSummary, and drawer balance methods.
//

import Foundation

// MARK: - Safe Drop

extension POSWindowSession {

    struct SafeDrop: Identifiable, Codable {
        let id: UUID
        let amount: Decimal
        let timestamp: Date
        let notes: String?

        init(amount: Decimal, notes: String? = nil) {
            self.id = UUID()
            self.amount = amount
            self.timestamp = Date()
            self.notes = notes
        }
    }

    // MARK: - Drawer Summary

    struct DrawerSummary {
        let openingCash: Decimal
        let cashSales: Decimal
        let safeDrops: Decimal
        let expectedBalance: Decimal
        let dropCount: Int
    }

    // MARK: - Drawer Error

    enum DrawerError: LocalizedError {
        case invalidAmount
        case insufficientFunds

        var errorDescription: String? {
            switch self {
            case .invalidAmount: return "Amount must be greater than zero"
            case .insufficientFunds: return "Not enough cash in drawer"
            }
        }
    }
}
