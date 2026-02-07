//
//  LabelRenderer.swift
//  Whale
//
//  Avery 5163 (2×4") label rendering and QR code generation.
//  Extracted from LabelPrintService for Apple engineering standards compliance.
//

import Foundation
import UIKit
import CoreImage

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

// MARK: - QR Code Generator

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

// MARK: - Label Renderer

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
