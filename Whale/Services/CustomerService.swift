//
//  CustomerService.swift
//  Whale
//
//  Customer data operations for ID scanning.
//  Uses Edge Function for 6-tier matching and verification.
//
//  DESIGN PRINCIPLES:
//  - Never throw errors from matching - return empty results for graceful UI
//  - All matching logic runs server-side via customer-verify Edge Function
//  - AAMVAParser still runs client-side (barcode parsing needs camera access)
//

import Foundation
import Supabase
import Functions
import os.log

// MARK: - RPC Parameter Types (must be outside enum for Sendable conformance)

/// Parameters for update_store_customer RPC call
private struct UpdateCustomerParams: Sendable {
    let p_relationship_id: String
    let p_first_name: String?
    let p_last_name: String?
    let p_email: String?
    let p_phone: String?
    let p_date_of_birth: String?
    let p_street_address: String?
    let p_city: String?
    let p_state: String?
    let p_postal_code: String?
    let p_drivers_license_number: String?
}

extension UpdateCustomerParams: Encodable {
    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(p_relationship_id, forKey: .p_relationship_id)
        try container.encodeIfPresent(p_first_name, forKey: .p_first_name)
        try container.encodeIfPresent(p_last_name, forKey: .p_last_name)
        try container.encodeIfPresent(p_email, forKey: .p_email)
        try container.encodeIfPresent(p_phone, forKey: .p_phone)
        try container.encodeIfPresent(p_date_of_birth, forKey: .p_date_of_birth)
        try container.encodeIfPresent(p_street_address, forKey: .p_street_address)
        try container.encodeIfPresent(p_city, forKey: .p_city)
        try container.encodeIfPresent(p_state, forKey: .p_state)
        try container.encodeIfPresent(p_postal_code, forKey: .p_postal_code)
        try container.encodeIfPresent(p_drivers_license_number, forKey: .p_drivers_license_number)
    }

    private enum CodingKeys: String, CodingKey {
        case p_relationship_id, p_first_name, p_last_name, p_email, p_phone
        case p_date_of_birth, p_street_address, p_city, p_state, p_postal_code
        case p_drivers_license_number
    }
}

/// Parameters for update_store_customer RPC - license only
private struct UpdateLicenseParams: Sendable {
    let p_relationship_id: String
    let p_drivers_license_number: String
}

extension UpdateLicenseParams: Encodable {
    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(p_relationship_id, forKey: .p_relationship_id)
        try container.encode(p_drivers_license_number, forKey: .p_drivers_license_number)
    }

    private enum CodingKeys: String, CodingKey {
        case p_relationship_id, p_drivers_license_number
    }
}

// MARK: - Customer Service

enum CustomerService {

    // MARK: - Edge Function Request

    private struct CustomerVerifyRequest: Encodable {
        let store_id: String
        let first_name: String?
        let middle_name: String?
        let last_name: String?
        let license_number: String?
        let date_of_birth: String?
        let street_address: String?
        let city: String?
        let state: String?
        let postal_code: String?
        let expiration_date: String?
    }

    // MARK: - Combined Match + Verify (Edge Function)

    /// Find matching customers AND verify ID in a single backend call.
    /// Uses the customer-verify Edge Function for all matching logic.
    /// NEVER throws - returns empty results on error for graceful UI.
    ///
    /// Returns both:
    /// - Matched customers with pending orders
    /// - Verification result (age, license status, warnings)
    static func findMatchesAndVerify(
        for scannedID: ScannedID,
        storeId: UUID
    ) async -> (matches: [CustomerMatch], verification: IDVerificationResult) {
        let request = CustomerVerifyRequest(
            store_id: storeId.uuidString,
            first_name: scannedID.firstName,
            middle_name: scannedID.middleName,
            last_name: scannedID.lastName,
            license_number: scannedID.licenseNumber,
            date_of_birth: scannedID.dateOfBirth,
            street_address: scannedID.streetAddress,
            city: scannedID.city,
            state: scannedID.state,
            postal_code: scannedID.zipCode,
            expiration_date: scannedID.expirationDate
        )

        do {
            let response: CustomerVerifyResponse = try await supabase.functions
                .invoke(
                    "customer-verify",
                    options: FunctionInvokeOptions(body: request)
                )

            if response.success {
                let matches = response.matches.map { $0.toCustomerMatch() }
                let verification = response.verification.toIDVerificationResult()

                Log.scanner.info("Edge function: Found \(matches.count) matches, verified=\(verification.isVerified)")
                return (matches, verification)
            } else {
                Log.scanner.error("Edge function error: \(response.error ?? "Unknown")")
                return ([], defaultVerificationResult())
            }
        } catch {
            Log.scanner.error("Edge function call failed: \(error.localizedDescription)")
            return ([], defaultVerificationResult())
        }
    }

