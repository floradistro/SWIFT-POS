//
//  OrderEnums.swift
//  Whale
//
//  Order-related enums: channel, fulfillment, status, and payment types.
//

import Foundation

// MARK: - Order Channel

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

// MARK: - Fulfillment Type

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

// MARK: - Order Status Group

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

// MARK: - OrderType (UI Abstraction)

/// UI-level order type abstraction computed from channel + fulfillmentType.
/// Used for filtering and display in the UI - NOT stored in database.
enum OrderType: String, Codable, CaseIterable, Sendable {
    case walkIn = "walk_in"
    case pos
    case pickup
    case shipping
    case delivery
    case direct

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
