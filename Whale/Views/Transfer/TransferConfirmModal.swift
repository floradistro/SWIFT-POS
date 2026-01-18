//
//  TransferConfirmModal.swift
//  Whale
//
//  Minimal liquid glass transfer confirmation.
//  Steve Jobs principle: Select products from grid → tap Transfer → pick destination → done.
//

import SwiftUI

struct TransferConfirmModal: View {
    @Binding var isPresented: Bool
    let products: [Product]
    let sourceLocation: Location
    let availableDestinations: [Location]
    let onTransferComplete: (InventoryTransfer) -> Void

    @EnvironmentObject private var session: SessionObserver
    @State private var selectedDestination: Location?
    @State private var quantities: [UUID: Int] = [:]
    @State private var isTransferring = false
    @State private var showSuccess = false
    @State private var createdTransfer: InventoryTransfer?
    @State private var errorMessage: String?

    private var totalUnits: Int {
        quantities.values.reduce(0, +)
    }

    private func quantity(for product: Product) -> Int {
        quantities[product.id] ?? 1
    }

    private func maxQuantity(for product: Product) -> Int {
        max(1, product.availableStock)
    }

    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture {
                    if !isTransferring && !showSuccess {
                        withAnimation(.spring(response: 0.3)) { isPresented = false }
                    }
                }

