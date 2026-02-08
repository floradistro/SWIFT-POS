//
//  CreateTransferSheet.swift
//  Whale
//
//  UI for creating inventory transfers between locations.
//

import SwiftUI
import os.log

// MARK: - Create Transfer Sheet

struct CreateTransferSheet: View {
    let storeId: UUID
    let sourceLocation: Location
    let onDismiss: () -> Void
    let onTransferCreated: (InventoryTransfer) -> Void

    @EnvironmentObject private var session: SessionObserver
    @Environment(\.dismiss) private var dismiss

    @State private var currentScreen: TransferScreen = .selectDestination
    @State private var isLoading = false
    @State private var errorMessage: String?

    @State private var selectedDestination: Location?
    @State private var transferItems: [TransferItemEntry] = []
    @State private var notes: String = ""
    @State private var searchText: String = ""
    @State private var availableProducts: [Product] = []
    @State private var isLoadingProducts = false
    @State private var createdTransfer: InventoryTransfer?

    enum TransferScreen { case selectDestination, addProducts, review, printing, success }

    private var availableDestinations: [Location] {
        session.locations.filter { $0.id != sourceLocation.id && $0.isActive }
    }

    private var filteredProducts: [Product] {
        guard !searchText.isEmpty else { return availableProducts }
        let search = searchText.lowercased()
        return availableProducts.filter {
            $0.name.lowercased().contains(search) || ($0.sku?.lowercased().contains(search) ?? false)
        }
    }

