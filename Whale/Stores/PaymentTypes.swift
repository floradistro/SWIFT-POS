//
//  PaymentTypes.swift
//  Whale
//
//  Payment-related types for UI rendering.
//  State machine logic is now in backend - these types are for display only.
//

import Foundation

// MARK: - UI State

/// Payment UI states - simplified to what the UI actually needs to render
enum UIPaymentState: Equatable {
    case idle
    case processing(message: String, amount: Decimal? = nil, label: String? = nil)
    case success(SaleCompletion)
    case failed(message: String)
}

// MARK: - Session Info

struct SessionInfo: Sendable {
    let storeId: UUID
    let locationId: UUID
    let registerId: UUID
    let sessionId: UUID
    let userId: UUID?
}
