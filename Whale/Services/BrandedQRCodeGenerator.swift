//
//  BrandedQRCodeGenerator.swift
//  Whale
//
//  Professional branded QR codes using dagronf/QRCode library.
//  Logo as full background with styled QR pixels on top.
//

import Foundation
import UIKit
import QRCode
import SwiftUI

// MARK: - QR Code Style

enum QRCodeStyle: String, CaseIterable, Identifiable {
    case standard = "Standard"
    case rounded = "Rounded"
    case dots = "Dots"
    case sharp = "Sharp"
    case leaf = "Leaf"
    case squircle = "Squircle"

    var id: String { rawValue }
    var displayName: String { rawValue }

    var icon: String {
        switch self {
        case .standard: return "qrcode"
        case .rounded: return "circle.grid.3x3"
        case .dots: return "circle.fill"
        case .sharp: return "square.fill"
        case .leaf: return "leaf.fill"
        case .squircle: return "app.fill"
        }
    }
}

// MARK: - QR Eye Style

enum QREyeStyle: String, CaseIterable, Identifiable {
    case standard = "Standard"
    case rounded = "Rounded"
    case circle = "Circle"
    case leaf = "Leaf"
    case shield = "Shield"
    case teardrop = "Teardrop"

    var id: String { rawValue }
}

// MARK: - Branded QR Code Generator

enum BrandedQRCodeGenerator {

    // MARK: - Main Generation Method

    /// Generate a professionally branded QR code
    /// Uses the QRCode library's native background image support
    static func generate(
        from string: String,
        size: CGFloat = 300,
        style: QRCodeStyle = .rounded,
        eyeStyle: QREyeStyle = .rounded,
        foregroundColor: UIColor = .black,
        backgroundColor: UIColor = .white,
        logoImage: UIImage? = nil,
        logoSizeRatio: CGFloat = 0.25
    ) -> UIImage? {

        guard let logo = logoImage, let logoCG = logo.cgImage else {
            // No logo - generate standard styled QR
            return generateStyledQR(
                from: string,
                size: size,
                style: style,
                eyeStyle: eyeStyle,
                foregroundColor: foregroundColor,
                backgroundColor: backgroundColor
            )
        }

        // Use the library's native background image feature
        return generateWithBackgroundImage(
            from: string,
            size: size,
            style: style,
            eyeStyle: eyeStyle,
            backgroundImage: logoCG
        )
    }

    // MARK: - Background Image QR (Using Library Features)

    /// Generate QR with logo in bottom-right corner (like Instagram example)
    /// Logo is fully visible, not transparent - QR pixels mask around it
    static func generateWithBackgroundImage(
        from string: String,
        size: CGFloat = 300,
        style: QRCodeStyle = .rounded,
        eyeStyle: QREyeStyle = .rounded,
        backgroundImage: CGImage,
        logoOpacity: CGFloat = 0.40
    ) -> UIImage? {

        guard let doc = try? QRCode.Document(utf8String: string) else { return nil }

        // High error correction for logo overlay
        doc.errorCorrection = .high

        // White background
        doc.design.style.background = QRCode.FillStyle.Solid(UIColor.white.cgColor)

        // Style the pixels
        doc.design.shape.onPixels = pixelShape(for: style)

        // Style the eyes
        let (eyeOuter, eyeInner) = eyeShapes(for: eyeStyle)
        doc.design.shape.eye = eyeOuter
        doc.design.shape.pupil = eyeInner

        // Solid black pixels
        doc.design.style.onPixels = QRCode.FillStyle.Solid(UIColor.black.cgColor)
        doc.design.style.eye = QRCode.FillStyle.Solid(UIColor.black.cgColor)
        doc.design.style.pupil = QRCode.FillStyle.Solid(UIColor.black.cgColor)

        // Logo in bottom-right corner - max size with minimal padding
        // Path coordinates are 0-1 fractional, bottom-right positioned
        let logoPath = CGPath(
            rect: CGRect(x: 0.72, y: 0.72, width: 0.26, height: 0.26),
            transform: nil
        )
        doc.logoTemplate = QRCode.LogoTemplate(
            image: backgroundImage,
            path: logoPath,
            inset: 2
        )

        // Generate high-res image
        let scale: CGFloat = 3.0
        let renderSize = CGSize(width: size * scale, height: size * scale)
        guard let cgImage = try? doc.cgImage(renderSize) else { return nil }

        return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
    }

    // MARK: - Gradient Branded QR

