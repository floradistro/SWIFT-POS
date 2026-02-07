//
//  OrderJoinedTypes.swift
//  Whale
//
//  Joined/embedded types used by Order: customer, employee,
//  fulfillment, location, and line item models.
//

import Foundation

// MARK: - Order Customer

/// Customer info from joined customers table
struct OrderCustomer: Codable, Sendable {
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

    var fullName: String? {
        let parts = [firstName, lastName].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// Memberwise initializer
    init(firstName: String?, lastName: String?, email: String?, phone: String?) {
        self.firstName = firstName
        self.lastName = lastName
        self.email = email
        self.phone = phone
    }

    /// Create from a Customer model
    init(customer: Customer) {
        self.firstName = customer.firstName
        self.lastName = customer.lastName
        self.email = customer.email
        self.phone = customer.phone
    }
}

// MARK: - Order Employee

/// Employee/staff info from joined staff table
struct OrderEmployee: Codable, Sendable {
    let id: UUID?
    let firstName: String?
    let lastName: String?
    let email: String?

    enum CodingKeys: String, CodingKey {
        case id
        case firstName = "first_name"
        case lastName = "last_name"
        case email
    }

    var fullName: String? {
        let parts = [firstName, lastName].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    var initials: String {
        let first = firstName?.prefix(1).uppercased() ?? ""
        let last = lastName?.prefix(1).uppercased() ?? ""
        return first + last
    }
}

// MARK: - Order Fulfillment

/// Fulfillment record from fulfillments table
struct OrderFulfillment: Identifiable, Codable, Sendable {
    let id: UUID
    let orderId: UUID?
    let type: FulfillmentType
    var status: FulfillmentStatus
    let deliveryLocationId: UUID?
    let deliveryAddress: AnyCodable?
    var carrier: String?
    var trackingNumber: String?
    var trackingUrl: String?
    let shippingCost: Decimal?
    let createdAt: Date?
    var shippedAt: Date?
    var deliveredAt: Date?

    // Joined location data
    let deliveryLocation: FulfillmentLocation?

    enum CodingKeys: String, CodingKey {
        case id
        case orderId = "order_id"
        case type
        case status
        case deliveryLocationId = "delivery_location_id"
        case deliveryAddress = "delivery_address"
        case carrier
        case trackingNumber = "tracking_number"
        case trackingUrl = "tracking_url"
        case shippingCost = "shipping_cost"
        case createdAt = "created_at"
        case shippedAt = "shipped_at"
        case deliveredAt = "delivered_at"
        case deliveryLocation = "delivery_location"
    }

    var locationName: String? {
        deliveryLocation?.name
    }

    var isComplete: Bool {
        status == .delivered || status == .shipped
    }
}

// MARK: - Fulfillment Location

/// Location info from joined locations table on fulfillments
struct FulfillmentLocation: Codable, Sendable {
    let id: UUID?
    let name: String?
    let addressLine1: String?
    let city: String?
    let state: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case addressLine1 = "address_line1"
        case city
        case state
    }

    var locationName: String? { name }
}

// MARK: - Order Source Location

/// Location info from joined locations table on orders (order.location_id)
struct OrderSourceLocation: Codable, Sendable {
    let id: UUID?
    let name: String?
    let addressLine1: String?
    let city: String?
    let state: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case addressLine1 = "address_line1"
        case city
        case state
    }

    var locationName: String? { name }
}

// MARK: - Order Item

struct OrderItem: Identifiable, Codable, Sendable {
    let id: UUID
    let orderId: UUID
    let productId: UUID
    let productName: String
    let quantity: Int
    let unitPrice: Decimal
    let lineTotal: Decimal

    // Tier/pricing schema fields
    let tierName: String?
    let tierQty: Double?
    let tierPrice: Decimal?
    let quantityGrams: Double?
    let quantityDisplay: String?

    // Line subtotal (before discount)
    let lineSubtotal: Decimal?

    // Variant info
    let variantName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case orderId = "order_id"
        case productId = "product_id"
        case productName = "product_name"
        case quantity
        case unitPrice = "unit_price"
        case lineTotal = "line_total"
        case tierName = "tier_name"
        case tierQty = "tier_qty"
        case tierPrice = "tier_price"
        case quantityGrams = "quantity_grams"
        case quantityDisplay = "quantity_display"
        case lineSubtotal = "line_subtotal"
        case variantName = "variant_name"
    }

    var tierLabel: String? { tierName }
    var tierQuantity: Double? { tierQty }
    var variantId: UUID? { nil }
    var originalLineTotal: Decimal { lineSubtotal ?? lineTotal }

    var discountAmount: Decimal? {
        guard let subtotal = lineSubtotal, subtotal > lineTotal else { return nil }
        return subtotal - lineTotal
    }

    var displaySubtitle: String? {
        var parts: [String] = []
        if let tier = tierName {
            parts.append(tier)
        }
        if let variant = variantName {
            parts.append(variant)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }
}

// MARK: - Order Location

/// Represents fulfillment status for a specific location in a multi-location order
struct OrderLocation: Identifiable, Codable, Sendable {
    let id: UUID
    let orderId: UUID
    let locationId: UUID
    let itemCount: Int?
    let totalQuantity: Decimal?
    let fulfillmentStatus: String?
    let notes: String?
    let trackingNumber: String?
    let trackingUrl: String?
    let shippingLabelUrl: String?
    let shippingCarrier: String?
    let shippingService: String?
    let shippingCost: Decimal?
    let shippedAt: Date?
    let fulfilledAt: Date?
    let createdAt: Date?
    let updatedAt: Date?

    // Joined location data
    let location: OrderLocationInfo?

    enum CodingKeys: String, CodingKey {
        case id
        case orderId = "order_id"
        case locationId = "location_id"
        case itemCount = "item_count"
        case totalQuantity = "total_quantity"
        case fulfillmentStatus = "fulfillment_status"
        case notes
        case trackingNumber = "tracking_number"
        case trackingUrl = "tracking_url"
        case shippingLabelUrl = "shipping_label_url"
        case shippingCarrier = "shipping_carrier"
        case shippingService = "shipping_service"
        case shippingCost = "shipping_cost"
        case shippedAt = "shipped_at"
        case fulfilledAt = "fulfilled_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case location
    }

    var locationName: String? {
        location?.name
    }

    var isShipped: Bool {
        fulfillmentStatus == "shipped" || fulfillmentStatus == "delivered" || fulfillmentStatus == "fulfilled"
    }

    var isPending: Bool {
        fulfillmentStatus == "unfulfilled" || fulfillmentStatus == "pending" || fulfillmentStatus == nil
    }
}

// MARK: - Order Location Info

/// Location info from joined locations table on order_locations
struct OrderLocationInfo: Codable, Sendable {
    let name: String?
    let addressLine1: String?
    let city: String?
    let state: String?

    enum CodingKeys: String, CodingKey {
        case name
        case addressLine1 = "address_line1"
        case city
        case state
    }
}
