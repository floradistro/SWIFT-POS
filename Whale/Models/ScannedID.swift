//
//  ScannedID.swift
//  Whale
//
//  Data model for parsed ID card information.
//  Extracted from PDF-417 barcodes on US/Canadian driver's licenses.
//

import Foundation

// MARK: - Date Formatters (Cached)

private enum DateFormatters {
    static let iso: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static let display: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd/yyyy"
        return formatter
    }()

    static let short: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter
    }()
}

// MARK: - Scanned ID

struct ScannedID: Sendable, Equatable {
    // Name fields
    let fullName: String?
    let firstName: String?
    let middleName: String?
    let lastName: String?

    // Identification
    let licenseNumber: String?
    let dateOfBirth: String?  // YYYY-MM-DD format

    // Address
    let streetAddress: String?
    let city: String?
    let state: String?
    let zipCode: String?

    // Physical characteristics (optional, not used for matching)
    let height: String?
    let eyeColor: String?

    // Document dates
    let issueDate: String?      // YYYY-MM-DD format
    let expirationDate: String? // YYYY-MM-DD format

    // Debug
    let rawData: String?
}

// MARK: - Computed Properties

extension ScannedID {
    /// Display name for UI
    var displayName: String {
        let parts = [firstName, lastName].compactMap { $0 }
        return parts.isEmpty ? "Unknown" : parts.joined(separator: " ")
    }

    /// Full display name including middle name
    var fullDisplayName: String {
        let parts = [firstName, middleName, lastName].compactMap { $0 }
        return parts.isEmpty ? "Unknown" : parts.joined(separator: " ")
    }

    /// Calculated age from date of birth
    var age: Int? {
        guard let dob = dateOfBirth else { return nil }
        return AgeCalculator.calculateAge(from: dob)
    }

    /// Check if 21 or older
    var isLegalAge: Bool {
        guard let age = age else { return false }
        return age >= 21
    }

    /// Check if license is expired
    var isExpired: Bool {
        guard let expStr = expirationDate,
              let exp = DateFormatters.iso.date(from: expStr) else { return false }
        return exp < Date()
    }

    /// Days until expiration (negative if expired)
    var daysUntilExpiration: Int? {
        guard let expStr = expirationDate,
              let exp = DateFormatters.iso.date(from: expStr) else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: exp).day
    }

    /// Formatted address for display
    var formattedAddress: String? {
        var parts: [String] = []

        if let street = streetAddress {
            parts.append(street)
        }

        var cityStateZip: [String] = []
        if let city = city { cityStateZip.append(city) }
        if let state = state { cityStateZip.append(state) }
        if let zip = zipCode { cityStateZip.append(zip) }

        if !cityStateZip.isEmpty {
            parts.append(cityStateZip.joined(separator: ", "))
        }

        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    /// Formatted date of birth for display (MM/DD/YYYY)
    var formattedDateOfBirth: String? {
        guard let dob = dateOfBirth,
              let date = DateFormatters.iso.date(from: dob) else { return nil }
        return DateFormatters.display.string(from: date)
    }
}

// MARK: - License Status

enum LicenseStatus: Sendable {
    case valid
    case expired(Date)
    case expiringSoon(daysRemaining: Int)
    case unknown

    var displayText: String {
        switch self {
        case .valid:
            return "Valid"
        case .expired(let date):
            return "Expired \(DateFormatters.short.string(from: date))"
        case .expiringSoon(let days):
            return "Expires in \(days) days"
        case .unknown:
            return "Unknown"
        }
    }

    var isAcceptable: Bool {
        switch self {
        case .valid, .expiringSoon:
            return true
        case .expired, .unknown:
            return false
        }
    }
}

extension ScannedID {
    var licenseStatus: LicenseStatus {
        guard let expStr = expirationDate,
              let exp = DateFormatters.iso.date(from: expStr) else { return .unknown }

        if exp < Date() {
            return .expired(exp)
        }

        if let days = daysUntilExpiration, days <= 30 {
            return .expiringSoon(daysRemaining: days)
        }

        return .valid
    }
}
