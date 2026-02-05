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

// MARK: - Order Channel (NEW - replaces order_type)

enum OrderChannel: String, Codable, CaseIterable, Sendable {
    case online
    case retail
    case invoice

    var displayName: String {
        switch self {
        case .online: return "Online"
        case .retail: return "In-Store"
        case .invoice: return "Invoice"
        }
    }

    var icon: String {
        switch self {
        case .online: return "globe"
        case .retail: return "storefront"
        case .invoice: return "doc.text"
        }
    }
}

// MARK: - Fulfillment Type (NEW - replaces delivery_type)

enum FulfillmentType: String, Codable, CaseIterable, Sendable {
    case ship
    case pickup
    case immediate

    var displayName: String {
        switch self {
        case .ship: return "Shipping"
        case .pickup: return "Pickup"
        case .immediate: return "Walk-in"
        }
    }

    var icon: String {
        switch self {
        case .ship: return "shippingbox"
        case .pickup: return "bag"
        case .immediate: return "storefront"
        }
    }
}

// MARK: - Fulfillment Status

enum FulfillmentStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case allocated
    case picked
    case packed
    case shipped
    case delivered
    case cancelled

    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .allocated: return "Allocated"
        case .picked: return "Picked"
        case .packed: return "Packed"
        case .shipped: return "Shipped"
        case .delivered: return "Delivered"
        case .cancelled: return "Cancelled"
        }
    }

    var color: String {
        switch self {
        case .pending: return "amber"
        case .allocated, .picked: return "blue"
        case .packed: return "green"
        case .shipped: return "sky"
        case .delivered: return "emerald"
        case .cancelled: return "red"
        }
    }
}

// MARK: - Order Status

enum OrderStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case confirmed
    case preparing
    case packing
    case packed
    case ready
    case outForDelivery = "out_for_delivery"
    case readyToShip = "ready_to_ship"
    case shipped
    case inTransit = "in_transit"
    case delivered
    case completed
    case cancelled

    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .confirmed: return "Confirmed"
        case .preparing: return "Preparing"
        case .packing: return "Packing"
        case .packed: return "Packed"
        case .ready: return "Ready"
        case .outForDelivery: return "Out for Delivery"
        case .readyToShip: return "Ready to Ship"
        case .shipped: return "Shipped"
        case .inTransit: return "In Transit"
        case .delivered: return "Delivered"
        case .completed: return "Completed"
        case .cancelled: return "Cancelled"
        }
    }

    var color: String {
        switch self {
        case .pending: return "amber"
        case .confirmed, .preparing, .packing: return "blue"
        case .packed, .ready, .readyToShip: return "green"
        case .outForDelivery, .shipped, .inTransit: return "sky"
        case .delivered, .completed: return "emerald"
        case .cancelled: return "red"
        }
    }

    /// Status groups for filtering
    var group: OrderStatusGroup {
        switch self {
        case .pending, .confirmed, .preparing, .packing, .packed, .ready, .readyToShip:
            return .active
        case .shipped, .inTransit, .outForDelivery:
            return .inProgress
        case .completed, .delivered:
            return .completed
        case .cancelled:
            return .cancelled
        }
    }
}

enum OrderStatusGroup: String, CaseIterable {
    case active
    case inProgress
    case completed
    case cancelled

    var displayName: String {
        switch self {
        case .active: return "Active"
        case .inProgress: return "In Progress"
        case .completed: return "Completed"
        case .cancelled: return "Cancelled"
        }
    }

    var statuses: [OrderStatus] {
        switch self {
        case .active:
            return [.pending, .confirmed, .preparing, .packing, .packed, .ready, .readyToShip]
        case .inProgress:
            return [.shipped, .inTransit, .outForDelivery]
        case .completed:
            return [.completed, .delivered]
        case .cancelled:
            return [.cancelled]
        }
    }
}

// MARK: - Payment Status

enum PaymentStatus: String, Codable, Sendable {
    case pending
    case paid
    case partial
    case failed
    case refunded
    case partiallyRefunded = "partially_refunded"

    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .paid: return "Paid"
        case .partial: return "Partial"
        case .failed: return "Failed"
        case .refunded: return "Refunded"
        case .partiallyRefunded: return "Partially Refunded"
        }
    }

    var color: String {
        switch self {
        case .pending: return "amber"
        case .paid: return "green"
        case .partial: return "orange"
        case .failed: return "red"
        case .refunded, .partiallyRefunded: return "gray"
        }
    }
}

// MARK: - Joined Data Structures

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
}

// MARK: - Fulfillment (NEW)

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

    /// Location name from joined data
    var locationName: String? {
        deliveryLocation?.name
    }

    /// Whether fulfillment is complete
    var isComplete: Bool {
        status == .delivered || status == .shipped
    }
}

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
}

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

    // Channel & Status (NEW schema)
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

    // Shipping Address (still on orders for convenience)
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

        // Try multiple keys for customer data:
        // - "customers" (direct table join)
        // - "customer" (RPC function returns singular)
        // - "v_store_customers" (view-based joins)
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
        self.customers = customers
        self.items = items
        self.fulfillments = fulfillments
        self.orderLocations = orderLocations
    }
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

    enum CodingKeys: String, CodingKey {
        case id
        case orderId = "order_id"
        case productId = "product_id"
        case productName = "product_name"
        case quantity
        case unitPrice = "unit_price"
        case lineTotal = "line_total"
    }
}

