//
//  LabelTemplateSheet.swift
//  Whale
//
//  Label printing sheet for products - extracted from LabelPrintService.
//

import SwiftUI
import os

// MARK: - Label Print Item Model

struct LabelPrintItem: Identifiable {
    let id = UUID()
    let product: Product
    var quantity: Int
    var tierLabel: String?
    var tierQuantity: Double?  // Quantity in grams for the selected tier
    var isWarehouseMode: Bool = false  // Warehouse can add stock via labels
    var customQuantityValue: Double = 0  // Custom quantity entered by user
    var isCustomQuantity: Bool = false  // Whether user selected custom quantity mode

    /// Available stock for this product (in base units, typically grams)
    var availableStock: Double {
        Double(product.availableStock)
    }

    /// Whether the product is weight-based (flower, concentrates) vs unit-based (edibles, pre-rolls)
    var isWeightBased: Bool {
        let category = product.primaryCategory?.name ?? ""
        let lower = category.lowercased()
        return lower.contains("flower") || lower.contains("concentrate") || lower.contains("hash")
    }

    /// Unit display string (e.g., "grams" or "units")
    var unitDisplayString: String {
        isWeightBased ? "grams" : "units"
    }

    /// Display label for the selected tier (e.g., "3.5g" or "Custom 28g")
    var displayTierLabel: String? {
        if let tier = tierLabel {
            return tier
        }
        if customQuantityValue > 0 {
            let formatted = customQuantityValue.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0f", customQuantityValue)
                : String(format: "%.1f", customQuantityValue)
            return "Custom \(formatted)g"
        }
        return nil
    }

    /// Max labels that can be printed based on stock and tier
    var maxLabels: Int {
        // Warehouse mode - no limit (adding stock)
        if isWarehouseMode { return 999 }

        // Use custom quantity if set
        let effectiveTierQty = customQuantityValue > 0 ? customQuantityValue : tierQuantity

        guard let tierQty = effectiveTierQty, tierQty > 0 else {
            // No tier selected - allow up to stock quantity labels
            return max(1, Int(availableStock))
        }
        return max(0, Int(floor(availableStock / tierQty)))
    }

    /// Tiers that have enough stock for at least 1 label
    func availableTiers(forWarehouse: Bool) -> [PricingTier] {
        let allTiers = product.allTiers.sorted { ($0.sortOrder ?? 0) < ($1.sortOrder ?? 0) }
        // Warehouse can print any tier (adding stock)
        if forWarehouse { return allTiers }
        // Retail - only tiers with enough stock
        return allTiers.filter { availableStock >= $0.quantity }
    }

    /// Whether there's enough stock for the current selection
    var hasStock: Bool {
        // Warehouse mode - always has "stock" (adding new)
        if isWarehouseMode { return true }

        // Use custom quantity if set
        let effectiveTierQty = customQuantityValue > 0 ? customQuantityValue : tierQuantity

        if let tierQty = effectiveTierQty {
            return availableStock >= tierQty * Double(max(1, quantity))
        }
        return availableStock >= Double(max(1, quantity))
    }
}

// MARK: - Label Template Sheet View

struct LabelTemplateSheet: View {
    let products: [Product]
    let store: Store?
    let location: Location?
    @Binding var isPrinting: Bool
    let onDismiss: () -> Void
    var embedded: Bool = false  // Legacy parameter, now always uses NavigationStack

    @Environment(\.dismiss) private var dismiss
    @State private var storeLogoImage: UIImage?
    @State private var isSelectingPrinter = false
    @State private var printItems: [LabelPrintItem] = []
    @State private var customQuantityInput: String = ""
    @State private var editingCustomItemId: UUID?
    @FocusState private var isCustomInputFocused: Bool

    @ObservedObject private var settings = LabelPrinterSettings.shared

    /// Whether current location is a warehouse (can add stock via labels)
    private var isWarehouse: Bool {
        location?.isWarehouse ?? false
    }

    private var totalLabels: Int {
        printItems.reduce(0) { $0 + $1.quantity }
    }

