//
//  InvoiceService.swift
//  Whale
//
//  Invoice creation and management.
//  Calls the send-invoice edge function to create invoices with payment links.
//

import Foundation
import Supabase
import os.log

// MARK: - Invoice Service

enum InvoiceService {

    private static let logger = Logger(subsystem: "com.whale.pos", category: "InvoiceService")
    private static var edgeFunctionURL: URL {
        guard let url = URL(string: "\(SupabaseConfig.baseURL)/functions/v1/send-invoice") else {
            fatalError("Invalid send-invoice edge function URL")
        }
        return url
    }

    /// Create and send an invoice
    /// - Parameters:
    ///   - storeId: The store ID
    ///   - customer: Optional customer (can send to non-customer email)
    ///   - customerName: Customer name for invoice
    ///   - customerEmail: Email to send invoice to
    ///   - customerPhone: Optional phone number
    ///   - lineItems: Invoice line items
    ///   - taxRate: Tax rate to apply (e.g., 0.08 for 8%)
    ///   - description: Optional invoice description
    ///   - notes: Optional notes to include
    ///   - dueDate: Optional due date
    ///   - locationId: Optional location ID
    ///   - sendEmail: Whether to send email (default true)
    /// - Returns: Invoice response with payment URL
    static func sendInvoice(
        storeId: UUID,
        customer: Customer? = nil,
        customerName: String,
        customerEmail: String,
        customerPhone: String? = nil,
        lineItems: [InvoiceLineItem],
        taxRate: Decimal = 0,
        description: String? = nil,
        notes: String? = nil,
        dueDate: Date? = nil,
        locationId: UUID? = nil,
        sendEmail: Bool = true
    ) async throws -> SendInvoiceResponse {

        // Calculate totals
        let subtotal = lineItems.reduce(Decimal(0)) { $0 + $1.subtotal }
        let taxAmount = lineItems.reduce(Decimal(0)) { $0 + $1.taxAmount }
        let discountAmount = lineItems.reduce(Decimal(0)) { $0 + $1.discountAmount }
        let totalAmount = subtotal + taxAmount - discountAmount

        // Format due date if provided
        var dueDateString: String? = nil
        if let dueDate = dueDate {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate]
            dueDateString = formatter.string(from: dueDate)
        }

        let request = SendInvoiceRequest(
            storeId: storeId,
            customerId: customer?.id,
            customerName: customerName,
            customerEmail: customerEmail,
            customerPhone: customerPhone ?? customer?.phone,
            description: description,
            lineItems: lineItems,
            subtotal: subtotal,
            taxAmount: taxAmount,
            discountAmount: discountAmount,
            totalAmount: totalAmount,
            dueDate: dueDateString,
            notes: notes,
            locationId: locationId,
            sendEmail: sendEmail
        )

        logger.info("📧 Sending invoice to \(customerEmail) for \(totalAmount)")

        // Get auth token for authenticated request
        let session = try await supabase.auth.session
        let accessToken = session.accessToken

        // Make request with auth headers
        var urlRequest = URLRequest(url: edgeFunctionURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let encoder = JSONEncoder()
        urlRequest.httpBody = try encoder.encode(request)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw InvoiceError.networkError("Invalid response")
        }

        if httpResponse.statusCode != 200 {
            // Try to parse error message
            if let errorResponse = try? JSONDecoder().decode(SendInvoiceResponse.self, from: data) {
                throw InvoiceError.serverError(errorResponse.error ?? "Unknown error")
            }
            throw InvoiceError.serverError("HTTP \(httpResponse.statusCode)")
        }

        let decoder = JSONDecoder()