    /// Convenience method that just returns matches (for backward compatibility)
    /// Uses the Edge Function but only returns the matches portion.
    static func findMatches(for scannedID: ScannedID, storeId: UUID) async -> [CustomerMatch] {
        let (matches, _) = await findMatchesAndVerify(for: scannedID, storeId: storeId)
        return matches
    }

    /// Default verification result for error cases
    private static func defaultVerificationResult() -> IDVerificationResult {
        IDVerificationResult(
            isVerified: false,
            ageVerification: nil,
            licenseStatus: .unknown,
            warnings: [.unknownLicenseStatus],
            verifiedAt: Date()
        )
    }

    // MARK: - Pending Orders (direct query for single customer)

    static func fetchPendingOrders(for customerId: UUID) async -> [Order] {
        do {
            let pendingStatuses = ["pending", "confirmed", "preparing", "packing", "packed", "ready", "ready_to_ship"]

            // customerId is the relationship ID (from user_creation_relationships.id)
            // orders.customer_id references user_creation_relationships.id
            let orders: [Order] = try await supabase
                .from("orders")
                .select("*, v_store_customers(first_name, last_name, email, phone), fulfillments(id, type, status, delivery_location_id, carrier, tracking_number, tracking_url, shipping_cost, created_at, shipped_at, delivered_at, delivery_location:delivery_location_id(id, name))")
                .eq("customer_id", value: customerId.uuidString)
                .in("status", values: pendingStatuses)
                .order("created_at", ascending: false)
                .limit(10)
                .execute()
                .value

            return orders
        } catch {
            Log.scanner.debug("Pending orders fetch failed: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Order History

    static func fetchOrderHistory(for customerId: UUID, limit: Int = 10) async -> [Order] {
        do {
            // customerId is the relationship ID (from user_creation_relationships.id)
            // orders.customer_id references user_creation_relationships.id
            let orders: [Order] = try await supabase
                .from("orders")
                .select("*, v_store_customers(first_name, last_name, email, phone), fulfillments(id, type, status, delivery_location_id, carrier, tracking_number, tracking_url, shipping_cost, created_at, shipped_at, delivered_at, delivery_location:delivery_location_id(id, name))")
                .eq("customer_id", value: customerId.uuidString)
                .order("created_at", ascending: false)
                .limit(limit)
                .execute()
                .value

            return orders
        } catch {
            Log.scanner.error("Order history fetch failed: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Customer Search by Name/Email/Phone

    /// Search customers by name, email, or phone
    /// Used for invoice creation and customer lookup
    static func searchCustomers(query: String, storeId: UUID, limit: Int = 20) async -> [Customer] {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard trimmed.count >= 2 else { return [] }

        do {
            // Use ilike for case-insensitive partial matching
            let customers: [Customer] = try await supabase
                .from("v_store_customers")
                .select()
                .eq("store_id", value: storeId.uuidString)
                .eq("is_active", value: true)
                .or("first_name.ilike.%\(trimmed)%,last_name.ilike.%\(trimmed)%,email.ilike.%\(trimmed)%,phone.ilike.%\(trimmed)%")
                .order("last_name", ascending: true)
                .limit(limit)
                .execute()
                .value

            return customers
        } catch {
            Log.scanner.debug("Customer search failed: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Customer Lookup by UUID

    static func fetchCustomer(id: UUID) async -> Customer? {
        do {
            let response: [Customer] = try await supabase
                .from("v_store_customers")
                .select()
                .eq("id", value: id.uuidString)
                .eq("is_active", value: true)
                .limit(1)
                .execute()
                .value

            return response.first
        } catch {
            Log.scanner.error("Customer lookup failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Create Customer

    static func createCustomer(_ data: NewCustomerFromScan, storeId: UUID, phone: String? = nil, email: String? = nil) async -> Result<Customer, CustomerServiceError> {
        guard let firstName = data.firstName, !firstName.trimmingCharacters(in: .whitespaces).isEmpty,
              let lastName = data.lastName, !lastName.trimmingCharacters(in: .whitespaces).isEmpty else {
            return .failure(.validationError("First name and last name are required"))
        }

        struct CreateCustomerRequest: Encodable {
            let store_id: String
            let first_name: String
            let middle_name: String?
            let last_name: String
            let date_of_birth: String?
            let street_address: String?
            let city: String?
            let state: String?
            let postal_code: String?
            let drivers_license_number: String?
            let phone: String?
            let email: String?
        }

        // Response model with String dates (edge function returns ISO8601 strings)
        // Uses flexible types to handle various JSON representations
        // Maps to new schema: platform_users + user_creation_relationships + store_customer_profiles
        struct EdgeCustomer: Decodable {
            let id: UUID                        // relationship ID
            let platform_user_id: UUID          // platform_users.id
            let store_id: UUID
            let first_name: String?
            let middle_name: String?
            let last_name: String?
            let email: String?
            let phone: String?
            let date_of_birth: String?
            let avatar_url: String?
            let street_address: String?
            let city: String?
            let state: String?
            let postal_code: String?
            let drivers_license_number: String?
            let id_verified: Bool?
            let is_active: Bool?
            let loyalty_points: Int?
            let loyalty_tier: String?
            let total_spent: Double?            // PostgreSQL numeric comes as number
            let total_orders: Int?
            let lifetime_value: Double?
            let email_consent: Bool?
            let sms_consent: Bool?
            let created_at: String
            let updated_at: String
        }

        struct CreateCustomerResponse: Decodable {
            let success: Bool
            let customer: EdgeCustomer?
            let error: String?
            let existing_customer_id: String?
        }

        // Clean phone - keep only digits
        let cleanPhone = phone?.filter { $0.isNumber }
        let validPhone = (cleanPhone?.count ?? 0) >= 10 ? cleanPhone : nil

        // Clean email
        let cleanEmail = email?.trimmingCharacters(in: .whitespaces).lowercased()
        let validEmail = (cleanEmail?.contains("@") ?? false) ? cleanEmail : nil

        let request = CreateCustomerRequest(
            store_id: storeId.uuidString,
            first_name: firstName.trimmingCharacters(in: .whitespaces),
            middle_name: data.middleName?.trimmingCharacters(in: .whitespaces),
            last_name: lastName.trimmingCharacters(in: .whitespaces),
            date_of_birth: data.dateOfBirth,
            street_address: data.streetAddress,
            city: data.city,
            state: data.state,
            postal_code: data.postalCode,
            drivers_license_number: data.driversLicenseNumber,
            phone: validPhone,
            email: validEmail
        )

        do {
            // Use edge function for customer creation (bypasses RLS)
            let response: CreateCustomerResponse = try await supabase.functions
                .invoke(
                    "create-customer",
                    options: FunctionInvokeOptions(body: request)
                )

            if response.success, let edgeCustomer = response.customer {
                // Create customer with date fallback
                let now = Date()
                let iso8601 = ISO8601DateFormatter()
                iso8601.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

                let createdAt = iso8601.date(from: edgeCustomer.created_at)
                    ?? ISO8601DateFormatter().date(from: edgeCustomer.created_at)
                    ?? now
                let updatedAt = iso8601.date(from: edgeCustomer.updated_at)
                    ?? ISO8601DateFormatter().date(from: edgeCustomer.updated_at)
                    ?? now

                // Convert Double to Decimal for monetary fields
                let totalSpent: Decimal? = edgeCustomer.total_spent.map { Decimal($0) }
                let lifetimeValue: Decimal? = edgeCustomer.lifetime_value.map { Decimal($0) }

                let customer = Customer(
                    id: edgeCustomer.id,
                    platformUserId: edgeCustomer.platform_user_id,
                    storeId: edgeCustomer.store_id,
                    firstName: edgeCustomer.first_name,
                    middleName: edgeCustomer.middle_name,
                    lastName: edgeCustomer.last_name,
                    email: edgeCustomer.email,
                    phone: edgeCustomer.phone,
                    dateOfBirth: edgeCustomer.date_of_birth,
                    avatarUrl: edgeCustomer.avatar_url,
                    streetAddress: edgeCustomer.street_address,
                    city: edgeCustomer.city,
                    state: edgeCustomer.state,
                    postalCode: edgeCustomer.postal_code,
                    driversLicenseNumber: edgeCustomer.drivers_license_number,
                    idVerified: edgeCustomer.id_verified,
                    isActive: edgeCustomer.is_active,
                    loyaltyPoints: edgeCustomer.loyalty_points,
                    loyaltyTier: edgeCustomer.loyalty_tier,
                    totalSpent: totalSpent,
                    totalOrders: edgeCustomer.total_orders,
                    lifetimeValue: lifetimeValue,
                    emailConsent: edgeCustomer.email_consent,
                    smsConsent: edgeCustomer.sms_consent,
                    createdAt: createdAt,
                    updatedAt: updatedAt
                )
                Log.scanner.info("Customer created: \(customer.displayName)")
                return .success(customer)
            } else {
                let errorMsg = response.error ?? "Failed to create customer"
                Log.scanner.error("Customer creation failed: \(errorMsg)")
                return .failure(.validationError(errorMsg))
            }
        } catch let error as FunctionsError {
            // Handle edge function errors
            if case .httpError(let code, let data) = error {
                Log.scanner.error("Edge function HTTP error \(code)")
                // Try to decode error response
                if let errorResponse = try? JSONDecoder().decode(CreateCustomerResponse.self, from: data) {
                    return .failure(.validationError(errorResponse.error ?? "Server error"))
                }
                if let errorText = String(data: data, encoding: .utf8) {
                    Log.scanner.error("Error body: \(errorText)")
                }
            }
            return .failure(.createFailed)
        } catch {
            Log.scanner.error("Customer creation failed: \(error.localizedDescription)")
            return .failure(.createFailed)
        }
    }

    // MARK: - Update Customer

    /// Updates customer data across the normalized schema via database function.
    /// Uses update_store_customer() which handles platform_users + store_customer_profiles.
    static func updateCustomer(_ customerId: UUID, fields: CustomerUpdateFields) async -> Result<Customer, CustomerServiceError> {
        let params = UpdateCustomerParams(
            p_relationship_id: customerId.uuidString,
            p_first_name: fields.firstName,
            p_last_name: fields.lastName,
            p_email: fields.email,
            p_phone: fields.phone,
            p_date_of_birth: fields.dateOfBirth,
            p_street_address: fields.streetAddress,
            p_city: fields.city,
            p_state: fields.state,
            p_postal_code: fields.postalCode,
            p_drivers_license_number: fields.driversLicenseNumber
        )

        do {
            // Call the database function that handles the normalized tables
            try await supabase
                .rpc("update_store_customer", params: params)
                .execute()

            // Fetch the updated customer from the view
            guard let customer = await fetchCustomer(id: customerId) else {
                return .failure(.notFound)
            }

            Log.scanner.info("Customer updated: \(customer.displayName)")
            return .success(customer)
        } catch {
            Log.scanner.error("Customer update failed: \(error.localizedDescription)")
            return .failure(.updateFailed)
        }
    }

    // MARK: - Update License Number

    /// Updates customer's driver's license in store_customer_profiles.
    static func updateCustomerLicense(_ customerId: UUID, licenseNumber: String) async {
        do {
            try await supabase
                .rpc("update_store_customer", params: UpdateLicenseParams(
                    p_relationship_id: customerId.uuidString,
                    p_drivers_license_number: licenseNumber
                ))
                .execute()

            Log.scanner.debug("Updated license for customer \(customerId.uuidString.prefix(8))")
        } catch {
            Log.scanner.warning("Failed to update license: \(error.localizedDescription)")
        }
    }

    // MARK: - Merge Customers

    /// Merge two customer records. Keeps primary, merges data from secondary.
    /// - Combines loyalty points
    /// - Reassigns all orders to primary
    /// - Marks secondary relationship as 'merged'
    /// - Allows specifying preferred email/phone when there are conflicts
    ///
    /// New schema: Updates across platform_users, store_customer_profiles, user_creation_relationships
    static func mergeCustomers(
        primary: Customer,
        secondary: Customer,
        storeId: UUID,
        preferredEmail: String? = nil,
        preferredPhone: String? = nil
    ) async -> Result<Customer, CustomerServiceError> {
        await mergeCustomers(
            primaryId: primary.id,
            secondaryId: secondary.id,
            preferredEmail: preferredEmail,
            preferredPhone: preferredPhone
        )
    }

    /// Merge two customer records by ID. Keeps primary, merges data from secondary.
    /// Uses the normalized schema: platform_users + store_customer_profiles + user_creation_relationships
    static func mergeCustomers(
        primaryId: UUID,
        secondaryId: UUID,
        preferredEmail: String? = nil,
        preferredPhone: String? = nil
    ) async -> Result<Customer, CustomerServiceError> {
        do {
            // 1. Fetch both customers from the view
            guard let primary = await fetchCustomer(id: primaryId) else {
                return .failure(.notFound)
            }
            guard let secondary = await fetchCustomer(id: secondaryId) else {
                return .failure(.notFound)
            }

            // 2. Calculate merged stats
            let mergedLoyaltyPoints = (primary.loyaltyPoints ?? 0) + (secondary.loyaltyPoints ?? 0)
            let mergedTotalSpent = (primary.totalSpent ?? 0) + (secondary.totalSpent ?? 0)
            let mergedTotalOrders = (primary.totalOrders ?? 0) + (secondary.totalOrders ?? 0)

            // 3. Update primary platform_user identity (fill blanks from secondary)
            struct PlatformUserUpdate: Encodable {
                let email: String?
                let phone: String?
                let first_name: String?
                let last_name: String?
                let date_of_birth: String?
            }

            let userUpdate = PlatformUserUpdate(
                email: preferredEmail ?? primary.email ?? secondary.email,
                phone: preferredPhone ?? primary.phone ?? secondary.phone,
                first_name: primary.firstName ?? secondary.firstName,
                last_name: primary.lastName ?? secondary.lastName,
                date_of_birth: primary.dateOfBirth ?? secondary.dateOfBirth
            )

            try await supabase
                .from("platform_users")
                .update(userUpdate)
                .eq("id", value: primary.platformUserId.uuidString)
                .execute()

            // 4. Update primary store_customer_profiles with merged stats
            struct ProfileUpdate: Encodable {
                let loyalty_points: Int
                let total_spent: Decimal
                let total_orders: Int
                let lifetime_value: Decimal
                let drivers_license_number: String?
                let street_address: String?
                let city: String?
                let state: String?
                let postal_code: String?
            }

            let profileUpdate = ProfileUpdate(
                loyalty_points: mergedLoyaltyPoints,
                total_spent: mergedTotalSpent,
                total_orders: mergedTotalOrders,
                lifetime_value: mergedTotalSpent,
                drivers_license_number: primary.driversLicenseNumber ?? secondary.driversLicenseNumber,
                street_address: primary.streetAddress ?? secondary.streetAddress,
                city: primary.city ?? secondary.city,
                state: primary.state ?? secondary.state,
                postal_code: primary.postalCode ?? secondary.postalCode
            )

            try await supabase
                .from("store_customer_profiles")
                .update(profileUpdate)
                .eq("relationship_id", value: primaryId.uuidString)
                .execute()

            // 5. Reassign all orders from secondary to primary platform_user
            struct OrderUpdate: Encodable {
                let platform_user_id: String
            }
            try await supabase
                .from("orders")
                .update(OrderUpdate(platform_user_id: primary.platformUserId.uuidString))
                .eq("platform_user_id", value: secondary.platformUserId.uuidString)
                .eq("store_id", value: primary.storeId.uuidString)
                .execute()

            // 6. Reassign loyalty transactions
            try await supabase
                .from("loyalty_transactions")
                .update(OrderUpdate(platform_user_id: primary.platformUserId.uuidString))
                .eq("platform_user_id", value: secondary.platformUserId.uuidString)
                .eq("store_id", value: primary.storeId.uuidString)
                .execute()

            // 7. Mark secondary relationship as merged
            struct RelationshipUpdate: Encodable {
                let status: String
            }
            try await supabase
                .from("user_creation_relationships")
                .update(RelationshipUpdate(status: "merged"))
                .eq("id", value: secondaryId.uuidString)
                .execute()

            // 8. Fetch and return updated primary
            guard let updatedCustomer = await fetchCustomer(id: primaryId) else {
                return .failure(.notFound)
            }

            Log.scanner.info("Merged customer \(secondaryId.uuidString.prefix(8)) into \(primaryId.uuidString.prefix(8))")
            return .success(updatedCustomer)

        } catch {
            Log.scanner.error("Customer merge failed: \(error.localizedDescription)")
            return .failure(.mergeFailed)
        }
    }
}

// MARK: - Update Fields

struct CustomerUpdateFields: Encodable {
    var firstName: String?
    var lastName: String?
    var email: String?
    var phone: String?
    var dateOfBirth: String?
    var streetAddress: String?
    var city: String?
    var state: String?
    var postalCode: String?
    var driversLicenseNumber: String?

    enum CodingKeys: String, CodingKey {
        case firstName = "first_name"
        case lastName = "last_name"
        case email
        case phone
        case dateOfBirth = "date_of_birth"
        case streetAddress = "street_address"
        case city
        case state
        case postalCode = "postal_code"
        case driversLicenseNumber = "drivers_license_number"
    }
}

// MARK: - Errors

enum CustomerServiceError: LocalizedError {
    case createFailed
    case updateFailed
    case notFound
    case mergeFailed
    case validationError(String)

    var errorDescription: String? {
        switch self {
        case .createFailed:
            return "Failed to create customer"
        case .updateFailed:
            return "Failed to update customer"
        case .notFound:
            return "Customer not found"
        case .mergeFailed:
            return "Failed to merge customers"
        case .validationError(let message):
            return message
        }
    }
}
