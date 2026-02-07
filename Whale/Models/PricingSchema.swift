//
//  PricingSchema.swift
//  Whale
//
//  Pricing schema and tier models for product pricing.
//

import Foundation

// MARK: - Pricing Schema

struct PricingSchema: Sendable {
    let id: UUID
    let name: String
    let defaultTiers: [PricingTier]?
}

extension PricingSchema: Codable {
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case defaultTiers = "tiers"
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // ID can be UUID or String
        if let uuid = try? container.decode(UUID.self, forKey: .id) {
            id = uuid
        } else if let str = try? container.decode(String.self, forKey: .id), let uuid = UUID(uuidString: str) {
            id = uuid
        } else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: container, debugDescription: "Invalid UUID")
        }

        name = try container.decode(String.self, forKey: .name)
        defaultTiers = try container.decodeIfPresent([PricingTier].self, forKey: .defaultTiers)
    }
}

// MARK: - Pricing Tier

struct PricingTier: Sendable, Identifiable {
    let id: String
    let label: String
    let quantity: Double
    let unit: String
    let defaultPrice: Decimal
    let sortOrder: Int?
}

extension PricingTier: Codable {
    enum CodingKeys: String, CodingKey {
        case id
        case label
        case quantity
        case unit
        case defaultPrice = "default_price"
        case sortOrder = "sort_order"
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)

        // Quantity can be Int or Double
        if let intVal = try? container.decode(Int.self, forKey: .quantity) {
            quantity = Double(intVal)
        } else {
            quantity = try container.decode(Double.self, forKey: .quantity)
        }

        unit = try container.decode(String.self, forKey: .unit)

        // Price can be Decimal, Double, Int, or String
        if let decimal = try? container.decode(Decimal.self, forKey: .defaultPrice) {
            defaultPrice = decimal
        } else if let double = try? container.decode(Double.self, forKey: .defaultPrice) {
            defaultPrice = Decimal(double)
        } else if let int = try? container.decode(Int.self, forKey: .defaultPrice) {
            defaultPrice = Decimal(int)
        } else if let str = try? container.decode(String.self, forKey: .defaultPrice), let decimal = Decimal(string: str) {
            defaultPrice = decimal
        } else {
            defaultPrice = 0
        }

        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder)
    }
}
