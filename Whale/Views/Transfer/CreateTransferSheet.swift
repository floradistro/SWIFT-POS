//
//  CreateTransferSheet.swift
//  Whale
//
//  UI for creating inventory transfers between locations.
//

import SwiftUI

// MARK: - Create Transfer Sheet

struct CreateTransferSheet: View {
    let storeId: UUID
    let sourceLocation: Location
    let onDismiss: () -> Void
    let onTransferCreated: (InventoryTransfer) -> Void

    @EnvironmentObject private var session: SessionObserver

    @State private var isPresented = true
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
        UnifiedModal(isPresented: $isPresented, id: "create-transfer", dismissOnTapOutside: currentScreen == .selectDestination) {
            VStack(spacing: 0) {
                ModalHeader(screenSubtitle, subtitle: screenTitle, onClose: navigateBack) {
                    if currentScreen != .selectDestination && currentScreen != .printing && currentScreen != .success {
                        EmptyView()
                    }
                }

                if let error = errorMessage {
                    TransferErrorBanner(error: error) { errorMessage = nil }
                }

                ScrollView(showsIndicators: false) {
                    screenContent
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                }
            }
        }
        .onChange(of: isPresented) { _, newValue in
            if !newValue { onDismiss() }
        }
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
                ProgressView().scaleEffect(1.5).tint(.white)
                Text("Creating transfer...").font(.system(size: 15, weight: .medium)).foregroundStyle(.white.opacity(0.7))
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
        case .selectDestination: isPresented = false
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

