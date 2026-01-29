//
//  OrderDetailModal.swift
//  Whale
//
//  Order detail view modal - clean, professional design.
//
//  ARCHITECTURE NOTE (2026-01-01):
//  Status workflow logic has been moved to the backend.
//  - nextStatus is now fetched via get_next_order_status RPC
//  - Item filtering uses get_order_items_for_location RPC
//  The view now focuses purely on display with minimal logic.
//

import SwiftUI

// MARK: - Order Detail Modal

struct OrderDetailModal: View {
    let order: Order
    @ObservedObject var store: OrderStore
    @Binding var isPresented: Bool
    @EnvironmentObject private var session: SessionObserver

    // Invoice tracking state
    @State private var invoice: Invoice?
    @State private var isLoadingInvoice = false
    @State private var invoiceError: String?
    @State private var showInvoiceDetail = false
    @State private var invoiceSubscriptionTask: Task<Void, Never>?

    // Shipping label state
    @State private var isGeneratingLabel = false
    @State private var labelError: String?

    private var currentOrder: Order {
        store.orders.first(where: { $0.id == order.id }) ?? order
    }

    private var isMultiLocationOrder: Bool {
        currentOrder.fulfillmentLocationNames.count > 1
    }

    var body: some View {
        UnifiedModal(isPresented: $isPresented, id: "order-detail") {
            VStack(spacing: 0) {
                // Header
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("#\(currentOrder.shortOrderNumber)")
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.5))
                        Text(currentOrder.formattedTotal)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }

                    Spacer()

                    // Status indicator
                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 6, height: 6)
                        Text(currentOrder.status.displayName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .glassEffect(.regular, in: .capsule)

                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))
                            .frame(width: 36, height: 36)
                    }
                    .tint(.white)
                    .glassEffect(.regular.interactive(), in: .circle)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 16)

                AdaptiveScrollView(maxHeight: 350, showsIndicators: true) {
                    VStack(spacing: 16) {
                        // Customer
                        if currentOrder.displayCustomerName != "Guest" {
                            OrderDetailCustomerSection(order: currentOrder)
                        }

                        // Items
                        if let items = currentOrder.items, !items.isEmpty {
                            OrderDetailItemsSection(order: currentOrder, session: session)
                        }

                        // Shipping with label printing
                        if currentOrder.orderType == .shipping {
                            OrderDetailShippingSection(
                                order: currentOrder,
                                session: session,
                                store: store,
                                isGeneratingLabel: $isGeneratingLabel,
                                labelError: $labelError
                            )
                        }

                        // Pickup
                        if currentOrder.orderType == .pickup {
                            OrderDetailPickupSection(order: currentOrder)
                        }

                        // Invoice
                        if currentOrder.orderType == .direct {
                            OrderDetailInvoiceSection(
                                order: currentOrder,
                                invoice: $invoice,
                                isLoading: $isLoadingInvoice,
                                error: $invoiceError,
                                showDetail: $showInvoiceDetail
                            )
                        }

                        // Notes
                        if let notes = currentOrder.staffNotes, !notes.isEmpty {
                            OrderDetailNotesSection(notes: notes)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                }
                .task {
                    if currentOrder.orderType == .direct {
                        subscribeToInvoiceUpdates()
                        await fetchInvoice()
                    }
                }
                .onDisappear {
                    invoiceSubscriptionTask?.cancel()
                    invoiceSubscriptionTask = nil
                }

                OrderDetailActionButton(order: currentOrder, store: store, isPresented: $isPresented)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
        }
        .sheet(isPresented: $showInvoiceDetail) {
            if let invoice = invoice {
                InvoiceDetailSheet(invoice: invoice) {
                    showInvoiceDetail = false
                }
            }
        }
    }

    private var statusColor: Color {
        switch currentOrder.status {
        case .pending, .preparing: return .white.opacity(0.6)
        case .ready, .readyToShip: return .white
        case .completed, .delivered, .shipped: return .white.opacity(0.4)
        case .cancelled: return .white.opacity(0.3)
        default: return .white.opacity(0.5)
        }
    }

    private func fetchInvoice() async {
        isLoadingInvoice = true
        invoiceError = nil
        defer { isLoadingInvoice = false }

        do {
            invoice = try await InvoiceService.fetchInvoiceByOrder(orderId: currentOrder.id)
        } catch {
            invoiceError = "Unable to load invoice"
        }
    }

    private func subscribeToInvoiceUpdates() {
        invoiceSubscriptionTask?.cancel()
        invoiceSubscriptionTask = Task {
            for await updatedInvoice in InvoiceService.subscribeToInvoiceByOrder(orderId: currentOrder.id) {
                await MainActor.run {
                    self.invoice = updatedInvoice
                    Haptics.light()
                }
            }
        }
    }
}

