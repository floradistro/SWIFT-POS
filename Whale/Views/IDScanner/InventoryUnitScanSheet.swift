//
//  InventoryUnitScanSheet.swift
//  Whale
//
//  Modal for inventory unit actions after scanning QR code.
//

import SwiftUI

enum InventorySheetScreen { case main, receive, transfer, audit, damage, reprint, success }
enum InventoryScanAction { case receive, transferOut, transferIn, convert, audit, damage, reprint }

struct InventoryUnitScanSheet: View {
    let unit: InventoryUnit
    let lookupResult: LookupResult
    let storeId: UUID
    let onDismiss: () -> Void
    let onAction: (InventoryScanAction) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var currentScreen: InventorySheetScreen = .main
    @State private var isLoading = false
    @State private var successMessage: String?
    @State private var errorMessage: String?
    @State private var binLocation = ""
    @State private var notes = ""
    @State private var auditQuantity = ""
    @State private var damageReason = ""

    @EnvironmentObject private var session: SessionObserver

    private var statusColor: Color {
        switch unit.status {
        case .available: return .green
        case .reserved: return .orange
        case .inTransit: return .blue
        case .consumed, .sold: return .gray
        case .damaged, .expired: return .red
        case .sample, .adjustment: return .purple
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    if let error = errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                            Text(error).font(Design.Typography.footnote).fontWeight(.medium).foregroundStyle(.white)
                            Spacer()
                            Button { errorMessage = nil } label: {
                                Image(systemName: "xmark").font(Design.Typography.caption1).fontWeight(.bold).foregroundStyle(.white.opacity(0.5)).frame(width: 28, height: 28)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(12)
                        .background(Color.red.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 20)
                    }

                    VStack(spacing: 12) {
                        switch currentScreen {
                        case .main: mainContent
                        case .receive: receiveContent
                        case .transfer: transferContent
                        case .audit: auditContent
                        case .damage: damageContent
                        case .reprint: reprintContent
                        case .success: successContent
                        }
                    }
                    .padding(.horizontal, 20).padding(.bottom, 20)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .navigationTitle("Inventory Unit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(currentScreen == .main || currentScreen == .success ? "Done" : "Back") {
                        if currentScreen == .main || currentScreen == .success {
                            dismiss()
                            onDismiss()
                        } else {
                            withAnimation(.spring(response: 0.3)) { currentScreen = .main; clearInputs() }
                        }
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text(unit.status.displayName)
                        .font(Design.Typography.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(statusColor))
                }
            }
        }
        .interactiveDismissDisabled(isLoading)
    }

    // MARK: - Header

    private var modalHeader: some View {
        HStack {
            Button {
                Haptics.light()
                if currentScreen == .main || currentScreen == .success { dismiss(); onDismiss() }
                else { withAnimation(.spring(response: 0.3)) { currentScreen = .main; clearInputs() } }
            } label: {
                Image(systemName: currentScreen == .main || currentScreen == .success ? "xmark" : "chevron.left")
                    .font(Design.Typography.footnote)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
                    .background(Circle().fill(.ultraThinMaterial))
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 2) {
                if currentScreen != .main && currentScreen != .success {
                    Text(unit.productName ?? "Inventory").font(Design.Typography.caption2).fontWeight(.medium).foregroundStyle(.white.opacity(0.4))
                }
                Text(headerTitle).font(Design.Typography.title2Rounded).fontWeight(.bold).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
            }

            Spacer()

            Text(unit.status.displayName).font(Design.Typography.caption2).fontWeight(.bold).foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 4).background(Capsule().fill(statusColor))
        }
        .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 12)
    }

    private var headerTitle: String {
        switch currentScreen {
        case .main: return unit.productName ?? "Inventory Unit"
        case .receive: return "Receive"
        case .transfer: return "Transfer"
        case .audit: return "Audit"
        case .damage: return "Report Damage"
        case .reprint: return "Reprint Label"
        case .success: return "Success"
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        ModalSection {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(statusColor.opacity(0.15)).frame(width: 56, height: 56)
                    VStack(spacing: 2) {
                        Image(systemName: unit.tierIcon).font(Design.Typography.headline).fontWeight(.semibold).foregroundStyle(statusColor)
                        Text(unit.qrPrefix).font(Design.Typography.caption2Mono).fontWeight(.bold).foregroundStyle(statusColor)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(unit.tierLabel ?? unit.tierId.uppercased()).font(Design.Typography.callout).fontWeight(.semibold).foregroundStyle(.white)
                    HStack(spacing: 6) {
                        Text(unit.quantityFormatted).font(Design.Typography.footnoteRounded).fontWeight(.bold).foregroundStyle(statusColor)
                        Text("•").foregroundStyle(.white.opacity(0.3))
                        Text("Gen \(unit.generation)").font(Design.Typography.caption1).foregroundStyle(.white.opacity(0.5))
                    }
                }
                Spacer()
                if let product = lookupResult.product, let imageUrl = product.featuredImage, let url = URL(string: imageUrl) {
                    AsyncImage(url: url) { image in image.resizable().aspectRatio(contentMode: .fill) } placeholder: { Color.white.opacity(0.1) }
                        .frame(width: 50, height: 50).clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }

        ModalSection {
            VStack(spacing: 10) {
                if let location = lookupResult.location { detailRow(icon: "mappin.circle.fill", label: "Location", value: location.name, color: .blue) }
                if let bin = unit.binLocation, !bin.isEmpty { detailRow(icon: "archivebox.fill", label: "Bin", value: bin, color: .purple) }
                if let batch = unit.batchNumber, !batch.isEmpty { detailRow(icon: "number.circle.fill", label: "Batch", value: batch, color: .orange) }
                detailRow(icon: "qrcode", label: "Code", value: unit.qrCode, color: .gray, mono: true)
            }
        }

        if let history = lookupResult.scanHistory, !history.isEmpty {
            ModalSection {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("HISTORY").font(Design.Typography.caption2).fontWeight(.bold).foregroundStyle(.white.opacity(0.4)).tracking(0.5)
                        Spacer()
                        Text("\(history.count) scans").font(Design.Typography.caption2).foregroundStyle(.white.opacity(0.3))
                    }
                    ForEach(history.prefix(3)) { scan in
                        HStack(spacing: 8) {
                            Circle().fill(scanColor(for: scan.operation)).frame(width: 6, height: 6)
                            Text(scan.operation.replacingOccurrences(of: "_", with: " ").capitalized).font(Design.Typography.caption1).fontWeight(.medium).foregroundStyle(.white)
                            Spacer()
                            Text(scan.scannedAt.formatted(.relative(presentation: .named))).font(Design.Typography.caption2).foregroundStyle(.white.opacity(0.4))
                        }
                    }
                }
            }
        }

        // Actions
        VStack(spacing: 8) {
            let isAtCurrentLocation = session.selectedLocation?.id == unit.currentLocationId

            if unit.status == .available {
                if isAtCurrentLocation {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill").font(Design.Typography.callout).foregroundStyle(.green)
                        Text("Already at this location").font(Design.Typography.footnote).fontWeight(.medium).foregroundStyle(.white.opacity(0.6))
                        Spacer()
                    }.padding(.vertical, 8).padding(.horizontal, 14)
                    actionRow("Transfer to Another Location", icon: "arrow.right.circle.fill", color: .blue) { navigateTo(.transfer) }
                } else {
                    actionRow("Receive / Transfer In", icon: "shippingbox.and.arrow.backward.fill", color: .green) { navigateTo(.receive) }
                }
            }

            if unit.status == .inTransit {
                actionRow("Complete Transfer", icon: "shippingbox.and.arrow.backward.fill", color: .green) { navigateTo(.receive) }
            }

            actionRow("Audit / Count", icon: "checklist", color: .orange) { auditQuantity = String(format: "%.1f", unit.quantity); navigateTo(.audit) }
            actionRow("Report Damage", icon: "exclamationmark.triangle.fill", color: .red) { navigateTo(.damage) }
            actionRow("Reprint Label", icon: "printer.fill", color: .gray) { navigateTo(.reprint) }
        }
    }

    // MARK: - Receive Content

    private var isTransferReceive: Bool { session.selectedLocation?.id != unit.currentLocationId }

    @ViewBuilder
    private var receiveContent: some View {
        unitSummaryCard

        if isTransferReceive {
            ModalSection {
                HStack(spacing: 12) {
                    Image(systemName: "shippingbox.and.arrow.backward.fill").font(Design.Typography.title2).foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("TRANSFER IN").font(Design.Typography.caption2).fontWeight(.bold).foregroundStyle(.blue).tracking(0.5)
                        Text("\(lookupResult.location?.name ?? "Unknown") → \(session.selectedLocation?.name ?? "Here")").font(Design.Typography.footnote).fontWeight(.semibold).foregroundStyle(.white)
                    }
                    Spacer()
                }
            }
        }

        ModalSection {
            VStack(alignment: .leading, spacing: 10) {
                Text(isTransferReceive ? "RECEIVE AT" : "CONFIRM LOCATION").font(Design.Typography.caption2).fontWeight(.bold).foregroundStyle(.white.opacity(0.4)).tracking(0.5)
                if let location = session.selectedLocation {
                    HStack(spacing: 12) {
                        Image(systemName: "mappin.circle.fill").font(Design.Typography.title3).foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(location.name).font(Design.Typography.subhead).fontWeight(.semibold).foregroundStyle(.white)
                            Text("Your Location").font(Design.Typography.caption2).foregroundStyle(.white.opacity(0.4))
                        }
                        Spacer()
                        Image(systemName: "checkmark.circle.fill").font(Design.Typography.headline).foregroundStyle(.green)
                    }
                } else {
                    Text("No location selected").font(Design.Typography.footnote).foregroundStyle(.white.opacity(0.5))
                }
            }
        }

        ModalSection {
            VStack(alignment: .leading, spacing: 8) {
                Text("BIN LOCATION (OPTIONAL)").font(Design.Typography.caption2).fontWeight(.bold).foregroundStyle(.white.opacity(0.4)).tracking(0.5)
                TextField("e.g., A-1-3, Shelf B", text: $binLocation).font(Design.Typography.subhead).fontWeight(.medium).foregroundStyle(.white).textInputAutocapitalization(.characters).padding(.vertical, 8)
            }
        }

        notesInput
        Spacer().frame(height: 8)
        ModalActionButton(isTransferReceive ? "Complete Transfer" : "Receive Unit", icon: isTransferReceive ? "shippingbox.and.arrow.backward.fill" : "arrow.down.circle.fill", isLoading: isLoading) { performReceive() }
    }

    // MARK: - Transfer Content

    @ViewBuilder
    private var transferContent: some View {
        unitSummaryCard

        ModalSection {
            VStack(alignment: .leading, spacing: 10) {
                Text("TRANSFER FROM").font(Design.Typography.caption2).fontWeight(.bold).foregroundStyle(.white.opacity(0.4)).tracking(0.5)
                if let location = lookupResult.location {
                    HStack(spacing: 12) {
                        Image(systemName: "building.2.fill").font(Design.Typography.headline).foregroundStyle(.blue)
                        Text(location.name).font(Design.Typography.subhead).fontWeight(.semibold).foregroundStyle(.white)
                        Spacer()
                    }
                }
            }
        }

        ModalSection {
            VStack(alignment: .leading, spacing: 10) {
                Text("TRANSFER TO").font(Design.Typography.caption2).fontWeight(.bold).foregroundStyle(.white.opacity(0.4)).tracking(0.5)
                Text("Select destination when scanning at receiving location").font(Design.Typography.footnote).foregroundStyle(.white.opacity(0.5))
            }
        }

        notesInput
        Spacer().frame(height: 8)
        ModalActionButton("Start Transfer", icon: "arrow.right.circle.fill", isLoading: isLoading) { performTransfer() }
    }

    // MARK: - Audit Content

    @ViewBuilder
    private var auditContent: some View {
        unitSummaryCard

        ModalSection {
            VStack(alignment: .leading, spacing: 12) {
                Text("VERIFY QUANTITY").font(Design.Typography.caption2).fontWeight(.bold).foregroundStyle(.white.opacity(0.4)).tracking(0.5)
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Expected").font(Design.Typography.caption2).foregroundStyle(.white.opacity(0.5))
                        Text(unit.quantityFormatted).font(Design.Typography.title3Rounded).fontWeight(.bold).foregroundStyle(.white.opacity(0.6))
                    }
                    Image(systemName: "arrow.right").font(Design.Typography.footnote).foregroundStyle(.white.opacity(0.3))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Actual").font(Design.Typography.caption2).foregroundStyle(.white.opacity(0.5))
                        HStack(spacing: 4) {
                            TextField("0", text: $auditQuantity).font(Design.Typography.title3Rounded).fontWeight(.bold).foregroundStyle(.white).keyboardType(.decimalPad).frame(width: 80)
                            Text(unit.baseUnit).font(Design.Typography.footnote).fontWeight(.medium).foregroundStyle(.white.opacity(0.5))
                        }
                    }
                }
                if let actual = Double(auditQuantity), actual != unit.quantity {
                    let variance = actual - unit.quantity
                    HStack(spacing: 6) {
                        Image(systemName: variance > 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill").font(Design.Typography.footnote)
                        Text(String(format: "%+.1f%@", variance, unit.baseUnit)).font(Design.Typography.footnote).fontWeight(.semibold)
                        Text("variance").font(Design.Typography.caption1).foregroundStyle(.white.opacity(0.5))
                    }.foregroundStyle(variance > 0 ? .green : .orange).padding(.top, 4)
                }
            }
        }

        notesInput
        Spacer().frame(height: 8)
        ModalActionButton("Confirm Audit", icon: "checkmark.circle.fill", isLoading: isLoading) { performAudit() }
    }

    // MARK: - Damage Content

    @ViewBuilder
    private var damageContent: some View {
        unitSummaryCard

        ModalSection {
            VStack(alignment: .leading, spacing: 10) {
                Text("DAMAGE REASON").font(Design.Typography.caption2).fontWeight(.bold).foregroundStyle(.white.opacity(0.4)).tracking(0.5)
                VStack(spacing: 8) {
                    damageReasonButton("Water Damage", icon: "drop.fill")
                    damageReasonButton("Physical Damage", icon: "hammer.fill")
                    damageReasonButton("Quality Issue", icon: "exclamationmark.triangle.fill")
                    damageReasonButton("Expired", icon: "clock.fill")
                    damageReasonButton("Other", icon: "ellipsis.circle.fill")
                }
            }
        }

        if damageReason == "Other" {
            ModalSection { TextField("Describe the issue...", text: $notes).font(Design.Typography.footnote).foregroundStyle(.white) }
        }

        Spacer().frame(height: 8)
        ModalActionButton("Report Damage", icon: "exclamationmark.triangle.fill", isEnabled: !damageReason.isEmpty, isLoading: isLoading) { performDamage() }
    }

    // MARK: - Reprint Content

    @ViewBuilder
    private var reprintContent: some View {
        unitSummaryCard

        ModalSection {
            VStack(spacing: 16) {
                if let qrImage = QRCodeGenerator.generate(from: unit.trackingURL, size: CGSize(width: 120, height: 120)) {
                    Image(uiImage: qrImage).interpolation(.none).resizable().frame(width: 120, height: 120).clipShape(RoundedRectangle(cornerRadius: 8))
                }
                VStack(spacing: 4) {
                    Text(unit.qrCode).font(Design.Typography.caption1Mono).fontWeight(.medium).foregroundStyle(.white.opacity(0.7))
                    Text(unit.trackingURL).font(Design.Typography.caption2).foregroundStyle(.white.opacity(0.4))
                }
            }.frame(maxWidth: .infinity).padding(.vertical, 8)
        }

        Spacer().frame(height: 8)
        ModalActionButton("Print Label", icon: "printer.fill", isLoading: isLoading) { performReprint() }
        ModalSecondaryButton(title: "Copy QR Code", icon: "doc.on.doc") { UIPasteboard.general.string = unit.qrCode; Haptics.medium() }
    }

    // MARK: - Success Content

    @ViewBuilder
    private var successContent: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 64)).foregroundStyle(.green).symbolEffect(.bounce, value: currentScreen == .success)
            Text(successMessage ?? "Operation Complete").font(Design.Typography.headline).fontWeight(.semibold).foregroundStyle(.white).multilineTextAlignment(.center)
            Text(unit.qrCode).font(Design.Typography.caption1Mono).foregroundStyle(.white.opacity(0.5))
        }.frame(maxWidth: .infinity).padding(.vertical, 24)

        ModalActionButton("Done", icon: "checkmark") { dismiss(); onDismiss() }
        ModalSecondaryButton(title: "Scan Another") { dismiss(); onDismiss(); onAction(.receive) }
    }

    // MARK: - Helper Views

    private var unitSummaryCard: some View {
        ModalSection {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(statusColor.opacity(0.15)).frame(width: 44, height: 44)
                    Image(systemName: unit.tierIcon).font(Design.Typography.callout).fontWeight(.semibold).foregroundStyle(statusColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(unit.productName ?? unit.tierLabel ?? "Unit").font(Design.Typography.footnote).fontWeight(.semibold).foregroundStyle(.white).lineLimit(1)
                    Text("\(unit.quantityFormatted) • \(unit.qrCode.prefix(12))...").font(Design.Typography.caption2Mono).foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
            }
        }
    }

    private var notesInput: some View {
        ModalSection {
            VStack(alignment: .leading, spacing: 8) {
                Text("NOTES (OPTIONAL)").font(Design.Typography.caption2).fontWeight(.bold).foregroundStyle(.white.opacity(0.4)).tracking(0.5)
                TextField("Add notes...", text: $notes).font(Design.Typography.footnote).foregroundStyle(.white)
            }
        }
    }

    private func detailRow(icon: String, label: String, value: String, color: Color, mono: Bool = false) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(Design.Typography.footnote).foregroundStyle(color).frame(width: 20)
            Text(label).font(Design.Typography.caption1).foregroundStyle(.white.opacity(0.5))
            Spacer()
            Text(value).font(mono ? Design.Typography.caption1Mono : Design.Typography.caption1).fontWeight(.medium).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
        }
    }

    private func actionRow(_ title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button { Haptics.light(); action() } label: {
            HStack(spacing: 12) {
                ZStack { Circle().fill(color.opacity(0.15)).frame(width: 36, height: 36); Image(systemName: icon).font(Design.Typography.subhead).foregroundStyle(color) }
                Text(title).font(Design.Typography.subhead).fontWeight(.medium).foregroundStyle(.white)
                Spacer()
                Image(systemName: "chevron.right").font(Design.Typography.caption1).fontWeight(.semibold).foregroundStyle(.white.opacity(0.3))
            }
            .padding(.vertical, 10).padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.ultraThinMaterial))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.white.opacity(0.1), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private func damageReasonButton(_ title: String, icon: String) -> some View {
        Button { Haptics.light(); damageReason = title } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).font(Design.Typography.footnote).foregroundStyle(damageReason == title ? .red : .white.opacity(0.5)).frame(width: 20)
                Text(title).font(Design.Typography.footnote).fontWeight(.medium).foregroundStyle(damageReason == title ? .white : .white.opacity(0.7))
                Spacer()
                if damageReason == title { Image(systemName: "checkmark.circle.fill").font(Design.Typography.callout).foregroundStyle(.red) }
            }
            .padding(.vertical, 10).padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.ultraThinMaterial))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(damageReason == title ? .red.opacity(0.3) : .white.opacity(0.1), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private func scanColor(for operation: String) -> Color {
        switch operation.lowercased() {
        case "receiving", "receive": return .green
        case "transfer_out", "transfer_in": return .blue
        case "audit": return .orange
        case "damage": return .red
        case "sale": return .purple
        default: return .gray
        }
    }

    private func navigateTo(_ screen: InventorySheetScreen) { withAnimation(.spring(response: 0.3)) { currentScreen = screen } }
    private func clearInputs() { binLocation = ""; notes = ""; auditQuantity = ""; damageReason = "" }

    // MARK: - Actions

    private func performReceive() {
        guard let locationId = session.selectedLocation?.id else { errorMessage = "No location selected"; return }
        isLoading = true
        let isTransfer = unit.currentLocationId != locationId
        let fromLocation = lookupResult.location?.name ?? "Unknown"
        let toLocation = session.selectedLocation?.name ?? "location"

        Task {
            do {
                let result = try await InventoryUnitService.shared.scan(qrCode: unit.qrCode, operation: .receiving, storeId: storeId, locationId: locationId, userId: session.userId, newBinLocation: binLocation.isEmpty ? nil : binLocation, notes: notes.isEmpty ? nil : notes)
                await MainActor.run {
                    isLoading = false
                    if result.success {
                        Haptics.success()
                        successMessage = isTransfer ? "Transferred from \(fromLocation) to \(toLocation)" : "Unit received at \(toLocation)"
                        navigateTo(.success)
                        onAction(.receive)
                    } else { errorMessage = result.error ?? "Receive failed" }
                }
            } catch { await MainActor.run { isLoading = false; errorMessage = error.localizedDescription } }
        }
    }

    private func performTransfer() {
        guard let locationId = session.selectedLocation?.id else { errorMessage = "No location selected"; return }
        isLoading = true

        Task {
            do {
                let result = try await InventoryUnitService.shared.scan(qrCode: unit.qrCode, operation: .transferOut, storeId: storeId, locationId: locationId, userId: session.userId, notes: notes.isEmpty ? nil : notes)
                await MainActor.run {
                    isLoading = false
                    if result.success {
                        Haptics.success()
                        successMessage = "Transfer started. Scan at destination to complete."
                        navigateTo(.success)
                        onAction(.transferOut)
                    } else { errorMessage = result.error ?? "Transfer failed" }
                }
            } catch { await MainActor.run { isLoading = false; errorMessage = error.localizedDescription } }
        }
    }

    private func performAudit() {
        guard let locationId = session.selectedLocation?.id else { errorMessage = "No location selected"; return }
        isLoading = true

        Task {
            do {
                let auditNotes = "Quantity verified: \(auditQuantity)\(unit.baseUnit)" + (notes.isEmpty ? "" : " - \(notes)")
                let result = try await InventoryUnitService.shared.scan(qrCode: unit.qrCode, operation: .audit, storeId: storeId, locationId: locationId, userId: session.userId, notes: auditNotes)
                await MainActor.run {
                    isLoading = false
                    if result.success {
                        Haptics.success()
                        successMessage = "Audit complete. Quantity verified."
                        navigateTo(.success)
                        onAction(.audit)
                    } else { errorMessage = result.error ?? "Audit failed" }
                }
            } catch { await MainActor.run { isLoading = false; errorMessage = error.localizedDescription } }
        }
    }

    private func performDamage() {
        guard let locationId = session.selectedLocation?.id else { errorMessage = "No location selected"; return }
        isLoading = true

        Task {
            do {
                let damageNotes = "Damage: \(damageReason)" + (notes.isEmpty ? "" : " - \(notes)")
                let result = try await InventoryUnitService.shared.scan(qrCode: unit.qrCode, operation: .damage, storeId: storeId, locationId: locationId, userId: session.userId, newStatus: "damaged", notes: damageNotes)
                await MainActor.run {
                    isLoading = false
                    if result.success {
                        Haptics.success()
                        successMessage = "Damage reported. Unit marked as damaged."
                        navigateTo(.success)
                        onAction(.damage)
                    } else { errorMessage = result.error ?? "Failed to report damage" }
                }
            } catch { await MainActor.run { isLoading = false; errorMessage = error.localizedDescription } }
        }
    }

    private func performReprint() {
        isLoading = true

        Task {
            if let locationId = session.selectedLocation?.id {
                _ = try? await InventoryUnitService.shared.scan(qrCode: unit.qrCode, operation: .reprint, storeId: storeId, locationId: locationId, userId: session.userId)
            }

            await MainActor.run {
                let product = lookupResult.product
                let labelData = InventoryLabelData(productName: product?.name ?? unit.productName ?? "Unknown", qrCode: unit.qrCode, trackingURL: unit.trackingURL, tierLabel: unit.tierLabel ?? unit.tierId, quantity: unit.quantityFormatted, batchNumber: unit.batchNumber, storeLogo: nil)
                LabelPrintService.printInventoryLabel(labelData, session: session)
                isLoading = false
                Haptics.success()
                successMessage = "Label sent to printer"
                navigateTo(.success)
                onAction(.reprint)
            }
        }
    }
}
