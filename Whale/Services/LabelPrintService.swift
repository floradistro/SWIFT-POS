//  LabelPrintService.swift - Avery 5163 (2×4") label printing

import Foundation
import UIKit
import CoreImage
import SwiftUI
import Combine
import os.log

// MARK: - Template & Config

struct LabelTemplate {
    static let labelWidth: CGFloat = 4.0    // inches
    static let labelHeight: CGFloat = 2.0   // inches
    static let rows = 5
    static let cols = 2
    static let marginTop: CGFloat = 0.5     // inches
    static let marginLeft: CGFloat = 0.15625
    static let gutterH: CGFloat = 0.1875
    static let gutterV: CGFloat = 0.0
    static let labelsPerSheet = 10

    static let pageWidth: CGFloat = 8.5
    static let pageHeight: CGFloat = 11.0
}

struct LabelConfig {
    let storeId: UUID?
    let locationId: UUID?
    let locationName: String
    let locationLicense: String?
    let distributorLicense: String?
    let storeLogoUrl: URL?
    let brandLogoFallback: String
    let weightTier: String?
    var storeLogoImage: UIImage?

    // Sale tracking
    let saleContext: SaleContext?
    let saleCode: String?

    static let `default` = LabelConfig(
        storeId: nil,
        locationId: nil,
        locationName: "Licensed Dispensary",
        locationLicense: nil,
        distributorLicense: nil,
        storeLogoUrl: nil,
        brandLogoFallback: "W",
        weightTier: nil,
        storeLogoImage: nil,
        saleContext: nil,
        saleCode: nil
    )

    init(
        storeId: UUID? = nil,
        locationId: UUID? = nil,
        locationName: String = "Licensed Dispensary",
        locationLicense: String? = nil,
        distributorLicense: String? = nil,
        storeLogoUrl: URL? = nil,
        brandLogoFallback: String = "W",
        weightTier: String? = nil,
        storeLogoImage: UIImage? = nil,
        saleContext: SaleContext? = nil,
        saleCode: String? = nil
    ) {
        self.storeId = storeId
        self.locationId = locationId
        self.locationName = locationName
        self.locationLicense = locationLicense
        self.distributorLicense = distributorLicense
        self.storeLogoUrl = storeLogoUrl
        self.brandLogoFallback = brandLogoFallback
        self.weightTier = weightTier
        self.storeLogoImage = storeLogoImage
        self.saleContext = saleContext
        self.saleCode = saleCode
    }
}

enum QRCodeGenerator {
    static func generate(from string: String, size: CGSize = CGSize(width: 100, height: 100)) -> UIImage? {
        guard let data = string.data(using: .utf8),
              let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }

        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel")

        guard let ciImage = filter.outputImage else { return nil }

        let scaleX = size.width / ciImage.extent.width
        let scaleY = size.height / ciImage.extent.height
        let scaledImage = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        let context = CIContext()
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }

        return UIImage(cgImage: cgImage)
    }

    /// Generate a branded QR code with logo overlay in center
    /// If logoImage is provided, it will be used. Otherwise falls back to logoText (single letter brand mark)
    /// Uses high error correction (H) to allow for center logo without breaking scan
    static func generateBranded(
        from string: String,
        size: CGSize,
        logoImage: UIImage? = nil,
        logoText: String = "W",
        logoSizeRatio: CGFloat = 0.22
    ) -> UIImage? {
        guard let data = string.data(using: .utf8),
              let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }

        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel")

        guard let ciImage = filter.outputImage else { return nil }

        let scaleX = size.width / ciImage.extent.width
        let scaleY = size.height / ciImage.extent.height
        let scaledImage = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        let context = CIContext()
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }

        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        defer { UIGraphicsEndImageContext() }

        guard let ctx = UIGraphicsGetCurrentContext() else { return UIImage(cgImage: cgImage) }

        // Draw QR code
        UIImage(cgImage: cgImage).draw(in: CGRect(origin: .zero, size: size))

        // Calculate logo dimensions
        let logoActualSize = size.width * logoSizeRatio
        let logoRect = CGRect(
            x: (size.width - logoActualSize) / 2,
            y: (size.height - logoActualSize) / 2,
            width: logoActualSize,
            height: logoActualSize
        )

        if let logo = logoImage {
            // Use provided logo image with rounded rect background
            let cornerRadius = logoActualSize * 0.18
            let bgRect = logoRect.insetBy(dx: -3, dy: -3)
            let bgPath = UIBezierPath(roundedRect: bgRect, cornerRadius: cornerRadius + 2)

            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: 1), blur: 2, color: UIColor.black.withAlphaComponent(0.12).cgColor)
            ctx.setFillColor(UIColor.white.cgColor)
            bgPath.fill()
            ctx.restoreGState()

            ctx.saveGState()
            UIBezierPath(roundedRect: logoRect, cornerRadius: cornerRadius).addClip()
            logo.draw(in: logoRect)
            ctx.restoreGState()
        } else {
            // Fallback to text logo (original behavior) - circular white background with letter
            // Draw white circle background
            ctx.setFillColor(UIColor.white.cgColor)
            ctx.fillEllipse(in: logoRect.insetBy(dx: -2, dy: -2))

            // Draw dark circle border
            ctx.setStrokeColor(UIColor.black.cgColor)
            ctx.setLineWidth(1.5)
            ctx.strokeEllipse(in: logoRect.insetBy(dx: -1, dy: -1))

            // Draw logo text centered
            let logoFont = UIFont.systemFont(ofSize: logoActualSize * 0.6, weight: .bold)
            let logoAttrs: [NSAttributedString.Key: Any] = [
                .font: logoFont,
                .foregroundColor: UIColor.black
            ]
            let logoTextSize = (logoText as NSString).size(withAttributes: logoAttrs)
            let logoTextPoint = CGPoint(
                x: logoRect.midX - logoTextSize.width / 2,
                y: logoRect.midY - logoTextSize.height / 2
            )
            logoText.draw(at: logoTextPoint, withAttributes: logoAttrs)
        }

        return UIGraphicsGetImageFromCurrentImageContext()
    }
}

