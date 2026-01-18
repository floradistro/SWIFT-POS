//  DockBulkActions.swift - Bulk actions for multi-select mode

import SwiftUI
import os.log

struct DockBulkActionsView: View {
    @ObservedObject var multiSelect: MultiSelectManager
    @ObservedObject var posStore: POSStore
    @ObservedObject var orderStore: OrderStore
    @EnvironmentObject private var session: SessionObserver

    @State private var showProductLabelSheet = false
    @State private var showOrderLabelSheet = false
    @State private var isPrintingProductLabels = false
    @State private var selectedProductsForLabels: [Product] = []

    var body: some View {
        VStack(spacing: 12) {
            header
            actionButtons
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fullScreenCover(isPresented: $showProductLabelSheet) {
            ProductLabelTemplateSheet(
                products: selectedProductsForLabels,
                store: session.store,
                location: session.selectedLocation,
                isPrinting: $isPrintingProductLabels,
                onDismiss: {
                    showProductLabelSheet = false
                    selectedProductsForLabels = []
                    multiSelect.exitMultiSelect()
                }
            )
            .presentationBackground(.clear)
        }
        .sheet(isPresented: $showOrderLabelSheet) {
            BulkOrderLabelSheet(
                orders: orderStore.orders.filter { multiSelect.isSelected($0.id) },
                onDismiss: {
                    showOrderLabelSheet = false
                    multiSelect.exitMultiSelect()
                }
            )
            .presentationDetents([.height(400)])
            .presentationDragIndicator(.visible)
        }
    }

    private var header: some View {
        HStack {
            Text("\(multiSelect.selectedCount) \(multiSelect.isProductSelectMode ? "products" : "orders")")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)

            Spacer()

            Button {
                Haptics.light()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    multiSelect.exitMultiSelect()
                }
            } label: {
                Text("Cancel")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    @ViewBuilder
    private var actionButtons: some View {
        if multiSelect.isProductSelectMode {
            productActions
        } else {
            orderActions
        }
    }

    private var productActions: some View {
        HStack(spacing: 10) {
            BulkActionButton(icon: "printer.fill", label: "Print", color: Design.Colors.Semantic.info) {
                selectedProductsForLabels = posStore.products.filter { multiSelect.isProductSelected($0.id) }
                showProductLabelSheet = true
            }
            BulkActionButton(icon: "tag.fill", label: "Price", color: Design.Colors.Semantic.accent) {
                handleBulkPriceUpdate()
            }
            BulkActionButton(icon: "square.and.arrow.up", label: "Export", color: Design.Colors.Semantic.success) {
                handleBulkExport()
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    private var orderActions: some View {
        HStack(spacing: 10) {
            BulkActionButton(icon: "printer.fill", label: "Print", color: Design.Colors.Semantic.info) {
                showOrderLabelSheet = true
            }
            BulkActionButton(icon: "checkmark.circle.fill", label: "Ready", color: Design.Colors.Semantic.success) {
                handleBulkMarkReady()
            }
            BulkActionButton(icon: "shippingbox.fill", label: "Fulfill", color: Design.Colors.Semantic.accent) {
                handleBulkFulfill()
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    // MARK: - Actions

    private func handleBulkPriceUpdate() {
        Log.ui.info("Bulk price update for \(multiSelect.selectedProductCount) products")
        Haptics.medium()
        multiSelect.clearSelection()
    }

    private func handleBulkExport() {
        let selectedProducts = posStore.products.filter { multiSelect.isProductSelected($0.id) }
        Log.ui.info("Bulk export \(selectedProducts.count) products")

        var csv = "Name,SKU,Price,Category\n"
        for product in selectedProducts {
            let name = product.name.replacingOccurrences(of: ",", with: ";")
            let sku = product.sku ?? ""
            let price = CurrencyFormatter.format(product.displayPrice)
            let category = product.categoryName ?? ""
            csv += "\(name),\(sku),\(price),\(category)\n"
        }

        let data = csv.data(using: .utf8) ?? Data()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("products_export.csv")
        try? data.write(to: url)

        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = rootVC.view
                popover.sourceRect = CGRect(x: rootVC.view.bounds.midX, y: rootVC.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            rootVC.present(activityVC, animated: true)
        }

        Haptics.success()
        multiSelect.clearSelection()
    }

    private func handleBulkMarkReady() {
        Task {
            let selectedIds = Array(multiSelect.selectedOrderIds)
            for orderId in selectedIds {
                await orderStore.updateStatus(orderId: orderId, status: .ready)
            }
            Haptics.success()
            multiSelect.clearSelection()
        }
    }

    private func handleBulkFulfill() {
        Task {
            let selectedIds = Array(multiSelect.selectedOrderIds)
            for orderId in selectedIds {
                await orderStore.updateStatus(orderId: orderId, status: .completed)
            }
            Haptics.success()
            multiSelect.clearSelection()
        }
    }
}
