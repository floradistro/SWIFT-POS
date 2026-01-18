//
//  Customer.swift
//  Whale
//
//  Customer model representing a user's relationship with a store.
//  Data comes from: platform_users + user_creation_relationships + store_customer_profiles
//  Used for ID scanning customer lookup and matching.
//

import Foundation

// MARK: - Customer

/// Represents a customer at a specific store.
/// This is a denormalized view combining:
/// - platform_users (identity: name, email, phone, DOB)
/// - user_creation_relationships (the link between user and store)
/// - store_customer_profiles (loyalty, spending stats at this store)
struct Customer: Identifiable, Codable, Sendable, Hashable {
    // Relationship ID (from user_creation_relationships)
    let id: UUID

    // Platform user ID (from platform_users)
    let platformUserId: UUID

    // Store context
    let storeId: UUID

    // Identity (from platform_users)
    let firstName: String?
    let middleName: String?
    let lastName: String?
    let email: String?
    let phone: String?
    let dateOfBirth: String?  // YYYY-MM-DD format
    let avatarUrl: String?

    // Address (from store_customer_profiles)
    let streetAddress: String?
    let city: String?
    let state: String?
    let postalCode: String?

    // Verification (from store_customer_profiles)
    let driversLicenseNumber: String?
    let idVerified: Bool?

    // Status (from user_creation_relationships)
    let isActive: Bool?

    // Loyalty & Stats (from store_customer_profiles)
    let loyaltyPoints: Int?
    let loyaltyTier: String?
    let totalSpent: Decimal?
    let totalOrders: Int?
    let lifetimeValue: Decimal?

    // Consent (from user_creation_relationships)
    let emailConsent: Bool?
    let smsConsent: Bool?

    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case platformUserId = "platform_user_id"
        case storeId = "store_id"
        case firstName = "first_name"
        case middleName = "middle_name"
        case lastName = "last_name"
        case email
        case phone
        case dateOfBirth = "date_of_birth"
        case avatarUrl = "avatar_url"
        case streetAddress = "street_address"
        case city
        case state
        case postalCode = "postal_code"
        case driversLicenseNumber = "drivers_license_number"
        case idVerified = "id_verified"
        case isActive = "is_active"
        case loyaltyPoints = "loyalty_points"
        case loyaltyTier = "loyalty_tier"
        case totalSpent = "total_spent"
        case totalOrders = "total_orders"
        case lifetimeValue = "lifetime_value"
        case emailConsent = "email_consent"
        case smsConsent = "sms_consent"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Computed Properties

extension Customer {
    var fullName: String {
        let parts = [firstName, middleName, lastName].compactMap { $0?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return parts.isEmpty ? "Unknown" : parts.joined(separator: " ")
    }

    var displayName: String {
        let parts = [firstName, lastName].compactMap { $0?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return parts.isEmpty ? "Unknown Customer" : parts.joined(separator: " ")
    }

    var initials: String {
        let first = firstName?.first.map(String.init) ?? ""
        let last = lastName?.first.map(String.init) ?? ""
        let result = first + last
        return result.isEmpty ? "?" : result.uppercased()
    }

    var age: Int? {
        guard let dob = dateOfBirth else { return nil }
        return AgeCalculator.calculateAge(from: dob)
    }

    var isLegalAge: Bool {
        guard let age = age else { return false }
        return age >= 21
    }

    var formattedAddress: String? {
        var parts: [String] = []
        if let street = streetAddress { parts.append(street) }

        var cityStateZip: [String] = []
        if let city = city { cityStateZip.append(city) }
        if let state = state { cityStateZip.append(state) }
        if let zip = postalCode { cityStateZip.append(zip) }

        if !cityStateZip.isEmpty {
            parts.append(cityStateZip.joined(separator: ", "))
        }

        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    var formattedTotalSpent: String {
        guard let spent = totalSpent else { return "$0" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: spent as NSDecimalNumber) ?? "$0"
    }

    var formattedLoyaltyPoints: String {
        guard let points = loyaltyPoints else { return "0" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: points)) ?? "0"
    }

    var loyaltyTierDisplay: String {
        loyaltyTier?.capitalized ?? "Standard"
    }

    var formattedPhone: String? {
        guard let phone = phone, !phone.isEmpty else { return nil }
        // Format as (XXX) XXX-XXXX if 10 digits
        let digits = phone.filter { $0.isNumber }
        guard digits.count == 10 else { return phone }
        let areaCode = String(digits.prefix(3))
        let middle = String(digits.dropFirst(3).prefix(3))
        let last = String(digits.suffix(4))
        return "(\(areaCode)) \(middle)-\(last)"
    }
}

// MARK: - Age Calculator

enum AgeCalculator {
    static func calculateAge(from dateOfBirth: String) -> Int? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        guard let dob = formatter.date(from: dateOfBirth) else { return nil }

        let calendar = Calendar.current
        let now = Date()
        let ageComponents = calendar.dateComponents([.year], from: dob, to: now)

        return ageComponents.year
    }

    static func isLegalAge(_ dateOfBirth: String, minimumAge: Int = 21) -> Bool {
        guard let age = calculateAge(from: dateOfBirth) else { return false }
        return age >= minimumAge
    }
}

// MARK: - Customer Match

struct CustomerMatch: Identifiable, Sendable {
    let id: UUID
    let customer: Customer
    let matchType: MatchType
    let confidence: Int  // 0-100
    let pendingOrderCount: Int
    let pendingOrders: [Order]
    let matchedFields: [String]