// MARK: - Order Location (Fulfillment per Location)

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

    /// Location name from joined data
    var locationName: String? {
        location?.name
    }

    /// Whether this location has been shipped
    var isShipped: Bool {
        fulfillmentStatus == "shipped" || fulfillmentStatus == "delivered" || fulfillmentStatus == "fulfilled"
    }

    /// Whether this location is still pending
    var isPending: Bool {
        fulfillmentStatus == "unfulfilled" || fulfillmentStatus == "pending" || fulfillmentStatus == nil
    }
}

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

// MARK: - Computed Properties

extension Order {
    /// Primary fulfillment (first one, most orders have only one)
    var primaryFulfillment: OrderFulfillment? {
        fulfillments?.first
    }

    /// Fulfillment type from primary fulfillment
    var fulfillmentType: FulfillmentType {
        primaryFulfillment?.type ?? .immediate
    }

    /// Fulfillment status from primary fulfillment
    var fulfillmentStatus: FulfillmentStatus {
        primaryFulfillment?.status ?? .pending
    }

    /// Delivery location ID from primary fulfillment
    var deliveryLocationId: UUID? {
        primaryFulfillment?.deliveryLocationId
    }

    /// Display name for customer
    var displayCustomerName: String {
        if let name = shippingName, !name.isEmpty, name != "Walk-In" {
            return name
        }
        return customers?.fullName ?? "Walk-in Customer"
    }

    /// Customer name (for compatibility)
    var customerName: String? {
        customers?.fullName
    }

    /// Customer email (for compatibility)
    var customerEmail: String? {
        customers?.email
    }

    /// Customer phone (for compatibility)
    var customerPhone: String? {
        customers?.phone
    }

    /// Fulfillment location name
    var fulfillmentLocationName: String? {
        primaryFulfillment?.locationName
    }

    /// Formatted date string for display
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.timeZone = TimeZone.current
        return formatter.string(from: createdAt)
    }

    /// Formatted total
    var formattedTotal: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: totalAmount as NSDecimalNumber) ?? "$0.00"
    }

    /// Short order number for display
    var shortOrderNumber: String {
        String(orderNumber.suffix(6))
    }

    /// Full shipping address
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

    /// Time since order was created
    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: createdAt, relativeTo: Date())
    }

    /// Display icon based on fulfillment type
    var displayIcon: String {
        fulfillmentType.icon
    }

    /// Display label based on channel and fulfillment type
    var displayTypeLabel: String {
        if channel == .online {
            return fulfillmentType == .ship ? "Online - Shipping" : "Online - Pickup"
        } else {
            return fulfillmentType.displayName
        }
    }

    /// Get tracking info from fulfillment
    var fulfillmentTrackingNumber: String? {
        primaryFulfillment?.trackingNumber ?? trackingNumber
    }

    var fulfillmentTrackingUrl: String? {
        primaryFulfillment?.trackingUrl ?? trackingUrl
    }

    var fulfillmentCarrier: String? {
        primaryFulfillment?.carrier
    }
}

// MARK: - OrderType (UI Abstraction)

/// UI-level order type abstraction computed from channel + fulfillmentType.
/// Used for filtering and display in the UI - NOT stored in database.
enum OrderType: String, Codable, CaseIterable, Sendable {
    case walkIn = "walk_in"
    case pos
    case pickup
    case shipping
    case delivery
    case direct  // Invoice/direct orders

    var displayName: String {
        switch self {
        case .walkIn, .pos: return "Walk-in"
        case .pickup: return "Pickup"
        case .shipping: return "Shipping"
        case .delivery: return "Delivery"
        case .direct: return "Invoice"
        }
    }

    var icon: String {
        switch self {
        case .walkIn, .pos: return "storefront"
        case .pickup: return "bag"
        case .shipping: return "shippingbox"
        case .delivery: return "car"
        case .direct: return "doc.text"
        }
    }

    /// Derive OrderType from channel + fulfillmentType
    static func from(channel: OrderChannel, fulfillmentType: FulfillmentType) -> OrderType {
        switch channel {
        case .retail:
            return .walkIn
        case .online:
            switch fulfillmentType {
            case .ship: return .shipping
            case .pickup: return .pickup
            case .immediate: return .walkIn
            }
        case .invoice:
            return .direct
        }
    }
}

// MARK: - Order UI Convenience

extension Order {
    /// Computed orderType from channel + fulfillmentType (for UI filtering)
    var orderType: OrderType {
        OrderType.from(channel: channel, fulfillmentType: fulfillmentType)
    }

    /// Delivery location name from fulfillment (for pickup orders)
    var deliveryLocationName: String? {
        primaryFulfillment?.deliveryLocation?.name
    }
}

// Note: AnyCodable is defined in Product.swift
