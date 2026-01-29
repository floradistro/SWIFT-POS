//
//  ShippingLabelService.swift
//  Whale
//
//  Native iOS shipping label generation and printing via EasyPost.
//  Bypasses browser - prints directly via AirPrint.
//

import Foundation
import UIKit
import Supabase
import os.log

// MARK: - Label Response

struct ShippingLabelResponse: Codable {
    let success: Bool
    let trackingNumber: String?
    let trackingUrl: String?
    let labelUrl: String?
    let carrier: String?
    let service: String?
    let cost: Double?
    let shipmentId: String?
    let error: String?
}

// MARK: - Shipping Label Service

enum ShippingLabelService {

    /// Generate a shipping label via EasyPost edge function
    static func generateLabel(orderId: UUID, locationId: UUID) async throws -> ShippingLabelResponse {
        Log.network.info("Generating shipping label for order: \(orderId.uuidString)")

        // Build request body
        struct LabelRequest: Encodable {
            let orderId: String
            let locationId: String
        }

        let request = LabelRequest(
            orderId: orderId.uuidString,
            locationId: locationId.uuidString
        )

        do {
            let response: ShippingLabelResponse = try await supabase.functions
                .invoke(
                    "easypost-create-label",
                    options: FunctionInvokeOptions(body: request)
                )

            if response.success {
                Log.network.info("Label generated successfully: \(response.trackingNumber ?? "unknown")")
            } else {
                Log.network.error("Label generation failed: \(response.error ?? "unknown error")")
            }

            return response
        } catch let error as FunctionsError {
            // Edge function returned an error status code
            Log.network.error("Edge function error: \(error.localizedDescription)")

            // Try to extract error message from the response body
            if case .httpError(let code, let data) = error {
                Log.network.error("HTTP error \(code)")
                if let errorResponse = try? JSONDecoder().decode(ShippingLabelResponse.self, from: data) {
                    return errorResponse
                }
                // Try to get raw error message
                if let message = String(data: data, encoding: .utf8) {
                    return ShippingLabelResponse(
                        success: false,
                        trackingNumber: nil,
                        trackingUrl: nil,
                        labelUrl: nil,
                        carrier: nil,
                        service: nil,
                        cost: nil,
                        shipmentId: nil,
                        error: "Server error: \(message)"
                    )
                }
            }

            return ShippingLabelResponse(
                success: false,
                trackingNumber: nil,
                trackingUrl: nil,
                labelUrl: nil,
                carrier: nil,
                service: nil,
                cost: nil,
                shipmentId: nil,
                error: error.localizedDescription
            )
        }
    }

    /// Download PDF data from label URL
    static func downloadLabelPDF(from urlString: String) async throws -> Data {
        guard let url = URL(string: urlString) else {
            throw LabelError.invalidURL
        }

        Log.network.info("Downloading label PDF from: \(urlString)")

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw LabelError.downloadFailed
        }

        Log.network.info("Label PDF downloaded: \(data.count) bytes")
        return data
    }

    /// Print label directly via AirPrint (no browser)
    @MainActor
    static func printLabel(pdfData: Data, jobName: String = "Shipping Label") async -> Bool {
        let printController = UIPrintInteractionController.shared

        // Configure print info
        let printInfo = UIPrintInfo(dictionary: nil)
        printInfo.jobName = jobName
        printInfo.outputType = .general
        printInfo.orientation = .portrait
        printInfo.duplex = .none

        // Dismiss any existing print UI first to reset state
        printController.dismiss(animated: false)

        // Small delay to let UI clean up
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        printController.printInfo = printInfo
        printController.printingItem = pdfData

        // Present native iOS print dialog
        return await withCheckedContinuation { continuation in
            // Get the top-most view controller for proper presentation on iPad
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.windows.first(where: { $0.isKeyWindow }),
                  let rootVC = window.rootViewController else {
                continuation.resume(returning: false)
                return
            }

            var topVC = rootVC
            while let presented = topVC.presentedViewController {
                topVC = presented
            }

            if UIDevice.current.userInterfaceIdiom == .pad {
                // For iPad: present from a centered source rect
                let sourceRect = CGRect(
                    x: topVC.view.bounds.midX - 1,
                    y: topVC.view.bounds.midY - 1,
                    width: 2,
                    height: 2
                )
                printController.present(from: sourceRect, in: topVC.view, animated: true) { _, completed, error in
                    if let error = error {
                        Log.ui.error("Print error: \(error.localizedDescription)")
                    }
                    continuation.resume(returning: completed)
                }
            } else {
                // For iPhone: present normally
                printController.present(animated: true) { _, completed, error in
                    if let error = error {
                        Log.ui.error("Print error: \(error.localizedDescription)")
                    }
                    continuation.resume(returning: completed)
                }
            }
        }
    }

    /// Print label from URL (download + print in one step)
    @MainActor
    static func printLabelFromURL(_ urlString: String, jobName: String = "Shipping Label") async throws -> Bool {
        let pdfData = try await downloadLabelPDF(from: urlString)
        return await printLabel(pdfData: pdfData, jobName: jobName)
    }

    /// Preview label in a share sheet (alternative to printing)
    @MainActor
    static func shareLabelPDF(pdfData: Data, from viewController: UIViewController) {
        let activityVC = UIActivityViewController(
            activityItems: [pdfData],
            applicationActivities: nil
        )

        // For iPad
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = viewController.view
            popover.sourceRect = CGRect(x: viewController.view.bounds.midX, y: viewController.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }

        viewController.present(activityVC, animated: true)
    }
}

// MARK: - Errors

enum LabelError: LocalizedError {
    case invalidURL
    case downloadFailed
    case printFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid label URL"
        case .downloadFailed: return "Failed to download label"
        case .printFailed: return "Failed to print label"
        }
    }
}
