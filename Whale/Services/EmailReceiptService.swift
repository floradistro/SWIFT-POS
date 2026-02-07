//
//  EmailReceiptService.swift
//  Whale
//
//  Service for sending email receipts for completed orders.
//  Sends order data to server-side React Email template via send-email function.
//

import Foundation
import os.log
import Supabase

// MARK: - Loyalty Data for Receipt

struct ReceiptLoyaltyData {
    let pointsEarned: Int
    let pointsRedeemed: Int
    let discountAmount: Decimal  // Dollar value of points redeemed

    static let empty = ReceiptLoyaltyData(pointsEarned: 0, pointsRedeemed: 0, discountAmount: 0)
}

enum EmailReceiptService {

    // MARK: - Send Receipt

    /// Send an email receipt for a completed order.
    /// Fetches complete order if needed, sends to server template.
    static func sendReceipt(for order: Order, to email: String) async throws {
        Log.email.debug("sendReceipt called for order: \(order.orderNumber)")
        Log.email.debug("Passed order has \(order.items?.count ?? 0) items")

        // ALWAYS fetch full order with items to ensure complete data
        let fullOrder: Order
        if let items = order.items, !items.isEmpty {
            fullOrder = order
            Log.email.debug("Using passed order (has \(items.count) items)")
        } else {
            Log.email.debug("Fetching complete order with items...")
            fullOrder = try await fetchOrderWithItems(orderId: order.id)
            Log.email.debug("Fetched order has \(fullOrder.items?.count ?? 0) items")
        }

        // Debug: Log what we're sending
        Log.email.debug("Order Number: \(fullOrder.shortOrderNumber)")
        Log.email.debug("Total: \(fullOrder.totalAmount)")
        Log.email.debug("Items count: \(fullOrder.items?.count ?? 0)")
        if let items = fullOrder.items {
            for (i, item) in items.enumerated() {
                let totalQty = item.tierQuantity.map { $0 * Double(item.quantity) }
                Log.email.debug("Item[\(i)]: \(item.productName) qty=\(item.quantity) tier=\(item.tierLabel ?? "nil") tierQty=\(item.tierQuantity ?? 0) totalQty=\(totalQty ?? 0)")
            }
        }

        let session = try await supabase.auth.session
        let accessToken = session.accessToken

        let url = SupabaseConfig.url.appendingPathComponent("functions/v1/send-email")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.timeoutInterval = 30

        // Fetch loyalty transactions for this order (points earned/redeemed)
        let loyaltyData = await fetchLoyaltyData(orderId: fullOrder.id)
        Log.email.debug("Loyalty data: pointsEarned=\(loyaltyData.pointsEarned) pointsRedeemed=\(loyaltyData.pointsRedeemed) discountAmount=\(loyaltyData.discountAmount)")

        // Build template data with full tier/pricing info for each item
        let templateData = buildTemplateData(order: fullOrder, customerEmail: email, loyaltyData: loyaltyData)

        // Build payload - use templateSlug for server-side React Email template
        let payload: [String: Any] = [
            "to": email,
            "subject": "Receipt for Order #\(fullOrder.shortOrderNumber)",
            "templateSlug": "receipt",
            "templateData": templateData,
            "storeId": fullOrder.storeId?.uuidString ?? "",
            "metadata": [
                "orderId": fullOrder.id.uuidString,
                "emailType": "receipt"
            ]
        ]

        // Debug: Log the payload
        if let payloadJson = try? JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted),
           let payloadString = String(data: payloadJson, encoding: .utf8) {
            Log.email.debug("Sending payload to send-email:")
            Log.email.debug("\(payloadString.prefix(3000))")
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw EmailReceiptError.networkError("Invalid response")
        }

        // Log response for debugging
        if let responseText = String(data: data, encoding: .utf8) {
            Log.email.debug("send-email response: \(responseText)")
        }

