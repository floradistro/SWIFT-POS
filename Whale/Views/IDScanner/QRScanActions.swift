//
//  QRScanActions.swift
//  Whale
//
//  Action methods and helpers for QRCodeScanSheet:
//  receive, transfer, reprint, split operations, and data loading.
//

import SwiftUI
import os.log

// MARK: - Data Loading

extension QRCodeScanSheet {

    func loadProduct() async {
        guard let productId = qrCode.productId else { return }

        do {
            product = try await ProductService.fetchProduct(productId)
        } catch {
            Log.scanner.error("Failed to load product: \(error.localizedDescription)")
        }
    }

    func loadOrder() async {
        guard let orderId = qrCode.orderId else { return }

        do {
            order = try await OrderService.fetchOrder(orderId: orderId)
        } catch {
            Log.scanner.error("Failed to load order: \(error.localizedDescription)")
        }
    }

    func checkPendingTransfer() async {
        // ATOMIC: Use the QR code's current_transfer_id to look up the active transfer
        // No need to search by product_id - QR code is the source of truth
        guard qrCode.isInTransit, let transferId = qrCode.currentTransferId else {
            Log.scanner.debug("QR code \(qrCode.code) status=\(qrCode.status.displayName), no active transfer")
            return
        }

        let transfer = await QRCodeLookupService.getActiveTransfer(
            qrCodeId: qrCode.id,
            transferId: transferId,
            storeId: storeId
        )

        if let transfer = transfer {
            activeTransfer = transfer
            Log.scanner.info("ATOMIC: Found transfer \(transfer.transferNumber) from \(transfer.sourceLocationName ?? "?") to \(transfer.destinationLocationName ?? "?")")
        } else {
            Log.scanner.warning("QR code has current_transfer_id but transfer not found")
        }
    }

    func loadLocations() async {
        do {
            availableLocations = try await LocationService.fetchActiveLocations(storeId: storeId)
        } catch {
            Log.scanner.error("Failed to load locations: \(error.localizedDescription)")
        }
    }
}

// MARK: - Receive & Transfer Actions

extension QRCodeScanSheet {

    func performReceive() {
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

    func performTransfer() {
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
}

// MARK: - Reprint Action

extension QRCodeScanSheet {

    func reprintLabel() {
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
}

// MARK: - Split Helpers

extension QRCodeScanSheet {

    /// Parse tier label to quantity in grams
    func parseTierQuantity(_ label: String) -> Double? {
        let lowercased = label.lowercased()

        // Handle pounds
        if lowercased.contains("lb") {
            if lowercased.contains("1/4") || lowercased.contains("qp") { return 113.4 }
            if lowercased.contains("1/2") || lowercased.contains("hp") { return 226.8 }
            if lowercased.contains("1 lb") || lowercased == "lb" || lowercased == "1lb" { return 453.6 }
        }

        // Handle ounces
        if lowercased.contains("oz") {
            if lowercased.contains("1/8") { return 3.5 }
            if lowercased.contains("1/4") { return 7.0 }
            if lowercased.contains("1/2") { return 14.0 }
            if lowercased.contains("1 oz") || lowercased == "oz" || lowercased == "1oz" { return 28.0 }
        }

        // Handle grams
        if let number = Double(lowercased.replacingOccurrences(of: "g", with: "").trimmingCharacters(in: .whitespaces)) {
            return number
        }

        return nil
    }

    /// Prepare split options based on current tier and product tiers
    func prepareSplitOptions() {
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
            .sorted { $0.quantity > $1.quantity }

        // Create split options
        splitOptions = smallerTiers.compactMap { tier in
            let count = Int(floor(sourceQty / tier.quantity))
            guard count >= 2 else { return nil }
            return SplitOption(tier: tier, count: count)
        }

        // Pre-select the first option if available
        selectedSplitOption = splitOptions.first
    }

    /// Perform the split - print labels and register new QR codes
    func performSplit() {
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
                    let saleContext = SaleContext(
                        orderId: UUID(),
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

            // Mark original QR code as split
            do {
                try await QRTrackingService.markQRCodeAsSplit(qrCodeId: qrCode.id, childCount: selected.count)
            } catch {
                Log.scanner.error("Failed to update split QR code status: \(error.localizedDescription)")
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

struct AnimatedCheckmark: Shape {
    var trimEnd: CGFloat

    var animatableData: CGFloat {
        get { trimEnd }
        set { trimEnd = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()

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
