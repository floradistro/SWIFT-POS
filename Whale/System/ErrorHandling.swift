//
//  ErrorHandling.swift
//  Whale
//
//  Centralized error handling and logging.
//  All errors flow through here for consistency.
//

import Foundation
import os.log

// MARK: - Logger

/// Centralized logging for the app
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.whale.pos"

    static let session = Logger(subsystem: subsystem, category: "session")
    static let network = Logger(subsystem: subsystem, category: "network")
    static let agent = Logger(subsystem: subsystem, category: "agent")
    static let ui = Logger(subsystem: subsystem, category: "ui")
    static let scanner = Logger(subsystem: subsystem, category: "scanner")
    static let deals = Logger(subsystem: subsystem, category: "deals")
    static let cart = Logger(subsystem: subsystem, category: "cart")
}

// MARK: - App Error

/// Unified error type for user-facing errors
enum AppError: LocalizedError, Sendable {
    case network(underlying: String)
    case authentication(underlying: String)
    case session(underlying: String)
    case agent(underlying: String)
    case unknown(underlying: String)

    var errorDescription: String? {
        switch self {
        case .network(let msg):
            return "Network error: \(msg)"
        case .authentication(let msg):
            return "Authentication failed: \(msg)"
        case .session(let msg):
            return "Session error: \(msg)"
        case .agent(let msg):
            return "Processing error: \(msg)"
        case .unknown(let msg):
            return "An error occurred: \(msg)"
        }
    }

    /// User-friendly message (hides technical details)
    var userMessage: String {
        switch self {
        case .network:
            return "Unable to connect. Please check your internet connection."
        case .authentication:
            return "Sign in failed. Please check your credentials."
        case .session:
            return "Session error. Please try signing in again."
        case .agent:
            return "Unable to process request. Please try again."
        case .unknown:
            return "Something went wrong. Please try again."
        }
    }
}

// MARK: - Error Mapping

extension Error {
    /// Convert any error to AppError for consistent handling
    func toAppError() -> AppError {
        if let appError = self as? AppError {
            return appError
        }

        if let sessionError = self as? AppSessionError {
            return .session(underlying: sessionError.localizedDescription)
        }

        // Check for common network errors
        let nsError = self as NSError
        if nsError.domain == NSURLErrorDomain {
            return .network(underlying: localizedDescription)
        }

        // Check for auth-related errors by message content
        let message = localizedDescription.lowercased()
        if message.contains("auth") || message.contains("sign") || message.contains("credential") {
            return .authentication(underlying: localizedDescription)
        }

        return .unknown(underlying: localizedDescription)
    }
}
