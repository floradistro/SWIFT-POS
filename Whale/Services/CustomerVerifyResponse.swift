//
//  CustomerVerifyResponse.swift
//  Whale
//
//  Response models for the customer-verify Edge Function.
//  Decodes the combined customer matching + age verification result.
//

import Foundation

// MARK: - Edge Function Response

struct CustomerVerifyResponse: Codable, Sendable {
    let success: Bool
    let matches: [EdgeCustomerMatch]
    let verification: EdgeVerificationResult
    let error: String?
}

// MARK: - Customer Match from Edge

struct EdgeCustomerMatch: Codable, Sendable {
    let customer: EdgeCustomer
    let matchType: String
    let confidence: Int
    let matchedFields: [String]
    let pendingOrders: [EdgeOrder]

    enum CodingKeys: String, CodingKey {
        case customer
        case matchType = "match_type"
        case confidence
        case matchedFields = "matched_fields"
        case pendingOrders = "pending_orders"
    }

    /// Convert to app-side CustomerMatch model
    func toCustomerMatch() -> CustomerMatch {
        let matchTypeEnum: CustomerMatch.MatchType = switch matchType {
        case "exact": .exact
        case "phone_dob": .phoneDOB
        case "email": .email
        case "name_dob": .high
        case "phone_only": .phoneOnly
        case "name_only": .nameOnly
        default: .fuzzy
        }

        return CustomerMatch(
            customer: customer.toCustomer(),
            matchType: matchTypeEnum,
            confidence: confidence,
            pendingOrderCount: pendingOrders.count,
            pendingOrders: pendingOrders.map { $0.toOrder() },
            matchedFields: matchedFields
        )
    }
}

// MARK: - Customer from Edge

struct EdgeCustomer: Codable, Sendable {
    let id: UUID
    let platformUserId: UUID
    let storeId: UUID
    let firstName: String?
    let middleName: String?
    let lastName: String?
    let email: String?
    let phone: String?
    let dateOfBirth: String?
    let avatarUrl: String?
    let streetAddress: String?
    let city: String?
    let state: String?
    let postalCode: String?
    let driversLicenseNumber: String?
    let idVerified: Bool?
    let isActive: Bool?
    let loyaltyPoints: Int?
    let loyaltyTier: String?
    let totalSpent: Double?
    let totalOrders: Int?
    let lifetimeValue: Double?
    let emailConsent: Bool?
    let smsConsent: Bool?
    let createdAt: String
    let updatedAt: String

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

    /// Convert to app-side Customer model
    func toCustomer() -> Customer {
        let iso8601 = ISO8601DateFormatter()
        iso8601.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let now = Date()
        let createdDate = iso8601.date(from: createdAt)
            ?? ISO8601DateFormatter().date(from: createdAt)
            ?? now
        let updatedDate = iso8601.date(from: updatedAt)
            ?? ISO8601DateFormatter().date(from: updatedAt)
            ?? now

        let totalSpentDecimal: Decimal? = totalSpent.map { Decimal($0) }
        let lifetimeValueDecimal: Decimal? = lifetimeValue.map { Decimal($0) }

        return Customer(
            id: id,
            platformUserId: platformUserId,
            storeId: storeId,
            firstName: firstName,
            middleName: middleName,
            lastName: lastName,
            email: email,
            phone: phone,
            dateOfBirth: dateOfBirth,
            avatarUrl: avatarUrl,
            streetAddress: streetAddress,
            city: city,
            state: state,
            postalCode: postalCode,
            driversLicenseNumber: driversLicenseNumber,
            idVerified: idVerified,
            isActive: isActive,
            loyaltyPoints: loyaltyPoints,
            loyaltyTier: loyaltyTier,
            totalSpent: totalSpentDecimal,
            totalOrders: totalOrders,
            lifetimeValue: lifetimeValueDecimal,
            emailConsent: emailConsent,
            smsConsent: smsConsent,
            createdAt: createdDate,
            updatedAt: updatedDate
        )
    }
}

// MARK: - Order from Edge

struct EdgeOrder: Codable, Sendable {
    let id: UUID
    let status: String
    let total: Double
    let createdAt: String
    let vStoreCustomers: EdgeOrderCustomer?
    let fulfillments: [EdgeFulfillment]?

    enum CodingKeys: String, CodingKey {
        case id
        case status
        case total
        case createdAt = "created_at"
        case vStoreCustomers = "v_store_customers"
        case fulfillments
    }

