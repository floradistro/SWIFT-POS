//
//  QRCodeScanSheet.swift
//  Whale
//
//  Modal shown when scanning a QR code from sale/product labels.
//  Provides contextual actions based on QR type and ownership.
//  External stores scanning see receive/transfer options.
//

import SwiftUI

enum QRScanScreen: Equatable { case main, receive, transfer, reprint, split, success }

// MARK: - Split Option

struct SplitOption: Identifiable {
    let id = UUID()
    let tier: PricingTier
    let count: Int

    var displayLabel: String {
        "\(count)x \(tier.label)"
    }
}

struct QRCodeScanSheet: View {
    let qrCode: ScannedQRCode
    let storeId: UUID
    let onDismiss: () -> Void

    @EnvironmentObject var session: SessionObserver
    @Environment(\.dismiss) var dismiss
    @State var currentScreen: QRScanScreen = .main
    @State var product: Product?
    @State var order: Order?
    @State var isLoading = false
    @State var isPrinting = false
    @State var successMessage = ""
    @State var errorMessage: String?

    // Animation states
    @State var contentOpacity: Double = 1
    @State var successScale: CGFloat = 0.5
    @State var successOpacity: Double = 0
    @State var checkmarkTrimEnd: CGFloat = 0

    // Active transfer info (from inventory_transfers table)
    @State var activeTransfer: InventoryTransfer?

    // Computed properties for transfer info - ATOMIC: Use QR code status as source of truth
    var isQRCodeInTransit: Bool { qrCode.isInTransit }
    var hasPendingTransfer: Bool { isQRCodeInTransit && activeTransfer != nil }
    var pendingTransferSourceName: String? { activeTransfer?.sourceLocationName }
    var pendingTransferDestinationName: String? { activeTransfer?.destinationLocationName }

    // Whether the current location is the destination of the active transfer
    var isAtTransferDestination: Bool {
        guard let transfer = activeTransfer,
              let currentLocationId = session.selectedLocation?.id else { return false }
        return transfer.destinationLocationId == currentLocationId
    }

    // Split package state
    @State var selectedSplitOption: SplitOption?
    @State var splitOptions: [SplitOption] = []

    // Transfer destination state
    @State var availableLocations: [Location] = []
    @State var selectedTransferDestination: Location?

    // Whether this QR's stored location matches current location
    var qrLocationMatchesCurrent: Bool {
        guard let currentLocationId = session.selectedLocation?.id else { return false }
        guard let qrLocationId = qrCode.locationId else {
            return true
        }
        return qrLocationId == currentLocationId
    }

    var isDifferentLocation: Bool {
        !qrLocationMatchesCurrent
    }

    var typeColor: Color {
        switch qrCode.type {
        case "sale": return Color(red: 34/255, green: 197/255, blue: 94/255)
        case "product": return Color(red: 59/255, green: 130/255, blue: 246/255)
        case "bulk": return Color(red: 251/255, green: 146/255, blue: 60/255)
        default: return Color(white: 0.5)
        }
    }

