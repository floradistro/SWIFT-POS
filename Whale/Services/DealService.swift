//
//  DealService.swift
//  Whale
//
//  Service for fetching and managing discount deals/campaigns.
//  All filtering now happens server-side via RPC functions.
//

import Foundation
import Supabase
import Combine
import os.log

// MARK: - Deal Service

enum DealService {

    // MARK: - Fetch Deals (Server-side filtered)

    /// Get all active deals for a store that apply to POS
    /// Filtering is done server-side via get_active_deals RPC
    static func getActivePOSDeals(storeId: UUID) async throws -> [Deal] {
        Log.deals.info("Fetching active POS deals for store: \(storeId)")

        let deals: [Deal] = try await supabase
            .rpc("get_active_deals", params: [
                "p_store_id": storeId.uuidString,
                "p_channel": "in_store"
            ])
            .execute()
            .value

        Log.deals.info("Found \(deals.count) active POS deals")
        return deals
    }

    /// Get auto-apply deals (no code required, automatic application)
    /// Server-side filtered by application_method and location
    static func getAutoApplyDeals(storeId: UUID, locationId: UUID?) async throws -> [Deal] {
        var params: [String: String] = [
            "p_store_id": storeId.uuidString,
            "p_channel": "in_store",
            "p_application_method": "auto"
        ]
        if let locationId = locationId {
            params["p_location_id"] = locationId.uuidString
        }

        let deals: [Deal] = try await supabase
            .rpc("get_active_deals", params: params)
            .execute()
            .value

        return deals
    }

    /// Get manual deals (selectable by staff)
    /// Server-side filtered by application_method and location
    static func getManualDeals(storeId: UUID, locationId: UUID?) async throws -> [Deal] {
        var params: [String: String] = [
            "p_store_id": storeId.uuidString,
            "p_channel": "in_store",
            "p_application_method": "manual"
        ]
        if let locationId = locationId {
            params["p_location_id"] = locationId.uuidString
        }

        let deals: [Deal] = try await supabase
            .rpc("get_active_deals", params: params)
            .execute()
            .value

        return deals
    }

    /// Validate and get deal by coupon code (server-side validation)
    static func getDealByCode(_ code: String, storeId: UUID) async throws -> Deal? {
        struct CouponResponse: Codable {
            let valid: Bool
            let error: String?
            let deal: Deal?
        }

        let response: CouponResponse = try await supabase
            .rpc("validate_coupon_code", params: [
                "p_store_id": storeId.uuidString,
                "p_code": code
            ])
            .execute()
            .value

        guard response.valid, let deal = response.deal else {
            return nil
        }

        return deal
    }

    // MARK: - Discount Calculation (Server-side)

    /// Calculate discount for an order subtotal (server-side)
    /// - Parameters:
    ///   - dealId: The deal UUID
    ///   - subtotal: Order subtotal amount
    ///   - channel: Sales channel ("in_store", "online", or "both"). Defaults to "in_store" for POS.
    static func calculateDiscount(dealId: UUID, subtotal: Decimal, channel: String = "in_store") async throws -> Decimal {
        struct DiscountResponse: Codable {
            let discount: Decimal
            let error: String?
        }

        let response: DiscountResponse = try await supabase
            .rpc("calculate_order_discount", params: [
                "p_deal_id": dealId.uuidString,
                "p_subtotal": String(describing: subtotal),
                "p_channel": channel
            ])
            .execute()
            .value

        return response.discount
    }

    // MARK: - Affiliate Code Validation

    /// Validate an affiliate referral code and get discount info
    static func validateAffiliateCode(_ code: String, storeId: UUID) async throws -> AffiliateCodeResult? {
        let result: [AffiliateCodeResult] = try await supabase
            .rpc("validate_affiliate_code", params: [
                "p_store_id": storeId.uuidString,
                "p_code": code.uppercased()
            ])
            .execute()
            .value

        return result.first
    }

    /// Calculate affiliate discount amount
    static func calculateAffiliateDiscount(subtotal: Decimal, rate: Decimal, type: String) -> Decimal {
        if type == "percentage" {
            return (subtotal * rate / 100).rounded(scale: 2)
        } else {
            return min(rate, subtotal)
        }
    }

