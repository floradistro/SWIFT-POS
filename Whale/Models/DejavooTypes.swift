//
//  DejavooTypes.swift
//  Whale
//
//  Dejavoo payment terminal types: config, payment types,
//  request/response DTOs, errors, and terminal protocol.
//

import Foundation

// MARK: - Dejavoo Configuration

struct DejavooConfig: Sendable {
    let authKey: String
    let tpn: String  // Terminal Profile Number
    let environment: DejavooEnvironment
    let timeoutSeconds: Int  // SPInProxyTimeout is in SECONDS (1-720)

    init(authKey: String, tpn: String, environment: DejavooEnvironment = .production, timeoutSeconds: Int = 180) {
        self.authKey = authKey
        self.tpn = tpn
        self.environment = environment
        self.timeoutSeconds = timeoutSeconds
    }
}

enum DejavooEnvironment: String, Sendable {
    case production
    case sandbox

    var baseURL: String {
        switch self {
        case .production: return "https://spin.spinpos.net"
        case .sandbox: return "https://test.spinpos.net/spin"
        }
    }
}

// MARK: - Payment Types

enum DejavooPaymentType: String, Sendable {
    case credit = "Credit"
    case debit = "Debit"
    case ebtFood = "EBT_Food"
    case ebtCash = "EBT_Cash"
    case gift = "Gift"
    case cash = "Cash"
    case check = "Check"
}

enum DejavooReceiptOption: String, Sendable {
    case none = "No"
    case both = "Both"
    case merchant = "Merchant"
    case customer = "Customer"
}

// MARK: - Request/Response Types

struct DejavooSaleRequest: Sendable {
    let amount: Decimal
    let tipAmount: Decimal
    let paymentType: DejavooPaymentType
    let referenceId: String
    let invoiceNumber: String?
    let printReceipt: DejavooReceiptOption
    let getReceipt: DejavooReceiptOption
    let getExtendedData: Bool
}

struct DejavooTransactionResponse: Sendable {
    let resultCode: String
    let statusCode: String
    let message: String
    let detailedMessage: String?

    // Transaction details
    let authCode: String?
    let referenceId: String?
    let paymentType: String?
    let amount: Decimal?
    let tipAmount: Decimal?
    let cardType: String?
    let cardLast4: String?
    let cardBin: String?
    let cardholderName: String?
    let receiptData: String?

    var isApproved: Bool {
        resultCode == "0" && statusCode == "0000"
    }
}

// MARK: - Dejavoo Errors

enum DejavooError: LocalizedError, Sendable {
    case networkError(String)
    case httpError(Int, String)
    case timeout
    case terminalUnavailable
    case invalidCredentials
    case transactionDeclined(statusCode: String, message: String)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .networkError(let message):
            return "Network error: \(message)"
        case .httpError(let code, let message):
            return "HTTP \(code): \(message)"
        case .timeout:
            return "Terminal did not respond in time"
        case .terminalUnavailable:
            return "Terminal is not available"
        case .invalidCredentials:
            return "Invalid terminal credentials"
        case .transactionDeclined(_, let message):
            return "Declined: \(message)"
        case .parseError(let message):
            return "Failed to parse response: \(message)"
        }
    }

    var isRetryable: Bool {
        switch self {
        case .networkError, .timeout, .terminalUnavailable:
            return true
        default:
            return false
        }
    }
}

// MARK: - Terminal Protocol

/// Protocol for payment terminals (enables mocking)
protocol PaymentTerminal: Sendable {
    func sale(
        amount: Decimal,
        tipAmount: Decimal,
        paymentType: DejavooPaymentType,
        referenceId: String,
        invoiceNumber: String?
    ) async throws -> DejavooTransactionResponse
}

// Default parameter extension
extension PaymentTerminal {
    func sale(
        amount: Decimal,
        referenceId: String
    ) async throws -> DejavooTransactionResponse {
        try await sale(
            amount: amount,
            tipAmount: 0,
            paymentType: .credit,
            referenceId: referenceId,
            invoiceNumber: nil
        )
    }
}
