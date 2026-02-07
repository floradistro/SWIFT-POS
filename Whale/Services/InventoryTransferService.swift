//
//  InventoryTransferService.swift
//  Whale
//
//  Service for managing inventory package transfers between locations.
//  Handles transfer creation, QR lookup, and receiving with inventory updates.
//  Extracted from InventoryUnitService for Apple engineering standards compliance.
//

import Foundation
import Supabase
import os.log

// MARK: - Inventory Transfer Service

@MainActor
final class InventoryTransferService {
    static let shared = InventoryTransferService()

    private let logger = Logger(subsystem: "com.whale", category: "InventoryTransferService")

    private init() {}

    // MARK: - Internal Types

    private struct ReceiveTransferInfo: Decodable {
        let id: UUID
        let source_location_id: UUID
        let destination_location_id: UUID
        let store_id: UUID
    }

    private struct ReceiveTransferItem: Decodable {
        let id: UUID
        let product_id: UUID
        let quantity: Double
        let qr_code_id: UUID?
    }

    // MARK: - Create Transfer

    /// Create a new transfer package
    func createTransfer(
        storeId: UUID,
        sourceLocationId: UUID,
        destinationLocationId: UUID,
        items: [(productId: UUID, quantity: Double)],
        notes: String?,
        userId: UUID?
    ) async throws -> InventoryTransfer {
        print("📦 Creating transfer: \(sourceLocationId) → \(destinationLocationId)")

        // Generate transfer number
        let transferNumber = "TRF-\(Int(Date().timeIntervalSince1970) % 1000000)"

        struct TransferInsert: Encodable {
            let id: String
            let store_id: String
            let transfer_number: String
            let source_location_id: String
            let destination_location_id: String
            let status: String
            let notes: String?
            let created_by_user_id: String?
        }

        let transferId = UUID()
        let transferInsert = TransferInsert(
            id: transferId.uuidString,
            store_id: storeId.uuidString,
            transfer_number: transferNumber,
            source_location_id: sourceLocationId.uuidString,
            destination_location_id: destinationLocationId.uuidString,
            status: "in_transit",
            notes: notes,
            created_by_user_id: userId?.uuidString
        )

        try await supabase
            .from("inventory_transfers")
            .insert(transferInsert)
            .execute()

        // Insert items
        struct ItemInsert: Encodable {
            let transfer_id: String
            let product_id: String
            let quantity: Double
        }

        for item in items {
            let itemInsert = ItemInsert(
                transfer_id: transferId.uuidString,
                product_id: item.productId.uuidString,
                quantity: item.quantity
            )
            try await supabase
                .from("inventory_transfer_items")
                .insert(itemInsert)
                .execute()
        }

        print("✅ Transfer created: \(transferNumber) with \(items.count) items")

        // Return the transfer
        return InventoryTransfer(
            id: transferId,
            storeId: storeId,
            transferNumber: transferNumber,
            sourceLocationId: sourceLocationId,
            destinationLocationId: destinationLocationId,
            status: .inTransit,
            notes: notes,
            trackingNumber: nil,
            shippedAt: Date(),
            receivedAt: nil,
            cancelledAt: nil,
            createdAt: Date(),
            updatedAt: Date(),
            createdByUserId: userId,
            approvedByUserId: nil,
            receivedByUserId: nil,
            cancelledByUserId: nil,
            sourceLocationName: nil,
            destinationLocationName: nil,
            items: nil,
            itemCount: items.count,
            totalQuantity: items.reduce(0) { $0 + $1.quantity }
        )
    }

    // MARK: - Lookup Transfer