    var body: some View {
        NavigationStack {
            sheetContent
                .navigationTitle("Print Labels")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            guard !isPrinting else { return }
                            dismiss()
                            onDismiss()
                        }
                    }
                }
        }
        .interactiveDismissDisabled(isPrinting)
    }

    @ViewBuilder
    private var sheetContent: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        // Template info (start position is now in Printer Settings)
                        ModalSection {
                            HStack {
                                Image(systemName: "rectangle.grid.2x2")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.6))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Avery 5163")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.white)
                                    Text("2×4\" • 10 per sheet • Starting at position \(settings.startPosition + 1)")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.white.opacity(0.5))
                                }
                                Spacer()
                            }
                        }

                        // Products with quantity controls
                        ForEach($printItems) { $item in
                            productRow(item: $item)
                        }

                        // Printer selection
                        ModalSection {
                            Button {
                                Haptics.light()
                                isSelectingPrinter = true
                            } label: {
                                HStack {
                                    Image(systemName: "printer")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.6))

                                    if let name = settings.printerName {
                                        Text(name)
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundStyle(.white)
                                    } else {
                                        Text("Select Printer")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundStyle(.white.opacity(0.5))
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.3))
                                }
                            }
                            .buttonStyle(.plain)
                        }

                        // Auto-print toggle
                        ModalSection {
                            HStack {
                                Image(systemName: settings.isAutoPrintEnabled ? "printer.fill" : "printer")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(settings.isAutoPrintEnabled ? Design.Colors.Semantic.accent : .white.opacity(0.5))

                                Text("Auto-print on sale")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.white)

                                Spacer()

                                Toggle("", isOn: $settings.isAutoPrintEnabled)
                                    .labelsHidden()
                                    .tint(Design.Colors.Semantic.accent)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 16)
                }

                // Print buttons
                HStack(spacing: 12) {
                    // Preview button - shows iOS print dialog with settings
                    Button {
                        Task { await printLabels(showPreview: true) }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "eye")
                                .font(.system(size: 14, weight: .medium))
                            Text("Preview")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.1)))
                    }
                    .disabled(totalLabels == 0 || isPrinting)
                    .opacity(totalLabels == 0 || isPrinting ? 0.5 : 1)

                    // Direct print button
                    ModalActionButton(
                        "Print \(totalLabels)",
                        isLoading: isPrinting
                    ) {
                        Task { await printLabels(showPreview: false) }
                    }
                    .disabled(totalLabels == 0)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        .sheet(isPresented: $isSelectingPrinter) {
            LabelPrinterSetupView(isPresented: $isSelectingPrinter)
        }
        .task {
            await loadStoreLogo()
            initializePrintItems()
        }
    }

    // MARK: - Helper Functions

    private func initializePrintItems() {
        let warehouseMode = isWarehouse
        printItems = products.map { LabelPrintItem(product: $0, quantity: 1, tierLabel: nil, isWarehouseMode: warehouseMode) }
    }

    @ViewBuilder
    private func productRow(item: Binding<LabelPrintItem>) -> some View {
        let maxLabels = item.wrappedValue.maxLabels
        let hasStock = item.wrappedValue.hasStock
        let stockAmount = Int(item.wrappedValue.availableStock)
        let isWarehouseItem = item.wrappedValue.isWarehouseMode

        ModalSection {
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    // Product image
                    if let url = item.wrappedValue.product.iconUrl {
                        AsyncImage(url: url) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Color.white.opacity(0.1)
                        }
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.white.opacity(0.1))
                            .frame(width: 40, height: 40)
                            .overlay {
                                Text(String(item.wrappedValue.product.name.prefix(1)))
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.4))
                            }
                    }

                    // Product name + stock info
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.wrappedValue.product.name)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        HStack(spacing: 4) {
                            if let tier = item.wrappedValue.displayTierLabel {
                                Text(tier)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(item.wrappedValue.isCustomQuantity ? .purple.opacity(0.9) : .white.opacity(0.5))
                                Text("•")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.white.opacity(0.3))
                            }
                            if isWarehouseItem {
                                Text("Adding stock")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.green.opacity(0.8))
                            } else {
                                Text("\(stockAmount)g in stock")
                                    .font(.system(size: 11))
                                    .foregroundStyle(stockAmount > 0 ? .white.opacity(0.5) : .red.opacity(0.8))
                            }
                        }
                    }

                    Spacer()

                    // Quantity stepper
                    HStack(spacing: 0) {
                        Button {
                            Haptics.light()
                            if item.wrappedValue.quantity > 0 {
                                item.wrappedValue.quantity -= 1
                            }
                        } label: {
                            Image(systemName: "minus")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 28)
                        }

                        Text("\(item.wrappedValue.quantity)")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 32)

                        Button {
                            Haptics.light()
                            if item.wrappedValue.quantity < maxLabels {
                                item.wrappedValue.quantity += 1
                            }
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(item.wrappedValue.quantity >= maxLabels ? .white.opacity(0.3) : .white)
                                .frame(width: 32, height: 28)
                        }
                        .disabled(item.wrappedValue.quantity >= maxLabels)
                    }
                    .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.08)))
                }

                // Tier chips
                let availableTiers = item.wrappedValue.availableTiers(forWarehouse: isWarehouseItem)
                if !availableTiers.isEmpty {
                    tierChips(item: item, availableTiers: availableTiers)
                } else if !item.wrappedValue.product.allTiers.isEmpty && !isWarehouseItem {
                    Text("Not enough stock for any size")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange.opacity(0.8))
                }
            }
        }
        .opacity(hasStock ? 1 : 0.5)
    }

    @ViewBuilder
    private func tierChips(item: Binding<LabelPrintItem>, availableTiers: [PricingTier]) -> some View {
        let isWarehouseItem = item.wrappedValue.isWarehouseMode
        let isEditingThis = editingCustomItemId == item.wrappedValue.id

        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    // No size option
                    tierChip(
                        label: "No Size",
                        isSelected: item.wrappedValue.tierLabel == nil && !item.wrappedValue.isCustomQuantity,
                        maxCount: nil
                    ) {
                        item.wrappedValue.tierLabel = nil
                        item.wrappedValue.tierQuantity = nil
                        item.wrappedValue.isCustomQuantity = false
                        item.wrappedValue.customQuantityValue = 0
                        editingCustomItemId = nil
                        // Clamp quantity to new max
                        let newMax = item.wrappedValue.maxLabels
                        if item.wrappedValue.quantity > newMax {
                            item.wrappedValue.quantity = max(0, newMax)
                        }
                    }

                    ForEach(availableTiers, id: \.id) { tier in
                        // Warehouse has no max, retail shows max based on stock
                        let maxForTier = isWarehouseItem ? nil : Int(floor(item.wrappedValue.availableStock / tier.quantity))
                        tierChip(
                            label: tier.label,
                            isSelected: item.wrappedValue.tierLabel == tier.label && !item.wrappedValue.isCustomQuantity,
                            maxCount: maxForTier
                        ) {
                            item.wrappedValue.tierLabel = tier.label
                            item.wrappedValue.tierQuantity = tier.quantity
                            item.wrappedValue.isCustomQuantity = false
                            item.wrappedValue.customQuantityValue = 0
                            editingCustomItemId = nil
                            // Clamp quantity to new max (only for retail)
                            if !isWarehouseItem, let tierMax = maxForTier, item.wrappedValue.quantity > tierMax {
                                item.wrappedValue.quantity = Swift.max(0, tierMax)
                            }
                        }
                    }

                    // Custom bulk option
                    customTierChip(
                        item: item,
                        isSelected: item.wrappedValue.isCustomQuantity,
                        isEditing: isEditingThis
                    )
                }
            }

            // Custom quantity input row (shown when Custom is selected)
            if item.wrappedValue.isCustomQuantity {
                customQuantityInputRow(item: item, isEditing: isEditingThis)
            }
        }
    }

    @ViewBuilder
    private func tierChip(label: String, isSelected: Bool, maxCount: Int?, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.light()
            action()
        } label: {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                if let max = maxCount {
                    Text("(\(max))")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(isSelected ? .black.opacity(0.5) : .white.opacity(0.4))
                }
            }
            .foregroundStyle(isSelected ? .black : .white.opacity(0.6))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Capsule())
            .background(Capsule().fill(isSelected ? .white : .white.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func customTierChip(item: Binding<LabelPrintItem>, isSelected: Bool, isEditing: Bool) -> some View {
        Button {
            Haptics.light()
            item.wrappedValue.isCustomQuantity = true
            item.wrappedValue.tierLabel = nil
            item.wrappedValue.tierQuantity = nil
            editingCustomItemId = item.wrappedValue.id
            // Initialize with existing value or empty
            if item.wrappedValue.customQuantityValue > 0 {
                customQuantityInput = String(format: "%.0f", item.wrappedValue.customQuantityValue)
            } else {
                customQuantityInput = ""
            }
            isCustomInputFocused = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "pencil.line")
                    .font(.system(size: 9, weight: .semibold))
                if isSelected && item.wrappedValue.customQuantityValue > 0 {
                    Text(item.wrappedValue.displayTierLabel ?? "Custom")
                        .font(.system(size: 11, weight: .semibold))
                } else {
                    Text("Custom")
                        .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                }
            }
            .foregroundStyle(isSelected ? .white : .white.opacity(0.6))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Capsule())
            .background(
                Capsule()
                    .fill(isSelected
                        ? LinearGradient(colors: [.purple, .purple.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        : LinearGradient(colors: [.white.opacity(0.1), .white.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func customQuantityInputRow(item: Binding<LabelPrintItem>, isEditing: Bool) -> some View {
        let isWeightBased = item.wrappedValue.isWeightBased
        let presets = isWeightBased ? [28, 56, 112, 224, 448] : [5, 10, 25, 50, 100]

        HStack(spacing: 8) {
            // Input field
            HStack(spacing: 6) {
                TextField("Enter amount", text: $customQuantityInput)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .keyboardType(.decimalPad)
                    .focused($isCustomInputFocused)
                    .frame(width: 80)
                    .onChange(of: customQuantityInput) { _, newValue in
                        // Update the custom quantity value as user types
                        if let value = Double(newValue), value > 0 {
                            item.wrappedValue.customQuantityValue = value
                            // Clamp label quantity if needed
                            let newMax = item.wrappedValue.maxLabels
                            if item.wrappedValue.quantity > newMax {
                                item.wrappedValue.quantity = max(1, newMax)
                            }
                        }
                    }

                Text(item.wrappedValue.unitDisplayString)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.purple.opacity(0.15))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.purple.opacity(0.3), lineWidth: 1)
            )

            // Quick presets
            HStack(spacing: 6) {
                ForEach(presets, id: \.self) { preset in
                    Button {
                        Haptics.light()
                        customQuantityInput = "\(preset)"
                        item.wrappedValue.customQuantityValue = Double(preset)
                        // Clamp label quantity if needed
                        let newMax = item.wrappedValue.maxLabels
                        if item.wrappedValue.quantity > newMax {
                            item.wrappedValue.quantity = max(1, newMax)
                        }
                    } label: {
                        Text(formatPresetLabel(preset, isWeightBased: isWeightBased))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(item.wrappedValue.customQuantityValue == Double(preset) ? .black : .white.opacity(0.7))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(item.wrappedValue.customQuantityValue == Double(preset) ? .white : .white.opacity(0.1))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            // Confirm button
            if item.wrappedValue.customQuantityValue > 0 {
                Button {
                    Haptics.medium()
                    isCustomInputFocused = false
                    editingCustomItemId = nil
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 4)
    }

    private func formatPresetLabel(_ value: Int, isWeightBased: Bool) -> String {
        guard isWeightBased else {
            // Unit-based: just show the number
            return "\(value)"
        }
        // Weight-based: show oz/lb conversions
        if value >= 448 { return "1lb" }
        if value >= 224 { return "½lb" }
        if value >= 112 { return "¼lb" }
        if value >= 56 { return "2oz" }
        if value >= 28 { return "1oz" }
        return "\(value)g"
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

    private func printLabels(showPreview: Bool = false) async {
        let itemsToPrint = printItems.filter { $0.quantity > 0 }
        guard !itemsToPrint.isEmpty else { return }

        guard let storeId = store?.id else {
            Log.ui.error("Cannot print labels: no store ID")
            return
        }

        isPrinting = true
        defer { isPrinting = false }

        var allProducts: [Product] = []
        var allTierLabels: [String?] = []

        for item in itemsToPrint {
            Log.ui.info("Label item: \(item.product.name) qty=\(item.quantity) isCustom=\(item.isCustomQuantity) customValue=\(item.customQuantityValue) tierLabel=\(item.tierLabel ?? "nil") displayTier=\(item.displayTierLabel ?? "nil") isWeightBased=\(item.isWeightBased)")
            for _ in 0..<item.quantity {
                allProducts.append(item.product)
                allTierLabels.append(item.displayTierLabel)
            }
        }

        let totalLabels = allProducts.count
        let pagesNeeded = (totalLabels + 9) / 10  // 10 labels per sheet
        Log.ui.info("📋 PRINT JOB: \(itemsToPrint.count) products → \(totalLabels) total labels → \(pagesNeeded) pages needed, showPreview=\(showPreview)")

        // Use new PrintService with backend-first QR registration
        // QR codes are guaranteed to be registered BEFORE printing
        let result = await PrintService.shared.printManualLabels(
            storeId: storeId,
            products: allProducts,
            tierLabels: allTierLabels,
            locationId: location?.id,
            locationName: location?.name ?? "Licensed Dispensary",
            storeLogoUrl: store?.fullLogoUrl,
            printerUrl: settings.printerUrl,
            startPosition: settings.startPosition,
            showPreview: showPreview
        )

        switch result {
        case .success(let itemsPrinted, let qrCodesRegistered):
            Log.ui.info("✅ Manual print SUCCESS: \(itemsPrinted) labels printed, \(qrCodesRegistered) QR codes registered")
        case .partialSuccess(let printed, let failed):
            Log.ui.warning("⚠️ Manual print partial: \(printed) printed, \(failed.count) failed")
        case .failure(let error):
            Log.ui.error("❌ Manual print FAILED: \(error.localizedDescription)")
            Haptics.error()
        }

        // Keep position persistent - user can manually change it in printer settings
        // This allows continuing on a partially-used label sheet

        onDismiss()
    }
}

// MARK: - Compatibility alias
typealias ProductLabelTemplateSheet = LabelTemplateSheet
typealias BulkLabelPrintSheet = LabelTemplateSheet
