//
//  PrintService.swift
//  Whale
//
//  Modern print service with backend-first QR registration.
//  Guarantees 100% QR code reliability - codes are registered BEFORE printing.
//
//  Architecture:
//  1. Client sends cart items to backend
//  2. Backend registers ALL QR codes and returns confirmed payload
//  3. Client renders and prints (QR codes guaranteed to work)
//  4. Retry uses same payload (no re-registration needed)
//

import Foundation
import UIKit
import os.log

// MARK: - Print Service

/// Thread-safe print service that serializes all operations
/// Uses backend-first QR registration for 100% reliability
@MainActor
final class PrintService {

    // MARK: - Singleton

    static let shared = PrintService()
    private init() {}

    // MARK: - Configuration

    private let maxRetries = 3
    private let baseRetryDelay: TimeInterval = 1.0

    // MARK: - Status Callback

    /// Optional callback for status updates
    var onStatusUpdate: ((PrintJobStatus) -> Void)?

    private func emitStatus(_ status: PrintJobStatus) {
        onStatusUpdate?(status)
    }

    // MARK: - Main Print Flow

    /// Prepare and print labels for cart items
    /// - QR codes are registered on backend BEFORE this returns
    /// - If successful, the returned payload can be used for retry without re-registration
    func printCartLabels(
        storeId: UUID,
        cartItems: [CartItem],
        saleContext: SaleContext,
        storeLogoUrl: URL?,
        printerUrl: URL,
        startPosition: Int = 0
    ) async -> PrintResult {

        emitStatus(.preparing)

        // Convert cart items to backend format
        let printCartItems = cartItems.map { item in
            PrintCartItem(
                productId: item.productId.uuidString,
                quantity: item.quantity,
                tierLabel: item.tierLabel,
                unitPrice: item.unitPrice
            )
        }

        guard !printCartItems.isEmpty else {
            let error = PrintError.noItems
            emitStatus(.failed(error))
            return .failure(error)
        }

        // Build sale context for backend
        let printSaleContext = PrintSaleContext(
            orderId: saleContext.orderId.uuidString,
            customerId: saleContext.customerId?.uuidString,
            staffId: saleContext.staffId?.uuidString,
            locationId: saleContext.locationId?.uuidString,
            locationName: saleContext.locationName,
            soldAt: ISO8601DateFormatter().string(from: saleContext.soldAt),
            orderType: saleContext.orderType,
            printSource: saleContext.printSource?.rawValue
        )

        // Step 1: Get confirmed payload from backend (with QR codes registered)
        let totalItems = printCartItems.reduce(0) { $0 + $1.quantity }
        emitStatus(.registeringQRCodes(count: totalItems))

        let payloadResult = await prepareLabelsWithRetry(
            storeId: storeId,
            items: printCartItems,
            saleContext: printSaleContext,
            storeLogoUrl: storeLogoUrl
        )

        guard case .success(let payload) = payloadResult else {
            if case .failure(let error) = payloadResult {
                emitStatus(.failed(error))
                return .failure(error)
            }
            let error = PrintError.backendError("Unknown error")
            emitStatus(.failed(error))
            return .failure(error)
        }

        emitStatus(.qrCodesRegistered(count: payload.items.count))

        // Step 2: Render and print locally
        let printResult = await printPayload(payload, to: printerUrl, startPosition: startPosition)

        emitStatus(.completed(printResult))
        return printResult
    }

    /// Print a pre-prepared payload (for retry scenarios)
    func printPayload(_ payload: PrintPayload, to printerUrl: URL, startPosition: Int = 0) async -> PrintResult {

        let pages = calculatePages(itemCount: payload.items.count, startPosition: startPosition)
        emitStatus(.rendering(pages: pages))

        // Render the labels
        let renderResult = await renderAndPrint(payload: payload, printerUrl: printerUrl, startPosition: startPosition)

        return renderResult
    }

    // MARK: - Backend Communication

    private enum PrepareResult {
        case success(PrintPayload)
        case failure(PrintError)
    }

