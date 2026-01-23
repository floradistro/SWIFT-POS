//
//  DejavooClient.swift
//  Whale
//
//  Dejavoo SPIN REST API client for payment terminal integration.
//  Handles card transactions, voids, refunds, and terminal health.
//
//  Documentation: https://app.theneo.io/dejavoo/spin/spin-rest-api-methods
//

import Foundation
import os.log

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

// MARK: - Dejavoo Client

actor DejavooClient: PaymentTerminal {

    private let config: DejavooConfig
    private let session: URLSession
    private let logger = Logger(subsystem: "com.whale.pos", category: "Dejavoo")

    init(config: DejavooConfig) {
        self.config = config

        let configuration = URLSessionConfiguration.default
        // URLSession timeout should be slightly longer than SPIn proxy timeout
        configuration.timeoutIntervalForRequest = TimeInterval(config.timeoutSeconds + 30)
        configuration.timeoutIntervalForResource = TimeInterval(config.timeoutSeconds + 60)
        self.session = URLSession(configuration: configuration)
    }

    // MARK: - Sale Transaction

    func sale(
        amount: Decimal,
        tipAmount: Decimal = 0,
        paymentType: DejavooPaymentType = .credit,
        referenceId: String,
        invoiceNumber: String? = nil
    ) async throws -> DejavooTransactionResponse {
        logger.info("💳 Starting sale: $\(amount) ref=\(referenceId)")

        let payload: [String: Any] = [
            "Amount": NSDecimalNumber(decimal: amount).doubleValue,
            "TipAmount": NSDecimalNumber(decimal: tipAmount).doubleValue,
            "PaymentType": paymentType.rawValue,
            "ReferenceId": referenceId,
            "InvoiceNumber": invoiceNumber ?? "",
            "PrintReceipt": DejavooReceiptOption.none.rawValue,
            "GetReceipt": DejavooReceiptOption.both.rawValue,
            "GetExtendedData": true,
            "Tpn": config.tpn,
            "Authkey": config.authKey,
            "SPInProxyTimeout": config.timeoutSeconds  // In seconds (1-720)
        ]

        return try await makeRequest(endpoint: "v2/Payment/Sale", payload: payload)
    }

    // MARK: - Void Transaction

    func void(referenceId: String) async throws -> DejavooTransactionResponse {
        logger.info("🔄 Voiding transaction: ref=\(referenceId)")

        let payload: [String: Any] = [
            "ReferenceId": referenceId,
            "PrintReceipt": DejavooReceiptOption.none.rawValue,
            "GetReceipt": DejavooReceiptOption.both.rawValue,
            "Tpn": config.tpn,
            "Authkey": config.authKey
        ]

        return try await makeRequest(endpoint: "v2/Payment/Void", payload: payload)
    }

    // MARK: - Refund Transaction

    func refund(
        amount: Decimal,
        paymentType: DejavooPaymentType = .credit,
        referenceId: String
    ) async throws -> DejavooTransactionResponse {
        logger.info("↩️ Processing refund: $\(amount) ref=\(referenceId)")

        let payload: [String: Any] = [
            "Amount": NSDecimalNumber(decimal: amount).doubleValue,
            "PaymentType": paymentType.rawValue,
            "ReferenceId": referenceId,
            "PrintReceipt": DejavooReceiptOption.none.rawValue,
            "GetReceipt": DejavooReceiptOption.both.rawValue,
            "GetExtendedData": true,
            "Tpn": config.tpn,
            "Authkey": config.authKey
        ]

        return try await makeRequest(endpoint: "v2/Payment/Return", payload: payload)
    }

    // MARK: - Health Check

    /// Lightweight ping to verify API connectivity (does NOT touch terminal)
    func ping() async throws -> Bool {
        let base = config.environment.baseURL
        let url = URL(string: "\(base)/v2/Payment/Sale")!

        var request = URLRequest(url: url)
        request.httpMethod = "OPTIONS"
        request.timeoutInterval = 5

        do {
            let (_, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                // Any response means API is reachable
                logger.debug("🏓 Ping response: \(httpResponse.statusCode)")
                return true
            }
            return false
        } catch {
            logger.warning("🏓 Ping failed: \(error.localizedDescription)")
            throw DejavooError.networkError(error.localizedDescription)
        }
    }

    /// Full test that sends to terminal (will prompt for card)
    func testConnection() async throws -> Bool {
        logger.info("🧪 Testing terminal connection...")

        let testRef = "TEST-\(Int(Date().timeIntervalSince1970))"

        do {
            // Send minimal transaction - terminal will prompt for card
            _ = try await sale(
                amount: 0.01,
                paymentType: .credit,
                referenceId: testRef
            )
            return true
        } catch let error as DejavooError {
            // Rethrow with more helpful message
            switch error {
            case .timeout:
                throw DejavooError.networkError(
                    "Terminal did not respond. Check:\n• Terminal is powered on\n• Connected to network\n• Not processing another transaction"
                )
            case .terminalUnavailable:
                throw DejavooError.networkError(
                    "Terminal unavailable. Check:\n• Terminal is powered on\n• Connected to network\n• TPN is correct"
                )
            default:
                throw error
            }
        }
    }

    // MARK: - Private Methods

    private func makeRequest(endpoint: String, payload: [String: Any]) async throws -> DejavooTransactionResponse {
        let base = config.environment.baseURL
        let url = URL(string: "\(base)/\(endpoint)")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        logger.debug("📤 Request: \(endpoint)")

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw DejavooError.networkError("Invalid response")
            }

            logger.debug("📥 Response: \(httpResponse.statusCode)")

            // Dejavoo returns 200 for success, but also returns valid JSON on 400
            // Always try to parse the response first
            return try parseResponse(data)

        } catch let error as DejavooError {
            throw error
        } catch let error as URLError {
            if error.code == .timedOut {
                logger.error("⏱️ Request timeout")
                throw DejavooError.timeout
            }
            logger.error("🌐 Network error: \(error.localizedDescription)")
            throw DejavooError.networkError(error.localizedDescription)
        } catch {
            logger.error("❓ Unknown error: \(error.localizedDescription)")
            throw DejavooError.networkError(error.localizedDescription)
        }
    }

    private func parseResponse(_ data: Data) throws -> DejavooTransactionResponse {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DejavooError.parseError("Invalid JSON")
        }

        guard let generalResponse = json["GeneralResponse"] as? [String: Any] else {
            throw DejavooError.parseError("Missing GeneralResponse")
        }

        let resultCode = generalResponse["ResultCode"] as? String ?? ""
        let statusCode = generalResponse["StatusCode"] as? String ?? ""
        let message = generalResponse["Message"] as? String ?? ""
        let detailedMessage = generalResponse["DetailedMessage"] as? String

        // Check for errors
        if resultCode != "0" || (statusCode != "0000" && !statusCode.isEmpty) {
            // Check specific error codes
            if statusCode == "2007" {
                throw DejavooError.timeout
            }
            if statusCode == "2011" || statusCode == "2001" {
                throw DejavooError.terminalUnavailable
            }

            throw DejavooError.transactionDeclined(
                statusCode: statusCode,
                message: detailedMessage ?? message
            )
        }

        // Parse successful response
        let amountValue = json["Amount"] as? Double
        let tipValue = json["TipAmount"] as? Double

        return DejavooTransactionResponse(
            resultCode: resultCode,
            statusCode: statusCode,
            message: message,
            detailedMessage: detailedMessage,
            authCode: json["AuthCode"] as? String,
            referenceId: json["ReferenceId"] as? String,
            paymentType: json["PaymentType"] as? String,
            amount: amountValue.map { Decimal($0) },
            tipAmount: tipValue.map { Decimal($0) },
            cardType: json["CardType"] as? String,
            cardLast4: json["CardLast4"] as? String,
            cardBin: json["CardBin"] as? String,
            cardholderName: json["CardholderName"] as? String,
            receiptData: json["ReceiptData"] as? String
        )
    }
}

