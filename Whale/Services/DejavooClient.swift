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