        do {
            let invoiceResponse = try decoder.decode(SendInvoiceResponse.self, from: data)

            if invoiceResponse.success {
                logger.info("✅ Invoice created: \(invoiceResponse.invoice?.invoiceNumber ?? "unknown")")
            } else {
                logger.error("❌ Invoice failed: \(invoiceResponse.error ?? "unknown")")
            }

            return invoiceResponse
        } catch {
            // Log raw response for debugging
            if let rawString = String(data: data, encoding: .utf8) {
                logger.error("❌ Failed to decode response: \(rawString.prefix(500))")
            }
            logger.error("❌ Decode error: \(error)")
            throw InvoiceError.serverError("Failed to parse response: \(error.localizedDescription)")
        }
    }

    /// Create an invoice from cart items - ALL calculations are backend-driven
    static func createFromCart(
        storeId: UUID,
        customer: Customer?,
        customerName: String,
        customerEmail: String,
        cartItems: [CartItem],
        taxRate: Decimal,
        locationId: UUID?,
        notes: String? = nil
    ) async throws -> SendInvoiceResponse {
        // Create line items with backend-calculated values
        var lineItems: [InvoiceLineItem] = []
        for item in cartItems {
            let productName = item.tierLabel != nil ? "\(item.productName) (\(item.tierLabel!))" : item.productName
            let lineItem = try await InvoiceLineItem.create(
                productId: item.productId,
                productName: productName,
                quantity: item.quantity,
                unitPrice: item.unitPrice,
                taxRate: taxRate
            )
            lineItems.append(lineItem)
        }

        return try await sendInvoice(
            storeId: storeId,
            customer: customer,
            customerName: customerName,
            customerEmail: customerEmail,
            lineItems: lineItems,
            taxRate: taxRate,
            notes: notes,
            locationId: locationId
        )
    }

    // MARK: - Fetch Invoice

    /// Fetch an invoice by ID
    static func fetchInvoice(id: UUID) async throws -> Invoice {
        logger.info("📄 Fetching invoice \(id)")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let invoice: Invoice = try await supabase
            .from("invoices")
            .select()
            .eq("id", value: id.uuidString)
            .single()
            .execute()
            .value

        return invoice
    }

    /// Fetch invoice by order ID
    static func fetchInvoiceByOrder(orderId: UUID) async throws -> Invoice? {
        // Use lowercase UUID for PostgreSQL compatibility
        let orderIdString = orderId.uuidString.lowercased()
        logger.info("📄 Fetching invoice for order \(orderIdString)")

        do {
            let invoices: [Invoice] = try await supabase
                .from("invoices")
                .select()
                .eq("order_id", value: orderIdString)
                .limit(1)
                .execute()
                .value

            logger.info("📄 Decoded \(invoices.count) invoices for order \(orderIdString)")

            if let invoice = invoices.first {
                logger.info("📄 Found invoice: \(invoice.invoiceNumber), status: \(invoice.status.rawValue)")
            } else {
                logger.info("📄 No invoice found for order \(orderIdString)")
            }

            return invoices.first
        } catch {
            logger.error("📄 Failed to fetch/decode invoice: \(error)")
            throw error
        }
    }

    /// Fetch all invoices for a store
    static func fetchInvoices(storeId: UUID, limit: Int = 50) async throws -> [Invoice] {
        logger.info("📄 Fetching invoices for store \(storeId)")

        let invoices: [Invoice] = try await supabase
            .from("invoices")
            .select()
            .eq("store_id", value: storeId.uuidString)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value

        logger.info("📄 Fetched \(invoices.count) invoices")
        return invoices
    }

    // MARK: - Resend Invoice

    private static var resendFunctionURL: URL {
        guard let url = URL(string: "\(SupabaseConfig.baseURL)/functions/v1/resend-invoice") else {
            fatalError("Invalid resend-invoice edge function URL")
        }
        return url
    }

    /// Resend an invoice email
    static func resendInvoice(invoiceId: UUID) async throws -> Bool {
        logger.info("📧 Resending invoice \(invoiceId)")

        // Get auth token
        let session = try await supabase.auth.session
        let accessToken = session.accessToken

        // Make request
        var urlRequest = URLRequest(url: resendFunctionURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let body = ["invoiceId": invoiceId.uuidString]
        urlRequest.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw InvoiceError.networkError("Invalid response")
        }

        if httpResponse.statusCode != 200 {
            if let errorJson = try? JSONDecoder().decode([String: String].self, from: data),
               let errorMessage = errorJson["error"] {
                throw InvoiceError.serverError(errorMessage)
            }
            throw InvoiceError.serverError("HTTP \(httpResponse.statusCode)")
        }

        // Parse response
        if let json = try? JSONDecoder().decode([String: Bool].self, from: data),
           let success = json["success"] {
            logger.info("✅ Invoice resent: \(success)")
            return success
        }

        return true
    }

    // MARK: - Send Reminder

    private static var reminderFunctionURL: URL {
        guard let url = URL(string: "\(SupabaseConfig.baseURL)/functions/v1/send-invoice-reminder") else {
            fatalError("Invalid send-invoice-reminder edge function URL")
        }
        return url
    }

    /// Send a payment reminder for an unpaid invoice
    static func sendReminder(invoiceId: UUID) async throws -> Bool {
        logger.info("🔔 Sending reminder for invoice \(invoiceId)")

        // Get auth token
        let session = try await supabase.auth.session
        let accessToken = session.accessToken

        // Make request
        var urlRequest = URLRequest(url: reminderFunctionURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let body = ["invoiceId": invoiceId.uuidString]
        urlRequest.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw InvoiceError.networkError("Invalid response")
        }

        if httpResponse.statusCode != 200 {
            if let errorJson = try? JSONDecoder().decode([String: String].self, from: data),
               let errorMessage = errorJson["error"] {
                throw InvoiceError.serverError(errorMessage)
            }
            throw InvoiceError.serverError("HTTP \(httpResponse.statusCode)")
        }

        // Parse response
        if let json = try? JSONDecoder().decode([String: Bool].self, from: data),
           let success = json["success"] {
            logger.info("✅ Reminder sent: \(success)")
            return success
        }

        return true
    }

    // MARK: - Real-time Subscription

    /// Subscribe to real-time updates for invoices on a specific order
    /// This allows subscribing before knowing the invoice ID
    /// Returns an AsyncStream that emits Invoice updates
    static func subscribeToInvoiceByOrder(orderId: UUID) -> AsyncStream<Invoice> {
        AsyncStream { continuation in
            let channelName = "invoice-order-\(orderId.uuidString.prefix(8))-\(UInt64(Date().timeIntervalSince1970 * 1000))"
            logger.info("📄 Subscribing to invoice updates for order: \(channelName)")

            let channel = supabase.channel(channelName)

            // Listen for changes on invoices for this order
            let changes = channel.postgresChange(
                UpdateAction.self,
                schema: "public",
                table: "invoices",
                filter: "order_id=eq.\(orderId.uuidString.lowercased())"
            )

            Task {
                await channel.subscribe()
                logger.info("📄 Invoice subscription active for order \(orderId.uuidString.prefix(8))")

                for await change in changes {
                    logger.info("📄 Invoice update received for order")

                    // Decode the updated invoice
                    do {
                        let record = change.record
                        let data = try JSONSerialization.data(withJSONObject: sanitizeForJSON(record))
                        let decoder = JSONDecoder()
                        let invoice = try decoder.decode(Invoice.self, from: data)
                        continuation.yield(invoice)
                    } catch {
                        logger.error("📄 Failed to decode invoice update: \(error)")
                    }
                }
            }

            continuation.onTermination = { _ in
                logger.info("📄 Invoice subscription terminated")
                Task {
                    await channel.unsubscribe()
                    await supabase.removeChannel(channel)
                }
            }
        }
    }

    /// Subscribe to real-time updates for a specific invoice by ID
    /// Returns an AsyncStream that emits Invoice updates
    static func subscribeToInvoice(invoiceId: UUID) -> AsyncStream<Invoice> {
        AsyncStream { continuation in
            let channelName = "invoice-\(invoiceId.uuidString.prefix(8))-\(UInt64(Date().timeIntervalSince1970 * 1000))"
            logger.info("📄 Subscribing to invoice updates: \(channelName)")

            let channel = supabase.channel(channelName)

            // Listen for changes on this specific invoice
            let changes = channel.postgresChange(
                UpdateAction.self,
                schema: "public",
                table: "invoices",
                filter: "id=eq.\(invoiceId.uuidString.lowercased())"
            )

            Task {
                await channel.subscribe()
                logger.info("📄 Invoice subscription active")

                for await change in changes {
                    logger.info("📄 Invoice update received")

                    // Decode the updated invoice
                    do {
                        let record = change.record
                        let data = try JSONSerialization.data(withJSONObject: sanitizeForJSON(record))
                        let decoder = JSONDecoder()
                        let invoice = try decoder.decode(Invoice.self, from: data)
                        continuation.yield(invoice)
                    } catch {
                        logger.error("📄 Failed to decode invoice update: \(error)")
                    }
                }
            }

            continuation.onTermination = { _ in
                logger.info("📄 Invoice subscription terminated")
                Task {
                    await channel.unsubscribe()
                    await supabase.removeChannel(channel)
                }
            }
        }
    }

    /// Sanitize record for JSON serialization (handle AnyJSON types)
    private static func sanitizeForJSON(_ record: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in record {
            if let dict = value as? [String: Any] {
                result[key] = sanitizeForJSON(dict)
            } else if let array = value as? [Any] {
                result[key] = array.map { item -> Any in
                    if let dictItem = item as? [String: Any] {
                        return sanitizeForJSON(dictItem) as Any
                    }
                    return convertToJSONSafe(item)
                }
            } else {
                result[key] = convertToJSONSafe(value)
            }
        }
        return result
    }

    private static func convertToJSONSafe(_ value: Any) -> Any {
        // Handle AnyJSON and other Swift-bridged types
        if let stringValue = value as? String { return stringValue }
        if let intValue = value as? Int { return intValue }
        if let doubleValue = value as? Double { return doubleValue }
        if let boolValue = value as? Bool { return boolValue }
        if value is NSNull { return NSNull() }
        // Convert unknown types to string representation
        return String(describing: value)
    }
}