// MARK: - Reference ID Generator

enum DejavooReferenceGenerator {
    /// Generate unique reference ID for transactions
    static func generate(prefix: String = "TXN") -> String {
        let timestamp = Int(Date().timeIntervalSince1970)
        let random = Int.random(in: 1000...9999)
        return "\(prefix)-\(timestamp)-\(random)"
    }
}

// MARK: - Card Type Parser

enum CardTypeParser {
    static func parse(_ cardType: String?) -> String? {
        guard let type = cardType?.lowercased() else { return nil }

        if type.contains("visa") { return "Visa" }
        if type.contains("mastercard") || type.contains("master") { return "Mastercard" }
        if type.contains("amex") || type.contains("american") { return "Amex" }
        if type.contains("discover") { return "Discover" }

        return cardType
    }
}

// MARK: - Mock Terminal (for testing without real hardware)

/// Mock terminal that simulates successful card transactions
/// Used for development and testing when no physical terminal is available
actor MockDejavooTerminal: PaymentTerminal {

    func sale(
        amount: Decimal,
        tipAmount: Decimal,
        paymentType: DejavooPaymentType,
        referenceId: String,
        invoiceNumber: String?
    ) async throws -> DejavooTransactionResponse {
        // Simulate terminal processing time
        try await Task.sleep(for: .milliseconds(1500))

        // Return successful mock response
        return DejavooTransactionResponse(
            resultCode: "0",
            statusCode: "0000",
            message: "Approved",
            detailedMessage: "Transaction approved",
            authCode: "MOCK\(Int.random(in: 100000...999999))",
            referenceId: referenceId,
            paymentType: paymentType.rawValue,
            amount: amount,
            tipAmount: tipAmount,
            cardType: "Visa",
            cardLast4: "4242",
            cardBin: "424242",
            cardholderName: "TEST CARD",
            receiptData: nil
        )
    }

    func void(referenceId: String) async throws -> DejavooTransactionResponse {
        try await Task.sleep(for: .milliseconds(500))
        return DejavooTransactionResponse(
            resultCode: "0",
            statusCode: "0000",
            message: "Voided",
            detailedMessage: nil,
            authCode: nil,
            referenceId: referenceId,
            paymentType: nil,
            amount: nil,
            tipAmount: nil,
            cardType: nil,
            cardLast4: nil,
            cardBin: nil,
            cardholderName: nil,
            receiptData: nil
        )
    }

    func refund(
        amount: Decimal,
        paymentType: DejavooPaymentType = .credit,
        referenceId: String
    ) async throws -> DejavooTransactionResponse {
        try await Task.sleep(for: .milliseconds(500))
        return DejavooTransactionResponse(
            resultCode: "0",
            statusCode: "0000",
            message: "Refunded",
            detailedMessage: nil,
            authCode: "REF\(Int.random(in: 100000...999999))",
            referenceId: referenceId,
            paymentType: paymentType.rawValue,
            amount: amount,
            tipAmount: nil,
            cardType: nil,
            cardLast4: nil,
            cardBin: nil,
            cardholderName: nil,
            receiptData: nil
        )
    }
}