    init(
        id: UUID = UUID(),
        customer: Customer,
        matchType: MatchType,
        confidence: Int,
        pendingOrderCount: Int = 0,
        pendingOrders: [Order] = [],
        matchedFields: [String] = []
    ) {
        self.id = id
        self.customer = customer
        self.matchType = matchType
        self.confidence = confidence
        self.pendingOrderCount = pendingOrderCount
        self.pendingOrders = pendingOrders
        self.matchedFields = matchedFields
    }

    enum MatchType: String, Sendable {
        case exact       // License number match (100%)
        case phoneDOB    // Phone + DOB match (95%)
        case email       // Email match (90%)
        case high        // Name + DOB match (85%)
        case phoneOnly   // Phone only (75%)
        case fuzzy       // Partial name match (50-70%)
        case nameOnly    // Name match without DOB (60%)

        var displayName: String {
            switch self {
            case .exact: return "Exact Match"
            case .phoneDOB: return "Phone + DOB"
            case .email: return "Email Match"
            case .high: return "High Match"
            case .phoneOnly: return "Phone Match"
            case .fuzzy: return "Possible Match"
            case .nameOnly: return "Name Match"
            }
        }

        var icon: String {
            switch self {
            case .exact: return "checkmark.seal.fill"
            case .phoneDOB: return "phone.badge.checkmark"
            case .email: return "envelope.badge.fill"
            case .high: return "checkmark.circle.fill"
            case .phoneOnly: return "phone.fill"
            case .fuzzy: return "questionmark.circle.fill"
            case .nameOnly: return "person.fill.questionmark"
            }
        }

        var confidenceScore: Int {
            switch self {
            case .exact: return 100
            case .phoneDOB: return 95
            case .email: return 90
            case .high: return 85
            case .phoneOnly: return 75
            case .nameOnly: return 60
            case .fuzzy: return 50
            }
        }

        var reason: String {
            switch self {
            case .exact: return "Same driver's license number"
            case .phoneDOB: return "Same phone number and date of birth"
            case .email: return "Same email address"
            case .high: return "Same name and date of birth"
            case .phoneOnly: return "Same phone number (could be family member)"
            case .nameOnly: return "Same name (could be different person)"
            case .fuzzy: return "Similar information"
            }
        }
    }
}

// MARK: - New Customer from Scan

struct NewCustomerFromScan: Sendable {
    let firstName: String?
    let middleName: String?
    let lastName: String?
    let dateOfBirth: String?
    let streetAddress: String?
    let city: String?
    let state: String?
    let postalCode: String?
    let driversLicenseNumber: String?

    init(from scannedID: ScannedID) {
        self.firstName = scannedID.firstName
        self.middleName = scannedID.middleName
        self.lastName = scannedID.lastName
        self.dateOfBirth = scannedID.dateOfBirth
        self.streetAddress = scannedID.streetAddress
        self.city = scannedID.city
        self.state = scannedID.state
        self.postalCode = scannedID.zipCode
        self.driversLicenseNumber = scannedID.licenseNumber
    }

    init(
        firstName: String?,
        middleName: String?,
        lastName: String?,
        dateOfBirth: String?,
        streetAddress: String?,
        city: String?,
        state: String?,
        postalCode: String?,
        driversLicenseNumber: String?
    ) {
        self.firstName = firstName
        self.middleName = middleName
        self.lastName = lastName
        self.dateOfBirth = dateOfBirth
        self.streetAddress = streetAddress
        self.city = city
        self.state = state
        self.postalCode = postalCode
        self.driversLicenseNumber = driversLicenseNumber
    }
}
