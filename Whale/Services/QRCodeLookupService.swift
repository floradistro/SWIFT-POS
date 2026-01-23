//
//  QRCodeLookupService.swift
//  Whale
//
//  Lookup QR codes from the qr_codes table (sale/product labels)
//  Atomic transfer tracking - QR code is the source of truth for location
//

import Foundation
import Supabase
import os.log

// MARK: - QR Code Status

enum QRCodeStatus: String, Codable, Sendable {
    case available = "available"
    case inTransit = "in_transit"
    case sold = "sold"
    case split = "split"
    case consumed = "consumed"

    var displayName: String {
        switch self {
        case .available: return "Available"
        case .inTransit: return "In Transit"
        case .sold: return "Sold"
        case .split: return "Split"
        case .consumed: return "Consumed"
        }
    }

    var icon: String {
        switch self {
        case .available: return "checkmark.circle.fill"
        case .inTransit: return "shippingbox.fill"
        case .sold: return "bag.fill"
        case .split: return "square.split.2x2.fill"
        case .consumed: return "flame.fill"
        }
    }
}

// MARK: - QR Code Record

struct ScannedQRCode: Codable, Identifiable, Sendable {
    let id: UUID
    let storeId: UUID
    let code: String
    let name: String
    let type: String
    let productId: UUID?
    let orderId: UUID?
    let locationId: UUID?
    let locationName: String?
    let tierLabel: String?
    let soldAt: Date?
    let totalScans: Int
    let lastScannedAt: Date?
    let isActive: Bool
    let createdAt: Date

    // New atomic transfer fields
    let status: QRCodeStatus
    let currentTransferId: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case storeId = "store_id"
        case code
        case name
        case type
        case productId = "product_id"
        case orderId = "order_id"
        case locationId = "location_id"
        case locationName = "location_name"
        case tierLabel = "tier_label"
        case soldAt = "sold_at"
        case totalScans = "total_scans"
        case lastScannedAt = "last_scanned_at"
        case isActive = "is_active"
        case createdAt = "created_at"
        case status
        case currentTransferId = "current_transfer_id"
    }

    // Custom decoder to handle missing/null status (for backward compat)
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        storeId = try container.decode(UUID.self, forKey: .storeId)
        code = try container.decode(String.self, forKey: .code)
        name = try container.decode(String.self, forKey: .name)
        type = try container.decode(String.self, forKey: .type)
        productId = try container.decodeIfPresent(UUID.self, forKey: .productId)
        orderId = try container.decodeIfPresent(UUID.self, forKey: .orderId)
        locationId = try container.decodeIfPresent(UUID.self, forKey: .locationId)
        locationName = try container.decodeIfPresent(String.self, forKey: .locationName)
        tierLabel = try container.decodeIfPresent(String.self, forKey: .tierLabel)
        soldAt = try container.decodeIfPresent(Date.self, forKey: .soldAt)
        totalScans = try container.decodeIfPresent(Int.self, forKey: .totalScans) ?? 0
        lastScannedAt = try container.decodeIfPresent(Date.self, forKey: .lastScannedAt)
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        // Default to available if status is missing (for pre-migration QR codes)
        status = try container.decodeIfPresent(QRCodeStatus.self, forKey: .status) ?? .available
        currentTransferId = try container.decodeIfPresent(UUID.self, forKey: .currentTransferId)
    }

    var isSale: Bool { type == "sale" }
    var isProduct: Bool { type == "product" }
    var isBulk: Bool { type == "bulk" }
    var isInTransit: Bool { status == .inTransit }
    var isAvailable: Bool { status == .available }
}

// MARK: - Lookup Service

enum QRCodeLookupService {
    private static let logger = Logger(subsystem: "com.whale.pos", category: "QRCodeLookup")