    private var totalQuantity: Double {
        transferItems.reduce(0) { $0 + $1.quantity }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    if let error = errorMessage {
                        TransferErrorBanner(error: error) { errorMessage = nil }
                    }

                    screenContent
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .navigationTitle(screenSubtitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if currentScreen != .printing && currentScreen != .success {
                        Button(currentScreen == .selectDestination ? "Cancel" : "Back") {
                            navigateBack()
                        }
                    }
                }
            }
        }
        .interactiveDismissDisabled(currentScreen == .printing)
        .task { await loadProducts() }
    }

    @ViewBuilder
    private var screenContent: some View {
        switch currentScreen {
        case .selectDestination:
            destinationContent
        case .addProducts:
            productsContent
        case .review:
            reviewContent
        case .printing:
            VStack(spacing: 24) {
                ProgressView().scaleEffect(1.5).tint(Design.Colors.Text.primary)
                Text("Creating transfer...").font(Design.Typography.subhead).fontWeight(.medium).foregroundStyle(Design.Colors.Text.quaternary)
            }.padding(.vertical, 40)
        case .success:
            successContent
        }
    }

    private var screenTitle: String {
        switch currentScreen {
        case .selectDestination: return "New Transfer"
        case .addProducts: return "Step 2 of 3"
        case .review: return "Step 3 of 3"
        case .printing: return "Creating"
        case .success: return "Complete"
        }
    }

    private var screenSubtitle: String {
        switch currentScreen {
        case .selectDestination: return "Select Destination"
        case .addProducts: return "Add Products"
        case .review: return "Review & Create"
        case .printing: return "Creating..."
        case .success: return "Transfer Created"
        }
    }

    private func navigateBack() {
        switch currentScreen {
        case .selectDestination:
            dismiss()
            onDismiss()
        case .addProducts: withAnimation(.spring(response: 0.3)) { currentScreen = .selectDestination }
        case .review: withAnimation(.spring(response: 0.3)) { currentScreen = .addProducts }
        case .printing, .success: break
        }
    }

    // MARK: - Destination Screen

    private var destinationContent: some View {
        VStack(spacing: 16) {
            ModalSection {
                TransferLocationRow(label: "FROM", location: sourceLocation, isCurrent: true)
            }

            Image(systemName: "arrow.down").font(Design.Typography.callout).fontWeight(.semibold).foregroundStyle(Design.Colors.Text.placeholder)

            ModalSection {
                VStack(alignment: .leading, spacing: 8) {
                    Text("TO").font(Design.Typography.caption2).fontWeight(.bold).foregroundStyle(Design.Colors.Text.subtle).tracking(0.5)
                    ForEach(availableDestinations, id: \.id) { location in
                        TransferDestinationRow(location: location, isSelected: selectedDestination?.id == location.id) {
                            Haptics.light()
                            selectedDestination = location
                        }
                    }
                    if availableDestinations.isEmpty {
                        Text("No other locations available").font(Design.Typography.footnote).foregroundStyle(Design.Colors.Text.disabled).padding(.vertical, 8)
                    }
                }
            }

            if selectedDestination != nil {
                ModalActionButton("Continue", icon: "arrow.right") {
                    withAnimation(.spring(response: 0.3)) { currentScreen = .addProducts }
                }
            }
        }
    }

    // MARK: - Products Screen

    private var productsContent: some View {
        VStack(spacing: 16) {
            ModalSection {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sourceLocation.name).font(Design.Typography.footnote).fontWeight(.medium).foregroundStyle(Design.Colors.Text.primary)
                        Text("Source").font(Design.Typography.caption2).foregroundStyle(Design.Colors.Text.subtle)
                    }
                    Spacer()
                    Image(systemName: "arrow.right").font(Design.Typography.caption1).fontWeight(.semibold).foregroundStyle(Design.Colors.Text.placeholder)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(selectedDestination?.name ?? "").font(Design.Typography.footnote).fontWeight(.medium).foregroundStyle(Design.Colors.Text.primary)
                        Text("Destination").font(Design.Typography.caption2).foregroundStyle(Design.Colors.Text.subtle)
                    }
                }
            }

            ModalTextInput(placeholder: "Search products...", text: $searchText)

            if !transferItems.isEmpty {
                ModalSection {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("SELECTED (\(transferItems.count))").font(Design.Typography.caption2).fontWeight(.bold).foregroundStyle(Design.Colors.Text.subtle).tracking(0.5)
                            Spacer()
                            Button { Haptics.light(); transferItems.removeAll() } label: {
                                Text("Clear All").font(Design.Typography.caption2).fontWeight(.medium).foregroundStyle(Design.Colors.Semantic.error)
                            }.buttonStyle(.plain)
                        }
                        ForEach($transferItems) { $item in
                            TransferSelectedItemRow(item: $item) { transferItems.removeAll { $0.id == item.id } }
                        }
                    }
                }
            }

            ModalSection {
                VStack(alignment: .leading, spacing: 8) {
                    Text("PRODUCTS").font(Design.Typography.caption2).fontWeight(.bold).foregroundStyle(Design.Colors.Text.subtle).tracking(0.5)
                    if isLoadingProducts {
                        HStack { ProgressView().scaleEffect(0.8).tint(Design.Colors.Text.primary); Text("Loading...").font(Design.Typography.footnote).foregroundStyle(Design.Colors.Text.disabled) }.padding(.vertical, 8)
                    } else {
                        ForEach(filteredProducts, id: \.id) { product in
                            TransferProductRow(product: product, isSelected: transferItems.contains { $0.productId == product.id }, storeLogoUrl: session.store?.fullLogoUrl) {
                                Haptics.light()
                                if transferItems.contains(where: { $0.productId == product.id }) {
                                    transferItems.removeAll { $0.productId == product.id }
                                } else {
                                    transferItems.append(TransferItemEntry(productId: product.id, productName: product.name, productSKU: product.sku, productImage: product.iconUrl?.absoluteString, quantity: 1))
                                }
                            }
                        }
                        if filteredProducts.isEmpty {
                            Text(searchText.isEmpty ? "No products found" : "No matching products").font(Design.Typography.footnote).foregroundStyle(Design.Colors.Text.disabled).padding(.vertical, 8)
                        }
                    }
                }
            }

            if !transferItems.isEmpty {
                ModalActionButton("Review Transfer", icon: "arrow.right") {
                    withAnimation(.spring(response: 0.3)) { currentScreen = .review }
                }
            }
        }
    }

    // MARK: - Review Screen

    private var reviewContent: some View {
        VStack(spacing: 16) {
            ModalSection {
                VStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) { Text("From").font(Design.Typography.caption2).foregroundStyle(Design.Colors.Text.subtle); Text(sourceLocation.name).font(Design.Typography.footnote).fontWeight(.semibold).foregroundStyle(Design.Colors.Text.primary) }
                        Spacer()
                        Image(systemName: "arrow.right").font(Design.Typography.footnote).fontWeight(.semibold).foregroundStyle(Design.Colors.Semantic.accent)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) { Text("To").font(Design.Typography.caption2).foregroundStyle(Design.Colors.Text.subtle); Text(selectedDestination?.name ?? "").font(Design.Typography.footnote).fontWeight(.semibold).foregroundStyle(Design.Colors.Text.primary) }
                    }
                    Divider().background(Design.Colors.Border.regular)
                    ModalInfoRow(label: "Total Items", value: "\(transferItems.count) products")
                    ModalInfoRow(label: "Total Quantity", value: "\(Int(totalQuantity)) units")
                }
            }

            ModalSection {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ITEMS").font(Design.Typography.caption2).fontWeight(.bold).foregroundStyle(Design.Colors.Text.subtle).tracking(0.5)
                    ForEach(transferItems) { item in
                        HStack {
                            Text(item.productName).font(Design.Typography.footnote).foregroundStyle(Design.Colors.Text.primary).lineLimit(1)
                            Spacer()
                            Text("x\(Int(item.quantity))").font(Design.Typography.footnoteRounded).fontWeight(.semibold).foregroundStyle(Design.Colors.Text.disabled)
                        }.padding(.vertical, 4)
                    }
                }
            }

            ModalSection {
                VStack(alignment: .leading, spacing: 8) {
                    Text("NOTES (OPTIONAL)").font(Design.Typography.caption2).fontWeight(.bold).foregroundStyle(Design.Colors.Text.subtle).tracking(0.5)
                    TextField("Add notes...", text: $notes, axis: .vertical).font(Design.Typography.footnote).foregroundStyle(Design.Colors.Text.primary).lineLimit(3...5)
                }
            }

            ModalActionButton("Create Transfer", icon: "shippingbox", isLoading: isLoading) {
                Task { await createTransfer() }
            }
        }
    }

    // MARK: - Success Screen

    private var successContent: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 56)).foregroundStyle(Design.Colors.Semantic.success)
            VStack(spacing: 4) {
                Text("Transfer Created").font(Design.Typography.title3).fontWeight(.bold).foregroundStyle(Design.Colors.Text.primary)
                if let transfer = createdTransfer {
                    Text(transfer.displayNumber).font(Design.Typography.subheadRounded).fontWeight(.semibold).foregroundStyle(Design.Colors.Text.disabled)
                }
            }

            if let transfer = createdTransfer {
                ModalSection {
                    VStack(spacing: 8) {
                        ModalInfoRow(label: "Package QR", value: transfer.qrCode)
                        ModalInfoRow(label: "Status", value: transfer.status.displayName, valueColor: transfer.status == .completed ? Design.Colors.Semantic.success : Design.Colors.Text.primary)
                        ModalInfoRow(label: "Items", value: "\(transferItems.count) products")
                    }
                }
            }

            VStack(spacing: 12) {
                ModalActionButton("Print Package Label", icon: "printer") {
                    Log.inventory.debug("Print: \(createdTransfer?.qrCode ?? "")")
                }
                Button {
                    if let transfer = createdTransfer { onTransferCreated(transfer) }
                    dismiss()
                    onDismiss()
                } label: {
                    Text("Done")
                        .font(Design.Typography.subhead).fontWeight(.medium)
                        .foregroundStyle(Design.Colors.Text.disabled)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Design.Colors.Glass.regular, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Actions

    private func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            availableProducts = try await ProductService.fetchProducts(storeId: storeId, locationId: sourceLocation.id)
        } catch {
            errorMessage = "Failed to load products"
        }
    }

    private func createTransfer() async {
        guard let destination = selectedDestination else { return }
        isLoading = true
        withAnimation(.spring(response: 0.3)) { currentScreen = .printing }

        do {
            let items = transferItems.map { (productId: $0.productId, quantity: $0.quantity) }
            let transfer = try await InventoryUnitService.shared.createTransfer(storeId: storeId, sourceLocationId: sourceLocation.id, destinationLocationId: destination.id, items: items, notes: notes.isEmpty ? nil : notes, userId: session.userId)
            createdTransfer = transfer
            withAnimation(.spring(response: 0.3)) { currentScreen = .success }
        } catch {
            errorMessage = error.localizedDescription
            withAnimation(.spring(response: 0.3)) { currentScreen = .review }
        }
        isLoading = false
    }
}

