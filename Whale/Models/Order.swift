//
//  Order.swift
//  Whale
//
//  Order model for POS.
//  Matches Supabase orders table structure.
//
//  ARCHITECTURE NOTE (2026-01-22):
//  Migrated to Oracle+Apple architecture:
//  - order_type/delivery_type replaced by channel + fulfillments.type
//  - pickup_location_id moved to fulfillments.delivery_location_id
//  - tracking info moved to fulfillments table
//  - Full event sourcing via order_events table
//

import Foundation

// MARK: - Order

struct Order: Identifiable, Codable, Sendable, Hashable {
    // Hashable conformance - hash based on id only for identity
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Order, rhs: Order) -> Bool {
        lhs.id == rhs.id
    }

    let id: UUID
    let orderNumber: String
    let storeId: UUID?
    let customerId: UUID?

    // Channel & Status
    let channel: OrderChannel
    var status: OrderStatus
    var paymentStatus: PaymentStatus

    // Pricing
    let subtotal: Decimal
    let taxAmount: Decimal
    let discountAmount: Decimal
    let totalAmount: Decimal
    let paymentMethod: String?

    // Timestamps
    let createdAt: Date
    let updatedAt: Date
    var completedAt: Date?

    // Shipping Address
    let shippingName: String?
    let shippingAddressLine1: String?
    let shippingAddressLine2: String?
    let shippingCity: String?
    let shippingState: String?
    let shippingZip: String?

    // Legacy tracking fields (still exist in DB, but prefer fulfillments)
    var trackingNumber: String?
    var trackingUrl: String?
    var staffNotes: String?

    // Employee who created the order
    let employeeId: UUID?
    let employee: OrderEmployee?

    // Source location (where order was placed)
    let locationId: UUID?
    let location: OrderSourceLocation?

    // Joined data
    let customers: OrderCustomer?
    var items: [OrderItem]?
    var fulfillments: [OrderFulfillment]?
    var orderLocations: [OrderLocation]?


    enum CodingKeys: String, CodingKey {
        case id
        case orderNumber = "order_number"
        case storeId = "store_id"
        case customerId = "customer_id"
        case channel
        case status
        case paymentStatus = "payment_status"
        case subtotal
        case taxAmount = "tax_amount"
        case discountAmount = "discount_amount"
        case totalAmount = "total_amount"
        case paymentMethod = "payment_method"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case completedAt = "completed_at"
        case shippingName = "shipping_name"
        case shippingAddressLine1 = "shipping_address_line1"
        case shippingAddressLine2 = "shipping_address_line2"
        case shippingCity = "shipping_city"
        case shippingState = "shipping_state"
        case shippingZip = "shipping_zip"
        case trackingNumber = "tracking_number"
        case trackingUrl = "tracking_url"
        case staffNotes = "staff_notes"
        case employeeId = "employee_id"
        case employee
        case locationId = "location_id"
        case location
        case customers
        case items = "order_items"
        case fulfillments
        case orderLocations = "order_locations"
    }

    // Custom decoder to handle database quirks
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        orderNumber = try container.decode(String.self, forKey: .orderNumber)

        // Handle UUID fields that might be empty strings
        storeId = Self.decodeOptionalUUID(from: container, forKey: .storeId)
        customerId = Self.decodeOptionalUUID(from: container, forKey: .customerId)

        channel = (try? container.decode(OrderChannel.self, forKey: .channel)) ?? .retail
        status = try container.decode(OrderStatus.self, forKey: .status)
        paymentStatus = (try? container.decode(PaymentStatus.self, forKey: .paymentStatus)) ?? .pending

        subtotal = (try? container.decode(Decimal.self, forKey: .subtotal)) ?? 0
        taxAmount = (try? container.decode(Decimal.self, forKey: .taxAmount)) ?? 0
        discountAmount = (try? container.decode(Decimal.self, forKey: .discountAmount)) ?? 0
        totalAmount = (try? container.decode(Decimal.self, forKey: .totalAmount)) ?? 0
        paymentMethod = try container.decodeIfPresent(String.self, forKey: .paymentMethod)

        createdAt = try Self.parseDate(from: container, forKey: .createdAt)
        updatedAt = try Self.parseDate(from: container, forKey: .updatedAt)
        completedAt = try Self.parseDateIfPresent(from: container, forKey: .completedAt)

        shippingName = try container.decodeIfPresent(String.self, forKey: .shippingName)
        shippingAddressLine1 = try container.decodeIfPresent(String.self, forKey: .shippingAddressLine1)
        shippingAddressLine2 = try container.decodeIfPresent(String.self, forKey: .shippingAddressLine2)
        shippingCity = try container.decodeIfPresent(String.self, forKey: .shippingCity)
        shippingState = try container.decodeIfPresent(String.self, forKey: .shippingState)
        shippingZip = try container.decodeIfPresent(String.self, forKey: .shippingZip)

        trackingNumber = try container.decodeIfPresent(String.self, forKey: .trackingNumber)
        trackingUrl = try container.decodeIfPresent(String.self, forKey: .trackingUrl)
        staffNotes = try container.decodeIfPresent(String.self, forKey: .staffNotes)

        // Employee
        employeeId = Self.decodeOptionalUUID(from: container, forKey: .employeeId)
        employee = try container.decodeIfPresent(OrderEmployee.self, forKey: .employee)

        // Source location
        locationId = Self.decodeOptionalUUID(from: container, forKey: .locationId)
        location = try container.decodeIfPresent(OrderSourceLocation.self, forKey: .location)

        // Try multiple keys for customer data
        if let c = try container.decodeIfPresent(OrderCustomer.self, forKey: .customers) {
            customers = c
        } else {
            enum AltKeys: String, CodingKey {
                case customer
                case vStoreCustomers = "v_store_customers"
            }
            let altContainer = try decoder.container(keyedBy: AltKeys.self)
            if let c = try altContainer.decodeIfPresent(OrderCustomer.self, forKey: .customer) {
                customers = c
            } else {
                customers = try altContainer.decodeIfPresent(OrderCustomer.self, forKey: .vStoreCustomers)
            }
        }

        items = try container.decodeIfPresent([OrderItem].self, forKey: .items)
        fulfillments = try container.decodeIfPresent([OrderFulfillment].self, forKey: .fulfillments)
        orderLocations = try container.decodeIfPresent([OrderLocation].self, forKey: .orderLocations)
    }

    // Helper to decode UUID that might be null or empty string
    private static func decodeOptionalUUID(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> UUID? {
        if let uuid = try? container.decodeIfPresent(UUID.self, forKey: key) {
            return uuid
        }
        if let uuidString = try? container.decodeIfPresent(String.self, forKey: key),
           !uuidString.isEmpty {
            return UUID(uuidString: uuidString)
        }
        return nil
    }

    // Helper to parse Postgres timestamps
    private static func parseDate(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Date {
        if let date = try? container.decode(Date.self, forKey: key) {
            return date
        }
        let dateString = try container.decode(String.self, forKey: key)
        return parseISO8601Date(dateString) ?? Date()
    }

    private static func parseDateIfPresent(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Date? {
        if let date = try? container.decodeIfPresent(Date.self, forKey: key) {
            return date
        }
        guard let dateString = try container.decodeIfPresent(String.self, forKey: key) else {
            return nil
        }
        return parseISO8601Date(dateString)
    }

    private static func parseISO8601Date(_ dateString: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: dateString) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: dateString)
    }

    // Memberwise initializer for programmatic creation
    init(
        id: UUID,
        orderNumber: String,
        storeId: UUID?,
        customerId: UUID?,
        channel: OrderChannel,
        status: OrderStatus,
        paymentStatus: PaymentStatus,
        subtotal: Decimal,
        taxAmount: Decimal,
        discountAmount: Decimal,
        totalAmount: Decimal,
        paymentMethod: String?,
        createdAt: Date,
        updatedAt: Date,
        completedAt: Date? = nil,
        shippingName: String? = nil,
        shippingAddressLine1: String? = nil,
        shippingAddressLine2: String? = nil,
        shippingCity: String? = nil,
        shippingState: String? = nil,
        shippingZip: String? = nil,
        trackingNumber: String? = nil,
        trackingUrl: String? = nil,
        staffNotes: String? = nil,
        employeeId: UUID? = nil,
        employee: OrderEmployee? = nil,
        locationId: UUID? = nil,
        location: OrderSourceLocation? = nil,
        customers: OrderCustomer? = nil,
        items: [OrderItem]? = nil,
        fulfillments: [OrderFulfillment]? = nil,
        orderLocations: [OrderLocation]? = nil
    ) {
        self.id = id
        self.orderNumber = orderNumber
        self.storeId = storeId
        self.customerId = customerId
        self.channel = channel
        self.status = status
        self.paymentStatus = paymentStatus
        self.subtotal = subtotal
        self.taxAmount = taxAmount
        self.discountAmount = discountAmount
        self.totalAmount = totalAmount
        self.paymentMethod = paymentMethod
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
        self.shippingName = shippingName
        self.shippingAddressLine1 = shippingAddressLine1
        self.shippingAddressLine2 = shippingAddressLine2
        self.shippingCity = shippingCity
        self.shippingState = shippingState
        self.shippingZip = shippingZip
        self.trackingNumber = trackingNumber
        self.trackingUrl = trackingUrl
        self.staffNotes = staffNotes
        self.employeeId = employeeId
        self.employee = employee
        self.locationId = locationId
        self.location = location
        self.customers = customers
        self.items = items
        self.fulfillments = fulfillments
        self.orderLocations = orderLocations
    }
}