final class LabelRenderer: UIPrintPageRenderer {
    private let products: [Product]
    private let startPosition: Int
    private let config: LabelConfig
    private let sealedDate: Date
    private var imageCache: [UUID: UIImage] = [:]
    private let fontMono = "SF Mono"
    private let saleCodes: [String]?  // Optional array of sale codes, one per product
    private let tierLabels: [String?]?  // Optional array of tier labels, one per product

    init(products: [Product], startPosition: Int = 0, config: LabelConfig, sealedDate: Date = Date(), saleCodes: [String]? = nil, tierLabels: [String?]? = nil) {
        self.products = products
        self.startPosition = startPosition
        self.config = config
        self.sealedDate = sealedDate
        self.saleCodes = saleCodes
        self.tierLabels = tierLabels
        super.init()
    }

    func setImageCache(_ cache: [UUID: UIImage]) {
        self.imageCache = cache
    }

    override var numberOfPages: Int {
        let totalSlots = startPosition + products.count
        return max(1, (totalSlots + LabelTemplate.labelsPerSheet - 1) / LabelTemplate.labelsPerSheet)
    }

    override var paperRect: CGRect {
        let ptsPerInch: CGFloat = 72
        return CGRect(x: 0, y: 0,
                     width: LabelTemplate.pageWidth * ptsPerInch,
                     height: LabelTemplate.pageHeight * ptsPerInch)
    }

    override var printableRect: CGRect { paperRect }

    override func drawPage(at pageIndex: Int, in printableRect: CGRect) {
        let ptsPerInch: CGFloat = 72
        let labelW = LabelTemplate.labelWidth * ptsPerInch
        let labelH = LabelTemplate.labelHeight * ptsPerInch
        let marginTop = LabelTemplate.marginTop * ptsPerInch
        let marginLeft = LabelTemplate.marginLeft * ptsPerInch
        let gutterH = LabelTemplate.gutterH * ptsPerInch

        for slot in 0..<LabelTemplate.labelsPerSheet {
            let globalSlot = pageIndex * LabelTemplate.labelsPerSheet + slot
            let productIndex = globalSlot - startPosition

            guard productIndex >= 0 && productIndex < products.count else { continue }

            let row = slot / LabelTemplate.cols
            let col = slot % LabelTemplate.cols

            let x = marginLeft + CGFloat(col) * (labelW + gutterH)
            let y = marginTop + CGFloat(row) * labelH
            let rect = CGRect(x: x, y: y, width: labelW, height: labelH)

            drawLabel(products[productIndex], at: productIndex, in: rect)
        }
    }

