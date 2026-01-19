//
//  SheetType.swift
//  Whale
//
//  Unified sheet type system. All sheets in the app are defined here.
//  This enables type-safe, centralized sheet management.
//

import Foundation
import SwiftUI

/// All possible sheet types in the app.
/// Each case carries the data needed to present that sheet.
enum SheetType: Identifiable, Equatable {
    // MARK: - Location & Store
    case locationPicker
    case registerPicker

    // MARK: - Customer
    case customerSearch(storeId: UUID)
    case customerDetail(customer: Customer)
    case idScanner(storeId: UUID)
    case customerScanned(storeId: UUID, scannedID: ScannedID, matches: [CustomerMatch])

    // MARK: - Orders
    case orderDetail(order: Order)
    case orderFilters
    case invoiceDetail(order: Order)

    // MARK: - Cart & Checkout
    case checkout(totals: CheckoutTotals, sessionInfo: SessionInfo)
    case tierSelector(product: Product, storeId: UUID, locationId: UUID)

    // MARK: - Cash Management
    case safeDrop(session: POSSession)
    case openCashDrawer

    // MARK: - Inventory & Transfer
    case createTransfer(storeId: UUID, sourceLocation: Location)
    case packageReceive(transfer: InventoryTransfer, items: [InventoryTransferItem], storeId: UUID)
    case inventoryUnitScan(unit: InventoryUnit, lookupResult: LookupResult, storeId: UUID)
    case qrCodeScan(qrCode: ScannedQRCode, storeId: UUID)

    // MARK: - Labels & Printing
    case labelTemplate(products: [Product])
    case orderLabelTemplate(orders: [Order])
    case bulkProductLabels(products: [Product])
    case printerSettings

    // MARK: - POS Settings
    case posSettings

    // MARK: - Identifiable

    var id: String {
        switch self {
        case .locationPicker: return "locationPicker"
        case .registerPicker: return "registerPicker"
        case .customerSearch: return "customerSearch"
        case .customerDetail(let c): return "customerDetail-\(c.id)"
        case .idScanner: return "idScanner"
        case .customerScanned(_, let id, _): return "customerScanned-\(id.licenseNumber ?? "unknown")"
        case .orderDetail(let o): return "orderDetail-\(o.id)"
        case .orderFilters: return "orderFilters"
        case .invoiceDetail(let o): return "invoiceDetail-\(o.id)"
        case .checkout: return "checkout"
        case .tierSelector(let p, _, _): return "tierSelector-\(p.id)"
        case .safeDrop: return "safeDrop"
        case .openCashDrawer: return "openCashDrawer"
        case .createTransfer(_, let loc): return "createTransfer-\(loc.id)"
        case .packageReceive(let t, _, _): return "packageReceive-\(t.id)"
        case .inventoryUnitScan(let u, _, _): return "inventoryUnitScan-\(u.id)"
        case .qrCodeScan: return "qrCodeScan"
        case .labelTemplate: return "labelTemplate"
        case .orderLabelTemplate: return "orderLabelTemplate"
        case .bulkProductLabels: return "bulkProductLabels"
        case .printerSettings: return "printerSettings"
        case .posSettings: return "posSettings"
        }
    }

    // MARK: - Presentation Style

    /// Whether this sheet should be presented as fullScreenCover
    var isFullScreen: Bool {
        switch self {
        case .idScanner, .bulkProductLabels:
            return true
        default:
            return false
        }
    }

    /// Preferred detents for this sheet type
    var detents: SheetDetents {
        switch self {
        case .locationPicker, .registerPicker:
            return .mediumLarge
        case .customerSearch, .customerDetail:
            return .large
        case .customerScanned:
            return .mediumLarge
        case .orderDetail, .invoiceDetail:
            return .large
        case .checkout:
            return .large
        case .tierSelector:
            return .mediumLarge
        case .safeDrop, .openCashDrawer:
            return .medium
        case .orderFilters:
            return .medium
        case .createTransfer(_, _):
            return .large
        case .labelTemplate, .orderLabelTemplate:
            return .mediumLarge
        case .printerSettings:
            return .medium
        case .posSettings:
            return .large
        default:
            return .large
        }
    }

    // MARK: - Equatable

    static func == (lhs: SheetType, rhs: SheetType) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Sheet Detents

enum SheetDetents {
    case small
    case medium
    case mediumLarge
    case large
    case full
}

// MARK: - SwiftUI Detents Extension

extension View {
    /// Apply presentation detents based on SheetDetents enum
    @ViewBuilder
    func applyDetents(_ detents: SheetDetents) -> some View {
        switch detents {
        case .small:
            self.presentationDetents([.fraction(0.3)])
                .presentationDragIndicator(.visible)
        case .medium:
            self.presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        case .mediumLarge:
            self.presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        case .large:
            self.presentationDetents([.large])
                .presentationDragIndicator(.visible)
        case .full:
            self.presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .interactiveDismissDisabled()
        }
    }
}

// Note: SessionInfo is defined in PaymentTypes.swift