    // MARK: - Record Usage

    /// Record that a deal was used in an order
    static func recordDealUsage(
        dealId: UUID,
        orderId: UUID,
        customerId: UUID?,
        discountAmount: Decimal
    ) async throws {
        Log.deals.info("Recording deal usage: \(dealId) for order: \(orderId)")

        // Insert usage record
        var usageRecord: [String: String] = [
            "deal_id": dealId.uuidString,
            "order_id": orderId.uuidString,
            "discount_amount": String(NSDecimalNumber(decimal: discountAmount).doubleValue)
        ]
        if let customerId = customerId {
            usageRecord["customer_id"] = customerId.uuidString
        }

        try await supabase
            .from("deal_usage")
            .insert(usageRecord)
            .execute()

        // Increment usage counter via RPC
        try await supabase
            .rpc("increment_deal_usage", params: ["p_deal_id": dealId.uuidString])
            .execute()

        Log.deals.info("Deal usage recorded successfully")
    }
}

// MARK: - Deal Store (Observable)

@MainActor
final class DealStore: ObservableObject {
    static let shared = DealStore()

    @Published private(set) var availableDeals: [Deal] = []
    @Published private(set) var couponDeals: [Deal] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?

    @Published var selectedDealId: UUID?

    private init() {}

    /// Currently selected deal
    var selectedDeal: Deal? {
        guard let id = selectedDealId else { return nil }
        return availableDeals.first { $0.id == id } ?? couponDeals.first { $0.id == id }
    }

    /// Load available deals for checkout (manual + coupon code deals)
    func loadDeals(storeId: UUID, locationId: UUID?) async {
        isLoading = true
        error = nil
        availableDeals = []
        couponDeals = []
        selectedDealId = nil

        do {
            async let manualDeals = DealService.getManualDeals(storeId: storeId, locationId: locationId)
            async let codeDeals = DealService.getActivePOSDeals(storeId: storeId)

            let manual = try await manualDeals
            let all = try await codeDeals

            availableDeals = manual
            couponDeals = all.filter { $0.applicationMethod == .code && $0.couponCode != nil }
            isLoading = false
            Log.deals.info("Loaded \(manual.count) manual deals, \(couponDeals.count) coupon deals")
        } catch {
            self.error = error.localizedDescription
            isLoading = false
            Log.deals.error("Failed to load deals: \(error)")
        }
    }

    /// Select a deal
    func selectDeal(_ deal: Deal) {
        if selectedDealId == deal.id {
            selectedDealId = nil  // Toggle off
        } else {
            selectedDealId = deal.id
        }
        Haptics.light()
    }

    /// Clear selection
    func clearSelection() {
        selectedDealId = nil
    }

    /// Calculate discount for checkout - ALL logic is server-side
    /// Returns 0 on network error (no fallback calculation)
    func calculateDiscount(for subtotal: Decimal) async -> Decimal {
        guard let deal = selectedDeal else { return 0 }
        do {
            return try await DealService.calculateDiscount(dealId: deal.id, subtotal: subtotal)
        } catch {
            Log.deals.error("Failed to calculate discount server-side: \(error)")
            // NO FALLBACK - return 0 if backend is unavailable
            // This ensures we never process discounts without server validation
            return 0
        }
    }

    /// Calculate discount for UI display - uses PaymentCalculatorService
    /// Backend-driven: ALL discount math happens server-side
    func calculateDisplayDiscount(for subtotal: Decimal) async -> Decimal {
        guard let deal = selectedDeal else { return 0 }
        do {
            let discountType: DiscountType
            switch deal.discountType {
            case .percentage: discountType = .percentage
            case .fixed: discountType = .fixed
            case .bogo: discountType = .bogo
            }
            return try await PaymentCalculatorService.shared.calculateDiscount(
                subtotal: subtotal,
                discountType: discountType,
                discountValue: deal.discountValue
            )
        } catch {
            Log.deals.error("Failed to calculate display discount: \(error)")
            return 0
        }
    }
}
