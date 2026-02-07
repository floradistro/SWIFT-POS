//
//  CustomerStore.swift
//  Whale
//
//  Customer data store - mirrors OrderStore pattern.
//  Handles customer list, filtering, and search.
//

import SwiftUI
import Combine
import Supabase
import os.log

@MainActor
final class CustomerStore: ObservableObject {
    static let shared = CustomerStore()

    // MARK: - Published State

    @Published private(set) var customers: [Customer] = []
    @Published private(set) var isLoading = false
    @Published var searchText = ""

    // Filters
    @Published var selectedLoyaltyTier: String?
    @Published var showVerifiedOnly = false
    @Published var sortOrder: SortOrder = .nameAsc

    // MARK: - Sort Options

    enum SortOrder: String, CaseIterable {
        case nameAsc = "Name A-Z"
        case nameDesc = "Name Z-A"
        case spentDesc = "Highest Spent"
        case spentAsc = "Lowest Spent"
        case recentFirst = "Most Recent"
        case oldestFirst = "Oldest First"
    }

    // MARK: - Computed Properties

    var filteredCustomers: [Customer] {
        var result = customers

        // Search filter
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { customer in
                customer.displayName.lowercased().contains(query) ||
                customer.email?.lowercased().contains(query) == true ||
                customer.phone?.contains(query) == true ||
                customer.formattedPhone?.contains(query) == true
            }
        }

        // Loyalty tier filter
        if let tier = selectedLoyaltyTier {
            result = result.filter { $0.loyaltyTier?.lowercased() == tier.lowercased() }
        }

        // Verified only filter
        if showVerifiedOnly {
            result = result.filter { $0.idVerified == true }
        }

        // Sort
        switch sortOrder {
        case .nameAsc:
            result.sort { ($0.lastName ?? "") < ($1.lastName ?? "") }
        case .nameDesc:
            result.sort { ($0.lastName ?? "") > ($1.lastName ?? "") }
        case .spentDesc:
            result.sort { ($0.totalSpent ?? 0) > ($1.totalSpent ?? 0) }
        case .spentAsc:
            result.sort { ($0.totalSpent ?? 0) < ($1.totalSpent ?? 0) }
        case .recentFirst:
            result.sort { $0.createdAt > $1.createdAt }
        case .oldestFirst:
            result.sort { $0.createdAt < $1.createdAt }
        }

        return result
    }

    var hasActiveFilters: Bool {
        selectedLoyaltyTier != nil || showVerifiedOnly || !searchText.isEmpty
    }

    var activeFilterCount: Int {
        var count = 0
        if selectedLoyaltyTier != nil { count += 1 }
        if showVerifiedOnly { count += 1 }
        return count
    }

    var loyaltyTiers: [String] {
        let tiers = Set(customers.compactMap { $0.loyaltyTier?.capitalized })
        return Array(tiers).sorted()
    }

    var customerCounts: [String: Int] {
        var counts: [String: Int] = [:]
        for tier in loyaltyTiers {
            counts[tier] = customers.filter { $0.loyaltyTier?.capitalized == tier }.count
        }
        return counts
    }

    var verifiedCount: Int {
        customers.filter { $0.idVerified == true }.count
    }

    // MARK: - Store ID

    private var storeId: UUID?

    // MARK: - Init

    private init() {}

    // MARK: - Data Loading

    func setStore(_ storeId: UUID) {
        guard self.storeId != storeId else { return }
        self.storeId = storeId
        Task { await loadCustomers() }
    }

    func loadCustomers() async {
        guard let storeId = storeId else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let response: [Customer] = try await supabase
                .from("v_store_customers")
                .select()
                .eq("store_id", value: storeId.uuidString)
                .eq("is_active", value: true)
                .order("last_name", ascending: true)
                .execute()
                .value

            customers = response
        } catch {
            Log.network.error("Failed to load customers: \(error)")
        }
    }

    func refresh() async {
        await loadCustomers()
    }

    // MARK: - Filters

    func clearFilters() {
        searchText = ""
        selectedLoyaltyTier = nil
        showVerifiedOnly = false
    }

    // MARK: - Customer Operations

    func refreshCustomer(customerId: UUID) async {
        guard let updated = await CustomerService.fetchCustomer(id: customerId) else { return }

        if let index = customers.firstIndex(where: { $0.id == customerId }) {
            customers[index] = updated
        }
    }
}