        guard httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw EmailReceiptError.serverError("HTTP \(httpResponse.statusCode): \(errorText)")
        }

        // Parse response
        struct SendEmailResponse: Decodable {
            let success: Bool
            let message: String?
            let error: String?
            let emailId: String?
        }

        let decoder = JSONDecoder()
        if let result = try? decoder.decode(SendEmailResponse.self, from: data) {
            if !result.success {
                throw EmailReceiptError.serverError(result.error ?? result.message ?? "Failed to send receipt")
            }
            Log.email.info("Receipt sent successfully, emailId: \(result.emailId ?? "unknown")")
        }
    }

    // MARK: - Build Template Data

    /// Build template data dictionary with all order details for React Email template.
    /// Includes full tier/pricing schema info for each line item.
    private static func buildTemplateData(order: Order, customerEmail: String, loyaltyData: ReceiptLoyaltyData) -> [String: Any] {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"

        let formatCurrency = { (value: Decimal) -> String in
            formatter.string(from: value as NSDecimalNumber) ?? "$0.00"
        }

        let formatDecimal = { (value: Decimal) -> String in
            "\(NSDecimalNumber(decimal: value).doubleValue)"
        }

        // Build items array with full tier/pricing details (camelCase for React Email)
        var items: [[String: Any]] = []
        for item in order.items ?? [] {
            // Calculate total quantity (e.g., 2 units × 3.5g = 7g total)
            let totalQuantity: Double? = item.tierQuantity.map { $0 * Double(item.quantity) }

            // Build item dictionary with all tier/pricing fields (camelCase)
            var itemDict: [String: Any] = [
                "id": item.id.uuidString,
                "productId": item.productId.uuidString,
                "productName": item.productName,
                "quantity": item.quantity,                              // Units sold (e.g., 2)
                "unitPrice": formatDecimal(item.unitPrice),
                "unitPriceFormatted": formatCurrency(item.unitPrice),
                "lineTotal": formatDecimal(item.lineTotal),
                "lineTotalFormatted": formatCurrency(item.lineTotal)
            ]

            // Tier info - critical for pricing schema (camelCase)
            if let tierLabel = item.tierLabel {
                itemDict["tierLabel"] = tierLabel                       // e.g., "3.5g", "1/4 oz"
            }
            if let tierQuantity = item.tierQuantity {
                itemDict["tierQuantity"] = tierQuantity                  // e.g., 3.5 (grams)
            }
            if let totalQty = totalQuantity {
                itemDict["totalQuantity"] = totalQty                     // e.g., 7.0 (2 × 3.5)

                // Format total quantity for display (e.g., "7g" or "14g")
                if let tierLabel = item.tierLabel {
                    // Extract unit from tier label (e.g., "g" from "3.5g")
                    let unit = tierLabel.replacingOccurrences(of: "[0-9./]", with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
                    if !unit.isEmpty {
                        // Format nicely (e.g., "7g" or "0.5oz")
                        if totalQty == totalQty.rounded() {
                            itemDict["totalQuantityFormatted"] = "\(Int(totalQty))\(unit)"
                        } else {
                            itemDict["totalQuantityFormatted"] = String(format: "%.1f%@", totalQty, unit)
                        }
                    }
                }
            }

            // Variant info (camelCase)
            if let variantId = item.variantId {
                itemDict["variantId"] = variantId.uuidString
            }
            if let variantName = item.variantName {
                itemDict["variantName"] = variantName                    // e.g., "Hybrid", "Indica"
            }

            // Discount info (camelCase)
            if let discountAmount = item.discountAmount, discountAmount > 0 {
                itemDict["discountAmount"] = formatDecimal(discountAmount)
                itemDict["discountAmountFormatted"] = formatCurrency(discountAmount)
                itemDict["originalLineTotal"] = formatDecimal(item.originalLineTotal)
                itemDict["originalLineTotalFormatted"] = formatCurrency(item.originalLineTotal)
            }

            // Display subtitle (tier + variant combined)
            if let subtitle = item.displaySubtitle {
                itemDict["displaySubtitle"] = subtitle
            }

            items.append(itemDict)
        }

        // Build complete template data (camelCase for React Email template)
        var templateData: [String: Any] = [
            // Order info (camelCase)
            "orderId": order.id.uuidString,
            "orderNumber": order.shortOrderNumber,
            "orderDate": order.formattedDate,
            "channel": order.channel.rawValue,

            // Items with full tier/pricing details
            "items": items,
            "itemCount": order.items?.count ?? 0,

            // Totals (camelCase)
            "subtotal": formatDecimal(order.subtotal),
            "subtotalFormatted": formatCurrency(order.subtotal),
            "taxAmount": formatDecimal(order.taxAmount),
            "taxAmountFormatted": formatCurrency(order.taxAmount),
            "discountAmount": formatDecimal(order.discountAmount),
            "discountAmountFormatted": formatCurrency(order.discountAmount),
            "totalAmount": formatDecimal(order.totalAmount),
            "totalAmountFormatted": formatCurrency(order.totalAmount),

            // Payment (camelCase)
            "paymentMethod": order.paymentMethod ?? "card",
            "paymentStatus": order.paymentStatus.rawValue,
            "paymentStatusDisplay": order.paymentStatus.displayName,

            // Loyalty data
            "loyaltyPointsRedeemed": loyaltyData.pointsRedeemed,
            "loyaltyDiscountFormatted": formatCurrency(loyaltyData.discountAmount),
            "pointsEarned": loyaltyData.pointsEarned
        ]

        // Customer info (camelCase)
        if let customer = order.customers {
            templateData["customerName"] = customer.fullName
            templateData["customerEmail"] = customer.email ?? customerEmail
            templateData["customerPhone"] = customer.phone
        } else {
            templateData["customerName"] = "Customer"
            templateData["customerEmail"] = customerEmail
        }

        // Store info
        if let storeId = order.storeId {
            templateData["storeId"] = storeId.uuidString
        }

        return templateData
    }

    // MARK: - Fetch Loyalty Data

    /// Fetches loyalty transactions for an order (points earned and redeemed).
    private static func fetchLoyaltyData(orderId: UUID) async -> ReceiptLoyaltyData {
        do {
            // Fetch loyalty transactions linked to this order
            let response = try await supabase
                .from("loyalty_transactions")
                .select("transaction_type, points, dollar_value")
                .eq("order_id", value: orderId.uuidString)
                .execute()

            struct LoyaltyTransaction: Decodable {
                let transactionType: String
                let points: Int
                let dollarValue: Decimal?

                enum CodingKeys: String, CodingKey {
                    case transactionType = "transaction_type"
                    case points
                    case dollarValue = "dollar_value"
                }
            }

            let transactions = try JSONDecoder().decode([LoyaltyTransaction].self, from: response.data)

            var pointsEarned = 0
            var pointsRedeemed = 0
            var discountAmount: Decimal = 0

            for tx in transactions {
                switch tx.transactionType {
                case "earn":
                    pointsEarned += tx.points
                case "redeem":
                    pointsRedeemed += tx.points
                    discountAmount += tx.dollarValue ?? 0
                default:
                    break
                }
            }

            return ReceiptLoyaltyData(
                pointsEarned: pointsEarned,
                pointsRedeemed: pointsRedeemed,
                discountAmount: discountAmount
            )
        } catch {
            Log.email.error("Failed to fetch loyalty data: \(error)")
            return .empty
        }
    }

    // MARK: - Fetch Complete Order

    /// Fetches a complete order with all items from the database.
    private static func fetchOrderWithItems(orderId: UUID) async throws -> Order {
        Log.email.debug("Fetching order \(orderId) with items...")

        let response = try await supabase
            .from("orders")
            .select("*, order_items(*), v_store_customers(first_name, last_name, email, phone)")
            .eq("id", value: orderId.uuidString)
            .single()
            .execute()

        // Debug: Show raw response
        if let jsonString = String(data: response.data, encoding: .utf8) {
            Log.email.debug("Raw order JSON (\(jsonString.count) chars):")
            Log.email.debug("\(jsonString.prefix(2000))")

            if jsonString.contains("\"order_items\"") {
                Log.email.debug("JSON contains order_items")
            } else {
                Log.email.error("JSON missing order_items!")
            }
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let order = try decoder.decode(Order.self, from: response.data)
            Log.email.info("Decoded order: \(order.orderNumber), items: \(order.items?.count ?? 0)")
            return order
        } catch {
            Log.email.error("Decode error: \(error)")
            throw EmailReceiptError.invalidOrder
        }
    }
}

// MARK: - Errors

enum EmailReceiptError: LocalizedError {
    case networkError(String)
    case serverError(String)
    case invalidOrder
    case noEmailAddress

    var errorDescription: String? {
        switch self {
        case .networkError(let message):
            return "Network error: \(message)"
        case .serverError(let message):
            return "Server error: \(message)"
        case .invalidOrder:
            return "Invalid order data"
        case .noEmailAddress:
            return "No email address for customer"
        }
    }
}