            Image(systemName: "arrow.down").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white.opacity(0.3))

            ModalSection {
                VStack(alignment: .leading, spacing: 8) {
                    Text("TO").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.4)).tracking(0.5)
                    ForEach(availableDestinations, id: \.id) { location in
                        TransferDestinationRow(location: location, isSelected: selectedDestination?.id == location.id) {
                            Haptics.light()
                            selectedDestination = location
                        }
                    }
                    if availableDestinations.isEmpty {
                        Text("No other locations available").font(.system(size: 13)).foregroundStyle(.white.opacity(0.5)).padding(.vertical, 8)
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
                        Text(sourceLocation.name).font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                        Text("Source").font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
                    }
                    Spacer()
                    Image(systemName: "arrow.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.3))
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(selectedDestination?.name ?? "").font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                        Text("Destination").font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
                    }
                }
            }

            ModalTextInput(placeholder: "Search products...", text: $searchText)

            if !transferItems.isEmpty {
                ModalSection {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("SELECTED (\(transferItems.count))").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.4)).tracking(0.5)
                            Spacer()
                            Button { Haptics.light(); transferItems.removeAll() } label: {
                                Text("Clear All").font(.system(size: 11, weight: .medium)).foregroundStyle(Design.Colors.Semantic.error)
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
                    Text("PRODUCTS").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.4)).tracking(0.5)
                    if isLoadingProducts {
                        HStack { ProgressView().scaleEffect(0.8).tint(.white); Text("Loading...").font(.system(size: 13)).foregroundStyle(.white.opacity(0.5)) }.padding(.vertical, 8)
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
                            Text(searchText.isEmpty ? "No products found" : "No matching products").font(.system(size: 13)).foregroundStyle(.white.opacity(0.5)).padding(.vertical, 8)
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
                        VStack(alignment: .leading, spacing: 2) { Text("From").font(.system(size: 10)).foregroundStyle(.white.opacity(0.4)); Text(sourceLocation.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white) }
                        Spacer()
                        Image(systemName: "arrow.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(Design.Colors.Semantic.accent)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) { Text("To").font(.system(size: 10)).foregroundStyle(.white.opacity(0.4)); Text(selectedDestination?.name ?? "").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white) }
                    }
                    Divider().background(.white.opacity(0.1))
                    ModalInfoRow(label: "Total Items", value: "\(transferItems.count) products")
                    ModalInfoRow(label: "Total Quantity", value: "\(Int(totalQuantity)) units")
                }
            }

            ModalSection {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ITEMS").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.4)).tracking(0.5)
                    ForEach(transferItems) { item in
                        HStack {
                            Text(item.productName).font(.system(size: 13)).foregroundStyle(.white).lineLimit(1)
                            Spacer()
                            Text("x\(Int(item.quantity))").font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.6))
                        }.padding(.vertical, 4)
                    }
                }
            }

            ModalSection {
                VStack(alignment: .leading, spacing: 8) {
                    Text("NOTES (OPTIONAL)").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.4)).tracking(0.5)
                    TextField("Add notes...", text: $notes, axis: .vertical).font(.system(size: 14)).foregroundStyle(.white).lineLimit(3...5)
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
                Text("Transfer Created").font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
                if let transfer = createdTransfer {
                    Text(transfer.displayNumber).font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.6))
                }
            }

            if let transfer = createdTransfer {
                ModalSection {
                    VStack(spacing: 8) {
                        ModalInfoRow(label: "Package QR", value: transfer.qrCode)
                        ModalInfoRow(label: "Status", value: transfer.status.displayName, valueColor: transfer.status == .completed ? Design.Colors.Semantic.success : .white)
                        ModalInfoRow(label: "Items", value: "\(transferItems.count) products")
                    }
                }
            }

            VStack(spacing: 12) {
                ModalActionButton("Print Package Label", icon: "printer") {
                    print("📄 Print: \(createdTransfer?.qrCode ?? "")")
                }
                ModalSecondaryButton(title: "Done") {
                    if let transfer = createdTransfer { onTransferCreated(transfer) }
                    isPresented = false
                }
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
            Text(error).font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
            Spacer()
            Button { onDismiss() } label: { Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.5)) }.buttonStyle(.plain)
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
            Text(label).font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.4)).tracking(0.5)
            HStack(spacing: 12) {
                Image(systemName: "building.2").font(.system(size: 16)).foregroundStyle(Design.Colors.Semantic.accent).frame(width: 24)
                Text(location.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                Spacer()
                if isCurrent {
                    Text("Current").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.5)).padding(.horizontal, 8).padding(.vertical, 4).background(Capsule().fill(.white.opacity(0.1)))
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
                    Circle().stroke(isSelected ? Design.Colors.Semantic.accent : .white.opacity(0.2), lineWidth: 2).frame(width: 22, height: 22)
                    if isSelected { Circle().fill(Design.Colors.Semantic.accent).frame(width: 12, height: 12) }
                }
                Image(systemName: "building.2").font(.system(size: 14)).foregroundStyle(.white.opacity(0.5)).frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(location.name).font(.system(size: 14, weight: .medium)).foregroundStyle(.white)
                    if let address = location.displayAddress { Text(address).font(.system(size: 11)).foregroundStyle(.white.opacity(0.4)).lineLimit(1) }
                }
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 10).fill(isSelected ? Design.Colors.Semantic.accent.opacity(0.1) : .white.opacity(0.05)))
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
                    Text(product.name).font(.system(size: 14, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                    if let sku = product.sku { Text(sku).font(.system(size: 11)).foregroundStyle(.white.opacity(0.4)) }
                }
                Spacer()
                if product.availableStock > 0 { Text("\(product.availableStock)").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.6)).padding(.horizontal, 8).padding(.vertical, 4).background(Capsule().fill(.white.opacity(0.1))) }
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle").font(.system(size: 20)).foregroundStyle(isSelected ? Design.Colors.Semantic.accent : .white.opacity(0.2))
            }.padding(.vertical, 8)
        }.buttonStyle(.plain)
    }
}

private struct TransferSelectedItemRow: View {
    @Binding var item: TransferItemEntry
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.1)).frame(width: 32, height: 32).overlay(Image(systemName: "cube.box").font(.system(size: 12)).foregroundStyle(.white.opacity(0.4)))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.productName).font(.system(size: 13, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                if let sku = item.productSKU { Text(sku).font(.system(size: 10)).foregroundStyle(.white.opacity(0.4)) }
            }
            Spacer()
            HStack(spacing: 0) {
                Button { Haptics.light(); if item.quantity > 1 { item.quantity -= 1 } } label: { Image(systemName: "minus").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white).frame(width: 28, height: 28) }.buttonStyle(.plain)
                Text("\(Int(item.quantity))").font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(.white).frame(width: 36)
                Button { Haptics.light(); item.quantity += 1 } label: { Image(systemName: "plus").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white).frame(width: 28, height: 28) }.buttonStyle(.plain)
            }.background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.1)))
            Button { Haptics.light(); onRemove() } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.4)).frame(width: 24, height: 24) }.buttonStyle(.plain)
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