    /// Lookup a transfer by QR code (P prefix)
    func lookupTransfer(qrCode: String, storeId: UUID) async throws -> TransferLookupResult {
        print("📦 Looking up transfer: \(qrCode)")

        // Extract transfer ID from QR (P + UUID)
        let transferIdString = String(qrCode.dropFirst()) // Remove P prefix
        guard let transferId = UUID(uuidString: transferIdString) else {
            return TransferLookupResult(success: false, found: false, transfer: nil, items: nil, error: "Invalid transfer QR")
        }

        // Fetch transfer with location names
        let response = try await supabase
            .from("inventory_transfers")
            .select("""
                *,
                source:locations!inventory_transfers_source_location_id_fkey(name),
                destination:locations!inventory_transfers_destination_location_id_fkey(name)
            """)
            .eq("id", value: transferId.uuidString)
            .eq("store_id", value: storeId.uuidString)
            .single()
            .execute()

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

        var transfer = try decoder.decode(InventoryTransfer.self, from: response.data)

        // Fetch items with product info
        let itemsResponse = try await supabase
            .from("inventory_transfer_items")
            .select("""
                *,
                product:products(name, sku, featured_image)
            """)
            .eq("transfer_id", value: transferId.uuidString)
            .execute()

        let items = try decoder.decode([InventoryTransferItem].self, from: itemsResponse.data)
        transfer.items = items

        print("✅ Found transfer \(transfer.transferNumber) with \(items.count) items")

        return TransferLookupResult(
            success: true,
            found: true,
            transfer: transfer,
            items: items,
            error: nil
        )
    }

    // MARK: - Receive Transfer

    /// Receive a transfer package (mark as completed, update inventory)
    func receiveTransfer(
        transferId: UUID,
        storeId: UUID,
        locationId: UUID,
        userId: UUID?,
        itemConditions: [UUID: ItemCondition]? = nil
    ) async throws -> Bool {
        print("📦 Receiving transfer: \(transferId)")

        let now = ISO8601DateFormatter().string(from: Date())

        // 1. Get transfer details including source/destination
        let transferResponse = try await supabase
            .from("inventory_transfers")
            .select("id, source_location_id, destination_location_id, store_id")
            .eq("id", value: transferId.uuidString)
            .single()
            .execute()

        let transfer = try JSONDecoder().decode(ReceiveTransferInfo.self, from: transferResponse.data)
        print("📦 Transfer: \(transfer.source_location_id) → \(transfer.destination_location_id)")

        // 2. Get transfer items with product info and qr_code_id
        let itemsResponse = try await supabase
            .from("inventory_transfer_items")
            .select("id, product_id, quantity, qr_code_id")
            .eq("transfer_id", value: transferId.uuidString)
            .execute()

        let items = try JSONDecoder().decode([ReceiveTransferItem].self, from: itemsResponse.data)
        print("📦 Processing \(items.count) items")

        // 3. For each item, update inventory (deduct from source, add to destination)
        for item in items {
            try await processTransferItem(
                item: item,
                transfer: transfer,
                transferId: transferId,
                userId: userId,
                itemConditions: itemConditions,
                now: now
            )
        }

        // 4. Mark transfer as completed
        struct TransferUpdate: Encodable {
            let status: String
            let received_at: String
            let received_by_user_id: String?
            let updated_at: String
        }

        let update = TransferUpdate(
            status: "completed",
            received_at: now,
            received_by_user_id: userId?.uuidString,
            updated_at: now
        )

        try await supabase
            .from("inventory_transfers")
            .update(update)
            .eq("id", value: transferId.uuidString)
            .execute()

        print("✅ Transfer received with \(items.count) items - inventory updated!")
        return true
    }

    // MARK: - Private Helpers

