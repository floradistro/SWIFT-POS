//  LabelPrintService.swift - Avery 5163 (2×4") label printing
//
//  Label rendering types are in LabelRenderer.swift

import Foundation
import UIKit
import SwiftUI
import Combine
import os.log

enum LabelPrintService {

    @MainActor
    static func printLabels(
        _ products: [Product],
        startPosition: Int? = nil,
        config: LabelConfig = .default,
        sealedDate: Date = Date()
    ) async -> Bool {
        // Use saved start position from settings if not explicitly provided
        let effectiveStartPosition = startPosition ?? LabelPrinterSettings.shared.startPosition

        if startPosition == nil {
            Log.label.debug("printLabels: Using saved position \(effectiveStartPosition + 1) (not explicitly provided)")
        } else {
            Log.label.debug("printLabels: Using explicit position \(effectiveStartPosition + 1)")
        }

        Log.ui.info("Printing \(products.count) labels starting at position \(effectiveStartPosition + 1)")

        // Register QR codes with location for transfer tracking
        if let storeId = config.storeId {
            let locationId = config.locationId
            let locationName = config.locationName
            Task.detached(priority: .utility) {
                await QRTrackingService.registerProducts(products, storeId: storeId, locationId: locationId, locationName: locationName, storeLogoUrl: config.storeLogoUrl)
            }
        }

        let imageCache = await LabelRenderer.prefetchImages(for: products)
        Log.label.debug("Prefetched \(imageCache.count) product images")
        let renderer = LabelRenderer(products: products, startPosition: effectiveStartPosition, config: config, sealedDate: sealedDate)
        renderer.setImageCache(imageCache)

        let printController = UIPrintInteractionController.shared
        let printInfo = UIPrintInfo(dictionary: nil)
        printInfo.jobName = "Product Labels"
        printInfo.outputType = .general
        printInfo.orientation = .portrait
        printInfo.duplex = .none

        printController.printInfo = printInfo
        printController.printPageRenderer = renderer

        return await withCheckedContinuation { continuation in
            // UIPrintInteractionController can call completion multiple times on errors
            // Use flag to ensure we only resume continuation once
            var hasResumed = false
            let resumeOnce: (Bool) -> Void = { completed in
                guard !hasResumed else {
                    Log.ui.warning("printWithPreview: ignoring duplicate completion callback")
                    return
                }
                hasResumed = true
                continuation.resume(returning: completed)
            }

            printController.present(animated: true) { _, completed, error in
                if let error = error {
                    Log.ui.error("Label print error: \(error.localizedDescription)")
                }
                resumeOnce(completed)
            }
        }
    }

    @MainActor
    static func printOrderLabels(_ orders: [Order], config: LabelConfig = .default) async -> Bool {
        let startPos = LabelPrinterSettings.shared.startPosition
        Log.label.debug("printOrderLabels: Using saved start position \(startPos + 1)")

        // Use optimized RPC fetch if printing single order
        if orders.count == 1, let order = orders.first {
            return await printOrderLabelsOptimized(orderId: order.id, config: config, startPosition: startPos)
        }

        // Legacy multi-order path (less common)
        return await printOrderLabelsLegacy(orders, config: config, startPosition: startPos)
    }

    /// Optimized single-order print using RPC (Apple standard: single database round trip)
    @MainActor
    private static func printOrderLabelsOptimized(orderId: UUID, config: LabelConfig, startPosition: Int) async -> Bool {
        Log.label.debug("Using optimized RPC fetch for order \(orderId)")

        do {
            guard let orderData = try await OrderService.fetchOrderForPrinting(orderId: orderId) else {
                Log.label.error("Order not found: \(orderId)")
                return false
            }

            Log.label.debug("Fetched order with \(orderData.items.count) items via RPC")

            // Convert to products for printing
            var products: [Product] = []
            for item in orderData.items {
                for _ in 0..<item.quantity {
                    products.append(item.product.toProduct())
                }
            }

            Log.label.info("Printing \(products.count) total labels")
            return await printLabels(products, startPosition: startPosition, config: config)
        } catch {
            Log.label.error("Error in optimized fetch: \(error.localizedDescription)")
            return false
        }
    }

