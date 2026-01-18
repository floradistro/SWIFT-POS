//
//  Creation.swift
//  Whale
//
//  Model for AI-generated creations (displays, dashboards, landing pages, etc.)
//

import Foundation

struct Creation: Identifiable, Codable, Sendable {
    let id: UUID
    let name: String
    let creation_type: String
    let status: String?
    let thumbnail_url: String?
    let deployed_url: String?
    let react_code: String?
    let created_at: String?
    let is_public: Bool?
    let visibility: String?
    let location_id: UUID?
    let is_pinned: Bool?
    let pinned_at: String?
    let pin_order: Int?
    let is_template: Bool?

    // Computed property for SmartDockView compatibility
    var type: String { creation_type }
    var thumbnailUrl: String? { thumbnail_url }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case creation_type
        case status
        case thumbnail_url
        case deployed_url
        case react_code
        case created_at
        case is_public
        case visibility
        case location_id
        case is_pinned
        case pinned_at
        case pin_order
        case is_template
    }
}