// MARK: - Supporting Views

private struct TransferErrorBanner: View {
    let error: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            Text(error).font(Design.Typography.footnote).fontWeight(.medium).foregroundStyle(Design.Colors.Text.primary)
            Spacer()
            Button { onDismiss() } label: { Image(systemName: "xmark").font(Design.Typography.caption1).fontWeight(.bold).foregroundStyle(Design.Colors.Text.disabled) }.buttonStyle(.plain)
        }
        .padding(12)
        .background(Color.red.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 20)
    }
}

private struct TransferLocationRow: View {
    let label: String
    let location: Location
    var isCurrent: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(Design.Typography.caption2).fontWeight(.bold).foregroundStyle(Design.Colors.Text.subtle).tracking(0.5)
            HStack(spacing: 12) {
                Image(systemName: "building.2").font(Design.Typography.callout).foregroundStyle(Design.Colors.Semantic.accent).frame(width: 24)
                Text(location.name).font(Design.Typography.subhead).fontWeight(.semibold).foregroundStyle(Design.Colors.Text.primary)
                Spacer()
                if isCurrent {
                    Text("Current").font(Design.Typography.caption2).fontWeight(.bold).foregroundStyle(Design.Colors.Text.disabled).padding(.horizontal, 8).padding(.vertical, 4).background(Capsule().fill(Design.Colors.Glass.thick))
                }
            }
        }
    }
}