    static func lookup(code: String, storeId: UUID) async throws -> ScannedQRCode? {
        logger.info("Looking up QR code: \(code)")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: dateString) {
                return date
            }

            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: dateString) {
                return date
            }

            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(dateString)")
        }

        // Try exact match first
        var response = try await supabase
            .from("qr_codes")
            .select()
            .eq("code", value: code)
            .eq("is_active", value: true)
            .limit(1)
            .execute()

        var records = try decoder.decode([ScannedQRCode].self, from: response.data)

        // If not found, try case-insensitive match
        if records.isEmpty {
            logger.info("Exact match not found, trying case-insensitive for: \(code)")
            response = try await supabase
                .from("qr_codes")
                .select()
                .ilike("code", pattern: code)
                .eq("is_active", value: true)
                .limit(1)
                .execute()
            records = try decoder.decode([ScannedQRCode].self, from: response.data)
        }

        if records.isEmpty {
            logger.warning("QR code not found: \(code)")
        } else {
            logger.info("Found QR code: \(records.first?.code ?? "nil")")
        }

        return records.first
    }

    static func recordScan(qrCodeId: UUID, storeId: UUID) async {
        do {
            // Insert scan record
            try await supabase
                .from("qr_scans")
                .insert([
                    "qr_code_id": qrCodeId.uuidString,
                    "store_id": storeId.uuidString,
                    "device_type": "pos_scanner"
                ])
                .execute()

            // Update last_scanned_at
            try await supabase
                .from("qr_codes")
                .update(["last_scanned_at": ISO8601DateFormatter().string(from: Date())])
                .eq("id", value: qrCodeId.uuidString)
                .execute()
        } catch {
            logger.error("Failed to record QR scan: \(error.localizedDescription)")
        }
    }

    /// Record a scan with operation type (receive, transfer_out, etc.)
    static func recordOperationScan(
        qrCodeId: UUID,
        storeId: UUID,
        operation: String,
        locationId: UUID? = nil,
        notes: String? = nil
    ) async throws {
        var data: [String: String] = [
            "qr_code_id": qrCodeId.uuidString,
            "store_id": storeId.uuidString,
            "device_type": "pos_scanner"
        ]

        // Add optional fields - these may not exist in schema yet
        // The insert will succeed with just the required fields
        if !operation.isEmpty {
            data["operation"] = operation
        }
        if let locationId = locationId {
            data["location_id"] = locationId.uuidString
        }
        if let notes = notes, !notes.isEmpty {
            data["notes"] = notes
        }

        try await supabase
            .from("qr_scans")
            .insert(data)
            .execute()

        // Update last_scanned_at and location_id on the QR code itself
        var updateData: [String: String] = [
            "last_scanned_at": ISO8601DateFormatter().string(from: Date())
        ]

        // If receiving, update the QR code's location to the new location
        if operation == "receive", let locationId = locationId {
            updateData["location_id"] = locationId.uuidString
        }

        try await supabase
            .from("qr_codes")
            .update(updateData)
            .eq("id", value: qrCodeId.uuidString)
            .execute()
    }

    /// Get the active transfer for this QR code using the current_transfer_id field
    /// This is the ATOMIC approach - QR code itself knows its transfer
    static func getActiveTransfer(
        qrCodeId: UUID,
        transferId: UUID?,
        storeId: UUID
    ) async -> InventoryTransfer? {
        guard let transferId = transferId else {
            logger.info("QR code \(qrCodeId) has no active transfer (current_transfer_id is nil)")
            return nil
        }

        do {
            let response = try await supabase
                .from("inventory_transfers")
                .select("""
                    *,
                    source:locations!inventory_transfers_source_location_id_fkey(name),
                    destination:locations!inventory_transfers_destination_location_id_fkey(name)
                """)
                .eq("id", value: transferId.uuidString)
                .limit(1)
                .execute()

            guard let jsonArray = try JSONSerialization.jsonObject(with: response.data) as? [[String: Any]],
                  let rawTransfer = jsonArray.first else {
                logger.warning("Transfer \(transferId) not found in database")
                return nil
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let dateString = try container.decode(String.self)
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = formatter.date(from: dateString) { return date }
                formatter.formatOptions = [.withInternetDateTime]
                if let date = formatter.date(from: dateString) { return date }
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date")
            }

            // Extract nested location names from the joined data
            var modifiedTransfer = rawTransfer
            if let source = rawTransfer["source"] as? [String: Any],
               let sourceName = source["name"] as? String {
                modifiedTransfer["source_location_name"] = sourceName
            }
            if let destination = rawTransfer["destination"] as? [String: Any],
               let destName = destination["name"] as? String {
                modifiedTransfer["destination_location_name"] = destName
            }

            let transferData = try JSONSerialization.data(withJSONObject: modifiedTransfer)
            let transfer = try decoder.decode(InventoryTransfer.self, from: transferData)

            logger.info("Found active transfer \(transfer.transferNumber) for QR code \(qrCodeId)")
            return transfer
        } catch {
            logger.error("Failed to get active transfer \(transferId): \(error.localizedDescription)")
            return nil
        }
    }

    /// Create a transfer for a QR code item
    /// ATOMIC: Sets QR code status to in_transit and links to the transfer
    static func createTransfer(
        qrCode: ScannedQRCode,
        storeId: UUID,
        sourceLocationId: UUID,
        destinationLocationId: UUID,
        userId: UUID?
    ) async throws -> InventoryTransfer {
        guard let productId = qrCode.productId else {
            throw NSError(domain: "QRCodeLookupService", code: 400, userInfo: [NSLocalizedDescriptionKey: "QR code has no product ID"])
        }

        // Verify QR code is available for transfer
        guard qrCode.status == .available else {
            throw NSError(domain: "QRCodeLookupService", code: 409, userInfo: [
                NSLocalizedDescriptionKey: "QR code is not available for transfer (status: \(qrCode.status.displayName))"
            ])
        }

        // Create the transfer using InventoryUnitService
        let transfer = try await InventoryUnitService.shared.createTransfer(
            storeId: storeId,
            sourceLocationId: sourceLocationId,
            destinationLocationId: destinationLocationId,
            items: [(productId: productId, quantity: 1)],
            notes: "Transfer of \(qrCode.name) via QR scan",
            userId: userId
        )

        // ATOMIC: Link the QR code to the transfer item
        // This marks this as a QR-based transfer so inventory table updates are skipped
        struct QRLinkUpdate: Encodable {
            let qr_code_id: String
        }
        try await supabase
            .from("inventory_transfer_items")
            .update(QRLinkUpdate(qr_code_id: qrCode.id.uuidString))
            .eq("transfer_id", value: transfer.id.uuidString)
            .execute()

        // ATOMIC: Update QR code status to in_transit and link to transfer
        try await supabase
            .from("qr_codes")
            .update([
                "status": "in_transit",
                "current_transfer_id": transfer.id.uuidString,
                "last_scanned_at": ISO8601DateFormatter().string(from: Date())
            ])
            .eq("id", value: qrCode.id.uuidString)
            .execute()

        logger.info("Created transfer \(transfer.transferNumber) and set QR code \(qrCode.code) to in_transit")
        return transfer
    }

    /// Complete a transfer (receive)
    /// ATOMIC: Sets QR code status back to available, clears transfer link, updates location
    static func completeTransfer(
        transferId: UUID,
        storeId: UUID,
        locationId: UUID,
        userId: UUID?,
        qrCodeId: UUID
    ) async throws {
        // Mark transfer as completed in the inventory system
        _ = try await InventoryUnitService.shared.receiveTransfer(
            transferId: transferId,
            storeId: storeId,
            locationId: locationId,
            userId: userId,
            itemConditions: nil
        )

        // ATOMIC: Reset QR code to available, clear transfer link, update location
        struct QRCodeUpdateComplete: Encodable {
            let status: String
            let current_transfer_id: String?
            let location_id: String
            let last_scanned_at: String
        }
        try await supabase
            .from("qr_codes")
            .update(QRCodeUpdateComplete(
                status: "available",
                current_transfer_id: nil,
                location_id: locationId.uuidString,
                last_scanned_at: ISO8601DateFormatter().string(from: Date())
            ))
            .eq("id", value: qrCodeId.uuidString)
            .execute()

        logger.info("Completed transfer \(transferId), set QR code to available at location \(locationId)")
    }

    /// Cancel a transfer
    /// ATOMIC: Reverts QR code status to available and clears transfer link
    static func cancelTransfer(
        transferId: UUID,
        qrCodeId: UUID
    ) async throws {
        // Cancel the transfer in the inventory system
        try await supabase
            .from("inventory_transfers")
            .update(["status": "cancelled", "cancelled_at": ISO8601DateFormatter().string(from: Date())])
            .eq("id", value: transferId.uuidString)
            .execute()

        // ATOMIC: Revert QR code to available, clear transfer link
        struct QRCodeUpdateCancel: Encodable {
            let status: String
            let current_transfer_id: String?
        }
        try await supabase
            .from("qr_codes")
            .update(QRCodeUpdateCancel(
                status: "available",
                current_transfer_id: nil
            ))
            .eq("id", value: qrCodeId.uuidString)
            .execute()

        logger.info("Cancelled transfer \(transferId), reverted QR code to available")
    }

    /// Check if there's a pending transfer_out for this QR code
    /// Returns transfer info: destination (where it's going) and source (where it came from)
    /// Looks for the most recent transfer_out that hasn't been followed by a receive
    @available(*, deprecated, message: "Use getActiveTransfer instead")
    static func getPendingTransfer(qrCodeId: UUID) async -> (destinationId: UUID, destinationName: String?, sourceId: UUID?, sourceName: String?)? {
        do {
            // Get ALL recent scans to understand the full history
            // We need to track where the item physically IS (not just inventory operations)
            let response = try await supabase
                .from("qr_scans")
                .select("operation, location_id, scanned_at")
                .eq("qr_code_id", value: qrCodeId.uuidString)
                .order("scanned_at", ascending: false)
                .limit(20)  // Get more history to trace the item's journey
                .execute()

            struct ScanRecord: Codable {
                let operation: String?
                let locationId: UUID?

                enum CodingKeys: String, CodingKey {
                    case operation
                    case locationId = "location_id"
                }
            }

            struct LocationRecord: Codable {
                let name: String
            }

            let decoder = JSONDecoder()
            let allRecords = try decoder.decode([ScanRecord].self, from: response.data)

            // Filter to just transfer_out and receive operations for checking pending state
            let inventoryRecords = allRecords.filter { $0.operation == "transfer_out" || $0.operation == "receive" }

            // If the last inventory operation was transfer_out, there's a pending transfer
            guard let mostRecent = inventoryRecords.first,
                  mostRecent.operation == "transfer_out",
                  let destinationId = mostRecent.locationId else {
                return nil
            }

            // Get the destination location name
            let destResponse = try await supabase
                .from("locations")
                .select("name")
                .eq("id", value: destinationId.uuidString)
                .limit(1)
                .execute()

            let destLocations = try decoder.decode([LocationRecord].self, from: destResponse.data)
            let destinationName = destLocations.first?.name

            // Find the SOURCE location - where the item physically IS right now
            // Logic: Before this transfer_out, where was the item?
            // - If there's a previous "receive" operation, that's where it is
            // - If there's a previous "transfer_out", the destination of that transfer is where it ended up
            var sourceId: UUID? = nil
            var sourceName: String? = nil

            // Look at ALL previous inventory operations (skip the current transfer_out)
            for prevRecord in inventoryRecords.dropFirst() {
                guard let prevLocationId = prevRecord.locationId else { continue }

                // For RECEIVE: The location_id is where the item was received
                // For TRANSFER_OUT: The location_id is where it was SENT TO (destination)
                // In both cases, this tells us the item's location AFTER that operation
                sourceId = prevLocationId
                let sourceResponse = try await supabase
                    .from("locations")
                    .select("name")
                    .eq("id", value: prevLocationId.uuidString)
                    .limit(1)
                    .execute()
                let sourceLocations = try decoder.decode([LocationRecord].self, from: sourceResponse.data)
                sourceName = sourceLocations.first?.name

                logger.info("Found source from previous \(prevRecord.operation ?? "unknown") operation: \(sourceName ?? "nil")")
                break
            }

            // If still no source found from scan history, check the QR code's location_id
            if sourceId == nil {
                let qrResponse = try await supabase
                    .from("qr_codes")
                    .select("location_id")
                    .eq("id", value: qrCodeId.uuidString)
                    .limit(1)
                    .execute()

                struct QRRecord: Codable {
                    let locationId: UUID?
                    enum CodingKeys: String, CodingKey {
                        case locationId = "location_id"
                    }
                }

                if let qrRecord = try? decoder.decode([QRRecord].self, from: qrResponse.data).first,
                   let qrLocationId = qrRecord.locationId {
                    sourceId = qrLocationId
                    let sourceResponse = try await supabase
                        .from("locations")
                        .select("name")
                        .eq("id", value: qrLocationId.uuidString)
                        .limit(1)
                        .execute()
                    let sourceLocations = try decoder.decode([LocationRecord].self, from: sourceResponse.data)
                    sourceName = sourceLocations.first?.name
                    logger.info("Found source from QR code location_id: \(sourceName ?? "nil")")
                }
            }

            // If we STILL have no source name, use a generic label (but NOT "External")
            if sourceName == nil {
                sourceName = "its current location"
                logger.warning("Could not determine source location for QR code \(qrCodeId)")
            }

            logger.info("Pending transfer: from '\(sourceName ?? "unknown")' to '\(destinationName ?? "unknown")'")
            return (destinationId, destinationName, sourceId, sourceName)
        } catch {
            logger.error("Failed to check pending transfer: \(error.localizedDescription)")
            return nil
        }
    }
}