// MARK: - Customer Section

private struct OrderDetailCustomerSection: View {
    let order: Order

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.white.opacity(0.1))
                .frame(width: 44, height: 44)
                .overlay(
                    Text(String(order.displayCustomerName.prefix(1)).uppercased())
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(order.displayCustomerName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)

                if let phone = order.customerPhone {
                    Text(phone)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }

            Spacer()

            // Payment status - subtle
            Text(order.paymentStatus.displayName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(order.paymentStatus == .paid ? .white.opacity(0.5) : .white.opacity(0.7))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.white.opacity(0.06)))
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04)))
    }
}

// MARK: - Items Section

private struct OrderDetailItemsSection: View {
    let order: Order
    let session: SessionObserver

    // Item separation is now loaded from backend RPC
    @State private var itemsForCurrentLocation: [OrderItem] = []
    @State private var itemsForOtherLocations: [OrderItem] = []
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                // Loading state
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.white.opacity(0.5))
                    Text("Loading items...")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                // Your location items
                if !itemsForCurrentLocation.isEmpty {
                    VStack(spacing: 0) {
                        HStack {
                            Text("Your Location")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.4))
                            Spacer()
                            Text("\(itemsForCurrentLocation.count) item\(itemsForCurrentLocation.count == 1 ? "" : "s")")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.3))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)

                        ForEach(itemsForCurrentLocation) { item in
                            OrderItemRow(item: item)
                        }
                    }
                }

                // Other location items (dimmed)
                if !itemsForOtherLocations.isEmpty {
                    VStack(spacing: 0) {
                        HStack {
                            Text("Other Locations")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.25))
                            Spacer()
                            Text("\(itemsForOtherLocations.count) item\(itemsForOtherLocations.count == 1 ? "" : "s")")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.2))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)

                        ForEach(itemsForOtherLocations) { item in
                            OrderItemRow(item: item, dimmed: true)
                        }
                    }
                }

                // Divider
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 1)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)

                // Totals
                OrderTotalsView(order: order)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
            }
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04)))
        .task {
            await loadItemsForLocation()
        }
    }

    private func loadItemsForLocation() async {
        guard let locationId = session.selectedLocation?.id else {
            // Fallback: show all items as "current location" items
            itemsForCurrentLocation = order.items ?? []
            itemsForOtherLocations = []
            isLoading = false
            return
        }

        do {
            let result = try await OrderService.getOrderItemsForLocation(
                orderId: order.id,
                locationId: locationId
            )
            itemsForCurrentLocation = result.forLocation
            itemsForOtherLocations = result.other
        } catch {
            // Fallback on error: show all items
            itemsForCurrentLocation = order.items ?? []
            itemsForOtherLocations = []
        }
        isLoading = false
    }
}

// MARK: - Item Row

private struct OrderItemRow: View {
    let item: OrderItem
    var dimmed: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Text("\(item.quantity)×")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(dimmed ? 0.25 : 0.4))
                .frame(width: 28, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.productName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(dimmed ? 0.35 : 0.9))
                    .lineLimit(1)

                if dimmed, let locationName = item.locationName {
                    Text(locationName)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.2))
                }
            }

            Spacer()

            Text(CurrencyFormatter.format(item.lineTotal))
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(dimmed ? 0.25 : 0.6))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

// MARK: - Order Totals

private struct OrderTotalsView: View {
    let order: Order

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Subtotal")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.4))
                Spacer()
                Text(CurrencyFormatter.format(order.subtotal))
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
            }

            HStack {
                Text("Tax")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.4))
                Spacer()
                Text(CurrencyFormatter.format(order.taxAmount))
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
            }

            if order.discountAmount > 0 {
                HStack {
                    Text("Discount")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.5))
                    Spacer()
                    Text("-\(CurrencyFormatter.format(order.discountAmount))")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
    }
}

// MARK: - Shipping Section (with Label Printing)