    private func drawLabel(_ product: Product, at index: Int, in rect: CGRect) {
        let padding: CGFloat = 8
        let inset = rect.insetBy(dx: padding, dy: padding)
        let cornerRadius: CGFloat = 6

        let labelColor = UIColor(white: 0.4, alpha: 1)
        let valueColor = UIColor.black

        var y = inset.minY

        // Strain badge width calculation
        var strainBadgeWidth: CGFloat = 0
        if let strain = product.strainType {
            let strainAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 9, weight: .bold),
                .foregroundColor: strainColor(for: strain)
            ]
            strainBadgeWidth = (strain.uppercased() as NSString).size(withAttributes: strainAttrs).width + 8
        }

        // Product name
        let nameFont = UIFont.systemFont(ofSize: 18, weight: .heavy)
        let namePara = NSMutableParagraphStyle()
        namePara.lineBreakMode = .byTruncatingTail
        let nameAttrs: [NSAttributedString.Key: Any] = [
            .font: nameFont,
            .paragraphStyle: namePara,
            .foregroundColor: valueColor
        ]
        let nameRect = CGRect(x: inset.minX, y: y, width: inset.width - strainBadgeWidth, height: 22)
        product.name.draw(in: nameRect, withAttributes: nameAttrs)

        // Strain badge
        if let strain = product.strainType {
            let strainAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 9, weight: .bold),
                .foregroundColor: strainColor(for: strain)
            ]
            strain.uppercased().draw(at: CGPoint(x: inset.maxX - strainBadgeWidth + 4, y: y + 5), withAttributes: strainAttrs)
        }
        y += 26

        // Middle row: Image | QR | THC values
        let middleHeight: CGFloat = 72
        let imageQrSize: CGFloat = middleHeight
        let gap: CGFloat = 6

        // Product image
        let imageRect = CGRect(x: inset.minX, y: y, width: imageQrSize, height: imageQrSize)
        UIGraphicsGetCurrentContext()?.saveGState()
        UIBezierPath(roundedRect: imageRect, cornerRadius: cornerRadius).addClip()

        if let productImage = imageCache[product.id] {
            productImage.draw(in: imageRect)
        } else if let storeLogo = config.storeLogoImage {
            UIColor(white: 0.98, alpha: 1).setFill()
            UIRectFill(imageRect)
            storeLogo.draw(in: imageRect)
        } else {
            UIColor(white: 0.93, alpha: 1).setFill()
            UIRectFill(imageRect)
            let initial = String(product.name.prefix(1)).uppercased()
            let initialAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 28, weight: .bold),
                .foregroundColor: UIColor(white: 0.7, alpha: 1)
            ]
            let initialSize = (initial as NSString).size(withAttributes: initialAttrs)
            initial.draw(at: CGPoint(x: imageRect.midX - initialSize.width/2, y: imageRect.midY - initialSize.height/2), withAttributes: initialAttrs)
        }
        UIGraphicsGetCurrentContext()?.restoreGState()

        // QR code
        let qrSize: CGFloat = imageQrSize
        let qrRect = CGRect(x: inset.minX + imageQrSize + gap, y: y, width: qrSize, height: qrSize)
        if let qrUrl = qrURL(for: product, at: index) {
            let qrImage = QRCodeGenerator.generateBranded(
                from: qrUrl.absoluteString,
                size: CGSize(width: qrSize * 3, height: qrSize * 3),
                logoImage: config.storeLogoImage,
                logoText: config.brandLogoFallback
            )
            UIGraphicsGetCurrentContext()?.saveGState()
            UIBezierPath(roundedRect: qrRect, cornerRadius: cornerRadius).addClip()
            qrImage?.draw(in: qrRect)
            UIGraphicsGetCurrentContext()?.restoreGState()
        }

        // THC values
        let thcX = inset.minX + (imageQrSize + gap) * 2 + 8
        let thcaValue = product.thcaPercentage ?? product.thcPercentage
        let d9ThcValue = product.d9ThcPercentage

        let thcLabelAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9, weight: .semibold),
            .foregroundColor: labelColor
        ]
        let thcValueAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 26, weight: .heavy),
            .foregroundColor: valueColor
        ]

        var thcY = y + 2
        "THCA".draw(at: CGPoint(x: thcX, y: thcY), withAttributes: thcLabelAttrs)
        let thcaStr = thcaValue != nil ? String(format: "%.1f%%", thcaValue!) : "—"
        thcaStr.draw(at: CGPoint(x: thcX, y: thcY + 10), withAttributes: thcValueAttrs)

        thcY += 38
        "Δ9-THC".draw(at: CGPoint(x: thcX, y: thcY), withAttributes: thcLabelAttrs)
        let d9Str = d9ThcValue != nil ? String(format: "%.2f%%", d9ThcValue!) : "—"
        d9Str.draw(at: CGPoint(x: thcX, y: thcY + 10), withAttributes: thcValueAttrs)

        y += middleHeight + 6

        // Footer
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MM/dd/yy"

        let footerLabelAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 6.5, weight: .semibold),
            .foregroundColor: labelColor
        ]
        let footerValueAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 7.5, weight: .medium),
            .foregroundColor: valueColor
        ]

        let footerY1 = inset.maxY - 18
        let footerY2 = inset.maxY - 9

        // Weight tier - use per-label tier if available, otherwise config.weightTier
        let labelTier: String? = {
            if let labels = tierLabels, index < labels.count {
                return labels[index]
            }
            return config.weightTier
        }()
        if let weightTier = labelTier {
            let weightAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 14, weight: .heavy),
                .foregroundColor: valueColor
            ]
            weightTier.draw(at: CGPoint(x: inset.minX, y: footerY1 + 2), withAttributes: weightAttrs)
        }

        // Location centered under QR
        let qrCenterX = inset.minX + imageQrSize + gap + (qrSize / 2)
        let locationPara = NSMutableParagraphStyle()
        locationPara.alignment = .center
        let locationAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 6, weight: .semibold),
            .foregroundColor: labelColor,
            .paragraphStyle: locationPara
        ]

        let locationWidth: CGFloat = qrSize + 10
        let locationRect = CGRect(x: qrCenterX - locationWidth/2, y: footerY1, width: locationWidth, height: 10)
        config.locationName.uppercased().draw(in: locationRect, withAttributes: locationAttrs)

        if let usda = config.distributorLicense {
            let usdaRect = CGRect(x: qrCenterX - locationWidth/2, y: footerY2, width: locationWidth, height: 10)
            usda.draw(in: usdaRect, withAttributes: locationAttrs)
        }

        // Dates
        let testedX = inset.maxX - 115
        "TESTED".draw(at: CGPoint(x: testedX, y: footerY1), withAttributes: footerLabelAttrs)
        let testDateStr = product.coa?.testDate.map { dateFormatter.string(from: $0) } ?? "—"
        testDateStr.draw(at: CGPoint(x: testedX + 32, y: footerY1), withAttributes: footerValueAttrs)

        "PACKED".draw(at: CGPoint(x: testedX, y: footerY2), withAttributes: footerLabelAttrs)
        dateFormatter.string(from: sealedDate).draw(at: CGPoint(x: testedX + 32, y: footerY2), withAttributes: footerValueAttrs)
    }

    private func strainColor(for strain: String) -> UIColor {
        switch strain.lowercased() {
        case "indica": return UIColor(red: 0.6, green: 0.2, blue: 0.8, alpha: 1)
        case "sativa": return UIColor(red: 0.2, green: 0.7, blue: 0.3, alpha: 1)
        case "hybrid": return UIColor(red: 0.9, green: 0.6, blue: 0.1, alpha: 1)
        default: return UIColor(white: 0.5, alpha: 1)
        }
    }

    private func qrURL(for product: Product, at index: Int) -> URL? {
        // First check for per-label sale codes (from autoPrintCartLabels)
        if let codes = saleCodes, index < codes.count {
            return URL(string: "https://floradistro.com/qr/\(codes[index])")
        }
        // Legacy: single sale code for all labels
        if let saleCode = config.saleCode {
            return URL(string: "https://floradistro.com/qr/\(saleCode)")
        }
        // Product-level QR codes
        if config.storeId != nil {
            return URL(string: "https://floradistro.com/qr/P\(product.id.uuidString.lowercased())")
        }
        return nil
    }

    static func prefetchImages(for products: [Product]) async -> [UUID: UIImage] {
        var cache: [UUID: UIImage] = [:]
        let productsWithImages = products.filter { $0.iconUrl != nil }
        let productsWithoutImages = products.count - productsWithImages.count

        if productsWithoutImages > 0 {
            print("🏷️ ⚠️ \(productsWithoutImages) products missing iconUrl")
        }

        await withTaskGroup(of: (UUID, UIImage?).self) { group in
            for product in products {
                guard let url = product.iconUrl else { continue }
                group.addTask {
                    do {
                        let (data, _) = try await URLSession.shared.data(from: url)
                        return (product.id, UIImage(data: data))
                    } catch {
                        print("🏷️ Failed to fetch image for \(product.name): \(error.localizedDescription)")
                        return (product.id, nil)
                    }
                }
            }
            for await (id, image) in group {
                if let image = image {
                    cache[id] = image
                }
            }
        }
        return cache
    }
}

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

