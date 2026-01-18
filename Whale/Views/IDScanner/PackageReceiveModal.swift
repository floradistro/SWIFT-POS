//
//  PackageReceiveModal.swift
//  Whale
//
//  Modal for receiving transfer packages after scanning QR code.
//

import SwiftUI

struct PackageReceiveModal: View {
    let transfer: InventoryTransfer
    let items: [InventoryTransferItem]
    let storeId: UUID
    let onDismiss: () -> Void

    @State private var isPresented = true
    @State private var isLoading = false
    @State private var isReceived = false
    @State private var errorMessage: String?

    @EnvironmentObject private var session: SessionObserver

    private var statusColor: Color {
        switch transfer.status {
        case .draft: return .gray
        case .approved: return .blue
        case .inTransit: return .orange
        case .completed: return .green
        case .cancelled: return .red
        }
    }

    var body: some View {
        UnifiedModal(isPresented: $isPresented, id: "package-receive", dismissOnTapOutside: !isLoading) {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button {
                        Haptics.light()
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(width: 44, height: 44)
                            .background(.white.opacity(0.1), in: Circle())
                    }.buttonStyle(.plain)

                    Spacer()

                    VStack(spacing: 2) {
                        Text("Package").font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
                        Text(transfer.displayNumber).font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    }

                    Spacer()

                    Text(transfer.status.displayName)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(statusColor))
                }
                .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 12)

                // Error banner
                if let error = errorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                        Text(error).font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                        Spacer()
                    }
                    .padding(12).background(Color.red.opacity(0.3)).padding(.horizontal, 20)
                }

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        if isReceived {
                            successContent
                        } else {
                            transferInfoCard
                            itemsList

                            if transfer.status == .inTransit {
                                ModalActionButton("Receive All \(items.count) Items", icon: "shippingbox.and.arrow.backward.fill", isLoading: isLoading) {
                                    receivePackage()
                                }
                            } else if transfer.status == .completed {
                                HStack(spacing: 10) {
                                    Image(systemName: "checkmark.circle.fill").font(.system(size: 18)).foregroundStyle(.green)
                                    Text("Already Received").font(.system(size: 15, weight: .medium)).foregroundStyle(.white.opacity(0.6))
                                }.padding(.vertical, 12)
                            }
                        }
                    }
                    .padding(.horizontal, 20).padding(.bottom, 20)
                }
            }
        }
        .onChange(of: isPresented) { _, newValue in if !newValue { onDismiss() } }
    }

    // MARK: - Transfer Info

    private var transferInfoCard: some View {
        ModalSection {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("FROM").font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.4))
                        Text(transfer.sourceLocationName ?? "Unknown").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    }
                    Image(systemName: "arrow.right").font(.system(size: 14, weight: .bold)).foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TO").font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.4))
                        Text(transfer.destinationLocationName ?? "Unknown").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    }
                    Spacer()
                }
                Divider().background(.white.opacity(0.1))
                HStack {
                    Label("\(items.count) items", systemImage: "cube.box").font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    if let date = transfer.shippedAt ?? transfer.createdAt as Date? {
                        Text(date.formatted(.relative(presentation: .named))).font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
                    }
                }
            }
        }
    }

    // MARK: - Items List

    private var itemsList: some View {
        ModalSection {
            VStack(alignment: .leading, spacing: 10) {
                Text("ITEMS").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.4)).tracking(0.5)

                ForEach(items) { item in
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.1)).frame(width: 40, height: 40)
                            .overlay(Image(systemName: "cube.box").font(.system(size: 16)).foregroundStyle(.white.opacity(0.3)))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.productName ?? "Unknown Product").font(.system(size: 13, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                            if let sku = item.productSKU { Text(sku).font(.system(size: 11)).foregroundStyle(.white.opacity(0.4)) }
                        }
                        Spacer()
                        Text("×\(Int(item.quantity))").font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    }
                    if item.id != items.last?.id { Divider().background(.white.opacity(0.05)) }
                }
            }
        }
    }

    // MARK: - Success Content

    private var successContent: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 64)).foregroundStyle(.green).symbolEffect(.bounce, value: isReceived)
            Text("Package Received!").font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
            Text("\(items.count) items added to inventory").font(.system(size: 14)).foregroundStyle(.white.opacity(0.6))
            Text(transfer.displayNumber).font(.system(size: 12, design: .monospaced)).foregroundStyle(.white.opacity(0.4))

            ModalActionButton("Done", icon: "checkmark") { isPresented = false }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 24)
    }

    // MARK: - Actions

    private func receivePackage() {
        guard let locationId = session.selectedLocation?.id else { errorMessage = "No location selected"; return }
        isLoading = true

        Task {
            do {
                let success = try await InventoryUnitService.shared.receiveTransfer(transferId: transfer.id, storeId: storeId, locationId: locationId, userId: session.userId)
                await MainActor.run {
                    isLoading = false
                    if success { Haptics.success(); isReceived = true }
                    else { errorMessage = "Failed to receive package" }
                }
            } catch {
                await MainActor.run { isLoading = false; errorMessage = error.localizedDescription }
            }
        }
    }
}
