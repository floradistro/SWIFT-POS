//
//  MultiSelectManager.swift
//  Whale
//
//  Manages multi-select mode for bulk operations.
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class MultiSelectManager: ObservableObject {
    static let shared = MultiSelectManager()

    @Published var isMultiSelectMode = false
    @Published var selectedProductIds: Set<UUID> = []
    @Published var selectedOrderIds: Set<UUID> = []

    private init() {}

    var selectedCount: Int {
        selectedProductIds.count + selectedOrderIds.count
    }

    var hasSelection: Bool {
        !selectedProductIds.isEmpty || !selectedOrderIds.isEmpty
    }

    var selectedProductCount: Int {
        selectedProductIds.count
    }

    var isProductSelectMode: Bool {
        !selectedProductIds.isEmpty
    }

    func isProductSelected(_ productId: UUID) -> Bool {
        selectedProductIds.contains(productId)
    }

    func isSelected(_ id: UUID) -> Bool {
        selectedProductIds.contains(id) || selectedOrderIds.contains(id)
    }

    func toggleMultiSelect() {
        isMultiSelectMode.toggle()
        if !isMultiSelectMode {
            selectedProductIds.removeAll()
            selectedOrderIds.removeAll()
        }
    }

    func toggleSelection(_ id: UUID) {
        // Check if we're in order mode (has order selections) or product mode
        if !selectedOrderIds.isEmpty || selectedProductIds.isEmpty {
            // Order selection mode - toggle in order set
            if selectedOrderIds.contains(id) {
                selectedOrderIds.remove(id)
            } else {
                selectedOrderIds.insert(id)
            }
        } else {
            // Product selection mode - toggle in product set
            if selectedProductIds.contains(id) {
                selectedProductIds.remove(id)
            } else {
                selectedProductIds.insert(id)
            }
        }
    }

    func toggleProductSelection(_ productId: UUID) {
        if selectedProductIds.contains(productId) {
            selectedProductIds.remove(productId)
        } else {
            selectedProductIds.insert(productId)
        }
    }

    func toggleOrderSelection(_ orderId: UUID) {
        if selectedOrderIds.contains(orderId) {
            selectedOrderIds.remove(orderId)
        } else {
            selectedOrderIds.insert(orderId)
        }
    }

    func startProductMultiSelect(_ productId: UUID) {
        isMultiSelectMode = true
        selectedProductIds.insert(productId)
    }

    func startMultiSelect() {
        isMultiSelectMode = true
    }

    func startMultiSelect(with orderId: UUID) {
        isMultiSelectMode = true
        selectedOrderIds.insert(orderId)
    }

    func selectAll(_ productIds: [UUID]) {
        selectedProductIds = Set(productIds)
    }

    func clearSelection() {
        selectedProductIds.removeAll()
        selectedOrderIds.removeAll()
    }

    func exitMultiSelect() {
        isMultiSelectMode = false
        selectedProductIds.removeAll()
        selectedOrderIds.removeAll()
    }
}