// MARK: - Label Printer Manager (Auto-print orchestration)

/// Manages auto-printing of labels after checkout
/// Singleton that coordinates with LabelPrintService
@MainActor
final class LabelPrinterManager {
    static let shared = LabelPrinterManager()

    private let logger = os.Logger(subsystem: "com.whale.pos", category: "LabelPrinterManager")

    private init() {}

    /// Print labels for an order (auto-print flow)
    func printOrder(_ order: Order) async throws {
        print("🏷️ LabelPrinterManager.printOrder called for order \(order.orderNumber)")

        guard LabelPrinterSettings.shared.autoPrintEnabled else {
            print("🏷️ Auto-print disabled in printOrder check")
            logger.info("Auto-print disabled, skipping")
            return
        }

        guard LabelPrinterSettings.shared.isPrinterConfigured else {
            print("🏷️ No printer configured - printerUrl is nil")
            logger.warning("No printer configured, skipping auto-print")
            throw LabelPrintError.noPrinterConfigured
        }

        print("🏷️ Printer configured: \(LabelPrinterSettings.shared.printerName ?? "unknown")")
        print("🏷️ Order items count: \(order.items?.count ?? 0)")

        // Build config from order context with store logo
        let storeLogoUrl = await SessionObserver.shared.store?.fullLogoUrl
        print("🏷️ Store logo URL: \(storeLogoUrl?.absoluteString ?? "none")")

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

        print("🏷️ Calling printOrderLabels with startPosition: \(LabelPrinterSettings.shared.startPosition)")
        let success = await LabelPrintService.printOrderLabels([order], config: config)

        if !success {
            print("🏷️ printOrderLabels returned false")
            throw LabelPrintError.printFailed
        }

        print("🏷️ Auto-print completed successfully for order \(order.orderNumber)")
        logger.info("Auto-printed labels for order \(order.orderNumber)")
    }
}

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
            print("🏷️ printLabels: Using saved position \(effectiveStartPosition + 1) (not explicitly provided)")
        } else {
            print("🏷️ printLabels: Using explicit position \(effectiveStartPosition + 1)")
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
        print("🏷️ Prefetched \(imageCache.count) product images")
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
        print("🏷️ printOrderLabels: Using saved start position \(startPos + 1)")

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
        print("🏷️ Using optimized RPC fetch for order \(orderId)")

        do {
            guard let orderData = try await OrderService.fetchOrderForPrinting(orderId: orderId) else {
                print("🏷️ Order not found: \(orderId)")
                return false
            }

            print("🏷️ Fetched order with \(orderData.items.count) items via RPC")

            // Convert to products for printing
            var products: [Product] = []
            for item in orderData.items {
                for _ in 0..<item.quantity {
                    products.append(item.product.toProduct())
                }
            }

            print("🏷️ Printing \(products.count) total labels")
            return await printLabels(products, startPosition: startPosition, config: config)
        } catch {
            print("🏷️ Error in optimized fetch: \(error.localizedDescription)")
            return false
        }
    }

    /// Legacy multi-order print path
    @MainActor
    private static func printOrderLabelsLegacy(_ orders: [Order], config: LabelConfig, startPosition: Int) async -> Bool {
        print("🏷️ Using legacy multi-order print path")

        // Collect unique product IDs and their quantities
        var productIdCounts: [UUID: Int] = [:]
        for order in orders {
            guard let items = order.items else { continue }
            for item in items {
                productIdCounts[item.productId, default: 0] += item.quantity
            }
        }

        guard !productIdCounts.isEmpty else {
            print("🏷️ No products to print")
            return true
        }

        // Fetch full product data
        let productIds = Array(productIdCounts.keys)
        print("🏷️ Fetching full product data for \(productIds.count) unique products")

        do {
            let fullProducts = try await ProductService.fetchProductsByIds(productIds)
            print("🏷️ Fetched \(fullProducts.count) full products")

            let productLookup = Dictionary(uniqueKeysWithValues: fullProducts.map { ($0.id, $0) })

            var products: [Product] = []
            for (productId, count) in productIdCounts {
                if let product = productLookup[productId] {
                    for _ in 0..<count {
                        products.append(product)
                    }
                }
            }

            print("🏷️ Printing \(products.count) total labels")
            return await printLabels(products, startPosition: startPosition, config: config)
        } catch {
            print("🏷️ Error fetching products: \(error.localizedDescription)")
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

        print("🏷️ autoPrintCartLabels: Printing \(printProducts.count) labels starting at position \(settings.startPosition + 1)")
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
