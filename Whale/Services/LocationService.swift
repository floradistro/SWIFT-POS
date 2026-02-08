//
//  LocationService.swift
//  Whale
//
//  Location fetch operations with Supabase.
//

import Foundation
import Supabase

enum LocationService {

    /// Fetch all active locations for a store (for transfers, etc.)
    static func fetchActiveLocations(storeId: UUID) async throws -> [Location] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let response = try await supabase
            .from("locations")
            .select()
            .eq("store_id", value: storeId.uuidString)
            .eq("is_active", value: true)
            .order("name")
            .execute()

        return try decoder.decode([Location].self, from: response.data)
    }

    /// Fetch active registers for a location
    static func fetchRegisters(locationId: UUID) async throws -> [Register] {
        try await supabase
            .from("pos_registers")
            .select()
            .eq("location_id", value: locationId.uuidString.lowercased())
            .eq("status", value: "active")
            .order("register_name")
            .execute()
            .value
    }
}