    private func processTransferItem(
        item: ReceiveTransferItem,
        transfer: ReceiveTransferInfo,
        transferId: UUID,
        userId: UUID?,
        itemConditions: [UUID: ItemCondition]?,
        now: String
    ) async throws {
        print("📦 Processing item: product=\(item.product_id), qty=\(item.quantity)")

        // For QR-based transfers, skip inventory table updates
        // The QR code itself tracks location - no need to modify inventory table
        if item.qr_code_id != nil {
            print("📦 QR-based transfer - skipping inventory table updates (QR code is source of truth)")

            // Still update the transfer item's received_quantity
            struct ItemUpdate: Encodable {
                let received_quantity: Double
                let updated_at: String
            }
            try await supabase
                .from("inventory_transfer_items")
                .update(ItemUpdate(received_quantity: item.quantity, updated_at: now))
                .eq("id", value: item.id.uuidString)
                .execute()
            print("📦 Updated transfer item received_quantity: \(item.quantity)")

            return
        }

        // Process source inventory deduction
        try await deductFromSourceInventory(
            item: item,
            transfer: transfer,
            transferId: transferId,
            userId: userId,
            now: now
        )

        // Process destination inventory addition
        try await addToDestinationInventory(
            item: item,
            transfer: transfer,
            transferId: transferId,
            userId: userId,
            now: now
        )

        // Update any linked QR code
        if let qrCodeId = item.qr_code_id {
            try await updateQRCodeLocation(
                qrCodeId: qrCodeId,
                destinationLocationId: transfer.destination_location_id,
                now: now
            )
        }

        // Update item received_quantity and condition
        try await updateTransferItemReceived(
            itemId: item.id,
            quantity: item.quantity,
            itemConditions: itemConditions,
            now: now
        )
    }

    private func deductFromSourceInventory(
        item: ReceiveTransferItem,
        transfer: ReceiveTransferInfo,
        transferId: UUID,
        userId: UUID?,
        now: String
    ) async throws {
        struct InvRecord: Decodable {
            let id: UUID
            let quantity: Double
        }

        let sourceInvResponse = try await supabase
            .from("inventory")
            .select("id, quantity")
            .eq("product_id", value: item.product_id.uuidString)
            .eq("location_id", value: transfer.source_location_id.uuidString)
            .limit(1)
            .execute()

        let sourceRecords = try JSONDecoder().decode([InvRecord].self, from: sourceInvResponse.data)

        guard let sourceInv = sourceRecords.first else { return }

        let newSourceQty = max(0, sourceInv.quantity - item.quantity)

        struct InvUpdate: Encodable {
            let quantity: Double
            let updated_at: String
        }

        try await supabase
            .from("inventory")
            .update(InvUpdate(quantity: newSourceQty, updated_at: now))
            .eq("id", value: sourceInv.id.uuidString)
            .execute()

        print("📦 Source inventory updated: \(sourceInv.quantity) → \(newSourceQty)")

        // Log transfer_out transaction
        try await logInventoryTransaction(
            storeId: transfer.store_id,
            locationId: transfer.source_location_id,
            productId: item.product_id,
            inventoryId: sourceInv.id,
            type: "transfer_out",
            quantityBefore: sourceInv.quantity,
            quantityChange: -item.quantity,
            quantityAfter: newSourceQty,
            reason: "Transfer to destination",
            referenceId: transferId,
            userId: userId
        )
    }