    /// Convert to app-side Order model
    func toOrder() -> Order {
        let iso8601 = ISO8601DateFormatter()
        iso8601.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let createdDate = iso8601.date(from: createdAt)
            ?? ISO8601DateFormatter().date(from: createdAt)
            ?? Date()

        let statusEnum = OrderStatus(rawValue: status) ?? .pending

        // Convert edge fulfillments to app-side fulfillments
        let appFulfillments: [OrderFulfillment]? = fulfillments?.map { f in
            let fulfillmentType = FulfillmentType(rawValue: f.type) ?? .pickup
            let fulfillmentStatus = f.status.flatMap { FulfillmentStatus(rawValue: $0) } ?? .pending
            return OrderFulfillment(
                id: f.id,
                orderId: id,
                type: fulfillmentType,
                status: fulfillmentStatus,
                deliveryLocationId: nil,
                deliveryAddress: nil,
                carrier: nil,
                trackingNumber: nil,
                trackingUrl: nil,
                shippingCost: nil,
                createdAt: createdDate,
                shippedAt: nil,
                deliveredAt: nil,
                deliveryLocation: f.deliveryLocation.map { loc in
                    FulfillmentLocation(id: nil, name: loc.name, addressLine1: nil, city: nil, state: nil)
                }
            )
        }

        return Order(
            id: id,
            orderNumber: "", // Not needed for pending orders display
            storeId: nil,
            customerId: nil,
            channel: .online, // Online pickup order
            status: statusEnum,
            paymentStatus: .pending,
            subtotal: Decimal(total),
            taxAmount: 0,
            discountAmount: 0,
            totalAmount: Decimal(total),
            paymentMethod: nil,
            createdAt: createdDate,
            updatedAt: createdDate,
            completedAt: nil,
            shippingName: nil,
            shippingAddressLine1: nil,
            shippingAddressLine2: nil,
            shippingCity: nil,
            shippingState: nil,
            shippingZip: nil,
            trackingNumber: nil,
            trackingUrl: nil,
            staffNotes: nil,
            customers: vStoreCustomers.map { OrderCustomer(
                firstName: $0.firstName,
                lastName: $0.lastName,
                email: $0.email,
                phone: $0.phone
            ) },
            items: nil,
            fulfillments: appFulfillments,
            orderLocations: nil
        )
    }
}

struct EdgeOrderCustomer: Codable, Sendable {
    let firstName: String?
    let lastName: String?
    let email: String?
    let phone: String?

    enum CodingKeys: String, CodingKey {
        case firstName = "first_name"
        case lastName = "last_name"
        case email
        case phone
    }
}

struct EdgeFulfillment: Codable, Sendable {
    let id: UUID
    let type: String
    let status: String?
    let deliveryLocation: EdgeDeliveryLocation?

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case status
        case deliveryLocation = "delivery_location"
    }
}

struct EdgeDeliveryLocation: Codable, Sendable {
    let name: String
}

// MARK: - Verification Result from Edge

struct EdgeVerificationResult: Codable, Sendable {
    let isVerified: Bool
    let age: Int?
    let minimumAge: Int
    let licenseStatus: String
    let licenseDaysRemaining: Int?
    let warnings: [EdgeVerificationWarning]
    let verifiedAt: String

    enum CodingKeys: String, CodingKey {
        case isVerified = "is_verified"
        case age
        case minimumAge = "minimum_age"
        case licenseStatus = "license_status"
        case licenseDaysRemaining = "license_days_remaining"
        case warnings
        case verifiedAt = "verified_at"
    }

    /// Convert to app-side AgeVerificationResult
    func toAgeVerificationResult() -> AgeVerificationResult {
        let iso8601 = ISO8601DateFormatter()
        iso8601.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let verifiedDate = iso8601.date(from: verifiedAt)
            ?? ISO8601DateFormatter().date(from: verifiedAt)
            ?? Date()

        return AgeVerificationResult(
            verified: isVerified,
            age: age ?? 0,
            minimumAge: minimumAge,
            verifiedAt: verifiedDate,
            verificationToken: isVerified ? "edge_\(age ?? 0)_\(Int(verifiedDate.timeIntervalSince1970))" : nil
        )
    }

    /// Convert to app-side IDVerificationResult
    func toIDVerificationResult() -> IDVerificationResult {
        let licenseStatusEnum: LicenseStatus = switch licenseStatus {
        case "valid": .valid
        case "expired":
            if let days = licenseDaysRemaining {
                .expired(Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date())
            } else {
                .expired(Date())
            }
        case "expiring_soon":
            .expiringSoon(daysRemaining: licenseDaysRemaining ?? 0)
        default: .unknown
        }

        let appWarnings: [VerificationWarning] = warnings.map { $0.toVerificationWarning() }

        let iso8601 = ISO8601DateFormatter()
        iso8601.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let verifiedDate = iso8601.date(from: verifiedAt)
            ?? ISO8601DateFormatter().date(from: verifiedAt)
            ?? Date()

        return IDVerificationResult(
            isVerified: isVerified,
            ageVerification: toAgeVerificationResult(),
            licenseStatus: licenseStatusEnum,
            warnings: appWarnings,
            verifiedAt: verifiedDate
        )
    }
}

struct EdgeVerificationWarning: Codable, Sendable {
    let type: String
    let message: String
    let severity: String

    func toVerificationWarning() -> VerificationWarning {
        switch type {
        case "missing_dob": return .missingDateOfBirth
        case "license_expired": return .licenseExpired
        case "license_expiring":
            // Extract days from message if possible, default to 7
            return .licenseExpiringSoon(days: 7)
        case "unknown_status": return .unknownLicenseStatus
        default: return .unknownLicenseStatus
        }
    }
}