            // Modal
            VStack(spacing: 0) {
                if showSuccess {
                    successContent
                } else {
                    mainContent
                }
            }
            .frame(maxWidth: 440)
            .glassEffect(.regular, in: .rect(cornerRadius: 28))
            .padding(.horizontal, 24)
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showSuccess)
        .onAppear {
            // Initialize quantities to 1 for each product
            for product in products {
                quantities[product.id] = 1
            }
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        VStack(spacing: 16) {
            // Header
            header

            // Route visualization
            routeSection

            // Destination picker
            destinationPicker

            // Products list with quantities
            if !products.isEmpty {
                productsSection
            }

            // Error message
            if let error = errorMessage {
                Text(error)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
            }

            // Action button
            actionButton
        }
        .padding(24)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Transfer")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("\(products.count) products • \(totalUnits) units")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }

            Spacer()

            // Close button
            Button {
                Haptics.light()
                withAnimation(.spring(response: 0.3)) { isPresented = false }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .tint(.white.opacity(0.6))
        }
    }

    private var routeSection: some View {
        HStack(spacing: 16) {
            // Source
            VStack(spacing: 6) {
                Image(systemName: "building.2.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.1))
                    .clipShape(Circle())

                Text(sourceLocation.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text("From")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .frame(maxWidth: .infinity)

            // Arrow
            Image(systemName: "arrow.right")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(selectedDestination != nil ? Design.Colors.Semantic.accent : .white.opacity(0.3))

            // Destination
            VStack(spacing: 6) {
                Image(systemName: selectedDestination != nil ? "building.2.fill" : "questionmark")
                    .font(.system(size: 20))
                    .foregroundStyle(selectedDestination != nil ? Design.Colors.Semantic.accent : .white.opacity(0.4))
                    .frame(width: 44, height: 44)
                    .background(selectedDestination != nil ? Design.Colors.Semantic.accent.opacity(0.2) : .white.opacity(0.05))
                    .clipShape(Circle())

                Text(selectedDestination?.name ?? "Select")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(selectedDestination != nil ? .white : .white.opacity(0.5))
                    .lineLimit(1)

                Text("To")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .frame(maxWidth: .infinity)
        }
        .padding(12)
        .background(.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var destinationPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DESTINATION")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.4))
                .tracking(0.5)

            if availableDestinations.isEmpty {
                Text("No other locations available")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            } else {
                // Liquid glass destination pills
                TransferDestinationFlow(spacing: 8) {
                    ForEach(availableDestinations, id: \.id) { location in
                        destinationPill(location)
                    }
                }
            }
        }
    }

    private func destinationPill(_ location: Location) -> some View {
        Button {
            Haptics.light()
            withAnimation(.spring(response: 0.25)) {
                selectedDestination = location
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "building.2")
                    .font(.system(size: 11, weight: .medium))

                Text(location.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(selectedDestination?.id == location.id ? .white : .white.opacity(0.7))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Capsule())
        }
        .buttonStyle(ScaleButtonStyle())
        .glassEffect(
            selectedDestination?.id == location.id ? .regular.interactive() : .regular,
            in: .capsule
        )
        .overlay(
            Capsule()
                .stroke(selectedDestination?.id == location.id ? Design.Colors.Semantic.accent : .clear, lineWidth: 2)
        )
    }

    // MARK: - Products Section

    private var productsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("QUANTITIES")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.4))
                .tracking(0.5)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(products, id: \.id) { product in
                        productRow(product)
                    }
                }
            }
            .frame(maxHeight: 180)
        }
    }

    private func productRow(_ product: Product) -> some View {
        HStack(spacing: 12) {
            // Product info
            VStack(alignment: .leading, spacing: 2) {
                Text(product.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text("Available: \(product.availableStock)")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
            }

            Spacer()

            // Quantity stepper
            HStack(spacing: 0) {
                Button {
                    Haptics.light()
                    let current = quantity(for: product)
                    if current > 1 {
                        quantities[product.id] = current - 1
                    }
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(ScaleButtonStyle())

                Text("\(quantity(for: product))")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 36)

                Button {
                    Haptics.light()
                    let current = quantity(for: product)
                    let max = maxQuantity(for: product)
                    if current < max {
                        quantities[product.id] = current + 1
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(ScaleButtonStyle())
            }
            .glassEffect(.regular, in: .capsule)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var actionButton: some View {
        Button {
            Haptics.medium()
            Task { await performTransfer() }
        } label: {
            HStack(spacing: 10) {
                if isTransferring {
                    ProgressView()
                        .scaleEffect(0.9)
                        .tint(.white)
                } else {
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 16, weight: .semibold))
                }

                Text(isTransferring ? "Transferring..." : "Transfer \(totalUnits) Units")
                    .font(.system(size: 16, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.capsule)
        .tint(.white)
        .disabled(selectedDestination == nil || isTransferring || totalUnits == 0)
        .opacity(selectedDestination == nil || totalUnits == 0 ? 0.5 : 1)
    }

    // MARK: - Success Content

    private var successContent: some View {
        VStack(spacing: 24) {
            // Success icon
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Design.Colors.Semantic.success)

            VStack(spacing: 8) {
                Text("Transfer Created")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                if let transfer = createdTransfer {
                    Text(transfer.displayNumber)
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            // Summary
            HStack(spacing: 20) {
                VStack(spacing: 4) {
                    Text("\(totalUnits)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Units")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }

                Rectangle()
                    .fill(.white.opacity(0.1))
                    .frame(width: 1, height: 36)

                VStack(spacing: 4) {
                    Text("\(products.count)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Products")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }

                if let transfer = createdTransfer {
                    Rectangle()
                        .fill(.white.opacity(0.1))
                        .frame(width: 1, height: 36)

                    VStack(spacing: 4) {
                        Text(transfer.status.displayName)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Design.Colors.Semantic.success)
                        Text("Status")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 24)
            .background(.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Done button
            Button {
                Haptics.medium()
                if let transfer = createdTransfer {
                    onTransferComplete(transfer)
                }
                withAnimation(.spring(response: 0.3)) { isPresented = false }
            } label: {
                Text("Done")
                    .font(.system(size: 16, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .tint(.white)
        }
        .padding(24)
    }

    // MARK: - Transfer Action

    private func performTransfer() async {
        guard let destination = selectedDestination,
              let storeId = session.storeId else { return }

        isTransferring = true
        errorMessage = nil

        do {
            let items = products.compactMap { product -> (productId: UUID, quantity: Double)? in
                guard let qty = quantities[product.id], qty > 0 else { return nil }
                return (productId: product.id, quantity: Double(qty))
            }

            let transfer = try await InventoryUnitService.shared.createTransfer(
                storeId: storeId,
                sourceLocationId: sourceLocation.id,
                destinationLocationId: destination.id,
                items: items,
                notes: "Bulk transfer from POS",
                userId: session.userId
            )

            createdTransfer = transfer
            Haptics.success()

            withAnimation(.spring(response: 0.4)) {
                showSuccess = true
            }
        } catch {
            errorMessage = error.localizedDescription
            Haptics.error()
        }

        isTransferring = false
    }
}

// MARK: - Flow Layout for Destination Pills

private struct TransferDestinationFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)

        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: ProposedViewSize(subviews[index].sizeThatFits(.unspecified))
            )
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: currentY + lineHeight), positions)
    }
}