// MARK: - Computed Properties

extension Order {
    var primaryFulfillment: OrderFulfillment? {
        fulfillments?.first
    }

    var fulfillmentType: FulfillmentType {
        primaryFulfillment?.type ?? .immediate
    }

    var fulfillmentStatus: FulfillmentStatus {
        primaryFulfillment?.status ?? .pending
    }

    var deliveryLocationId: UUID? {
        primaryFulfillment?.deliveryLocationId
    }

    var displayCustomerName: String {
        if let name = shippingName, !name.isEmpty, name != "Walk-In" {
            return name
        }
        return customers?.fullName ?? "Walk-in Customer"
    }

    var customerName: String? {
        customers?.fullName
    }

    var customerEmail: String? {
        customers?.email
    }

    var customerPhone: String? {
        customers?.phone
    }

    var fulfillmentLocationName: String? {
        primaryFulfillment?.locationName
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.timeZone = TimeZone.current
        return formatter.string(from: createdAt)
    }

    var formattedTotal: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: totalAmount as NSDecimalNumber) ?? "$0.00"
    }

    var shortOrderNumber: String {
        String(orderNumber.suffix(6))
    }

    var fullShippingAddress: String? {
        guard let line1 = shippingAddressLine1 else { return nil }
        var parts = [line1]
        if let line2 = shippingAddressLine2, !line2.isEmpty {
            parts.append(line2)
        }
        if let city = shippingCity, let state = shippingState, let zip = shippingZip {
            parts.append("\(city), \(state) \(zip)")
        }
        return parts.joined(separator: "\n")
    }

    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: createdAt, relativeTo: Date())
    }

    var displayIcon: String {
        fulfillmentType.icon
    }

    var displayTypeLabel: String {
        if channel == .online {
            return fulfillmentType == .ship ? "Online - Shipping" : "Online - Pickup"
        } else {
            return fulfillmentType.displayName
        }
    }

    var fulfillmentTrackingNumber: String? {
        primaryFulfillment?.trackingNumber ?? trackingNumber
    }

    var fulfillmentTrackingUrl: String? {
        primaryFulfillment?.trackingUrl ?? trackingUrl
    }

    var fulfillmentCarrier: String? {
        primaryFulfillment?.carrier
    }

    var orderType: OrderType {
        OrderType.from(channel: channel, fulfillmentType: fulfillmentType)
    }

    var deliveryLocationName: String? {
        primaryFulfillment?.deliveryLocation?.name
    }
}