    private func addToDestinationInventory(
        item: ReceiveTransferItem,
        transfer: ReceiveTransferInfo,
        transferId: UUID,
        userId: UUID?,
        now: String
    ) async throws {
        struct InvRecord: Decodable {
            let id: UUID
            let quantity: Double
        }

        let destInvResponse = try await supabase
            .from("inventory")
            .select("id, quantity")
            .eq("product_id", value: item.product_id.uuidString)
            .eq("location_id", value: transfer.destination_location_id.uuidString)
            .limit(1)
            .execute()

        let destRecords = try JSONDecoder().decode([InvRecord].self, from: destInvResponse.data)

        if let destInv = destRecords.first {
            // Update existing record
            let newDestQty = destInv.quantity + item.quantity

            struct InvUpdate: Encodable {
                let quantity: Double
                let updated_at: String
            }

            try await supabase
                .from("inventory")
                .update(InvUpdate(quantity: newDestQty, updated_at: now))
                .eq("id", value: destInv.id.uuidString)
                .execute()

            print("📦 Destination inventory updated: \(destInv.quantity) → \(newDestQty)")

            // Log transfer_in transaction
            try await logInventoryTransaction(
                storeId: transfer.store_id,
                locationId: transfer.destination_location_id,
                productId: item.product_id,
                inventoryId: destInv.id,
                type: "transfer_in",
                quantityBefore: destInv.quantity,
                quantityChange: item.quantity,
                quantityAfter: newDestQty,
                reason: "Transfer from source",
                referenceId: transferId,
                userId: userId
            )
        } else {
            // Create new inventory record at destination
            struct InvInsert: Encodable {
                let store_id: String
                let location_id: String
                let product_id: String
                let quantity: Double
            }

            let newInv = InvInsert(
                store_id: transfer.store_id.uuidString,
                location_id: transfer.destination_location_id.uuidString,
                product_id: item.product_id.uuidString,
                quantity: item.quantity
            )

            let insertResponse = try await supabase
                .from("inventory")
                .insert(newInv)
                .select("id")
                .single()
                .execute()

            struct InsertedInv: Decodable {
                let id: UUID
            }

            let insertedInv = try JSONDecoder().decode(InsertedInv.self, from: insertResponse.data)

            print("📦 Created new inventory record at destination: \(insertedInv.id)")

            // Log transfer_in transaction for new record
            try await logInventoryTransaction(
                storeId: transfer.store_id,
                locationId: transfer.destination_location_id,
                productId: item.product_id,
                inventoryId: insertedInv.id,
                type: "transfer_in",
                quantityBefore: 0,
                quantityChange: item.quantity,
                quantityAfter: item.quantity,
                reason: "Transfer from source (new location)",
                referenceId: transferId,
                userId: userId
            )
        }
    }

    private func logInventoryTransaction(
        storeId: UUID,
        locationId: UUID,
        productId: UUID,
        inventoryId: UUID,
        type: String,
        quantityBefore: Double,
        quantityChange: Double,
        quantityAfter: Double,
        reason: String,
        referenceId: UUID,
        userId: UUID?
    ) async throws {
        struct TransactionInsert: Encodable {
            let store_id: String
            let location_id: String
            let product_id: String
            let inventory_id: String
            let transaction_type: String
            let quantity_before: Double
            let quantity_change: Double
            let quantity_after: Double
            let reason: String
            let reference_type: String
            let reference_id: String
            let performed_by_user_id: String?
        }

        let txn = TransactionInsert(
            store_id: storeId.uuidString,
            location_id: locationId.uuidString,
            product_id: productId.uuidString,
            inventory_id: inventoryId.uuidString,
            transaction_type: type,
            quantity_before: quantityBefore,
            quantity_change: quantityChange,
            quantity_after: quantityAfter,
            reason: reason,
            reference_type: "inventory_transfer",
            reference_id: referenceId.uuidString,
            performed_by_user_id: userId?.uuidString
        )

        try await supabase
            .from("inventory_transactions")
            .insert(txn)
            .execute()

        print("📦 Logged \(type) transaction")
    }

    private func updateQRCodeLocation(
        qrCodeId: UUID,
        destinationLocationId: UUID,
        now: String
    ) async throws {
        struct QRUpdate: Encodable {
            let status: String
            let current_transfer_id: String?
            let location_id: String
            let updated_at: String
        }

        try await supabase
            .from("qr_codes")
            .update(QRUpdate(
                status: "available",
                current_transfer_id: nil,
                location_id: destinationLocationId.uuidString,
                updated_at: now
            ))
            .eq("id", value: qrCodeId.uuidString)
            .execute()

        print("📦 Updated QR code \(qrCodeId) - status=available, location=destination")
    }

    private func updateTransferItemReceived(
        itemId: UUID,
        quantity: Double,
        itemConditions: [UUID: ItemCondition]?,
        now: String
    ) async throws {
        struct ItemUpdate: Encodable {
            let received_quantity: Double
            let updated_at: String
            var condition: String?
        }

        var itemUpdate = ItemUpdate(received_quantity: quantity, updated_at: now)
        if let conditions = itemConditions, let condition = conditions[itemId] {
            itemUpdate.condition = condition.rawValue
        }

        try await supabase
            .from("inventory_transfer_items")
            .update(itemUpdate)
            .eq("id", value: itemId.uuidString)
            .execute()
    }
}
