//
//  Register.swift
//  Whale
//
//  Created by Fahad Khan on 12/15/25.
//

import Foundation

struct Register: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let locationId: UUID
    let storeId: UUID?
    let registerNumber: String
    let registerName: String
    let status: String
    let deviceId: String?
    let deviceName: String?
    let deviceType: String?
    let allowCash: Bool
    let allowCard: Bool
    let allowRefunds: Bool
    let allowVoids: Bool
    let requireManagerApproval: Bool
    let hardwareModel: String?
    let createdAt: Date?
    let updatedAt: Date?


    enum CodingKeys: String, CodingKey {
        case id
        case locationId = "location_id"
        case storeId = "store_id"
        case registerNumber = "register_number"
        case registerName = "register_name"
        case status
        case deviceId = "device_id"
        case deviceName = "device_name"
        case deviceType = "device_type"
        case allowCash = "allow_cash"
        case allowCard = "allow_card"
        case allowRefunds = "allow_refunds"
        case allowVoids = "allow_voids"
        case requireManagerApproval = "require_manager_approval"
        case hardwareModel = "hardware_model"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var displayName: String {
        if !registerName.isEmpty {
            return registerName
        }
        return "Register \(registerNumber)"
    }
}
