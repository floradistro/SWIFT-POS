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
    case storePicker
    case registerPicker

    // MARK: - Customer
    case customerSearch(storeId: UUID)
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

    // MARK: - Product
    case productDetail(product: Product)

    // MARK: - Labels & Printing
    case labelTemplate(products: [Product])
    case orderLabelTemplate(orders: [Order])
    case bulkProductLabels(products: [Product])
    case printerSettings

    // MARK: - POS Settings
    case posSettings
    case appearance

    // MARK: - Alerts & Errors
    case errorAlert(title: String, message: String)

    // MARK: - Identifiable

    var id: String {
        switch self {
        case .locationPicker: return "locationPicker"
        case .storePicker: return "storePicker"
        case .registerPicker: return "registerPicker"
        case .customerSearch: return "customerSearch"
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
        case .productDetail(let p): return "productDetail-\(p.id)"
        case .labelTemplate: return "labelTemplate"
        case .orderLabelTemplate: return "orderLabelTemplate"
        case .bulkProductLabels: return "bulkProductLabels"
        case .printerSettings: return "printerSettings"
        case .posSettings: return "posSettings"
        case .appearance: return "appearance"
        case .errorAlert(let title, _): return "errorAlert-\(title)"
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
        case .locationPicker, .storePicker, .registerPicker:
            return .mediumLarge
        case .customerSearch:
            return .large
        case .customerScanned:
            return .mediumLarge
        case .orderDetail, .invoiceDetail:
            return .large
        case .checkout:
            return .large
        case .tierSelector:
            return .mediumLarge
        case .productDetail:
            return .large
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
        case .appearance:
            return .large
        case .errorAlert:
            return .fitted  // Content-fitted for simple error messages
        case .idScanner, .bulkProductLabels:
            return .full  // Full screen
        case .packageReceive, .inventoryUnitScan, .qrCodeScan:
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
    case small           // ~30% height
    case medium          // ~50% height
    case mediumLarge     // Medium + Large options
    case large           // Full height
    case fitted          // Auto-size to content (ideal for simple sheets on mobile)
    case full            // Full height, non-dismissable
}

// MARK: - SwiftUI Detents Extension

extension View {
    /// Apply presentation detents based on SheetDetents enum
    /// Adapts to device size - on compact (iPhone), sheets fit content better
    @ViewBuilder
    func applyDetents(_ detents: SheetDetents) -> some View {
        let isCompact = UIScreen.main.bounds.width < 500  // iPhone portrait

        switch detents {
        case .small:
            self.presentationDetents([.fraction(0.3)])
                .presentationDragIndicator(.visible)
        case .medium:
            self.presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        case .mediumLarge:
            // On iPhone, start at medium; on iPad, offer both options
            self.presentationDetents(isCompact ? [.medium, .large] : [.medium, .large])
                .presentationDragIndicator(.visible)
        case .large:
            // On iPhone, allow medium as an option so content doesn't feel empty
            self.presentationDetents(isCompact ? [.medium, .large] : [.large])
                .presentationDragIndicator(.visible)
        case .fitted:
            // Content-fitted - on iPhone use height, on iPad use medium
            self.presentationDetents(isCompact ? [.height(400), .medium, .large] : [.medium, .large])
                .presentationDragIndicator(.visible)
        case .full:
            self.presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .interactiveDismissDisabled()
        }
    }
}

// Note: SessionInfo is defined in PaymentTypes.swift