    /// Legacy multi-order print path
    @MainActor
    private static func printOrderLabelsLegacy(_ orders: [Order], config: LabelConfig, startPosition: Int) async -> Bool {
        Log.label.debug("Using legacy multi-order print path")

        // Collect unique product IDs and their quantities
        var productIdCounts: [UUID: Int] = [:]
        for order in orders {
            guard let items = order.items else { continue }
            for item in items {
                productIdCounts[item.productId, default: 0] += item.quantity
            }
        }

        guard !productIdCounts.isEmpty else {
            Log.label.warning("No products to print")
            return true
        }

        // Fetch full product data
        let productIds = Array(productIdCounts.keys)
        Log.label.debug("Fetching full product data for \(productIds.count) unique products")

        do {
            let fullProducts = try await ProductService.fetchProductsByIds(productIds)
            Log.label.debug("Fetched \(fullProducts.count) full products")

            let productLookup = Dictionary(uniqueKeysWithValues: fullProducts.map { ($0.id, $0) })

            var products: [Product] = []
            for (productId, count) in productIdCounts {
                if let product = productLookup[productId] {
                    for _ in 0..<count {
                        products.append(product)
                    }
                }
            }

            Log.label.info("Printing \(products.count) total labels")
            return await printLabels(products, startPosition: startPosition, config: config)
        } catch {
            Log.label.error("Error fetching products: \(error.localizedDescription)")
            return false
        }
    }

    @MainActor
    static func autoPrintCartLabels(
        cartItems: [CartItem],
        products: [Product],
        config: LabelConfig,
        sealedDate: Date = Date()
    ) async -> Bool {
        let settings = LabelPrinterSettings.shared

        guard settings.isReadyToAutoPrint else {
            Log.ui.info("Auto-print not ready")
            return false
        }

        guard !cartItems.isEmpty else { return true }

        let productLookup = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
        var printProducts: [Product] = []
        var saleCodes: [String] = []  // One code per label
        var tierLabels: [String?] = []  // Track tier for each label

        for item in cartItems {
            guard let product = productLookup[item.productId] else { continue }
            for _ in 0..<item.quantity {
                printProducts.append(product)
                // Generate unique sale code for each unit
                let (_, code) = QRTrackingService.saleTrackingURL()
                saleCodes.append(code)
                tierLabels.append(item.tierLabel)
            }
        }

        guard !printProducts.isEmpty else { return true }

        Log.label.info("autoPrintCartLabels: Printing \(printProducts.count) labels starting at position \(settings.startPosition + 1)")
        Log.ui.info("Auto-printing \(printProducts.count) labels with sale codes")

        guard let printerUrl = settings.printerUrl else { return false }

        // Register QR codes with edge function (fire and forget)
        if let storeId = config.storeId, let saleContext = config.saleContext {
            let capturedTierLabels = tierLabels
            Task.detached {
                for (index, product) in printProducts.enumerated() {
                    let code = saleCodes[index]
                    let tierLabel = capturedTierLabels[index]
                    await QRTrackingService.registerSaleItemWithCode(
                        code: code,
                        product: product,
                        storeId: storeId,
                        saleContext: saleContext,
                        quantityIndex: index,
                        tierLabel: tierLabel,
                        storeLogoUrl: config.storeLogoUrl
                    )
                }
                Log.ui.info("Registered \(printProducts.count) QR codes")
            }
        }

        // Fetch store logo
        var updatedConfig = config
        if updatedConfig.storeLogoImage == nil, let logoUrl = config.storeLogoUrl {
            do {
                let (data, _) = try await URLSession.shared.data(from: logoUrl)
                updatedConfig = LabelConfig(
                    storeId: config.storeId,
                    locationId: config.locationId,
                    locationName: config.locationName,
                    locationLicense: config.locationLicense,
                    distributorLicense: config.distributorLicense,
                    storeLogoUrl: config.storeLogoUrl,
                    brandLogoFallback: config.brandLogoFallback,
                    weightTier: config.weightTier,
                    storeLogoImage: UIImage(data: data),
                    saleContext: config.saleContext,
                    saleCode: config.saleCode
                )
            } catch {
                Log.ui.warning("Failed to load store logo")
            }
        }

        let imageCache = await LabelRenderer.prefetchImages(for: printProducts)
        let renderer = LabelRenderer(products: printProducts, startPosition: settings.startPosition, config: updatedConfig, sealedDate: sealedDate, saleCodes: saleCodes, tierLabels: tierLabels)
        renderer.setImageCache(imageCache)

        return await printDirect(renderer: renderer, to: printerUrl, jobName: "Auto Labels")
    }

