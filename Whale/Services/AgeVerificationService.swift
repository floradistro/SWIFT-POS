//
//  AgeVerificationService.swift
//  Whale
//
//  Server-side age verification for compliance.
//  Uses the customer-verify Edge Function for verification.
//  Provides signed verification tokens to prevent client-side bypass.
//

import Foundation
import Supabase
import Functions
import os.log

// MARK: - Age Verification Service

enum AgeVerificationService {

    // MARK: - Edge Function Request

    private struct VerifyRequest: Encodable {
        let store_id: String
        let date_of_birth: String?
        let expiration_date: String?
    }

    // MARK: - Verify Age

    /// Verify age server-side via Edge Function.
    /// - Parameters:
    ///   - dateOfBirth: Date of birth in YYYY-MM-DD format
    ///   - storeId: Store ID for audit logging
    /// - Returns: Verification result with token if verified
    static func verifyAge(dateOfBirth: String, storeId: UUID) async throws -> AgeVerificationResult {
        let request = VerifyRequest(
            store_id: storeId.uuidString,
            date_of_birth: dateOfBirth,
            expiration_date: nil
        )

        do {
            let response: CustomerVerifyResponse = try await supabase.functions
                .invoke(
                    "customer-verify",
                    options: FunctionInvokeOptions(body: request)
                )

            if response.success {
                Log.scanner.info("Age verification via Edge: Age=\(response.verification.age ?? 0), Verified=\(response.verification.isVerified)")
                return response.verification.toAgeVerificationResult()
            } else {
                throw AgeVerificationError.verificationFailed
            }
        } catch let error as AgeVerificationError {
            throw error
        } catch {
            Log.scanner.error("Edge function call failed: \(error.localizedDescription)")
            throw AgeVerificationError.networkError(underlying: error.localizedDescription)
        }
    }

    /// Server-side verification with full ID data via Edge Function.
    /// Uses CustomerService.findMatchesAndVerify for combined operation.
    /// - Parameters:
    ///   - scannedID: Full scanned ID data
    ///   - storeId: Store ID
    /// - Returns: Comprehensive verification result
    static func verifyID(_ scannedID: ScannedID, storeId: UUID) async throws -> IDVerificationResult {
        let (_, verification) = await CustomerService.findMatchesAndVerify(
            for: scannedID,
            storeId: storeId
        )
        return verification
    }
}

// MARK: - Age Verification Result

struct AgeVerificationResult: Sendable {
    let verified: Bool
    let age: Int
    let minimumAge: Int
    let verifiedAt: Date
    let verificationToken: String?

    var isUnder21: Bool {
        age < 21
    }
}

// MARK: - ID Verification Result

struct IDVerificationResult: Sendable {
    let isVerified: Bool
    let ageVerification: AgeVerificationResult?
    let licenseStatus: LicenseStatus
    let warnings: [VerificationWarning]
    let verifiedAt: Date

    var hasWarnings: Bool {
        !warnings.isEmpty
    }
}

// MARK: - Verification Warning

enum VerificationWarning: Sendable {
    case missingDateOfBirth
    case licenseExpired
    case licenseExpiringSoon(days: Int)
    case unknownLicenseStatus

    var message: String {
        switch self {
        case .missingDateOfBirth:
            return "Date of birth not found on ID"
        case .licenseExpired:
            return "Driver's license is expired"
        case .licenseExpiringSoon(let days):
            return "License expires in \(days) days"
        case .unknownLicenseStatus:
            return "Could not verify license expiration"
        }
    }

    var severity: WarningSeverity {
        switch self {
        case .missingDateOfBirth:
            return .high
        case .licenseExpired:
            return .medium
        case .licenseExpiringSoon:
            return .low
        case .unknownLicenseStatus:
            return .low
        }
    }
}

enum WarningSeverity: Sendable {
    case low
    case medium
    case high
}

// MARK: - Errors

enum AgeVerificationError: LocalizedError, Sendable {
    case invalidDateOfBirth
    case verificationFailed
    case networkError(underlying: String)

    var errorDescription: String? {
        switch self {
        case .invalidDateOfBirth:
            return "Invalid date of birth format"
        case .verificationFailed:
            return "Age verification failed"
        case .networkError(let msg):
            return "Network error: \(msg)"
        }
    }
}
