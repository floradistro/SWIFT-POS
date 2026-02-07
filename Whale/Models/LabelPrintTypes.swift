//
//  LabelPrintTypes.swift
//  Whale
//
//  Label printer settings, manager, and error types.
//

import Foundation
import Combine
import os.log

// MARK: - Label Printer Settings

@MainActor
final class LabelPrinterSettings: ObservableObject {
    static let shared = LabelPrinterSettings()

    @Published var isAutoPrintEnabled: Bool {
        didSet { UserDefaults.standard.set(isAutoPrintEnabled, forKey: "labelAutoPrintEnabled") }
    }

    @Published var printerUrl: URL? {
        didSet {
            if let url = printerUrl {
                UserDefaults.standard.set(url.absoluteString, forKey: "labelPrinterUrl")
            } else {
                UserDefaults.standard.removeObject(forKey: "labelPrinterUrl")
            }
        }
    }

    @Published var printerName: String? {
        didSet { UserDefaults.standard.set(printerName, forKey: "labelPrinterName") }
    }

    @Published var startPosition: Int {
        didSet { UserDefaults.standard.set(startPosition, forKey: "labelStartPosition") }
    }

    var isReadyToAutoPrint: Bool {
        isAutoPrintEnabled && printerUrl != nil
    }

    var isPrinterConfigured: Bool {
        printerUrl != nil
    }

    /// Alias for isAutoPrintEnabled (for CheckoutSheet compatibility)
    var autoPrintEnabled: Bool {
        isAutoPrintEnabled
    }

    private init() {
        self.isAutoPrintEnabled = UserDefaults.standard.bool(forKey: "labelAutoPrintEnabled")
        if let urlString = UserDefaults.standard.string(forKey: "labelPrinterUrl") {
            self.printerUrl = URL(string: urlString)
        }
        self.printerName = UserDefaults.standard.string(forKey: "labelPrinterName")
        self.startPosition = UserDefaults.standard.integer(forKey: "labelStartPosition")
    }

    /// Pre-warm printer connection for faster printing (no-op in simplified version)
    func prewarmPrinter() {
        // Printer connection is established on-demand in simplified version
    }

    /// Alias for prewarmPrinter (for CheckoutSheet compatibility)
    func startPrewarming() {
        prewarmPrinter()
    }

    /// Stop pre-warming printer (no-op in simplified version)
    func stopPrewarming() {
        // No persistent connection to stop in simplified version
    }
}

// MARK: - Label Printer Manager

/// Manages auto-printing of labels after checkout
/// Singleton that coordinates with LabelPrintService
@MainActor
final class LabelPrinterManager {
    static let shared = LabelPrinterManager()

    private let logger = os.Logger(subsystem: "com.whale.pos", category: "LabelPrinterManager")

    private init() {}

    /// Print labels for an order (auto-print flow)
    func printOrder(_ order: Order) async throws {
        Log.label.info("LabelPrinterManager.printOrder called for order \(order.orderNumber)")

        guard LabelPrinterSettings.shared.autoPrintEnabled else {
            Log.label.debug("Auto-print disabled in printOrder check")
            logger.info("Auto-print disabled, skipping")
            return
        }

        guard LabelPrinterSettings.shared.isPrinterConfigured else {
            Log.label.warning("No printer configured - printerUrl is nil")
            logger.warning("No printer configured, skipping auto-print")
            throw LabelPrintError.noPrinterConfigured
        }

        Log.label.debug("Printer configured: \(LabelPrinterSettings.shared.printerName ?? "unknown")")
        Log.label.debug("Order items count: \(order.items?.count ?? 0)")

        // Build config from order context with store logo
        let storeLogoUrl = await SessionObserver.shared.store?.fullLogoUrl
        Log.label.debug("Store logo URL: \(storeLogoUrl?.absoluteString ?? "none")")

        let config = LabelConfig(
            storeId: order.storeId,
            locationId: order.deliveryLocationId,
            locationName: order.primaryFulfillment?.deliveryLocation?.name ?? "Licensed Dispensary",
            locationLicense: nil,
            distributorLicense: nil,
            storeLogoUrl: storeLogoUrl,
            brandLogoFallback: "W",
            weightTier: nil,
            storeLogoImage: nil,
            saleContext: nil,
            saleCode: nil
        )

        Log.label.debug("Calling printOrderLabels with startPosition: \(LabelPrinterSettings.shared.startPosition)")
        let success = await LabelPrintService.printOrderLabels([order], config: config)

        if !success {
            Log.label.error("printOrderLabels returned false")
            throw LabelPrintError.printFailed
        }

        Log.label.info("Auto-print completed successfully for order \(order.orderNumber)")
        logger.info("Auto-printed labels for order \(order.orderNumber)")
    }
}

// MARK: - Label Print Error

enum LabelPrintError: LocalizedError {
    case noPrinterConfigured
    case printFailed
    case noItems
    case orderFetchFailed(String)

    var errorDescription: String? {
        switch self {
        case .noPrinterConfigured: return "No label printer configured. Go to Settings > Label Printer to set up."
        case .printFailed: return "Label printing failed. Check printer is on and connected to WiFi."
        case .noItems: return "No items to print"
        case .orderFetchFailed(let reason): return "Failed to fetch order: \(reason)"
        }
    }
}
