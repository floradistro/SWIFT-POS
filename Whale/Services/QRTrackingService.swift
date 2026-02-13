//
//  QRTrackingService.swift
//  Whale
//
//  QR Code tracking integration with Flora Distro analytics.
//  Generates tracked URLs and registers QR codes for analytics.
//

import Foundation
import Supabase
import os.log

// MARK: - QR Tracking Service

enum QRTrackingService {

    // MARK: - Configuration

    /// Base URL for tracking (Flora Distro storefront landing pages)
    static let trackingBaseURL = "https://floradistro.com/qr"

    /// Supabase Edge Function URL for QR registration (more reliable than analytics app)
    static var edgeFunctionURL: String { "\(SupabaseConfig.baseURL)/functions/v1/qr-register" }

    /// Whether tracking is enabled (can be toggled for testing)
    static var isTrackingEnabled: Bool {
        // Always enabled now that system is deployed
        return true
    }

    // MARK: - URL Generation

    /// Generate a tracked QR URL for a product
    /// Returns: floradistro.com/qr/PROD{productId}
    static func trackingURL(for product: Product) -> URL? {
        let code = generateCode(type: .product, id: product.id.uuidString)
        return URL(string: "\(trackingBaseURL)/\(code)")
    }

    /// Generate a tracked QR URL for an order
    /// Returns: floradistro.com/qr/ORD{orderId}
    static func trackingURL(for order: Order) -> URL? {
        let code = generateCode(type: .order, id: order.id.uuidString)
        return URL(string: "\(trackingBaseURL)/\(code)")
    }

    /// Generate a tracked QR URL with a custom code
    static func trackingURL(code: String) -> URL? {
        return URL(string: "\(trackingBaseURL)/\(code)")
    }

    /// Generate a sale-level tracked QR URL (unique per unit)
    /// Returns a new unique URL for each call
    static func saleTrackingURL() -> (url: URL, code: String)? {
        let saleItemId = UUID().uuidString.lowercased()
        let code = "S\(saleItemId)"
        guard let url = URL(string: "\(trackingBaseURL)/\(code)") else { return nil }
        return (url, code)
    }

    /// Generate a unique code for QR tracking
    private static func generateCode(type: QRCodeType, id: String) -> String {
        // Use full UUID for direct database lookup (lowercase for consistency)
        let fullId = id.lowercased()

        switch type {
        case .product:
            return "P\(fullId)"
        case .sale:
            return "S\(fullId)"
        case .order:
            return "O\(fullId)"
        case .location:
            return "L\(fullId)"
        case .campaign:
            return "C\(fullId)"
        case .custom:
            return fullId
        }
    }

    // MARK: - QR URL for Labels

    /// Get the URL to use for QR code on labels
    /// If tracking enabled: returns tracking URL
    /// If tracking disabled: returns original COA URL
    static func labelQRURL(for product: Product) -> URL? {
        if isTrackingEnabled {
            return trackingURL(for: product) // already optional
        } else {
            return product.coaUrl
        }
    }

    // MARK: - Registration

    /// Register a product QR code with analytics (product-level, same code for all units)
    @MainActor
    static func registerProduct(
        _ product: Product,
        storeId: UUID,
        locationId: UUID? = nil,
        locationName: String? = nil,
        storeLogoUrl: URL? = nil,
        brandColor: String? = nil
    ) async {
        guard isTrackingEnabled else { return }

        let code = generateCode(type: .product, id: product.id.uuidString)

        let registration = QRCodeRegistration(
            storeId: storeId.uuidString,
            code: code,
            name: product.name,
            type: QRCodeType.product.rawValue,
            destinationUrl: product.coaUrl?.absoluteString ?? "https://floradistro.com",
            landingPageTitle: product.name,
            landingPageDescription: buildProductDescription(product),
            landingPageImageUrl: product.imageUrl,
            landingPageCtaText: "View Lab Results",
            landingPageCtaUrl: product.coaUrl?.absoluteString,
            productId: product.id.uuidString,
            orderId: nil,
            locationId: locationId?.uuidString,
            campaignName: "product_labels",
            logoUrl: storeLogoUrl?.absoluteString,
            brandColor: brandColor ?? "#10b981",
            tags: ["product", "label", product.strainType ?? "unknown"].compactMap { $0 },
            customerId: nil,
            staffId: nil,
            soldAt: nil,
            unitPrice: nil,
            quantityIndex: nil,
            locationName: locationName,
            orderType: nil,
            printSource: nil,
            tierLabel: nil
        )

        await register(registration)
    }