private struct OrderDetailShippingSection: View {
    let order: Order
    let session: SessionObserver
    let store: OrderStore
    @Binding var isGeneratingLabel: Bool
    @Binding var labelError: String?

    private var hasTrackingNumber: Bool {
        order.trackingNumber != nil || (order.orderLocations?.contains { $0.trackingNumber != nil } ?? false)
    }

    private var needsLabel: Bool {
        guard let locationId = session.selectedLocation?.id else { return false }

        // Check if this location needs to generate a label
        if let orderLocs = order.orderLocations {
            return orderLocs.contains { $0.locationId == locationId && $0.trackingNumber == nil }
        }
        return order.trackingNumber == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("SHIPPING")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))
                    .tracking(0.5)

                Spacer()

                Text(order.orderType.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            }

            // Address
            if let address = order.fullShippingAddress {
                Text(address)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(3)
            }

            // Tracking info or Generate Label button
            if let orderLocs = order.orderLocations, !orderLocs.isEmpty {
                ForEach(orderLocs, id: \.id) { orderLoc in
                    if let tracking = orderLoc.trackingNumber {
                        TrackingRow(
                            locationName: orderLoc.locationName,
                            tracking: tracking,
                            carrier: orderLoc.shippingCarrier,
                            labelUrl: orderLoc.shippingLabelUrl
                        )
                    } else if orderLoc.locationId == session.selectedLocation?.id {
                        GenerateLabelButton(
                            orderId: order.id,
                            locationId: orderLoc.locationId,
                            store: store,
                            isGenerating: $isGeneratingLabel,
                            error: $labelError
                        )
                    } else {
                        PendingLabelRow(locationName: orderLoc.locationName ?? "Other Location")
                    }
                }
            } else if let tracking = order.trackingNumber {
                TrackingRow(
                    locationName: nil,
                    tracking: tracking,
                    carrier: order.shippingCarrier,
                    labelUrl: order.shippingLabelUrl
                )
            } else if let locationId = session.selectedLocation?.id {
                GenerateLabelButton(
                    orderId: order.id,
                    locationId: locationId,
                    store: store,
                    isGenerating: $isGeneratingLabel,
                    error: $labelError
                )
            }

            // Error message
            if let error = labelError {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(.red.opacity(0.8))
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04)))
    }
}

// MARK: - Tracking Row

private struct TrackingRow: View {
    let locationName: String?
    let tracking: String
    let carrier: String?
    let labelUrl: String?

    @State private var isPrinting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let name = locationName {
                Text(name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    if let carrierName = carrier {
                        Text(carrierName.uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.3))
                            .tracking(0.5)
                    }
                    Text(tracking)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.8))
                }

                Spacer()

                HStack(spacing: 10) {
                    // Copy button
                    Button {
                        UIPasteboard.general.string = tracking
                        Haptics.success()
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.5))
                            .frame(width: 36, height: 36)
                    }
                    .tint(.white)
                    .glassEffect(.regular.interactive(), in: .circle)

                    // Print label button
                    if let url = labelUrl {
                        Button {
                            Task { await printLabel(url: url) }
                        } label: {
                            Group {
                                if isPrinting {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "printer")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.white.opacity(0.5))
                                }
                            }
                            .frame(width: 36, height: 36)
                        }
                        .tint(.white)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .disabled(isPrinting)
                    }
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.04)))
    }

    private func printLabel(url: String) async {
        isPrinting = true

        // Close the modal so native print dialog can receive touches
        await MainActor.run {
            ModalManager.shared.close(id: "order-detail")
        }

        // Small delay for modal to dismiss
        try? await Task.sleep(nanoseconds: 400_000_000)

        do {
            let printed = try await ShippingLabelService.printLabelFromURL(url, jobName: "Shipping Label - \(tracking)")
            if printed {
                Haptics.success()
            }
        } catch {
            Haptics.error()
        }

        isPrinting = false
    }
}

// MARK: - Generate Label Button

private struct GenerateLabelButton: View {
    let orderId: UUID
    let locationId: UUID
    let store: OrderStore
    @Binding var isGenerating: Bool
    @Binding var error: String?

