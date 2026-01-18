//
//  Location.swift
//  Whale
//
//  Created by Fahad Khan on 12/14/25.
//

import Foundation

struct Location: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let slug: String
    let type: String
    let storeId: UUID?
    let addressLine1: String?
    let addressLine2: String?
    let city: String?
    let state: String?
    let zip: String?
    let country: String?
    let phone: String?
    let email: String?
    let isDefault: Bool
    let isActive: Bool
    let isPrimary: Bool
    let posEnabled: Bool
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case slug
        case type
        case storeId = "store_id"
        case addressLine1 = "address_line1"
        case addressLine2 = "address_line2"
        case city
        case state
        case zip
        case country
        case phone
        case email
        case isDefault = "is_default"
        case isActive = "is_active"
        case isPrimary = "is_primary"
        case posEnabled = "pos_enabled"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }


    var displayAddress: String? {
        var parts: [String] = []
        if let addr = addressLine1, !addr.isEmpty { parts.append(addr) }
        if let c = city, !c.isEmpty { parts.append(c) }
        if let s = state, !s.isEmpty { parts.append(s) }
        if let z = zip, !z.isEmpty { parts.append(z) }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// Whether this location is a warehouse (can add stock via labels)
    var isWarehouse: Bool {
        type.lowercased() == "warehouse"
    }

    /// Whether this location is a retail store
    var isRetail: Bool {
        let t = type.lowercased()
        return t == "store" || t == "retail"
    }
}