    /// Register a sale-level QR code (unique per unit sold, with full tracking)
    @MainActor
    static func registerSaleItem(
        _ product: Product,
        storeId: UUID,
        saleContext: SaleContext,
        quantityIndex: Int,
        storeLogoUrl: URL? = nil,
        brandColor: String? = nil
    ) async -> String {
        // Generate unique code for this specific sale item
        let saleItemId = UUID().uuidString.lowercased()
        let code = "S\(saleItemId)"

        await registerSaleItemWithCode(
            code: code,
            product: product,
            storeId: storeId,
            saleContext: saleContext,
            quantityIndex: quantityIndex,
            storeLogoUrl: storeLogoUrl,
            brandColor: brandColor
        )

        return code
    }

    /// Register a sale-level QR code with a pre-generated code
    /// Used when the code needs to be generated upfront (e.g., for label printing)
    @MainActor
    static func registerSaleItemWithCode(
        code: String,
        product: Product,
        storeId: UUID,
        saleContext: SaleContext,
        quantityIndex: Int,
        tierLabel: String? = nil,
        storeLogoUrl: URL? = nil,
        brandColor: String? = nil
    ) async {
        guard isTrackingEnabled else { return }

        let dateFormatter = ISO8601DateFormatter()
        let soldAtString = dateFormatter.string(from: saleContext.soldAt)

        let registration = QRCodeRegistration(
            storeId: storeId.uuidString,
            code: code,
            name: product.name,
            type: QRCodeType.sale.rawValue,
            destinationUrl: "https://floradistro.com/qr/\(code)",
            landingPageTitle: product.name,
            landingPageDescription: buildProductDescription(product),
            landingPageImageUrl: product.imageUrl,
            landingPageCtaText: "View Lab Results",
            landingPageCtaUrl: product.coaUrl?.absoluteString,
            productId: product.id.uuidString,
            orderId: saleContext.orderId.uuidString,
            locationId: saleContext.locationId?.uuidString,
            campaignName: "sale_tracking",
            logoUrl: storeLogoUrl?.absoluteString,
            brandColor: brandColor ?? "#10b981",
            tags: ["sale", "tracked", product.strainType ?? "unknown"].compactMap { $0 },
            customerId: saleContext.customerId?.uuidString,
            staffId: saleContext.staffId?.uuidString,
            soldAt: soldAtString,
            unitPrice: saleContext.unitPrice.map { "\($0)" },
            quantityIndex: quantityIndex,
            locationName: saleContext.locationName,
            orderType: saleContext.orderType,
            printSource: saleContext.printSource?.rawValue,
            tierLabel: tierLabel
        )

        await register(registration)
    }

    /// Register multiple sale items for an order (one QR per unit sold)
    @MainActor
    static func registerSaleItems(
        products: [(product: Product, quantity: Int, unitPrice: Decimal?)],
        storeId: UUID,
        saleContext: SaleContext,
        storeLogoUrl: URL? = nil,
        brandColor: String? = nil
    ) async -> [String] {
        guard isTrackingEnabled else { return [] }

        var codes: [String] = []

        for (product, quantity, unitPrice) in products {
            let context = SaleContext(
                orderId: saleContext.orderId,
                customerId: saleContext.customerId,
                staffId: saleContext.staffId,
                locationId: saleContext.locationId,
                locationName: saleContext.locationName,
                soldAt: saleContext.soldAt,
                unitPrice: unitPrice ?? saleContext.unitPrice,
                orderType: saleContext.orderType,
                printSource: saleContext.printSource
            )

            for index in 1...quantity {
                let code = await registerSaleItem(
                    product,
                    storeId: storeId,
                    saleContext: context,
                    quantityIndex: index,
                    storeLogoUrl: storeLogoUrl,
                    brandColor: brandColor
                )
                codes.append(code)
            }
        }

        return codes
    }