    /// Print with iOS system print preview dialog
    @MainActor
    static func printWithPreview(renderer: UIPrintPageRenderer, jobName: String) async -> Bool {
        let printController = UIPrintInteractionController.shared
        let printInfo = UIPrintInfo(dictionary: nil)
        printInfo.jobName = jobName
        printInfo.outputType = .general
        printInfo.orientation = .portrait
        printInfo.duplex = .none

        printController.printInfo = printInfo
        printController.printPageRenderer = renderer

        return await withCheckedContinuation { continuation in
            // UIPrintInteractionController can call completion multiple times on errors
            // Use flag to ensure we only resume continuation once
            var hasResumed = false
            let resumeOnce: (Bool) -> Void = { completed in
                guard !hasResumed else {
                    Log.ui.warning("printWithPreview: ignoring duplicate completion callback")
                    return
                }
                hasResumed = true
                continuation.resume(returning: completed)
            }

            printController.present(animated: true) { _, completed, error in
                if let error = error {
                    Log.ui.error("Print preview error: \(error.localizedDescription)")
                }
                resumeOnce(completed)
            }
        }
    }

    @MainActor
    static func printDirect(renderer: UIPrintPageRenderer, to printerUrl: URL, jobName: String) async -> Bool {
        let printController = UIPrintInteractionController.shared
        let printInfo = UIPrintInfo(dictionary: nil)
        printInfo.jobName = jobName
        printInfo.outputType = .general
        printInfo.orientation = .portrait
        printInfo.duplex = .none

        printController.printInfo = printInfo
        printController.printPageRenderer = renderer

        let printer = UIPrinter(url: printerUrl)

        return await withCheckedContinuation { continuation in
            // UIPrintInteractionController can call completion multiple times on errors
            // Use flag to ensure we only resume continuation once
            var hasResumed = false
            let resumeOnce: (Bool) -> Void = { completed in
                guard !hasResumed else {
                    Log.ui.warning("printDirect: ignoring duplicate completion callback")
                    return
                }
                hasResumed = true
                continuation.resume(returning: completed)
            }

            printController.print(to: printer, completionHandler: { _, completed, error in
                if let error = error {
                    Log.ui.error("Direct print error: \(error.localizedDescription)")
                }
                resumeOnce(completed)
            })
        }
    }

    @MainActor
    static func selectPrinter() async -> Bool {
        // Get the existing printer if we have one saved
        var existingPrinter: UIPrinter? = nil
        if let printerUrl = LabelPrinterSettings.shared.printerUrl {
            existingPrinter = UIPrinter(url: printerUrl)
        }

        let picker = UIPrinterPickerController(initiallySelectedPrinter: existingPrinter)

        return await withCheckedContinuation { continuation in
            var hasResumed = false
            let resumeOnce: (Bool) -> Void = { result in
                guard !hasResumed else { return }
                hasResumed = true
                continuation.resume(returning: result)
            }

            // Find the key window
            guard let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
                  let window = windowScene.windows.first(where: { $0.isKeyWindow }) ?? windowScene.windows.first else {
                Log.ui.error("selectPrinter: Could not find window")
                resumeOnce(false)
                return
            }

            let completionHandler: UIPrinterPickerController.CompletionHandler = { controller, selected, error in
                if let error = error {
                    Log.ui.error("Printer picker error: \(error.localizedDescription)")
                }
                if selected, let printer = controller.selectedPrinter {
                    LabelPrinterSettings.shared.printerUrl = printer.url
                    LabelPrinterSettings.shared.printerName = printer.displayName
                    Log.ui.info("Selected printer: \(printer.displayName)")
                }
                resumeOnce(selected)
            }

            var presented = false

            // iPad requires presenting from a rect in a view
            if UIDevice.current.userInterfaceIdiom == .pad {
                // Present from center of window for iPad popover
                let centerRect = CGRect(x: window.bounds.midX - 1, y: window.bounds.midY - 1, width: 2, height: 2)
                presented = picker.present(from: centerRect, in: window, animated: true, completionHandler: completionHandler)
            } else {
                // iPhone can use simple presentation
                presented = picker.present(animated: true, completionHandler: completionHandler)
            }

            if !presented {
                Log.ui.error("selectPrinter: Failed to present picker")
                resumeOnce(false)
            }
        }
    }

    /// Print a single inventory unit label
    static func printInventoryLabel(_ labelData: InventoryLabelData, session: SessionObserver) {
        Task {
            let config = LabelConfig(
                storeId: session.store?.id,
                locationId: session.selectedLocation?.id,
                locationName: session.selectedLocation?.name ?? "Licensed Dispensary",
                distributorLicense: session.store?.distributorLicenseNumber,
                storeLogoUrl: session.store?.fullLogoUrl,
                brandLogoFallback: String(session.store?.businessName?.prefix(1) ?? "W"),
                weightTier: labelData.tierLabel
            )

            // Create a minimal product for the label
            let product = Product(
                id: UUID(),
                name: labelData.productName,
                storeId: session.store?.id
            )

            let _ = await printLabels([product], config: config)
        }
    }
}
