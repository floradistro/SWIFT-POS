//
//  SheetContainer.swift
//  Whale
//
//  Resolves SheetType to actual SwiftUI views.
//  Single place to configure all sheet presentations.
//

import SwiftUI
import Supabase
import os.log

struct SheetContainer: View {
    let sheetType: SheetType
    @EnvironmentObject private var session: SessionObserver
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        sheetContent
            .presentationDetents(detentsForType)
            .presentationDragIndicator(.visible)
            .tint(Design.Colors.Semantic.accent)
            .id(theme.themeVersion)
    }

    // MARK: - Sheet Content

    @ViewBuilder
    private var sheetContent: some View {
        switch sheetType {

        // MARK: Location & Store
        case .locationPicker:
            LocationPickerSheet()

        case .storePicker:
            StorePickerSheet()

        case .registerPicker:
            RegisterPickerSheet()

        // MARK: Customer
        case .customerSearch(let storeId):
            ManualCustomerEntrySheet(
                storeId: storeId,
                onCustomerCreated: { customer in
                    NotificationCenter.default.post(
                        name: .sheetCustomerSelected,
                        object: customer
                    )
                    SheetCoordinator.shared.dismiss()
                },
                onCancel: {
                    SheetCoordinator.shared.dismiss()
                }
            )

        case .idScanner(let storeId):
            IDScannerView(
                storeId: storeId,
                onCustomerSelected: { customer in
                    NotificationCenter.default.post(
                        name: .sheetCustomerSelected,
                        object: customer
                    )
                    SheetCoordinator.shared.dismiss()
                },
                onDismiss: {
                    SheetCoordinator.shared.dismiss()
                }
            )

        case .customerScanned(let storeId, let scannedID, let matches):
            ManualCustomerEntrySheet(
                storeId: storeId,
                onCustomerCreated: { customer in
                    NotificationCenter.default.post(
                        name: .sheetCustomerSelected,
                        object: customer
                    )
                    SheetCoordinator.shared.dismiss()
                },
                onCancel: {
                    SheetCoordinator.shared.dismiss()
                },
                scannedID: scannedID,
                scannedMatches: matches
            )
            .onAppear {
                Log.ui.debug("SheetContainer creating customerScanned sheet - scannedID: \(scannedID.fullDisplayName), matches: \(matches.count)")
            }

        // MARK: Orders
        case .orderDetail(let order):
            OrderDetailSheet(order: order)

        case .orderFilters:
            AdvancedOrderFiltersSheet(
                store: OrderStore.shared,
                isPresented: .constant(true)
            )

        case .invoiceDetail(let order):
            InvoiceDetailSheetWrapper(order: order)

        // MARK: Cart & Checkout
        case .checkout(let totals, let sessionInfo):
            CheckoutSheetWrapper(totals: totals, sessionInfo: sessionInfo)

        case .tierSelector(let product, let storeId, let locationId):
            TierSelectorSheetWrapper(product: product, storeId: storeId, locationId: locationId)

        // MARK: Cash Management
        case .safeDrop(let posSession):
            SafeDropSheet(posSession: posSession)

        case .openCashDrawer:
            OpenCashDrawerSheet()

        // MARK: Inventory & Transfer
        case .createTransfer(let storeId, let sourceLocation):
            CreateTransferSheet(
                storeId: storeId,
                sourceLocation: sourceLocation,
                onDismiss: { SheetCoordinator.shared.dismiss() },
                onTransferCreated: { _ in SheetCoordinator.shared.dismiss() }
            )

        case .packageReceive(let transfer, let items, let storeId):
            PackageReceiveSheet(
                transfer: transfer,
                items: items,
                storeId: storeId,
                onDismiss: { SheetCoordinator.shared.dismiss() }
            )

        case .inventoryUnitScan(let unit, let lookupResult, let storeId):
            InventoryUnitScanSheet(
                unit: unit,
                lookupResult: lookupResult,
                storeId: storeId,
                onDismiss: { SheetCoordinator.shared.dismiss() },
                onAction: { _ in }
            )

        case .qrCodeScan(let qrCode, let storeId):
            QRCodeScanSheet(
                qrCode: qrCode,
                storeId: storeId,
                onDismiss: { SheetCoordinator.shared.dismiss() }
            )

        // MARK: Product Detail
        case .productDetail(let product):
            ProductDetailSheetWrapper(product: product)

        // MARK: Labels & Printing
        case .labelTemplate(let products):
            LabelTemplateSheetWrapper(products: products)

        case .orderLabelTemplate(let orders):
            OrderLabelTemplateSheetWrapper(orders: orders)

        case .bulkProductLabels(let products):
            BulkProductLabelSheet(products: products)

        case .printerSettings:
            PrinterSettingsSheet()

        case .posSettings:
            POSSettingsSheet()

        case .appearance:
            ThemeSettingsView()

        case .errorAlert(let title, let message):
            ErrorAlertSheet(title: title, message: message)
        }
    }

    // MARK: - Detents

    private var detentsForType: Set<PresentationDetent> {
        let isCompact = UIScreen.main.bounds.width < 500  // iPhone portrait

        switch sheetType.detents {
        case .small:
            return [.fraction(0.25)]
        case .medium:
            return [.medium]
        case .mediumLarge:
            return [.medium, .large]
        case .large:
            // On iPhone, also allow medium to avoid empty space
            return isCompact ? [.medium, .large] : [.large]
        case .fitted:
            // Content-fitted - on iPhone use smaller sizes first
            return isCompact ? [.height(350), .medium, .large] : [.medium, .large]
        case .full:
            return [.large]
        }
    }
}

// MARK: - Sheet Notifications

extension Notification.Name {
    static let sheetCustomerSelected = Notification.Name("sheetCustomerSelected")
    static let sheetOrderCompleted = Notification.Name("sheetOrderCompleted")
    static let sheetDismissed = Notification.Name("sheetDismissed")
}

// Note: All wrapper views moved to SheetWrappers.swift