    /// Call backend to prepare labels with retry logic
    private func prepareLabelsWithRetry(
        storeId: UUID,
        items: [PrintCartItem],
        saleContext: PrintSaleContext,
        storeLogoUrl: URL?
    ) async -> PrepareResult {

        var lastError: PrintError = .networkError("Unknown")
        let retries = maxRetries

        for attempt in 1...retries {
            let result = await prepareLabels(
                storeId: storeId,
                items: items,
                saleContext: saleContext,
                storeLogoUrl: storeLogoUrl
            )

            switch result {
            case .success:
                return result
            case .failure(let error):
                lastError = error

                // Don't retry for certain errors
                if case .noItems = error { return result }
                if case .notConfigured = error { return result }

                if attempt < retries {
                    let delay = baseRetryDelay * pow(2.0, Double(attempt - 1))
                    Log.network.info("PrintService: Retry \(attempt)/\(retries) after \(delay)s")
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }

        return .failure(lastError)
    }

    /// Single attempt to prepare labels via backend
    private func prepareLabels(
        storeId: UUID,
        items: [PrintCartItem],
        saleContext: PrintSaleContext,
        storeLogoUrl: URL?
    ) async -> PrepareResult {

        let urlString = "\(SupabaseConfig.baseURL)/functions/v1/prepare-print-labels"
        guard let url = URL(string: urlString) else {
            return .failure(.notConfigured("Invalid backend URL"))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        // Build request body
        let body: [String: Any] = [
            "store_id": storeId.uuidString,
            "items": items.map { item -> [String: Any] in
                var dict: [String: Any] = [
                    "product_id": item.productId,
                    "quantity": item.quantity
                ]
                if let tierLabel = item.tierLabel {
                    dict["tier_label"] = tierLabel
                }
                if let unitPrice = item.unitPrice {
                    dict["unit_price"] = NSDecimalNumber(decimal: unitPrice).doubleValue
                }
                return dict
            },
            "sale_context": buildSaleContextDict(saleContext),
            "store_logo_url": storeLogoUrl?.absoluteString ?? NSNull()
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            return .failure(.backendError("Failed to encode request: \(error.localizedDescription)"))
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(.networkError("Invalid response"))
            }

            if httpResponse.statusCode != 200 {
                if let errorBody = String(data: data, encoding: .utf8) {
                    Log.network.error("PrintService: Backend error \(httpResponse.statusCode): \(errorBody)")
                }
                return .failure(.backendError("HTTP \(httpResponse.statusCode)"))
            }

            let decoder = JSONDecoder()
            let result = try decoder.decode(PrepareLabelsResponse.self, from: data)

            if result.success, let payload = result.payload {
                if let skipped = result.skippedProducts, !skipped.isEmpty {
                    Log.network.warning("PrintService: Prepared \(payload.items.count) items, \(result.qrCodesRegistered ?? 0) QR codes registered, \(skipped.count) products skipped (deleted)")
                } else {
                    Log.network.info("PrintService: Prepared \(payload.items.count) items, \(result.qrCodesRegistered ?? 0) QR codes registered")
                }
                return .success(payload)
            } else {
                return .failure(.backendError(result.error ?? "Unknown backend error"))
            }

        } catch let error as DecodingError {
            Log.network.error("PrintService: Decode error: \(error)")
            return .failure(.backendError("Failed to decode response"))
        } catch {
            Log.network.error("PrintService: Network error: \(error.localizedDescription)")
            return .failure(.networkError(error.localizedDescription))
        }
    }

    private func buildSaleContextDict(_ ctx: PrintSaleContext) -> [String: Any] {
        var dict: [String: Any] = ["order_id": ctx.orderId]
        if let v = ctx.customerId { dict["customer_id"] = v }
        if let v = ctx.staffId { dict["staff_id"] = v }
        if let v = ctx.locationId { dict["location_id"] = v }
        if let v = ctx.locationName { dict["location_name"] = v }
        if let v = ctx.soldAt { dict["sold_at"] = v }
        if let v = ctx.orderType { dict["order_type"] = v }
        if let v = ctx.printSource { dict["print_source"] = v }
        return dict
    }

    // MARK: - Rendering and Printing

    /// Render payload to labels and send to printer
    private func renderAndPrint(payload: PrintPayload, printerUrl: URL, startPosition: Int) async -> PrintResult {

        // Convert PrintableItems to Products for the existing LabelRenderer
        var products: [Product] = []
        var saleCodes: [String] = []
        var tierLabels: [String?] = []

        for item in payload.items {
            // Build customFields dictionary to populate computed properties
            // Product.strainType reads from customFields["strain_type"]
            // Product.thcaPercentage reads from customFields["thca_percentage"]
            // Product.coaUrl reads from customFields["coa_url"]
            var customFields: [String: AnyCodable] = [:]

            if let strainType = item.product.strainType {
                customFields["strain_type"] = AnyCodable(strainType)
            }
            if let thca = item.product.thcaPercentage {
                customFields["thca_percentage"] = AnyCodable(thca)
            }
            if let d9Thc = item.product.d9ThcPercentage {
                customFields["d9_thc"] = AnyCodable(d9Thc)
            }
            if let coaUrl = item.product.coaUrl {
                customFields["coa_url"] = AnyCodable(coaUrl)
            }
            if let testDate = item.product.testDate {
                customFields["test_date"] = AnyCodable(testDate)
            }
            if let batchNumber = item.product.batchNumber {
                customFields["batch_number"] = AnyCodable(batchNumber)
            }

            // Create Product using the full memberwise initializer
            // LabelRenderer uses: id, name, strainType (computed), thcaPercentage (computed), featuredImage
            let product = Product(
                id: UUID(uuidString: item.product.id) ?? UUID(),
                name: item.product.name,
                description: item.product.description,
                featuredImage: item.product.featuredImage,
                customFields: customFields.isEmpty ? nil : customFields,
                storeId: UUID(uuidString: payload.config.storeId) ?? UUID()
            )

            products.append(product)
            saleCodes.append(item.saleCode)
            tierLabels.append(item.tierLabel)
        }

        // Parse sealed date
        let sealedDate: Date
        if let date = ISO8601DateFormatter().date(from: payload.sealedDate) {
            sealedDate = date
        } else {
            sealedDate = Date()
        }

        // Fetch store logo if available
        var storeLogoImage: UIImage?
        if let logoUrlString = payload.config.storeLogoUrl,
           let logoUrl = URL(string: logoUrlString) {
            do {
                let (data, _) = try await URLSession.shared.data(from: logoUrl)
                storeLogoImage = UIImage(data: data)
            } catch {
                Log.ui.warning("PrintService: Failed to load store logo")
            }
        }

        // Build LabelConfig
        let config = LabelConfig(
            storeId: UUID(uuidString: payload.config.storeId),
            locationId: payload.saleContext.locationId.flatMap { UUID(uuidString: $0) },
            locationName: payload.config.locationName ?? "Licensed Dispensary",
            locationLicense: nil,
            distributorLicense: payload.config.distributorLicense,
            storeLogoUrl: payload.config.storeLogoUrl.flatMap { URL(string: $0) },
            brandLogoFallback: "W",
            weightTier: nil,
            storeLogoImage: storeLogoImage,
            saleContext: nil,
            saleCode: nil
        )

        // Prefetch product images
        let imageCache = await LabelRenderer.prefetchImages(for: products)

        // Create renderer
        let renderer = LabelRenderer(
            products: products,
            startPosition: startPosition,
            config: config,
            sealedDate: sealedDate,
            saleCodes: saleCodes,
            tierLabels: tierLabels
        )
        renderer.setImageCache(imageCache)

        emitStatus(.sending)

        // Print directly to printer
        let success = await LabelPrintService.printDirect(renderer: renderer, to: printerUrl, jobName: "Labels")

        if success {
            return .success(itemsPrinted: payload.items.count, qrCodesRegistered: payload.items.count)
        } else {
            return .failure(.printerUnavailable("Print job failed"))
        }
    }

    // MARK: - Manual Print (No Sale Context)

    /// Print labels for products manually (not from a sale)
    /// Used by LabelTemplateSheet for inventory labeling
    func printManualLabels(
        storeId: UUID,
        products: [Product],
        tierLabels: [String?],
        locationId: UUID?,
        locationName: String?,
        storeLogoUrl: URL?,
        printerUrl: URL?,
        startPosition: Int = 0,
        showPreview: Bool = false
    ) async -> PrintResult {

        guard !products.isEmpty else {
            return .failure(.noItems)
        }

        emitStatus(.preparing)

        // Convert products to cart items format (1 label per product entry)
        var printCartItems: [PrintCartItem] = []
        var tierLabelMap: [String: String] = [:] // product_id -> tier_label

        for (index, product) in products.enumerated() {
            let tierLabel = tierLabels.indices.contains(index) ? tierLabels[index] : nil

            // Group by product_id + tier_label
            let key = "\(product.id.uuidString)-\(tierLabel ?? "none")"
            if let existingIndex = printCartItems.firstIndex(where: { "\($0.productId)-\($0.tierLabel ?? "none")" == key }) {
                // Increment quantity for existing item
                let existing = printCartItems[existingIndex]
                printCartItems[existingIndex] = PrintCartItem(
                    productId: existing.productId,
                    quantity: existing.quantity + 1,
                    tierLabel: existing.tierLabel,
                    unitPrice: nil
                )
            } else {
                printCartItems.append(PrintCartItem(
                    productId: product.id.uuidString,
                    quantity: 1,
                    tierLabel: tierLabel,
                    unitPrice: nil
                ))
            }
        }

        // Generate a tracking ID for manual print jobs
        let manualPrintId = "manual-\(UUID().uuidString.prefix(8))"

        // Build sale context for backend (manual print tracking)
        let printSaleContext = PrintSaleContext(
            orderId: manualPrintId,
            customerId: nil,
            staffId: nil,
            locationId: locationId?.uuidString,
            locationName: locationName,
            soldAt: ISO8601DateFormatter().string(from: Date()),
            orderType: "manual_print",
            printSource: "manual_inventory"
        )

        // Step 1: Get confirmed payload from backend (with QR codes registered)
        let totalItems = products.count
        emitStatus(.registeringQRCodes(count: totalItems))

        let payloadResult = await prepareLabelsWithRetry(
            storeId: storeId,
            items: printCartItems,
            saleContext: printSaleContext,
            storeLogoUrl: storeLogoUrl
        )

        guard case .success(let payload) = payloadResult else {
            if case .failure(let error) = payloadResult {
                emitStatus(.failed(error))
                return .failure(error)
            }
            let error = PrintError.backendError("Unknown error")
            emitStatus(.failed(error))
            return .failure(error)
        }

        emitStatus(.qrCodesRegistered(count: payload.items.count))

        // Step 2: Render and print
        if showPreview {
            let printResult = await printPayloadWithPreview(payload, startPosition: startPosition)
            emitStatus(.completed(printResult))
            return printResult
        } else if let printerUrl = printerUrl {
            let printResult = await printPayload(payload, to: printerUrl, startPosition: startPosition)
            emitStatus(.completed(printResult))
            return printResult
        } else {
            // No printer - show preview
            let printResult = await printPayloadWithPreview(payload, startPosition: startPosition)
            emitStatus(.completed(printResult))
            return printResult
        }
    }

    /// Print payload with iOS print preview dialog
    private func printPayloadWithPreview(_ payload: PrintPayload, startPosition: Int) async -> PrintResult {

        let pages = calculatePages(itemCount: payload.items.count, startPosition: startPosition)
        emitStatus(.rendering(pages: pages))

        // Convert PrintableItems to Products for LabelRenderer
        var products: [Product] = []
        var saleCodes: [String] = []
        var tierLabels: [String?] = []

        for item in payload.items {
            var customFields: [String: AnyCodable] = [:]

            if let strainType = item.product.strainType {
                customFields["strain_type"] = AnyCodable(strainType)
            }
            if let thca = item.product.thcaPercentage {
                customFields["thca_percentage"] = AnyCodable(thca)
            }
            if let d9Thc = item.product.d9ThcPercentage {
                customFields["d9_thc"] = AnyCodable(d9Thc)
            }
            if let coaUrl = item.product.coaUrl {
                customFields["coa_url"] = AnyCodable(coaUrl)
            }
            if let testDate = item.product.testDate {
                customFields["test_date"] = AnyCodable(testDate)
            }
            if let batchNumber = item.product.batchNumber {
                customFields["batch_number"] = AnyCodable(batchNumber)
            }

            let product = Product(
                id: UUID(uuidString: item.product.id) ?? UUID(),
                name: item.product.name,
                description: item.product.description,
                featuredImage: item.product.featuredImage,
                customFields: customFields.isEmpty ? nil : customFields,
                storeId: UUID(uuidString: payload.config.storeId) ?? UUID()
            )

            products.append(product)
            saleCodes.append(item.saleCode)
            tierLabels.append(item.tierLabel)
        }

        // Parse sealed date
        let sealedDate: Date
        if let date = ISO8601DateFormatter().date(from: payload.sealedDate) {
            sealedDate = date
        } else {
            sealedDate = Date()
        }

        // Fetch store logo if available
        var storeLogoImage: UIImage?
        if let logoUrlString = payload.config.storeLogoUrl,
           let logoUrl = URL(string: logoUrlString) {
            do {
                let (data, _) = try await URLSession.shared.data(from: logoUrl)
                storeLogoImage = UIImage(data: data)
            } catch {
                Log.ui.warning("PrintService: Failed to load store logo")
            }
        }

        // Build LabelConfig
        let config = LabelConfig(
            storeId: UUID(uuidString: payload.config.storeId),
            locationId: payload.saleContext.locationId.flatMap { UUID(uuidString: $0) },
            locationName: payload.config.locationName ?? "Licensed Dispensary",
            locationLicense: nil,
            distributorLicense: payload.config.distributorLicense,
            storeLogoUrl: payload.config.storeLogoUrl.flatMap { URL(string: $0) },
            brandLogoFallback: "W",
            weightTier: nil,
            storeLogoImage: storeLogoImage,
            saleContext: nil,
            saleCode: nil
        )

        // Prefetch product images
        let imageCache = await LabelRenderer.prefetchImages(for: products)

        // Create renderer
        let renderer = LabelRenderer(
            products: products,
            startPosition: startPosition,
            config: config,
            sealedDate: sealedDate,
            saleCodes: saleCodes,
            tierLabels: tierLabels
        )
        renderer.setImageCache(imageCache)

        emitStatus(.sending)

        // Show iOS print preview dialog
        let success = await LabelPrintService.printWithPreview(renderer: renderer, jobName: "Labels")

        if success {
            return .success(itemsPrinted: payload.items.count, qrCodesRegistered: payload.items.count)
        } else {
            return .failure(.cancelled)
        }
    }

    // MARK: - Order Print

    /// Print labels for existing orders
    /// Used by OrderLabelTemplateSheet for already-completed sales
    func printOrderLabels(
        orders: [Order],
        storeId: UUID,
        locationId: UUID?,
        locationName: String?,
        storeLogoUrl: URL?
    ) async -> PrintResult {

        // Build list of products with quantities from orders
        var printCartItems: [PrintCartItem] = []

        for order in orders {
            guard let items = order.items else { continue }
            for item in items {
                printCartItems.append(PrintCartItem(
                    productId: item.productId.uuidString,
                    quantity: item.quantity,
                    tierLabel: nil,  // OrderItem doesn't track tier
                    unitPrice: item.unitPrice
                ))
            }
        }

        guard !printCartItems.isEmpty else {
            return .failure(.noItems)
        }

        emitStatus(.preparing)

        // Use the first order's ID as the primary order context
        let primaryOrderId = orders.first?.id.uuidString ?? "order-\(UUID().uuidString.prefix(8))"

        let printSaleContext = PrintSaleContext(
            orderId: primaryOrderId,
            customerId: orders.first?.customerId?.uuidString,
            staffId: nil,  // Order doesn't track staff
            locationId: locationId?.uuidString,
            locationName: locationName,
            soldAt: orders.first?.completedAt?.ISO8601Format() ?? ISO8601DateFormatter().string(from: Date()),
            orderType: "order_reprint",
            printSource: "order_labels"
        )

        // Step 1: Get confirmed payload from backend
        let totalItems = printCartItems.reduce(0) { $0 + $1.quantity }
        emitStatus(.registeringQRCodes(count: totalItems))

        let payloadResult = await prepareLabelsWithRetry(
            storeId: storeId,
            items: printCartItems,
            saleContext: printSaleContext,
            storeLogoUrl: storeLogoUrl
        )

        guard case .success(let payload) = payloadResult else {
            if case .failure(let error) = payloadResult {
                emitStatus(.failed(error))
                return .failure(error)
            }
            let error = PrintError.backendError("Unknown error")
            emitStatus(.failed(error))
            return .failure(error)
        }

        emitStatus(.qrCodesRegistered(count: payload.items.count))

        // Step 2: Show print preview (orders typically use preview)
        let printResult = await printPayloadWithPreview(payload, startPosition: 0)
        emitStatus(.completed(printResult))
        return printResult
    }

    // MARK: - Helpers

    private func calculatePages(itemCount: Int, startPosition: Int) -> Int {
        let labelsPerPage = LabelTemplate.rows * LabelTemplate.cols
        let totalLabels = itemCount + startPosition
        return (totalLabels + labelsPerPage - 1) / labelsPerPage
    }
}