    /// Generate QR with gradient pixels over logo watermark background
    static func generateGradientBranded(
        from string: String,
        size: CGFloat = 300,
        style: QRCodeStyle = .rounded,
        eyeStyle: QREyeStyle = .rounded,
        backgroundImage: CGImage,
        gradientColors: [UIColor],
        logoOpacity: CGFloat = 0.18
    ) -> UIImage? {

        guard let doc = try? QRCode.Document(utf8String: string) else { return nil }

        doc.errorCorrection = .high

        // Create watermark version
        let watermarkImage = createWatermarkImage(from: backgroundImage, opacity: logoOpacity)
        doc.design.style.background = QRCode.FillStyle.Image(watermarkImage)

        doc.design.shape.onPixels = pixelShape(for: style)

        let (eyeOuter, eyeInner) = eyeShapes(for: eyeStyle)
        doc.design.shape.eye = eyeOuter
        doc.design.shape.pupil = eyeInner

        // Apply gradient to pixels
        let cgColors = gradientColors.map { $0.cgColor }
        if let gradient = try? QRCode.FillStyle.LinearGradient(
            try DSFGradient(pins: cgColors.enumerated().map { index, color in
                DSFGradient.Pin(color, CGFloat(index) / CGFloat(max(cgColors.count - 1, 1)))
            }),
            startPoint: CGPoint(x: 0, y: 0),
            endPoint: CGPoint(x: 1, y: 1)
        ) {
            doc.design.style.onPixels = gradient
        }

        doc.design.style.eyeBackground = UIColor.white.cgColor
        doc.design.style.eye = QRCode.FillStyle.Solid(UIColor.black.cgColor)
        doc.design.style.pupil = QRCode.FillStyle.Solid(UIColor.black.cgColor)
        doc.design.style.backgroundFractionalCornerRadius = 0.03

        let scale: CGFloat = 3.0
        let renderSize = CGSize(width: size * scale, height: size * scale)
        guard let cgImage = try? doc.cgImage(renderSize) else { return nil }

        return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
    }

    // MARK: - Standard Styled QR (no logo)

    static func generateStyledQR(
        from string: String,
        size: CGFloat = 300,
        style: QRCodeStyle = .rounded,
        eyeStyle: QREyeStyle = .rounded,
        foregroundColor: UIColor = .black,
        backgroundColor: UIColor = .white
    ) -> UIImage? {

        guard let doc = try? QRCode.Document(utf8String: string) else { return nil }

        doc.errorCorrection = .medium
        doc.design.shape.onPixels = pixelShape(for: style)

        let (eyeOuter, eyeInner) = eyeShapes(for: eyeStyle)
        doc.design.shape.eye = eyeOuter
        doc.design.shape.pupil = eyeInner

        doc.design.style.onPixels = QRCode.FillStyle.Solid(foregroundColor.cgColor)
        doc.design.style.background = QRCode.FillStyle.Solid(backgroundColor.cgColor)
        doc.design.style.eye = QRCode.FillStyle.Solid(foregroundColor.cgColor)
        doc.design.style.pupil = QRCode.FillStyle.Solid(foregroundColor.cgColor)

        doc.design.style.backgroundFractionalCornerRadius = 0.02

        let scale: CGFloat = 3.0
        let renderSize = CGSize(width: size * scale, height: size * scale)
        guard let cgImage = try? doc.cgImage(renderSize) else { return nil }

        return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
    }

    // MARK: - Store QR (Main Method for Labels)

    /// Generate store-branded QR - logo as full background
    static func generateStoreQR(
        url: URL,
        storeLogo: UIImage?,
        brandColor: UIColor? = nil,
        size: CGFloat = 300
    ) -> UIImage? {

        if let logo = storeLogo, let logoCG = logo.cgImage {
            return generateWithBackgroundImage(
                from: url.absoluteString,
                size: size,
                style: .rounded,
                eyeStyle: .rounded,
                backgroundImage: logoCG
            )
        } else {
            return generateStyledQR(
                from: url.absoluteString,
                size: size,
                style: .rounded,
                eyeStyle: .rounded,
                foregroundColor: brandColor ?? .black,
                backgroundColor: .white
            )
        }
    }

    /// Generate QR with text initial when no logo
    static func generateWithInitial(
        from string: String,
        initial: String,
        size: CGFloat = 300,
        style: QRCodeStyle = .rounded,
        foregroundColor: UIColor = .black
    ) -> UIImage? {

        let initialImage = createInitialImage(initial, size: 600, color: foregroundColor)

        if let cgImage = initialImage.cgImage {
            return generateWithBackgroundImage(
                from: string,
                size: size,
                style: style,
                eyeStyle: .rounded,
                backgroundImage: cgImage
            )
        }

        return generateStyledQR(
            from: string,
            size: size,
            style: style,
            eyeStyle: .rounded,
            foregroundColor: foregroundColor
        )
    }

    // MARK: - Private Helpers

