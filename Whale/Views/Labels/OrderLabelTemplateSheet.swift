//
//  OrderLabelTemplateSheet.swift
//  Whale
//
//  Label printing sheet for orders - extracted from LabelPrintService.
//

import SwiftUI
import os

struct OrderLabelTemplateSheet: View {
    let orders: [Order]
    let store: Store?
    let location: Location?
    @Binding var isPrinting: Bool
    let onDismiss: () -> Void

    @State private var isPresented = true
    @State private var storeLogoImage: UIImage?

    private var totalItems: Int {
        orders.reduce(0) { $0 + ($1.items ?? []).reduce(0) { $0 + $1.quantity } }
    }

    var body: some View {
        UnifiedModal(isPresented: $isPresented, id: "order-labels", dismissOnTapOutside: !isPrinting) {
            VStack(spacing: 0) {
                ModalHeader("Print Order Labels", subtitle: "\(orders.count) order\(orders.count == 1 ? "" : "s")", onClose: {
                    guard !isPrinting else { return }
                    onDismiss()
                }) { EmptyView() }

                VStack(spacing: 12) {
                    ModalSection {
                        HStack {
                            Image(systemName: "shippingbox")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.white.opacity(0.6))

                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(totalItems) item\(totalItems == 1 ? "" : "s")")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white)
                                Text("One label per item")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                            Spacer()
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                Spacer().frame(height: 20)

                ModalActionButton(
                    "Print \(totalItems) Label\(totalItems == 1 ? "" : "s")",
                    isLoading: isPrinting
                ) {
                    Task { await printLabels() }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .task {
            await loadStoreLogo()
        }
    }

    private func loadStoreLogo() async {
        guard let url = store?.fullLogoUrl else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            storeLogoImage = UIImage(data: data)
        } catch {
            Log.network.warning("Failed to load store logo: \(error.localizedDescription)")
        }
    }

    private func printLabels() async {
        guard let storeId = store?.id else {
            Log.ui.error("Cannot print order labels: no store ID")
            return
        }

        isPrinting = true
        defer { isPrinting = false }

        // Use new PrintService with backend-first QR registration
        // QR codes are guaranteed to be registered BEFORE printing
        let result = await PrintService.shared.printOrderLabels(
            orders: orders,
            storeId: storeId,
            locationId: location?.id,
            locationName: location?.name ?? "Licensed Dispensary",
            storeLogoUrl: store?.fullLogoUrl
        )

        switch result {
        case .success(let itemsPrinted, let qrCodesRegistered):
            Log.ui.info("✅ Order print SUCCESS: \(itemsPrinted) labels printed, \(qrCodesRegistered) QR codes registered")
        case .partialSuccess(let printed, let failed):
            Log.ui.warning("⚠️ Order print partial: \(printed) printed, \(failed.count) failed")
        case .failure(let error):
            Log.ui.error("❌ Order print FAILED: \(error.localizedDescription)")
            Haptics.error()
        }

        onDismiss()
    }
}
