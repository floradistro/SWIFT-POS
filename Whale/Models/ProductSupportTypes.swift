//
//  ProductSupportTypes.swift
//  Whale
//
//  Supporting types for Product: category, inventory,
//  store fields, and field definitions.
//

import Foundation

// MARK: - Product Category

struct ProductCategory: Codable, Sendable {
    let id: UUID
    let name: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
    }
}

// MARK: - Product Inventory

struct ProductInventory: Codable, Sendable {
    let id: UUID
    let productId: UUID
    let locationId: UUID
    let totalQuantity: Decimal?
    let heldQuantity: Decimal?
    let availableQuantity: Decimal?

    enum CodingKeys: String, CodingKey {
        case id
        case productId = "product_id"
        case locationId = "location_id"
        case totalQuantity = "total_quantity"
        case heldQuantity = "held_quantity"
        case availableQuantity = "available_quantity"
    }

    var quantity: Int {
        let decimal = availableQuantity ?? totalQuantity ?? 0
        return NSDecimalNumber(decimal: decimal).intValue
    }

    init(id: UUID, productId: UUID, locationId: UUID, totalQuantity: Decimal?, heldQuantity: Decimal?, availableQuantity: Decimal?) {
        self.id = id
        self.productId = productId
        self.locationId = locationId
        self.totalQuantity = totalQuantity
        self.heldQuantity = heldQuantity
        self.availableQuantity = availableQuantity
    }
}

// MARK: - Store Product Field

struct StoreProductField: Codable, Sendable, Identifiable {
    let id: UUID
    let storeId: UUID
    let categoryId: UUID?
    let fieldId: String
    let fieldDefinition: FieldDefinition
    let sortOrder: Int

    var displayLabel: String {
        fieldDefinition.label ?? formatFieldId(fieldId)
    }

    private func formatFieldId(_ id: String) -> String {
        id.replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }

    enum CodingKeys: String, CodingKey {
        case id
        case storeId = "store_id"
        case categoryId = "category_id"
        case fieldId = "field_id"
        case fieldDefinition = "field_definition"
        case sortOrder = "sort_order"
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        storeId = try container.decode(UUID.self, forKey: .storeId)
        categoryId = try container.decodeIfPresent(UUID.self, forKey: .categoryId)
        fieldId = try container.decode(String.self, forKey: .fieldId)
        fieldDefinition = try container.decode(FieldDefinition.self, forKey: .fieldDefinition)
        sortOrder = (try? container.decodeIfPresent(Int.self, forKey: .sortOrder)) ?? 0
    }
}

// MARK: - Field Definition

struct FieldDefinition: Codable, Sendable {
    let type: String?
    let label: String?
    let options: [String]?

    enum CodingKeys: String, CodingKey {
        case type
        case label
        case options
    }
}
