//
//  Order.swift
//  Whale
//
//  Order model for POS.
//  Matches Supabase orders table structure.
//
//  ARCHITECTURE NOTE (2026-01-01):
//  Location-based filtering logic has been moved to the backend.
//  The database now handles:
//  - hasItemsForLocation via is_order_visible_to_location RPC
//  - itemsForLocation via get_order_items_for_location RPC
//  The remaining helpers here are purely for display purposes.
//

import Foundation

// MARK: - Order Type

enum OrderType: String, Codable, CaseIterable, Sendable {
    case walkIn = "walk_in"
    case pos = "pos"          // Alias for walk_in (website uses 'pos')
    case pickup = "pickup"
    case delivery = "delivery"
    case shipping = "shipping"
    case direct = "direct"    // Invoice/direct order - customer pays via payment link

    var displayName: String {
        switch self {
        case .walkIn, .pos: return "Walk-in"
        case .pickup: return "Pickup"
        case .delivery: return "Delivery"
        case .shipping: return "Shipping"
        case .direct: return "Invoice"
        }
    }

    var icon: String {
        switch self {
        case .walkIn, .pos: return "storefront"
        case .pickup: return "bag"
        case .delivery: return "car"
        case .shipping: return "shippingbox"
        case .direct: return "paperplane"
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

/// Pickup location info from joined locations table
struct OrderPickupLocation: Codable, Sendable {
    let name: String?
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

    // Type & Status
    let orderType: OrderType
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

    // Pickup Location
    let pickupLocationId: UUID?

    // Shipping Address
    let shippingName: String?
    let shippingAddressLine1: String?
    let shippingAddressLine2: String?
    let shippingCity: String?
    let shippingState: String?
    let shippingZip: String?

    // Tracking
    var trackingNumber: String?
    var trackingUrl: String?
    var shippingLabelUrl: String?
    var shippingCarrier: String?
    var staffNotes: String?

    // Joined data
    let customers: OrderCustomer?
    let pickupLocation: OrderPickupLocation?
    var items: [OrderItem]?
    var orderLocations: [OrderLocation]?


    enum CodingKeys: String, CodingKey {
        case id
        case orderNumber = "order_number"
        case storeId = "store_id"
        case customerId = "customer_id"
        case orderType = "order_type"
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
        case pickupLocationId = "pickup_location_id"
        case shippingName = "shipping_name"
        case shippingAddressLine1 = "shipping_address_line1"
        case shippingAddressLine2 = "shipping_address_line2"
        case shippingCity = "shipping_city"
        case shippingState = "shipping_state"
        case shippingZip = "shipping_zip"
        case trackingNumber = "tracking_number"
        case trackingUrl = "tracking_url"
        case shippingLabelUrl = "shipping_label_url"
        case shippingCarrier = "shipping_carrier"
        case staffNotes = "staff_notes"
        case customers
        case pickupLocation = "pickup_location"
        case items = "order_items"
        case orderLocations = "order_locations"
    }

    // Custom decoder to handle empty string UUIDs from database
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        orderNumber = try container.decode(String.self, forKey: .orderNumber)

        // Handle UUID fields that might be empty strings
        storeId = Self.decodeOptionalUUID(from: container, forKey: .storeId)
        customerId = Self.decodeOptionalUUID(from: container, forKey: .customerId)
        pickupLocationId = Self.decodeOptionalUUID(from: container, forKey: .pickupLocationId)

        orderType = try container.decode(OrderType.self, forKey: .orderType)
        status = try container.decode(OrderStatus.self, forKey: .status)
        paymentStatus = try container.decode(PaymentStatus.self, forKey: .paymentStatus)

        subtotal = try container.decode(Decimal.self, forKey: .subtotal)
        taxAmount = try container.decode(Decimal.self, forKey: .taxAmount)
        discountAmount = try container.decode(Decimal.self, forKey: .discountAmount)
        totalAmount = try container.decode(Decimal.self, forKey: .totalAmount)
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
        shippingLabelUrl = try container.decodeIfPresent(String.self, forKey: .shippingLabelUrl)
        shippingCarrier = try container.decodeIfPresent(String.self, forKey: .shippingCarrier)
        staffNotes = try container.decodeIfPresent(String.self, forKey: .staffNotes)

        // Try both old `customers` key and new `v_store_customers` key (for view-based joins)
        if let c = try container.decodeIfPresent(OrderCustomer.self, forKey: .customers) {
            customers = c
        } else {
            // Try the alternate key from v_store_customers join
            enum AltKeys: String, CodingKey { case vStoreCustomers = "v_store_customers" }
            let altContainer = try decoder.container(keyedBy: AltKeys.self)
            customers = try altContainer.decodeIfPresent(OrderCustomer.self, forKey: .vStoreCustomers)
        }
        pickupLocation = try container.decodeIfPresent(OrderPickupLocation.self, forKey: .pickupLocation)
        items = try container.decodeIfPresent([OrderItem].self, forKey: .items)
        orderLocations = try container.decodeIfPresent([OrderLocation].self, forKey: .orderLocations)
    }

    // Helper to decode UUID that might be null or empty string
    private static func decodeOptionalUUID(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> UUID? {
        // Try decoding as UUID first
        if let uuid = try? container.decodeIfPresent(UUID.self, forKey: key) {
            return uuid
        }
        // Try decoding as String and convert (handles empty string case)
        if let uuidString = try? container.decodeIfPresent(String.self, forKey: key),
           !uuidString.isEmpty {
            return UUID(uuidString: uuidString)
        }
        return nil
    }

    // Helper to parse Postgres timestamps (with timezone offset like -05:00)
    private static func parseDate(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Date {
        // Try decoding as Date first (if decoder has date strategy configured)
        if let date = try? container.decode(Date.self, forKey: key) {
            return date
        }

        // Fallback: decode as string and parse manually
        let dateString = try container.decode(String.self, forKey: key)
        return parseISO8601Date(dateString) ?? Date()
    }

    // Helper to parse optional Postgres timestamps
    private static func parseDateIfPresent(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Date? {
        // Try decoding as Date first
        if let date = try? container.decodeIfPresent(Date.self, forKey: key) {
            return date
        }

        // Fallback: decode as string and parse
        guard let dateString = try container.decodeIfPresent(String.self, forKey: key) else {
            return nil
        }
        return parseISO8601Date(dateString)
    }

    // Shared ISO8601 date parser
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
        orderType: OrderType,
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
        pickupLocationId: UUID? = nil,
        shippingName: String? = nil,
        shippingAddressLine1: String? = nil,
        shippingAddressLine2: String? = nil,
        shippingCity: String? = nil,
        shippingState: String? = nil,
        shippingZip: String? = nil,
        trackingNumber: String? = nil,
        trackingUrl: String? = nil,
        shippingLabelUrl: String? = nil,
        shippingCarrier: String? = nil,
        staffNotes: String? = nil,
        customers: OrderCustomer? = nil,
        pickupLocation: OrderPickupLocation? = nil,
        items: [OrderItem]? = nil,
        orderLocations: [OrderLocation]? = nil
    ) {
        self.id = id
        self.orderNumber = orderNumber
        self.storeId = storeId
        self.customerId = customerId
        self.orderType = orderType
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
        self.pickupLocationId = pickupLocationId
        self.shippingName = shippingName
        self.shippingAddressLine1 = shippingAddressLine1
        self.shippingAddressLine2 = shippingAddressLine2
        self.shippingCity = shippingCity
        self.shippingState = shippingState
        self.shippingZip = shippingZip
        self.trackingNumber = trackingNumber
        self.trackingUrl = trackingUrl
        self.shippingLabelUrl = shippingLabelUrl
        self.shippingCarrier = shippingCarrier
        self.staffNotes = staffNotes
        self.customers = customers
        self.pickupLocation = pickupLocation
        self.items = items
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
    // Fulfillment location (smart routed)
    let locationId: UUID?
    let pickupLocationName: String?
    // Nested location from join
    let location: OrderItemLocation?

    enum CodingKeys: String, CodingKey {
        case id
        case orderId = "order_id"
        case productId = "product_id"
        case productName = "product_name"
        case quantity
        case unitPrice = "unit_price"
        case lineTotal = "line_total"
        case locationId = "location_id"
        case pickupLocationName = "pickup_location_name"
        case location
    }

    /// Location name from either nested join or direct field
    var locationName: String? {
        location?.name ?? pickupLocationName
    }
}

/// Location info from joined locations table on order_items
struct OrderItemLocation: Codable, Sendable {
    let name: String?
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
    /// Display name for customer
    var displayCustomerName: String {
        // Prioritize shipping_name (set by backend) over joined customer record
        // This ensures consistent naming across all order sources
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

    /// Pickup location name (for compatibility)
    var pickupLocationName: String? {
        pickupLocation?.name
    }

    /// Formatted date string for display
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.timeZone = TimeZone.current  // Explicitly use device timezone
        return formatter.string(from: createdAt)
    }

    /// Fulfillment location name - works for all order types
    /// For pickup: uses pickup_location
    /// For shipping/delivery: gets location from first item (smart routed)
    var fulfillmentLocationName: String? {
        // First try order-level pickup location
        if let locationName = pickupLocation?.name {
            return locationName
        }
        // For shipping orders, get from first item's location
        // Check both the nested join and the direct pickup_location_name field
        if let items = items, let firstItem = items.first {
            // Try nested location join first
            if let nestedName = firstItem.location?.name {
                return nestedName
            }
            // Fall back to direct pickup_location_name field
            if let directName = firstItem.pickupLocationName {
                return directName
            }
        }
        return nil
    }

    /// All unique fulfillment location names (for multi-location orders)
    var fulfillmentLocationNames: [String] {
        var locations: [String] = []
        // Add order-level location if present
        if let locationName = pickupLocation?.name {
            locations.append(locationName)
        }
        // Add item-level locations
        if let items = items {
            for item in items {
                if let locationName = item.locationName, !locations.contains(locationName) {
                    locations.append(locationName)
                }
            }
        }
        return locations
    }

    /// Check if this order has items for a specific location
    /// NOTE: For permission checks, use OrderService.isOrderVisibleToLocation() instead
    /// This is kept for backward compatibility and display purposes
    @available(*, deprecated, message: "Use OrderService.isOrderVisibleToLocation() for permission checks")
    func hasItemsForLocation(_ locationId: UUID) -> Bool {
        // For pickup orders, check pickup_location_id
        if orderType == .pickup, pickupLocationId == locationId {
            return true
        }
        // For all order types, check if any items are routed to this location
        return items?.contains { $0.locationId == locationId } ?? false
    }

    /// Get items filtered to a specific location (for multi-location fulfillment)
    /// NOTE: For complete item separation, use OrderService.getOrderItemsForLocation() instead
    @available(*, deprecated, message: "Use OrderService.getOrderItemsForLocation() for RPC-based item separation")
    func itemsForLocation(_ locationId: UUID) -> [OrderItem] {
        guard let items = items else { return [] }
        return items.filter { $0.locationId == locationId }
    }

    /// Check if this is a multi-location order (items split across locations)
    @available(*, deprecated, message: "Use fulfillmentLocationNames.count > 1 instead")
    var isMultiLocation: Bool {
        guard let items = items else { return false }
        let uniqueLocations = Set(items.compactMap { $0.locationId })
        return uniqueLocations.count > 1
    }

    /// Total quantity of items for a specific location
    @available(*, deprecated, message: "Use OrderService.getOrderItemsForLocation() for RPC-based item separation")
    func quantityForLocation(_ locationId: UUID) -> Int {
        itemsForLocation(locationId).reduce(0) { $0 + $1.quantity }
    }

    // MARK: - Order Location Helpers

    /// Get the order_location record for a specific location
    func orderLocation(for locationId: UUID) -> OrderLocation? {
        orderLocations?.first { $0.locationId == locationId }
    }

    /// Get fulfillment status for a specific location
    func fulfillmentStatus(for locationId: UUID) -> String? {
        orderLocation(for: locationId)?.fulfillmentStatus
    }

    /// Get tracking info for a specific location
    func trackingInfo(for locationId: UUID) -> (number: String?, carrier: String?, url: String?)? {
        guard let loc = orderLocation(for: locationId) else { return nil }
        return (loc.trackingNumber, loc.shippingCarrier, loc.trackingUrl)
    }

    /// Check if a specific location has been shipped
    func isLocationShipped(_ locationId: UUID) -> Bool {
        orderLocation(for: locationId)?.isShipped ?? false
    }

    /// Check if all locations have been shipped
    var allLocationsShipped: Bool {
        guard let locations = orderLocations, !locations.isEmpty else {
            // No order_locations - fall back to order-level status
            return status == .shipped || status == .delivered || status == .completed
        }
        return locations.allSatisfy { $0.isShipped }
    }

    /// Count of shipped vs total locations
    var shippedLocationsCount: (shipped: Int, total: Int) {
        guard let locations = orderLocations else { return (0, 0) }
        let shipped = locations.filter { $0.isShipped }.count
        return (shipped, locations.count)
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
}
