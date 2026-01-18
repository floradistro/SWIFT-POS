//
//  CreationCollection.swift
//  Whale
//
//  Model for collections of creations (menus, displays, etc.)
//  Collections can be global (store-wide) or location-specific.
//

import Foundation

struct CreationCollection: Identifiable, Codable, Sendable {
    let id: UUID
    let name: String
    let description: String?
    let logoUrl: String?
    let accentColor: String?
    let isPublic: Bool?
    let locationId: UUID?
    let createdAt: String?

    // Populated from join
    var creationCount: Int?
    var locationName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case logoUrl = "logo_url"
        case accentColor = "accent_color"
        case isPublic = "is_public"
        case locationId = "location_id"
        case createdAt = "created_at"
        case creationCount = "creation_count"
        case locationName = "location_name"
    }

    /// Whether this is a global (store-wide) collection
    var isGlobal: Bool {
        locationId == nil
    }
}