    /// Register an order QR code with analytics
    @MainActor
    static func registerOrder(
        _ order: Order,
        storeId: UUID,
        storeLogoUrl: URL? = nil,
        brandColor: String? = nil
    ) async {
        guard isTrackingEnabled else { return }

        let code = generateCode(type: .order, id: order.id.uuidString)

        let registration = QRCodeRegistration(
            storeId: storeId.uuidString,
            code: code,
            name: "Order #\(order.orderNumber)",
            type: QRCodeType.order.rawValue,
            destinationUrl: "https://floradistro.com/orders/\(order.id.uuidString)",
            landingPageTitle: "Order Status",
            landingPageDescription: "Track your order in real-time",
            landingPageImageUrl: nil,
            landingPageCtaText: "Track Order",
            landingPageCtaUrl: "/orders/\(order.id.uuidString)/track",
            productId: nil,
            orderId: order.id.uuidString,
            locationId: nil,
            campaignName: "order_tracking",
            logoUrl: storeLogoUrl?.absoluteString,
            brandColor: brandColor ?? "#10b981",
            tags: ["order", "shipping", "tracking"],
            customerId: order.customerId?.uuidString,
            staffId: nil,
            soldAt: nil,
            unitPrice: nil,
            quantityIndex: nil,
            locationName: nil,
            orderType: order.orderType.rawValue,
            printSource: nil,  // Order QR codes are not for product labels
            tierLabel: nil
        )

        await register(registration)
    }

    /// Register a batch of product QR codes (more efficient)
    @MainActor
    static func registerProducts(
        _ products: [Product],
        storeId: UUID,
        locationId: UUID? = nil,
        locationName: String? = nil,
        storeLogoUrl: URL? = nil,
        brandColor: String? = nil
    ) async {
        guard isTrackingEnabled else { return }

        // Register in parallel with limited concurrency
        await withTaskGroup(of: Void.self) { group in
            for product in products {
                group.addTask {
                    await registerProduct(
                        product,
                        storeId: storeId,
                        locationId: locationId,
                        locationName: locationName,
                        storeLogoUrl: storeLogoUrl,
                        brandColor: brandColor
                    )
                }
            }
        }
    }

    // MARK: - Private Helpers

    private static func buildProductDescription(_ product: Product) -> String {
        var parts: [String] = []

        if let strain = product.strainType {
            parts.append(strain)
        }

        if let thc = product.thcPercentage {
            parts.append(String(format: "THC: %.1f%%", thc))
        }

        if parts.isEmpty {
            return "Premium cannabis product with verified lab results"
        }

        return parts.joined(separator: " | ")
    }

    private static func register(_ registration: QRCodeRegistration) async {
        guard let url = URL(string: edgeFunctionURL) else {
            Log.network.error("Invalid edge function URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")

        do {
            let encoder = JSONEncoder()
            request.httpBody = try encoder.encode(registration)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                Log.network.error("QR registration failed: invalid response")
                return
            }

            if httpResponse.statusCode == 200 {
                let decoder = JSONDecoder()
                if let result = try? decoder.decode(QRRegistrationResponse.self, from: data),
                   result.success {
                    Log.network.info("QR registered: \(registration.code)")
                } else {
                    Log.network.warning("QR registration response parse failed")
                }
            } else {
                Log.network.error("QR registration failed: \(httpResponse.statusCode)")
                if let responseBody = String(data: data, encoding: .utf8) {
                    Log.network.debug("Response: \(responseBody)")
                }
            }
        } catch {
            // Silent failure - don't block label printing if analytics fails
            Log.network.warning("QR registration error: \(error.localizedDescription)")
        }
    }

    /// Mark a QR code as split with the given child count
    static func markQRCodeAsSplit(qrCodeId: UUID, childCount: Int) async throws {
        struct SplitUpdate: Encodable {
            let status: String
            let child_count: Int
        }
        try await supabase
            .from("qr_codes")
            .update(SplitUpdate(status: "split", child_count: childCount))
            .eq("id", value: qrCodeId.uuidString)
            .execute()
    }
}

// MARK: - LabelPrintService Integration

extension QRTrackingService {

    /// Prepare tracked QR URLs for a batch of products before printing
    /// Call this before printing labels to ensure QR codes are registered
    @MainActor
    static func prepareForLabelPrint(
        products: [Product],
        storeId: UUID?,
        storeLogoUrl: URL? = nil
    ) async {
        guard let storeId = storeId, isTrackingEnabled else { return }

        // Register all products in background
        // Don't await - let it happen async while printing proceeds
        Task.detached(priority: .utility) {
            await registerProducts(
                products,
                storeId: storeId,
                storeLogoUrl: storeLogoUrl
            )
        }
    }
}
