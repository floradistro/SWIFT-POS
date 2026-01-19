//
//  QRCodeScanSheet.swift
//  Whale
//
//  Modal shown when scanning a QR code from sale/product labels.
//  Provides contextual actions based on QR type and ownership.
//  External stores scanning see receive/transfer options.
//

import SwiftUI
import Supabase

enum QRScanScreen: Equatable { case main, receive, transfer, reprint, split, success }

// MARK: - Split Option

struct SplitOption: Identifiable {
    let id = UUID()
    let tier: PricingTier
    let count: Int  // How many of this tier you get from the split

    var displayLabel: String {
        "\(count)x \(tier.label)"
    }
}

struct QRCodeScanSheet: View {
    let qrCode: ScannedQRCode
    let storeId: UUID
    let onDismiss: () -> Void

    @EnvironmentObject private var session: SessionObserver
    @Environment(\.dismiss) private var dismiss
    @State private var currentScreen: QRScanScreen = .main
    @State private var product: Product?
    @State private var order: Order?
    @State private var isLoading = false
    @State private var isPrinting = false
    @State private var successMessage = ""
    @State private var errorMessage: String?

    // Animation states
    @State private var contentOpacity: Double = 1
    @State private var successScale: CGFloat = 0.5
    @State private var successOpacity: Double = 0
    @State private var checkmarkTrimEnd: CGFloat = 0

    // Active transfer info (from inventory_transfers table)
    @State private var activeTransfer: InventoryTransfer?

    // Computed properties for transfer info - ATOMIC: Use QR code status as source of truth
    private var isQRCodeInTransit: Bool { qrCode.isInTransit }
    private var hasPendingTransfer: Bool { isQRCodeInTransit && activeTransfer != nil }
    private var pendingTransferSourceName: String? { activeTransfer?.sourceLocationName }
    private var pendingTransferDestinationName: String? { activeTransfer?.destinationLocationName }

    // Whether the current location is the destination of the active transfer
    private var isAtTransferDestination: Bool {
        guard let transfer = activeTransfer,
              let currentLocationId = session.selectedLocation?.id else { return false }
        return transfer.destinationLocationId == currentLocationId
    }

    // Split package state
    @State private var selectedSplitOption: SplitOption?
    @State private var splitOptions: [SplitOption] = []

    // Transfer destination state
    @State private var availableLocations: [Location] = []
    @State private var selectedTransferDestination: Location?

    // Whether this QR's stored location matches current location
    // Note: This is based on the QR code's location_id field, which may be nil for legacy codes
    private var qrLocationMatchesCurrent: Bool {
        guard let currentLocationId = session.selectedLocation?.id else { return false }
        guard let qrLocationId = qrCode.locationId else {
            // QR has no location - assume current for legacy codes (unless there's a pending transfer)
            return true
        }
        return qrLocationId == currentLocationId
    }

    // Whether this QR is at a different location than current
    private var isDifferentLocation: Bool {
        !qrLocationMatchesCurrent
    }

    private var typeColor: Color {
        switch qrCode.type {
        case "sale": return Color(red: 34/255, green: 197/255, blue: 94/255) // Emerald green
        case "product": return Color(red: 59/255, green: 130/255, blue: 246/255) // Blue
        case "bulk": return Color(red: 251/255, green: 146/255, blue: 60/255) // Orange
        default: return Color(white: 0.5)
        }
    }

