//
//  InventoryTransfer.swift
//  Whale
//
//  Package/batch transfer between locations.
//  Supports restocks, store-to-store transfers, returns to warehouse.
//

import Foundation

// MARK: - Transfer

struct InventoryTransfer: Identifiable, Codable, Hashable {
    let id: UUID
    let storeId: UUID
    let transferNumber: String
    let sourceLocationId: UUID
    let destinationLocationId: UUID
    var status: TransferStatus
    var notes: String?
    var trackingNumber: String?
    var shippedAt: Date?
    var receivedAt: Date?
    var cancelledAt: Date?
    let createdAt: Date
    var updatedAt: Date
    let createdByUserId: UUID?
    var approvedByUserId: UUID?
    var receivedByUserId: UUID?
    var cancelledByUserId: UUID?

    // Joined data (not in DB)
    var sourceLocationName: String?
    var destinationLocationName: String?
    var items: [InventoryTransferItem]?
    var itemCount: Int?
    var totalQuantity: Double?

    // MARK: - Computed

    var qrCode: String {
        "P\(id.uuidString.lowercased())"
    }

    var trackingURL: String {
        "https://floradistro.com/qr/\(qrCode)"
    }

    var displayNumber: String {
        "#\(transferNumber)"
    }

    var statusColor: String {
        status.color
    }

    // MARK: - Coding Keys

    enum CodingKeys: String, CodingKey {
        case id
        case storeId = "store_id"
        case transferNumber = "transfer_number"
        case sourceLocationId = "source_location_id"
        case destinationLocationId = "destination_location_id"
        case status
        case notes
        case trackingNumber = "tracking_number"
        case shippedAt = "shipped_at"
        case receivedAt = "received_at"
        case cancelledAt = "cancelled_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case createdByUserId = "created_by_user_id"
        case approvedByUserId = "approved_by_user_id"
        case receivedByUserId = "received_by_user_id"
        case cancelledByUserId = "cancelled_by_user_id"
        case sourceLocationName = "source_location_name"
        case destinationLocationName = "destination_location_name"
        case items
        case itemCount = "item_count"
        case totalQuantity = "total_quantity"
    }
}

// MARK: - Transfer Status

enum TransferStatus: String, Codable, CaseIterable {
    case draft
    case approved
    case inTransit = "in_transit"
    case completed
    case cancelled

    var displayName: String {
        switch self {
        case .draft: return "Draft"
        case .approved: return "Approved"
        case .inTransit: return "In Transit"
        case .completed: return "Completed"
        case .cancelled: return "Cancelled"
        }
    }

    var color: String {
        switch self {
        case .draft: return "gray"
        case .approved: return "blue"
        case .inTransit: return "orange"
        case .completed: return "green"
        case .cancelled: return "red"
        }
    }

    var icon: String {
        switch self {
        case .draft: return "doc.text"
        case .approved: return "checkmark.seal"
        case .inTransit: return "shippingbox"
        case .completed: return "checkmark.circle.fill"
        case .cancelled: return "xmark.circle"
        }
    }
}

// MARK: - Transfer Item

struct InventoryTransferItem: Identifiable, Codable, Hashable {
    let id: UUID
    let transferId: UUID
    let productId: UUID
    var quantity: Double
    var receivedQuantity: Double
    var condition: ItemCondition?
    var conditionNotes: String?
    let createdAt: Date
    var updatedAt: Date

    // Joined data
    var productName: String?
    var productSKU: String?
    var productImage: String?

    // MARK: - Computed

    var isFullyReceived: Bool {
        receivedQuantity >= quantity
    }

    var pendingQuantity: Double {
        max(0, quantity - receivedQuantity)
    }

    // MARK: - Coding Keys

    enum CodingKeys: String, CodingKey {
        case id
        case transferId = "transfer_id"
        case productId = "product_id"
        case quantity
        case receivedQuantity = "received_quantity"
        case condition
        case conditionNotes = "condition_notes"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case productName = "product_name"
        case productSKU = "product_sku"
        case productImage = "product_image"
    }
}

// MARK: - Item Condition

enum ItemCondition: String, Codable, CaseIterable {
    case good
    case damaged
    case expired
    case rejected

    var displayName: String {
        rawValue.capitalized
    }

    var color: String {
        switch self {
        case .good: return "green"
        case .damaged: return "orange"
        case .expired: return "red"
        case .rejected: return "gray"
        }
    }
}

// MARK: - Transfer Create Request

struct CreateTransferRequest: Encodable {
    let store_id: String
    let source_location_id: String
    let destination_location_id: String
    let notes: String?
    let created_by_user_id: String?
    let items: [CreateTransferItemRequest]
}

struct CreateTransferItemRequest: Encodable {
    let product_id: String
    let quantity: Double
}

// MARK: - Transfer Lookup Result

struct TransferLookupResult {
    let success: Bool
    let found: Bool
    let transfer: InventoryTransfer?
    let items: [InventoryTransferItem]?
    let error: String?
}