    var typeIcon: String {
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

    var modalHeader: some View {
        HStack(spacing: 12) {
            Button {
                Haptics.light()
                if currentScreen == .main || currentScreen == .success {
                    dismiss(); onDismiss()
                } else {
                    navigateTo(.main)
                }
            } label: {
                Image(systemName: currentScreen == .main || currentScreen == .success ? "xmark" : "chevron.left")
                    .font(Design.Typography.footnote).fontWeight(.semibold)
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(.ultraThinMaterial))
            }
            .buttonStyle(ScaleButtonStyle())

            Spacer()

            VStack(spacing: 3) {
                if currentScreen != .main && currentScreen != .success {
                    Text(qrCode.name)
                        .font(Design.Typography.caption2).fontWeight(.medium)
                        .foregroundStyle(.white.opacity(0.35))
                        .lineLimit(1)
                }
                Text(headerTitle)
                    .font(Design.Typography.headlineRounded).fontWeight(.bold)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .animation(.easeInOut(duration: 0.2), value: currentScreen)

            Spacer()

            Text(qrCode.type.capitalized)
                .font(Design.Typography.caption2).fontWeight(.bold)
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

    var headerTitle: String {
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
    var currentTierQuantity: Double? {
        guard let tierLabel = qrCode.tierLabel else { return nil }
        return parseTierQuantity(tierLabel)
    }

    /// The largest tier quantity for this product (for split calculations when no tier is specified)
    var largestTierQuantity: Double? {
        product?.allTiers.max(by: { $0.quantity < $1.quantity })?.quantity
    }

    /// Whether this QR code can be split (has a tier and product tiers)
    var canSplit: Bool {
        guard !qrCode.isSale else { return false }
        guard let product = product else { return false }
        if let currentQty = currentTierQuantity {
            return product.allTiers.contains { $0.quantity < currentQty }
        }
        return product.allTiers.count >= 2
    }

    // MARK: - Main Content

    @ViewBuilder
    var mainContent: some View {
        // Product info card with gradient accent
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
                        .frame(width: 48, height: 48)
                    Circle()
                        .stroke(typeColor.opacity(0.3), lineWidth: 1)
                        .frame(width: 48, height: 48)
                    Image(systemName: typeIcon)
                        .font(Design.Typography.headline).fontWeight(.semibold)
                        .foregroundStyle(typeColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(product?.name ?? qrCode.name)
                        .font(Design.Typography.callout).fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        if let locationName = qrCode.locationName {
                            Label {
                                Text(locationName)
                                    .font(Design.Typography.caption1).fontWeight(.medium)
                            } icon: {
                                Image(systemName: "location.fill")
                                    .font(Design.Typography.caption2)
                            }
                            .foregroundStyle(.white.opacity(0.45))
                        }

                        if qrCode.totalScans > 0 {
                            Text("\(qrCode.totalScans) scans")
                                .font(Design.Typography.caption2).fontWeight(.semibold)
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
                    if let order = order {
                        detailRow("Order", value: "#\(order.orderNumber)", icon: "number.square.fill")
                    }
                    if let soldAt = qrCode.soldAt {
                        detailRow("Sold", value: formatSoldDate(soldAt), icon: "clock.fill")
                    }
                    if let tierLabel = qrCode.tierLabel {
                        detailRow("Size", value: tierLabel, icon: "scalemass.fill")
                    }
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
                            .font(Design.Typography.callout).fontWeight(.medium)
                            .foregroundStyle(.orange)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("In Transit")
                            .font(Design.Typography.footnote).fontWeight(.semibold)
                            .foregroundStyle(.orange)

                        if let fromLocation = pendingTransferSourceName,
                           let toLocation = pendingTransferDestinationName {
                            Text("\(fromLocation) → \(toLocation)")
                                .font(Design.Typography.caption1)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }

                    Spacer()

                    if let transfer = activeTransfer {
                        Text(transfer.transferNumber)
                            .font(Design.Typography.caption2Mono).fontWeight(.semibold)
                            .foregroundStyle(.orange.opacity(0.8))
                    }
                }
            }
        }

        // Actions - context-aware based on transfer state
        VStack(spacing: 10) {
            if !qrCode.isSale {
                if isQRCodeInTransit {
                    if isAtTransferDestination, let fromLocation = pendingTransferSourceName {
                        actionRow("Receive from \(fromLocation)", icon: "tray.and.arrow.down.fill", color: Color(red: 34/255, green: 197/255, blue: 94/255), isPrimary: true) {
                            navigateTo(.receive)
                        }
                    } else if let toLocation = pendingTransferDestinationName {
                        HStack(spacing: 12) {
                            Image(systemName: "info.circle.fill")
                                .font(Design.Typography.callout)
                                .foregroundStyle(.orange)
                            Text("Scan at \(toLocation) to receive this item")
                                .font(Design.Typography.footnote)
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
                    if canSplit {
                        actionRow("Split Package", icon: "square.split.2x2.fill", color: Color(red: 168/255, green: 85/255, blue: 247/255), isPrimary: true) {
                            prepareSplitOptions()
                            navigateTo(.split)
                        }
                    }

                    actionRow("Transfer Out", icon: "arrow.up.forward.square.fill", color: Color(red: 59/255, green: 130/255, blue: 246/255)) {
                        navigateTo(.transfer)
                    }

                    actionRow("Add to Inventory", icon: "tray.and.arrow.down.fill", color: Color(red: 34/255, green: 197/255, blue: 94/255)) {
                        navigateTo(.receive)
                    }
                }
            }

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

    // MARK: - Helper Views

    var summaryCard: some View {
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
                        .font(Design.Typography.callout).fontWeight(.semibold)
                        .foregroundStyle(typeColor)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(product?.name ?? qrCode.name)
                        .font(Design.Typography.subhead).fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        if let tierLabel = qrCode.tierLabel {
                            Text(tierLabel)
                                .font(Design.Typography.caption2).fontWeight(.medium)
                                .foregroundStyle(typeColor)
                        } else {
                            Text(qrCode.type.capitalized)
                                .font(Design.Typography.caption2).fontWeight(.medium)
                                .foregroundStyle(typeColor)
                        }
                        Text("•")
                            .foregroundStyle(.white.opacity(0.3))
                        Text(qrCode.code.prefix(10) + "...")
                            .font(Design.Typography.caption2Mono)
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
                Spacer()
            }
        }
    }

    func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .font(Design.Typography.footnote).fontWeight(.medium)
                .foregroundStyle(.white)
            Spacer()
            Button { errorMessage = nil } label: {
                Image(systemName: "xmark")
                    .font(Design.Typography.caption1).fontWeight(.bold)
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

    func actionRow(_ title: String, icon: String, color: Color, isPrimary: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.light()
            action()
        } label: {
            HStack(spacing: 14) {
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
                        .font(Design.Typography.subhead).fontWeight(.medium)
                        .foregroundStyle(isPrimary ? .white : color)
                }
                .shadow(color: isPrimary ? color.opacity(0.3) : .clear, radius: 4, y: 2)

                Text(title)
                    .font(Design.Typography.subhead).fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(Design.Typography.caption2).fontWeight(.bold)
                    .foregroundStyle(.white.opacity(0.25))
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.white.opacity(0.1), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(isPrinting || isLoading)
        .accessibilityLabel(title)
    }

    func navigateTo(_ screen: QRScanScreen) {
        withAnimation(.easeOut(duration: 0.15)) {
            contentOpacity = 0
        }

        Task { @MainActor in try? await Task.sleep(for: .seconds(0.15));
            currentScreen = screen

            withAnimation(.easeIn(duration: 0.2)) {
                contentOpacity = 1
            }

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
}