    private var typeIcon: String {
        switch qrCode.type {
        case "sale": return "tag.fill"
        case "product": return "leaf.fill"
        case "bulk": return "shippingbox.fill"
        default: return "qrcode"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    if let error = errorMessage {
                        errorBanner(error)
                    }

                    VStack(spacing: 12) {
                        switch currentScreen {
                        case .main: mainContent
                        case .receive: receiveContent
                        case .transfer: transferContent
                        case .reprint: reprintContent
                        case .split: splitContent
                        case .success: successContent
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                    .opacity(contentOpacity)
                    .contentShape(Rectangle())
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .navigationTitle(qrCode.type.capitalized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if currentScreen == .main || currentScreen == .success {
                        Button("Done") {
                            dismiss()
                            onDismiss()
                        }
                    } else {
                        Button("Back") {
                            withAnimation(.spring(response: 0.3)) { currentScreen = .main }
                        }
                    }
                }
            }
        }
        .interactiveDismissDisabled(isPrinting || isLoading)
        .task {
            await loadProduct()
            await loadLocations()
            if qrCode.isSale, qrCode.orderId != nil {
                await loadOrder()
            }
            await checkPendingTransfer()
            await QRCodeLookupService.recordScan(qrCodeId: qrCode.id, storeId: storeId)
        }
    }

    // MARK: - Header

    private var modalHeader: some View {
        HStack(spacing: 12) {
            // Back/Close button
            Button {
                Haptics.light()
                if currentScreen == .main || currentScreen == .success {
                    dismiss(); onDismiss()
                } else {
                    navigateTo(.main)
                }
            } label: {
                Image(systemName: currentScreen == .main || currentScreen == .success ? "xmark" : "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(.ultraThinMaterial))
            }
            .buttonStyle(ScaleButtonStyle())

            Spacer()

            // Title
            VStack(spacing: 3) {
                if currentScreen != .main && currentScreen != .success {
                    Text(qrCode.name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.35))
                        .lineLimit(1)
                }
                Text(headerTitle)
                    .font(.system(size: currentScreen == .main ? 18 : 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .animation(.easeInOut(duration: 0.2), value: currentScreen)

            Spacer()

            // Type badge with subtle gradient
            Text(qrCode.type.capitalized)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [typeColor, typeColor.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .shadow(color: typeColor.opacity(0.3), radius: 4, y: 2)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 14)
    }

    private var headerTitle: String {
        switch currentScreen {
        case .main: return qrCode.name
        case .receive: return "Receive"
        case .transfer: return "Transfer Out"
        case .reprint: return "Reprint Label"
        case .split: return "Split Package"
        case .success: return "Success"
        }
    }

    /// Current tier quantity in grams (from QR code or product default)
    private var currentTierQuantity: Double? {
        // Parse tier from label like "1 lb", "1/4 lb", "1 oz", "3.5g"
        guard let tierLabel = qrCode.tierLabel else { return nil }
        return parseTierQuantity(tierLabel)
    }

    /// The largest tier quantity for this product (for split calculations when no tier is specified)
    private var largestTierQuantity: Double? {
        product?.allTiers.max(by: { $0.quantity < $1.quantity })?.quantity
    }

    /// Whether this QR code can be split (has a tier and product tiers)
    private var canSplit: Bool {
        guard !qrCode.isSale else { return false }  // Can't split sold items
        guard let product = product else { return false }  // Need product info
        // If we have a tier label, check if there are smaller tiers
        if let currentQty = currentTierQuantity {
            return product.allTiers.contains { $0.quantity < currentQty }
        }
        // If no tier label, show split if product has multiple tiers (user can select from largest)
        return product.allTiers.count >= 2
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        // Product info card with gradient accent
        ModalSection {
            HStack(spacing: 14) {
                // Type icon with gradient background
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [typeColor.opacity(0.25), typeColor.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)
                    Circle()
                        .stroke(typeColor.opacity(0.3), lineWidth: 1)
                        .frame(width: 48, height: 48)
                    Image(systemName: typeIcon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(typeColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(product?.name ?? qrCode.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        if let locationName = qrCode.locationName {
                            Label {
                                Text(locationName)
                                    .font(.system(size: 12, weight: .medium))
                            } icon: {
                                Image(systemName: "location.fill")
                                    .font(.system(size: 9))
                            }
                            .foregroundStyle(.white.opacity(0.45))
                        }

                        if qrCode.totalScans > 0 {
                            Text("\(qrCode.totalScans) scans")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(typeColor.opacity(0.9))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(typeColor.opacity(0.15), in: Capsule())
                        }
                    }
                }

                Spacer()

                if let url = product?.iconUrl {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.white.opacity(0.08))
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(.white.opacity(0.1), lineWidth: 0.5)
                    )
                }
            }
        }

        // Sale details section (only for sale QR codes)
        if qrCode.isSale {
            ModalSection {
                VStack(spacing: 12) {
                    // Order info
                    if let order = order {
                        detailRow("Order", value: "#\(order.orderNumber)", icon: "number.square.fill")
                    }

                    // Sold date
                    if let soldAt = qrCode.soldAt {
                        detailRow("Sold", value: formatSoldDate(soldAt), icon: "clock.fill")
                    }

                    // Tier/weight
                    if let tierLabel = qrCode.tierLabel {
                        detailRow("Size", value: tierLabel, icon: "scalemass.fill")
                    }

                    // Sold location
                    if let locationName = qrCode.locationName {
                        detailRow("Location", value: locationName, icon: "building.2.fill")
                    }
                }
            }
        }

        // Status indicator for in-transit items
        if isQRCodeInTransit {
            ModalSection {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.orange.opacity(0.2))
                            .frame(width: 40, height: 40)
                        Image(systemName: "shippingbox.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.orange)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("In Transit")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.orange)

                        if let fromLocation = pendingTransferSourceName,
                           let toLocation = pendingTransferDestinationName {
                            Text("\(fromLocation) → \(toLocation)")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }

                    Spacer()

                    if let transfer = activeTransfer {
                        Text(transfer.transferNumber)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.orange.opacity(0.8))
                    }
                }
            }
        }

        // Actions - context-aware based on transfer state
        // ATOMIC Logic:
        // - If QR is in_transit AND we're at destination → show "Receive" prominently
        // - If QR is in_transit AND we're NOT at destination → show info only (can't transfer or split)
        // - If QR is available → show Split/Transfer Out
        VStack(spacing: 10) {
            if !qrCode.isSale {
                if isQRCodeInTransit {
                    // Item is in transit
                    if isAtTransferDestination, let fromLocation = pendingTransferSourceName {
                        // We're at the destination - show receive
                        actionRow("Receive from \(fromLocation)", icon: "tray.and.arrow.down.fill", color: Color(red: 34/255, green: 197/255, blue: 94/255), isPrimary: true) {
                            navigateTo(.receive)
                        }
                    } else if let toLocation = pendingTransferDestinationName {
                        // We're NOT at destination - show where to receive
                        HStack(spacing: 12) {
                            Image(systemName: "info.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.orange)
                            Text("Scan at \(toLocation) to receive this item")
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(.orange.opacity(0.1))
                        )
                    }
                } else {
                    // Item is available - show standard actions
                    // Split Package - for bulk/product types with a tier that can be split
                    if canSplit {
                        actionRow("Split Package", icon: "square.split.2x2.fill", color: Color(red: 168/255, green: 85/255, blue: 247/255), isPrimary: true) {
                            prepareSplitOptions()
                            navigateTo(.split)
                        }
                    }

                    // Transfer Out - available when item is at this location
                    actionRow("Transfer Out", icon: "arrow.up.forward.square.fill", color: Color(red: 59/255, green: 130/255, blue: 246/255)) {
                        navigateTo(.transfer)
                    }

                    // Add to Inventory - for initial receiving
                    actionRow("Add to Inventory", icon: "tray.and.arrow.down.fill", color: Color(red: 34/255, green: 197/255, blue: 94/255)) {
                        navigateTo(.receive)
                    }
                }
            }

            // Same store - can reprint
            if qrCode.storeId == storeId {
                actionRow("Reprint Label", icon: "printer.fill", color: Color(white: 0.55)) {
                    navigateTo(.reprint)
                }
            }

            actionRow("View Lab Results", icon: "doc.text.fill", color: Color(red: 251/255, green: 146/255, blue: 60/255)) {
                if let url = URL(string: "https://floradistro.com/qr/\(qrCode.code)") {
                    UIApplication.shared.open(url)
                }
            }
        }
    }

    // MARK: - Sale Detail Helpers

    private func detailRow(_ label: String, value: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 20)

            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.5))

            Spacer()

            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
        }
    }

    private func formatSoldDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    // MARK: - Receive Content

    @ViewBuilder
    private var receiveContent: some View {
        summaryCard

        // Determine source location and whether to show transfer visual
        let currentLocationName = session.selectedLocation?.name ?? ""
        let fromLocation = pendingTransferSourceName ?? qrCode.locationName ?? "External"
        let sourceIsDifferent = pendingTransferSourceName != nil &&
            fromLocation.lowercased() != currentLocationName.lowercased()
        let greenColor = Color(red: 34/255, green: 197/255, blue: 94/255)

        // Only show transfer visual if source is different from current location
        if sourceIsDifferent {
            ModalSection {
                HStack(spacing: 0) {
                    // From location
                    VStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(greenColor.opacity(0.15))
                                .frame(width: 36, height: 36)
                            Image(systemName: "building.2.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(greenColor.opacity(0.7))
                        }
                        Text(fromLocation)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)

                    // Arrow
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(greenColor)
                        Text("Transfer")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(greenColor.opacity(0.6))
                    }
                    .frame(width: 60)

                    // To location (current)
                    VStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [greenColor, greenColor.opacity(0.8)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 36, height: 36)
                                .shadow(color: greenColor.opacity(0.4), radius: 6, y: 2)
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        Text(session.selectedLocation?.name ?? "Here")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 8)
            }

            ModalActionButton("Receive from \(fromLocation)", icon: "tray.and.arrow.down.fill", isLoading: isLoading, style: .success) {
                performReceive()
            }
        } else {
            // Item is already at this location - show simple receive UI
            ModalSection {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [greenColor, greenColor.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 44, height: 44)
                            .shadow(color: greenColor.opacity(0.4), radius: 6, y: 2)
                        Image(systemName: "tray.and.arrow.down.fill")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add to Inventory")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(session.selectedLocation?.name ?? "Current Location")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.6))
                    }

                    Spacer()
                }
                .padding(.vertical, 4)
            }

            ModalActionButton("Receive Into Inventory", icon: "tray.and.arrow.down.fill", isLoading: isLoading, style: .success) {
                performReceive()
            }
        }
    }

    // MARK: - Transfer Content

    /// Locations available for transfer (excludes current location)
    private var transferDestinations: [Location] {
        availableLocations.filter { $0.id != session.selectedLocation?.id }
    }

    @ViewBuilder
    private var transferContent: some View {
        summaryCard

        let blueColor = Color(red: 59/255, green: 130/255, blue: 246/255)

        // Transfer flow visualization
        ModalSection {
            HStack(spacing: 0) {
                // From location (current)
                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [blueColor, blueColor.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 36, height: 36)
                            .shadow(color: blueColor.opacity(0.4), radius: 6, y: 2)
                        Image(systemName: "building.2.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    Text(session.selectedLocation?.name ?? "Here")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)

                // Arrow
                VStack(spacing: 4) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(blueColor)
                    Text("Transfer")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(blueColor.opacity(0.6))
                }
                .frame(width: 60)

                // To location (destination) - shows selected or placeholder
                VStack(spacing: 6) {
                    ZStack {
                        if selectedTransferDestination != nil {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [blueColor, blueColor.opacity(0.8)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 36, height: 36)
                                .shadow(color: blueColor.opacity(0.4), radius: 6, y: 2)
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                        } else {
                            Circle()
                                .fill(blueColor.opacity(0.15))
                                .frame(width: 36, height: 36)
                            Circle()
                                .stroke(blueColor.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                                .frame(width: 36, height: 36)
                            Image(systemName: "questionmark")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(blueColor.opacity(0.6))
                        }
                    }
                    Text(selectedTransferDestination?.name ?? "Select")
                        .font(.system(size: 11, weight: selectedTransferDestination != nil ? .semibold : .medium))
                        .foregroundStyle(selectedTransferDestination != nil ? .white : .white.opacity(0.5))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 8)
        }

        // Location picker - scrollable for many locations
        ModalSection {
            VStack(spacing: 8) {
                HStack {
                    Text("Select Destination")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                }

                if transferDestinations.isEmpty {
                    Text("No other locations available")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(.vertical, 8)
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(transferDestinations) { location in
                                transferLocationRow(location, color: blueColor)
                            }
                        }
                    }
                    .frame(maxHeight: 220)  // Limit height to prevent overflow
                }
            }
        }

        // Transfer button
        if let destination = selectedTransferDestination {
            ModalActionButton("Transfer to \(destination.name)", icon: "arrow.up.forward.square.fill", isLoading: isLoading) {
                performTransfer()
            }
        } else {
            // Disabled state
            HStack(spacing: 10) {
                Image(systemName: "arrow.up.forward.square.fill")
                    .font(.system(size: 17, weight: .semibold))
                Text("Select a destination")
                    .font(.system(size: 17, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(0.3))
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.ultraThinMaterial))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.1), lineWidth: 0.5))
        }
    }

    @ViewBuilder
    private func transferLocationRow(_ location: Location, color: Color) -> some View {
        let isSelected = selectedTransferDestination?.id == location.id

        Button {
            Haptics.light()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedTransferDestination = location
            }
        } label: {
            HStack(spacing: 12) {
                // Selection indicator
                ZStack {
                    Circle()
                        .stroke(isSelected ? color : .white.opacity(0.2), lineWidth: 2)
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle()
                            .fill(color)
                            .frame(width: 14, height: 14)
                    }
                }

                // Location icon
                Image(systemName: location.isWarehouse ? "shippingbox.fill" : "building.2.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? color : .white.opacity(0.5))
                    .frame(width: 20)

                // Location name
                Text(location.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)

                Spacer()

                // Location type badge
                Text(location.type.capitalized)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isSelected ? color : .white.opacity(0.4))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(.ultraThinMaterial))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.ultraThinMaterial))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(isSelected ? color.opacity(0.3) : .white.opacity(0.1), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Reprint Content

    @ViewBuilder
    private var reprintContent: some View {
        summaryCard

        ModalActionButton("Print Label", icon: "printer.fill", isLoading: isPrinting) {
            reprintLabel()
        }
    }

    // MARK: - Split Content

    @ViewBuilder
    private var splitContent: some View {
        let purpleColor = Color(red: 168/255, green: 85/255, blue: 247/255)

        // Current package info
        summaryCard

        // Split visualization
        ModalSection {
            VStack(spacing: 16) {
                // Current tier at top
                HStack(spacing: 0) {
                    VStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [purpleColor, purpleColor.opacity(0.8)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 44, height: 44)
                                .shadow(color: purpleColor.opacity(0.4), radius: 6, y: 2)
                            Image(systemName: "shippingbox.fill")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(.white)
                        }
                        Text(qrCode.tierLabel ?? "Package")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }

                // Arrow down
                Image(systemName: "arrow.down")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(purpleColor)

                // Split options
                if splitOptions.isEmpty {
                    Text("No split options available")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 8) {
                        ForEach(splitOptions) { option in
                            splitOptionRow(option, color: purpleColor)
                        }
                    }
                }
            }
            .padding(.vertical, 8)
        }

        // Split button
        if let selected = selectedSplitOption {
            Button {
                Haptics.medium()
                performSplit()
            } label: {
                HStack(spacing: 10) {
                    if isPrinting {
                        ProgressView()
                            .tint(.black)
                            .scaleEffect(0.9)
                    } else {
                        Image(systemName: "square.split.2x2.fill")
                            .font(.system(size: 17, weight: .semibold))
                        Text("Split into \(selected.displayLabel)")
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .contentShape(RoundedRectangle(cornerRadius: 16))
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isPrinting)
        } else {
            // Disabled state
            HStack(spacing: 10) {
                Image(systemName: "square.split.2x2.fill")
                    .font(.system(size: 17, weight: .semibold))
                Text("Select a split option")
                    .font(.system(size: 17, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(0.3))
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.ultraThinMaterial))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.1), lineWidth: 0.5))
        }
    }

    @ViewBuilder
    private func splitOptionRow(_ option: SplitOption, color: Color) -> some View {
        let isSelected = selectedSplitOption?.id == option.id

        Button {
            Haptics.light()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedSplitOption = option
            }
        } label: {
            HStack(spacing: 12) {
                // Selection indicator
                ZStack {
                    Circle()
                        .stroke(isSelected ? color : .white.opacity(0.2), lineWidth: 2)
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle()
                            .fill(color)
                            .frame(width: 14, height: 14)
                    }
                }

                // Count badge
                Text("\(option.count)x")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(isSelected ? color : .white.opacity(0.7))
                    .frame(width: 36)

                // Tier label
                Text(option.tier.label)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)

                Spacer()

                // Small icons showing the split
                HStack(spacing: 3) {
                    ForEach(0..<min(option.count, 6), id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(isSelected ? color.opacity(0.6) : .white.opacity(0.15))
                            .frame(width: 12, height: 12)
                    }
                    if option.count > 6 {
                        Text("+\(option.count - 6)")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.ultraThinMaterial))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(isSelected ? color.opacity(0.3) : .white.opacity(0.1), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Success Content

    @ViewBuilder
    private var successContent: some View {
        VStack(spacing: 20) {
            // Animated checkmark circle
            ZStack {
                // Outer glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(red: 34/255, green: 197/255, blue: 94/255).opacity(0.3), .clear],
                            center: .center,
                            startRadius: 20,
                            endRadius: 60
                        )
                    )
                    .frame(width: 100, height: 100)

                // Background circle
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 34/255, green: 197/255, blue: 94/255),
                                Color(red: 22/255, green: 163/255, blue: 74/255)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 64, height: 64)
                    .shadow(color: Color(red: 34/255, green: 197/255, blue: 94/255).opacity(0.4), radius: 12, y: 4)

                // Animated checkmark path
                AnimatedCheckmark(trimEnd: checkmarkTrimEnd)
                    .stroke(.white, style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                    .frame(width: 28, height: 28)
            }
            .scaleEffect(successScale)
            .opacity(successOpacity)

            VStack(spacing: 6) {
                Text("Success")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text(successMessage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
            .opacity(successOpacity)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)

        // Done button
        Button {
            Haptics.medium()
            dismiss(); onDismiss()
        } label: {
            Text("Done")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .contentShape(RoundedRectangle(cornerRadius: 14))
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helper Views

    private var summaryCard: some View {
        ModalSection {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [typeColor.opacity(0.25), typeColor.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                    Circle()
                        .stroke(typeColor.opacity(0.3), lineWidth: 1)
                        .frame(width: 44, height: 44)
                    Image(systemName: typeIcon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(typeColor)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(product?.name ?? qrCode.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        if let tierLabel = qrCode.tierLabel {
                            Text(tierLabel)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(typeColor)
                        } else {
                            Text(qrCode.type.capitalized)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(typeColor)
                        }
                        Text("•")
                            .foregroundStyle(.white.opacity(0.3))
                        Text(qrCode.code.prefix(10) + "...")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
                Spacer()
            }
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
            Spacer()
            Button { errorMessage = nil } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
                    .background(Circle().fill(.ultraThinMaterial))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.white.opacity(0.1), lineWidth: 0.5))
        .padding(.horizontal, 20)
    }

    private func actionRow(_ title: String, icon: String, color: Color, isPrimary: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.light()
            action()
        } label: {
            HStack(spacing: 14) {
                // Icon with refined styling
                ZStack {
                    Circle()
                        .fill(
                            isPrimary
                                ? LinearGradient(colors: [color, color.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                : LinearGradient(colors: [color.opacity(0.2), color.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 38, height: 38)
                    if !isPrimary {
                        Circle()
                            .stroke(color.opacity(0.25), lineWidth: 1)
                            .frame(width: 38, height: 38)
                    }
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(isPrimary ? .white : color)
                }
                .shadow(color: isPrimary ? color.opacity(0.3) : .clear, radius: 4, y: 2)

                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.25))
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())  // Make entire area tappable
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.white.opacity(0.1), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)  // Use plain style to avoid interference
        .disabled(isPrinting || isLoading)
    }

    private func navigateTo(_ screen: QRScanScreen) {
        // Animate content out, then in
        withAnimation(.easeOut(duration: 0.15)) {
            contentOpacity = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            currentScreen = screen

            withAnimation(.easeIn(duration: 0.2)) {
                contentOpacity = 1
            }

            // If navigating to success, trigger the checkmark animation
            if screen == .success {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.1)) {
                    successScale = 1
                    successOpacity = 1
                }
                withAnimation(.easeOut(duration: 0.5).delay(0.3)) {
                    checkmarkTrimEnd = 1
                }
            }
        }
    }

    // MARK: - Actions

    private func performReceive() {
        guard let locationId = session.selectedLocation?.id else {
            errorMessage = "No location selected"
            return
        }
        isLoading = true

        Task {
            do {
                // If there's an active transfer, complete it using the proper system
                if let transfer = activeTransfer {
                    try await QRCodeLookupService.completeTransfer(
                        transferId: transfer.id,
                        storeId: storeId,
                        locationId: locationId,
                        userId: SessionObserver.shared.userId,
                        qrCodeId: qrCode.id
                    )

                    await MainActor.run {
                        isLoading = false
                        Haptics.success()
                        successMessage = "Transfer \(transfer.transferNumber) completed at \(session.selectedLocation?.name ?? "location")"
                        navigateTo(.success)
                    }
                } else {
                    // No active transfer - just record the receive operation and update QR code location
                    try await QRCodeLookupService.recordOperationScan(
                        qrCodeId: qrCode.id,
                        storeId: storeId,
                        operation: "receive",
                        locationId: locationId,
                        notes: nil
                    )

                    await MainActor.run {
                        isLoading = false
                        Haptics.success()
                        successMessage = "Received at \(session.selectedLocation?.name ?? "location")"
                        navigateTo(.success)
                    }
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func performTransfer() {
        guard let destination = selectedTransferDestination else {
            errorMessage = "No destination selected"
            return
        }
        guard let sourceLocationId = session.selectedLocation?.id ?? qrCode.locationId else {
            errorMessage = "No source location available"
            return
        }
        isLoading = true

        Task {
            do {
                // Create a proper transfer using the inventory_transfers system
                let transfer = try await QRCodeLookupService.createTransfer(
                    qrCode: qrCode,
                    storeId: storeId,
                    sourceLocationId: sourceLocationId,
                    destinationLocationId: destination.id,
                    userId: SessionObserver.shared.userId
                )

                await MainActor.run {
                    isLoading = false
                    Haptics.success()
                    successMessage = "Transfer \(transfer.transferNumber) created. Scan at \(destination.name) to receive."
                    navigateTo(.success)
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func reprintLabel() {
        isPrinting = true

        Task {
            let labelProduct = product ?? Product(id: qrCode.productId ?? UUID(), name: qrCode.name, storeId: storeId)

            let config = LabelConfig(
                storeId: session.store?.id,
                locationId: session.selectedLocation?.id,
                locationName: session.selectedLocation?.name ?? qrCode.locationName ?? "Licensed Dispensary",
                distributorLicense: session.store?.distributorLicenseNumber,
                storeLogoUrl: session.store?.fullLogoUrl,
                brandLogoFallback: String(session.store?.businessName?.prefix(1) ?? "F")
            )

            let _ = await LabelPrintService.printLabels([labelProduct], config: config)

            await MainActor.run {
                isPrinting = false
                Haptics.success()
                successMessage = "Label sent to printer"
                navigateTo(.success)
            }
        }
    }

    private func loadProduct() async {
        guard let productId = qrCode.productId else { return }

        do {
            let response = try await supabase
                .from("products")
                .select()
                .eq("id", value: productId.uuidString.lowercased())
                .limit(1)
                .execute()

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let products = try decoder.decode([Product].self, from: response.data)
            product = products.first
        } catch {
            print("Failed to load product: \(error.localizedDescription)")
        }
    }

    private func loadOrder() async {
        guard let orderId = qrCode.orderId else { return }

        do {
            let response = try await supabase
                .from("orders")
                .select()
                .eq("id", value: orderId.uuidString.lowercased())
                .limit(1)
                .execute()

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let orders = try decoder.decode([Order].self, from: response.data)
            order = orders.first
        } catch {
            print("Failed to load order: \(error.localizedDescription)")
        }
    }

    private func checkPendingTransfer() async {
        // ATOMIC: Use the QR code's current_transfer_id to look up the active transfer
        // No need to search by product_id - QR code is the source of truth
        guard qrCode.isInTransit, let transferId = qrCode.currentTransferId else {
            print("📦 QR code \(qrCode.code) status=\(qrCode.status.displayName), no active transfer")
            return
        }

        let transfer = await QRCodeLookupService.getActiveTransfer(
            qrCodeId: qrCode.id,
            transferId: transferId,
            storeId: storeId
        )

        if let transfer = transfer {
            activeTransfer = transfer
            print("📦 ATOMIC: Found transfer \(transfer.transferNumber) from \(transfer.sourceLocationName ?? "?") to \(transfer.destinationLocationName ?? "?")")
        } else {
            print("📦 Warning: QR code has current_transfer_id but transfer not found")
        }
    }

    private func loadLocations() async {
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let response = try await supabase
                .from("locations")
                .select()
                .eq("store_id", value: storeId.uuidString)
                .eq("is_active", value: true)
                .order("name")
                .execute()

            let locations = try decoder.decode([Location].self, from: response.data)
            availableLocations = locations
        } catch {
            print("Failed to load locations: \(error.localizedDescription)")
        }
    }

    // MARK: - Split Helpers

    /// Parse tier label to quantity in grams
    private func parseTierQuantity(_ label: String) -> Double? {
        let lowercased = label.lowercased()

        // Handle pounds
        if lowercased.contains("lb") {
            if lowercased.contains("1/4") || lowercased.contains("qp") { return 113.4 }  // 1/4 lb
            if lowercased.contains("1/2") || lowercased.contains("hp") { return 226.8 }  // 1/2 lb
            if lowercased.contains("1 lb") || lowercased == "lb" || lowercased == "1lb" { return 453.6 }  // 1 lb
        }

        // Handle ounces
        if lowercased.contains("oz") {
            if lowercased.contains("1/8") { return 3.5 }   // 1/8 oz
            if lowercased.contains("1/4") { return 7.0 }   // 1/4 oz
            if lowercased.contains("1/2") { return 14.0 }  // 1/2 oz
            if lowercased.contains("1 oz") || lowercased == "oz" || lowercased == "1oz" { return 28.0 }  // 1 oz
        }

        // Handle grams
        if let number = Double(lowercased.replacingOccurrences(of: "g", with: "").trimmingCharacters(in: .whitespaces)) {
            return number
        }

        return nil
    }

    /// Prepare split options based on current tier and product tiers
    private func prepareSplitOptions() {
        guard let product = product else {
            splitOptions = []
            return
        }

        // Use current tier quantity if available, otherwise use largest tier
        let sourceQty = currentTierQuantity ?? largestTierQuantity ?? 0
        guard sourceQty > 0 else {
            splitOptions = []
            return
        }

        // Get all smaller tiers
        let smallerTiers = product.allTiers
            .filter { $0.quantity < sourceQty && $0.quantity > 0 }
            .sorted { $0.quantity > $1.quantity }  // Largest to smallest

        // Create split options
        splitOptions = smallerTiers.compactMap { tier in
            let count = Int(floor(sourceQty / tier.quantity))
            guard count >= 2 else { return nil }  // Only show if we can make at least 2
            return SplitOption(tier: tier, count: count)
        }

        // Pre-select the first option if available
        selectedSplitOption = splitOptions.first
    }

    /// Perform the split - print labels and register new QR codes
    private func performSplit() {
        guard let selected = selectedSplitOption,
              let product = product else { return }

        isPrinting = true

        Task {
            // Create products array for printing (one per split unit)
            var printProducts: [Product] = []
            var saleCodes: [String] = []
            var tierLabels: [String?] = []

            for _ in 0..<selected.count {
                printProducts.append(product)
                let (_, code) = QRTrackingService.saleTrackingURL()
                saleCodes.append(code)
                tierLabels.append(selected.tier.label)
            }

            // Fetch store logo
            var storeLogoImage: UIImage?
            if let logoUrl = session.store?.fullLogoUrl {
                if let (data, _) = try? await URLSession.shared.data(from: logoUrl) {
                    storeLogoImage = UIImage(data: data)
                }
            }

            // Register all QR codes
            if let storeId = session.store?.id {
                for (index, code) in saleCodes.enumerated() {
                    // Create a minimal sale context for inventory tracking
                    let saleContext = SaleContext(
                        orderId: UUID(),  // Generate new ID for split operation
                        customerId: nil,
                        staffId: nil,
                        locationId: session.selectedLocation?.id,
                        locationName: session.selectedLocation?.name,
                        soldAt: Date(),
                        unitPrice: nil,
                        orderType: nil,
                        printSource: .fulfillment
                    )

                    await QRTrackingService.registerSaleItemWithCode(
                        code: code,
                        product: product,
                        storeId: storeId,
                        saleContext: saleContext,
                        quantityIndex: index + 1,
                        tierLabel: selected.tier.label,
                        storeLogoUrl: session.store?.fullLogoUrl
                    )
                }
            }

            // Prepare label config
            let config = LabelConfig(
                storeId: session.store?.id,
                locationId: session.selectedLocation?.id,
                locationName: session.selectedLocation?.name ?? "Licensed Dispensary",
                distributorLicense: session.store?.distributorLicenseNumber,
                storeLogoUrl: session.store?.fullLogoUrl,
                brandLogoFallback: String(session.store?.businessName?.prefix(1) ?? "F"),
                weightTier: selected.tier.label,
                storeLogoImage: storeLogoImage
            )

            // Prefetch product images
            let imageCache = await LabelRenderer.prefetchImages(for: printProducts)
            let renderer = LabelRenderer(
                products: printProducts,
                startPosition: 0,
                config: config,
                sealedDate: Date(),
                saleCodes: saleCodes,
                tierLabels: tierLabels
            )
            renderer.setImageCache(imageCache)

            // Print labels
            let settings = LabelPrinterSettings.shared
            if let printerUrl = settings.printerUrl {
                let _ = await LabelPrintService.printDirect(renderer: renderer, to: printerUrl, jobName: "Split Labels")
            } else {
                let _ = await LabelPrintService.printLabels(printProducts, config: config)
            }

            // Mark original QR code as split (set status, keep is_active for lookup)
            do {
                struct SplitUpdate: Encodable {
                    let status: String
                    let child_count: Int
                }
                try await supabase
                    .from("qr_codes")
                    .update(SplitUpdate(status: "split", child_count: selected.count))
                    .eq("id", value: qrCode.id.uuidString)
                    .execute()
            } catch {
                // Non-critical - log but don't fail
                print("Failed to update split QR code status: \(error.localizedDescription)")
            }

            await MainActor.run {
                isPrinting = false
                Haptics.success()
                successMessage = "Split into \(selected.displayLabel) - labels printing"
                navigateTo(.success)
            }
        }
    }
}

// MARK: - Animated Checkmark Shape

private struct AnimatedCheckmark: Shape {
    var trimEnd: CGFloat

    var animatableData: CGFloat {
        get { trimEnd }
        set { trimEnd = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()

        // Standard checkmark proportions
        let startX = rect.width * 0.2
        let startY = rect.height * 0.5
        let midX = rect.width * 0.4
        let midY = rect.height * 0.7
        let endX = rect.width * 0.8
        let endY = rect.height * 0.3

        path.move(to: CGPoint(x: startX, y: startY))
        path.addLine(to: CGPoint(x: midX, y: midY))
        path.addLine(to: CGPoint(x: endX, y: endY))

        return path.trimmedPath(from: 0, to: trimEnd)
    }
}