private struct TransferDestinationRow: View {
    let location: Location
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().stroke(isSelected ? Design.Colors.Semantic.accent : Design.Colors.Text.ghost, lineWidth: 2).frame(width: 22, height: 22)
                    if isSelected { Circle().fill(Design.Colors.Semantic.accent).frame(width: 12, height: 12) }
                }
                Image(systemName: "building.2").font(Design.Typography.footnote).foregroundStyle(Design.Colors.Text.disabled).frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(location.name).font(Design.Typography.footnote).fontWeight(.medium).foregroundStyle(Design.Colors.Text.primary)
                    if let address = location.displayAddress { Text(address).font(Design.Typography.caption2).foregroundStyle(Design.Colors.Text.subtle).lineLimit(1) }
                }
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 10).fill(isSelected ? Design.Colors.Semantic.accent.opacity(0.1) : Design.Colors.Glass.thin))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(isSelected ? Design.Colors.Semantic.accent.opacity(0.3) : .clear, lineWidth: 1))
        }.buttonStyle(.plain)
    }
}

private struct TransferProductRow: View {
    let product: Product
    let isSelected: Bool
    let storeLogoUrl: URL?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                CachedAsyncImage(url: product.iconUrl, placeholderLogoUrl: storeLogoUrl, dimAmount: 0.1).frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.name).font(Design.Typography.footnote).fontWeight(.medium).foregroundStyle(Design.Colors.Text.primary).lineLimit(1)
                    if let sku = product.sku { Text(sku).font(Design.Typography.caption2).foregroundStyle(Design.Colors.Text.subtle) }
                }
                Spacer()
                if product.availableStock > 0 { Text("\(product.availableStock)").font(Design.Typography.caption2).fontWeight(.semibold).foregroundStyle(Design.Colors.Text.disabled).padding(.horizontal, 8).padding(.vertical, 4).background(Capsule().fill(Design.Colors.Glass.thick)) }
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle").font(Design.Typography.title3).foregroundStyle(isSelected ? Design.Colors.Semantic.accent : Design.Colors.Text.ghost)
            }.padding(.vertical, 8)
        }.buttonStyle(.plain)
    }
}

private struct TransferSelectedItemRow: View {
    @Binding var item: TransferItemEntry
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6).fill(Design.Colors.Glass.thick).frame(width: 32, height: 32).overlay(Image(systemName: "cube.box").font(Design.Typography.caption1).foregroundStyle(Design.Colors.Text.subtle))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.productName).font(Design.Typography.footnote).fontWeight(.medium).foregroundStyle(Design.Colors.Text.primary).lineLimit(1)
                if let sku = item.productSKU { Text(sku).font(Design.Typography.caption2).foregroundStyle(Design.Colors.Text.subtle) }
            }
            Spacer()
            HStack(spacing: 0) {
                Button { Haptics.light(); if item.quantity > 1 { item.quantity -= 1 } } label: { Image(systemName: "minus").font(Design.Typography.caption1).fontWeight(.semibold).foregroundStyle(Design.Colors.Text.primary).frame(width: 28, height: 28) }.buttonStyle(.plain)
                Text("\(Int(item.quantity))").font(Design.Typography.footnoteRounded).fontWeight(.semibold).foregroundStyle(Design.Colors.Text.primary).frame(width: 36)
                Button { Haptics.light(); item.quantity += 1 } label: { Image(systemName: "plus").font(Design.Typography.caption1).fontWeight(.semibold).foregroundStyle(Design.Colors.Text.primary).frame(width: 28, height: 28) }.buttonStyle(.plain)
            }.background(RoundedRectangle(cornerRadius: 8).fill(Design.Colors.Glass.thick))
            Button { Haptics.light(); onRemove() } label: { Image(systemName: "xmark").font(Design.Typography.caption2).fontWeight(.bold).foregroundStyle(Design.Colors.Text.subtle).frame(width: 24, height: 24) }.buttonStyle(.plain)
        }.padding(.vertical, 4)
    }
}

// MARK: - Transfer Item Entry

struct TransferItemEntry: Identifiable {
    let id = UUID()
    let productId: UUID
    let productName: String
    let productSKU: String?
    let productImage: String?
    var quantity: Double
}