    private static func pixelShape(for style: QRCodeStyle) -> QRCodePixelShapeGenerator {
        switch style {
        case .standard: return QRCode.PixelShape.Square()
        case .rounded: return QRCode.PixelShape.RoundedPath(cornerRadiusFraction: 0.7)
        case .dots: return QRCode.PixelShape.Circle()
        case .sharp: return QRCode.PixelShape.Sharp()
        case .leaf: return QRCode.PixelShape.Pointy()
        case .squircle: return QRCode.PixelShape.Squircle()
        }
    }

    private static func eyeShapes(for style: QREyeStyle) -> (QRCodeEyeShapeGenerator, QRCodePupilShapeGenerator) {
        switch style {
        case .standard: return (QRCode.EyeShape.Square(), QRCode.PupilShape.Square())
        case .rounded: return (QRCode.EyeShape.RoundedRect(), QRCode.PupilShape.RoundedRect())
        case .circle: return (QRCode.EyeShape.Circle(), QRCode.PupilShape.Circle())
        case .leaf: return (QRCode.EyeShape.Leaf(), QRCode.PupilShape.Leaf())
        case .shield: return (QRCode.EyeShape.Shield(), QRCode.PupilShape.Shield())
        case .teardrop: return (QRCode.EyeShape.Teardrop(), QRCode.PupilShape.Circle())
        }
    }

    private static func createWatermarkImage(from image: CGImage, opacity: CGFloat) -> CGImage {
        let width = image.width
        let height = image.height

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return image
        }

        // Fill with white
        context.setFillColor(UIColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Draw the original image with reduced opacity
        context.setAlpha(opacity)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        return context.makeImage() ?? image
    }

    private static func createInitialImage(_ initial: String, size: CGFloat, color: UIColor) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { ctx in
            // Light gradient background
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

            // Draw large centered initial
            let font = UIFont.systemFont(ofSize: size * 0.55, weight: .bold)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color.withAlphaComponent(0.25)
            ]

            let text = String(initial.prefix(1)).uppercased()
            let textSize = text.size(withAttributes: attributes)
            let point = CGPoint(
                x: (size - textSize.width) / 2,
                y: (size - textSize.height) / 2
            )
            text.draw(at: point, withAttributes: attributes)
        }
    }
}

// MARK: - SwiftUI Preview Helper

struct BrandedQRCodeView: View {
    let content: String
    let size: CGFloat
    let style: QRCodeStyle
    let logoImage: UIImage?
    let foregroundColor: Color

    init(
        _ content: String,
        size: CGFloat = 200,
        style: QRCodeStyle = .rounded,
        logoImage: UIImage? = nil,
        foregroundColor: Color = .black
    ) {
        self.content = content
        self.size = size
        self.style = style
        self.logoImage = logoImage
        self.foregroundColor = foregroundColor
    }

    var body: some View {
        if let image = BrandedQRCodeGenerator.generate(
            from: content,
            size: size,
            style: style,
            foregroundColor: UIColor(foregroundColor),
            logoImage: logoImage
        ) {
            Image(uiImage: image)
                .resizable()
                .frame(width: size, height: size)
        } else {
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(width: size, height: size)
                .overlay(
                    Image(systemName: "qrcode")
                        .font(.largeTitle)
                        .foregroundColor(.gray)
                )
        }
    }
}

// MARK: - Style Picker View

struct QRStylePicker: View {
    @Binding var selectedStyle: QRCodeStyle

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(QRCodeStyle.allCases) { style in
                    Button {
                        Haptics.light()
                        selectedStyle = style
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: style.icon)
                                .font(.system(size: 20))
                                .foregroundColor(selectedStyle == style ? .white : .white.opacity(0.6))

                            Text(style.displayName)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(selectedStyle == style ? .white : .white.opacity(0.5))
                        }
                        .frame(width: 64, height: 56)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(selectedStyle == style ? Design.Colors.Semantic.accent.opacity(0.3) : Color.white.opacity(0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(selectedStyle == style ? Design.Colors.Semantic.accent : Color.clear, lineWidth: 1.5)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack(spacing: 20) {
            Text("Branded QR Codes")
                .font(.title2.bold())
                .foregroundColor(.white)

            HStack(spacing: 16) {
                ForEach([QRCodeStyle.standard, .rounded, .dots], id: \.self) { style in
                    VStack {
                        BrandedQRCodeView(
                            "https://example.com",
                            size: 100,
                            style: style
                        )
                        Text(style.displayName)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            }

            HStack(spacing: 16) {
                ForEach([QRCodeStyle.sharp, .leaf, .squircle], id: \.self) { style in
                    VStack {
                        BrandedQRCodeView(
                            "https://example.com",
                            size: 100,
                            style: style
                        )
                        Text(style.displayName)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            }
        }
        .padding()
    }
}