    var body: some View {
        Button {
            Task { await generateLabel() }
        } label: {
            HStack(spacing: 8) {
                if isGenerating {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "shippingbox")
                        .font(.system(size: 13))
                }
                Text(isGenerating ? "Generating..." : "Generate Shipping Label")
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
        }
        .tint(.white)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 10))
        .disabled(isGenerating)
    }

    private func generateLabel() async {
        isGenerating = true
        error = nil

        do {
            let response = try await ShippingLabelService.generateLabel(orderId: orderId, locationId: locationId)
            if response.success {
                Haptics.success()

                // Refresh the order to get the updated tracking info
                await store.refreshOrder(orderId: orderId)

                // If label URL exists, offer to print immediately
                if let labelUrl = response.labelUrl {
                    let _ = try? await ShippingLabelService.printLabelFromURL(labelUrl, jobName: "Shipping Label")
                }
            } else {
                error = response.error ?? "Failed to generate label"
                Haptics.error()
            }
        } catch {
            self.error = error.localizedDescription
            Haptics.error()
        }

        isGenerating = false
    }
}

// MARK: - Pending Label Row

private struct PendingLabelRow: View {
    let locationName: String

    var body: some View {
        HStack(spacing: 8) {
            Text(locationName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))

            Spacer()

            Text("Awaiting label")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.3))
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.03)))
    }
}

// MARK: - Pickup Section

private struct OrderDetailPickupSection: View {
    let order: Order

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("PICKUP")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))
                    .tracking(0.5)

                Spacer()

                if order.status == .ready {
                    Text("READY")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.white.opacity(0.1)))
                }
            }

            Text(order.pickupLocationName ?? "Store Location")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04)))
    }
}

// MARK: - Invoice Section

private struct OrderDetailInvoiceSection: View {
    let order: Order
    @Binding var invoice: Invoice?
    @Binding var isLoading: Bool
    @Binding var error: String?
    @Binding var showDetail: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("INVOICE")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))
                    .tracking(0.5)

                Spacer()

                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.7)
                } else if let invoice = invoice {
                    Text(invoice.status.displayName.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                }
            }

            if let invoice = invoice {
                InvoiceTrackingBadges(invoice: invoice)

                Button {
                    showDetail = true
                    Haptics.light()
                } label: {
                    HStack(spacing: 6) {
                        Text("View Details")
                            .font(.system(size: 13, weight: .medium))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .tint(.white)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 8))
            } else if let errorMsg = error {
                Text(errorMsg)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04)))
    }
}

// MARK: - Notes Section

private struct OrderDetailNotesSection: View {
    let notes: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NOTES")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.4))
                .tracking(0.5)

            Text(notes)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04)))
    }
}

// MARK: - Order Action Button

private struct OrderDetailActionButton: View {
    let order: Order
    let store: OrderStore
    @Binding var isPresented: Bool
    @State private var isUpdating = false
    @State private var nextStatus: OrderStatus?
    @State private var actionLabel: String?
    @State private var isLoadingNextStatus = true

    var body: some View {
        Group {
            if isLoadingNextStatus {
                // Loading state
                HStack(spacing: 8) {
                    ProgressView().tint(.white.opacity(0.5)).scaleEffect(0.8)
                    Text("Loading...")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(0.4))
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .glassEffect(.regular, in: .rect(cornerRadius: 12))
            } else if let next = nextStatus, let label = actionLabel {
                Button {
                    Task { await updateStatus(to: next) }
                } label: {
                    HStack(spacing: 8) {
                        if isUpdating {
                            ProgressView().tint(.black).scaleEffect(0.9)
                        }
                        Text(label)
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.roundedRectangle(radius: 12))
                .disabled(isUpdating)
            } else {
                // Completed state
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Complete")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(0.4))
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .glassEffect(.regular, in: .rect(cornerRadius: 12))
            }
        }
        .task {
            await loadNextStatus()
        }
        .onChange(of: order.status) { _, _ in
            Task { await loadNextStatus() }
        }
    }

    private func loadNextStatus() async {
        isLoadingNextStatus = true
        do {
            let result = try await OrderService.getNextOrderStatus(orderId: order.id)
            nextStatus = result.nextStatus
            actionLabel = result.actionLabel
        } catch {
            // Fallback to nil - will show "Complete" state
            nextStatus = nil
            actionLabel = nil
        }
        isLoadingNextStatus = false
    }

    private func updateStatus(to status: OrderStatus) async {
        isUpdating = true
        await store.updateStatus(orderId: order.id, status: status)
        isUpdating = false
        Haptics.success()
    }
}
