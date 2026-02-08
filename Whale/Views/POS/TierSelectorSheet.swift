//
//  TierSelectorSheet.swift
//  Whale
//
//  Product tier selector - liquid glass design.
//

import SwiftUI
import os.log

struct TierSelectorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SessionObserver

    let product: Product
    let onSelectTier: (PricingTier) -> Void
    let onSelectVariantTier: ((PricingTier, ProductVariant) -> Void)?
    let onInventoryUpdated: ((UUID, Int) -> Void)?
    let onPrintLabels: (() -> Void)?
    let onViewCOA: (() -> Void)?
    let onShowDetail: (() -> Void)?

    @State private var localStock: Int
    @State private var selectedVariantId: UUID? = nil
    @State private var variantTiers: [PricingTier] = []

    // Quick audit
    @State private var showQuickAudit = false
    @State private var auditQuantity = ""
    @State private var auditReason: QuickAuditReason = .count
    @State private var isSubmitting = false
    @State private var auditError: String?

    @Namespace private var animation

    // Legacy init
    init(
        isPresented: Binding<Bool>,
        product: Product,
        onSelectTier: @escaping (PricingTier) -> Void,
        onSelectVariantTier: ((PricingTier, ProductVariant) -> Void)? = nil,
        onInventoryUpdated: ((UUID, Int) -> Void)? = nil,
        onPrintLabels: (() -> Void)? = nil,
        onViewCOA: (() -> Void)? = nil,
        onShowDetail: (() -> Void)? = nil
    ) {
        self.product = product
        self.onSelectTier = onSelectTier
        self.onSelectVariantTier = onSelectVariantTier
        self.onInventoryUpdated = onInventoryUpdated
        self.onPrintLabels = onPrintLabels
        self.onViewCOA = onViewCOA
        self.onShowDetail = onShowDetail
        self._localStock = State(initialValue: product.availableStock)
    }

    // Clean init
    init(
        product: Product,
        onSelectTier: @escaping (PricingTier) -> Void,
        onSelectVariantTier: ((PricingTier, ProductVariant) -> Void)? = nil,
        onInventoryUpdated: ((UUID, Int) -> Void)? = nil,
        onPrintLabels: (() -> Void)? = nil,
        onViewCOA: (() -> Void)? = nil,
        onShowDetail: (() -> Void)? = nil
    ) {
        self.product = product
        self.onSelectTier = onSelectTier
        self.onSelectVariantTier = onSelectVariantTier
        self.onInventoryUpdated = onInventoryUpdated
        self.onPrintLabels = onPrintLabels
        self.onViewCOA = onViewCOA
        self.onShowDetail = onShowDetail
        self._localStock = State(initialValue: product.availableStock)
    }

    private var variants: [ProductVariant] { product.enabledVariants }
    private var hasVariants: Bool { !variants.isEmpty }

    private var selectedVariant: ProductVariant? {
        guard let id = selectedVariantId else { return nil }
        return variants.first { $0.id == id }
    }

    private var currentTiers: [PricingTier] {
        let tiers = selectedVariant != nil ? variantTiers : product.allTiers
        return tiers.sorted { ($0.sortOrder ?? 0) < ($1.sortOrder ?? 0) }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    // SKU row
                    if let sku = product.sku {
                        HStack {
                            Text(sku)
                                .font(Design.Typography.caption2Mono).fontWeight(.medium)
                                .foregroundStyle(.white.opacity(0.4))
                            Spacer()
                            if let cat = product.categoryName {
                                Text(cat)
                                    .font(Design.Typography.caption2).fontWeight(.medium)
                                    .foregroundStyle(.white.opacity(0.3))
                            }
                        }
                        .padding(.horizontal, 4)
                    }

                    // Stock section
                    stockSection

                    // Variants
                    if hasVariants {
                        variantPicker
                    }

                    // Tiers
                    tiersSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            .navigationTitle(product.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.white.opacity(0.7))
                }
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 12) {
                        Button {
                            Haptics.light()
                            dismiss()
                            Task { @MainActor in
                                try? await Task.sleep(for: .seconds(0.3))
                                onShowDetail?()
                            }
                        } label: {
                            Image(systemName: "info.circle")
                                .font(Design.Typography.body)
                                .foregroundStyle(.white.opacity(0.7))
                        }

                        toolbarMenu
                    }
                }
            }
            }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Stock Section

    private var stockSection: some View {
        Group {
            // Only show stock section for inventory-tracked products
            if !product.isService {
                ModalSection {
                    if showQuickAudit {
                        auditEditor
                    } else {
                        stockDisplay
                    }
                }
            }
        }
    }

    private var stockDisplay: some View {
        Button {
            Haptics.light()
            auditQuantity = formatStock(Double(localStock))
            auditError = nil
            showQuickAudit = true
        } label: {
            HStack(spacing: 12) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.white.opacity(0.1))
                        RoundedRectangle(cornerRadius: 4)
                            .fill(stockColor.opacity(0.8))
                            .frame(width: geo.size.width * stockPercentage)
                    }
                }
                .frame(height: 8)

                Text("\(localStock)g")
                    .font(Design.Typography.subheadRounded).fontWeight(.semibold)
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(minWidth: 50, alignment: .trailing)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var stockPercentage: CGFloat {
        let stock = Double(localStock)
        guard stock > 0 else { return 0 }
        return min(1, max(0.05, stock / max(100, stock)))
    }

    private var stockColor: Color {
        if localStock <= 10 && localStock > 0 { return .orange }
        if localStock <= 0 { return .red }
        return Design.Colors.Semantic.success
    }

    // MARK: - Audit Editor

    private var auditEditor: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                TextField("Qty", text: $auditQuantity)
                    .keyboardType(.decimalPad)
                    .font(Design.Typography.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.08)))

                if isSubmitting {
                    ProgressView().tint(.white)
                        .frame(width: 44, height: 44)
                } else {
                    Button {
                        Haptics.light()
                        showQuickAudit = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(Design.Typography.footnote).fontWeight(.semibold)
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(.white.opacity(0.1)))
                    }

                    Button { submitAudit() } label: {
                        Image(systemName: "checkmark")
                            .font(Design.Typography.footnote).fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(.white.opacity(0.15)))
                    }
                }
            }

            // Reason chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(QuickAuditReason.allCases, id: \.self) { reason in
                        Button {
                            Haptics.light()
                            auditReason = reason
                        } label: {
                            Text(reason.displayName)
                                .font(Design.Typography.footnote).fontWeight(auditReason == reason ? .semibold : .medium)
                                .foregroundStyle(auditReason == reason ? .white : .white.opacity(0.6))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .frame(minHeight: 44)
                                .background(Capsule().fill(.white.opacity(auditReason == reason ? 0.2 : 0.08)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if let error = auditError {
                Text(error)
                    .font(Design.Typography.caption2)
                    .foregroundStyle(Design.Colors.Semantic.error)
            }
        }
    }

    // MARK: - Variant Picker

    private var variantPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                variantChip(name: "Base", isSelected: selectedVariantId == nil) {
                    Haptics.light()
                    withAnimation(.spring(response: 0.3)) {
                        selectedVariantId = nil
                        variantTiers = []
                    }
                }

                ForEach(variants) { variant in
                    variantChip(name: variant.variantName, isSelected: selectedVariantId == variant.id) {
                        Haptics.light()
                        withAnimation(.spring(response: 0.3)) {
                            selectedVariantId = variant.id
                            variantTiers = variant.pricingTiers
                        }
                        // If no tiers loaded, fetch schema on-demand
                        if variant.pricingTiers.isEmpty, let schemaId = variant.pricingSchemaId {
                            Task {
                                await loadVariantSchema(schemaId: schemaId)
                            }
                        }
                    }
                }
            }
        }
    }

    private func variantChip(name: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(name)
                .font(Design.Typography.subhead).fontWeight(isSelected ? .semibold : .medium)
                .foregroundStyle(isSelected ? .white : .white.opacity(0.6))
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .frame(minHeight: 44)
                .contentShape(Capsule())
        }
        .buttonStyle(ScaleButtonStyle())
        .glassEffect(.regular.interactive(), in: .capsule)
        .overlay(Capsule().stroke(isSelected ? .white.opacity(0.3) : .clear, lineWidth: 1))
    }

    // MARK: - Tiers Section

    private var tiersSection: some View {
        VStack(spacing: 10) {
            if currentTiers.isEmpty {
                Text("No pricing available")
                    .font(Design.Typography.footnote)
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(height: 60)
            } else {
                ForEach(currentTiers, id: \.id) { tier in
                    tierButton(tier)
                }
            }
        }
    }

    private func tierButton(_ tier: PricingTier) -> some View {
        Button {
            Haptics.medium()
            if let variant = selectedVariant, let callback = onSelectVariantTier {
                callback(tier, variant)
            } else {
                onSelectTier(tier)
            }
            dismiss()
        } label: {
            HStack {
                Text(tier.label)
                    .font(Design.Typography.callout).fontWeight(.semibold)
                    .foregroundStyle(.white)
                Spacer()
                Text(CurrencyFormatter.format(tier.defaultPrice))
                    .font(Design.Typography.headlineRounded).fontWeight(.bold)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(minHeight: 56)
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(ScaleButtonStyle())
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
    }

    // MARK: - Toolbar Menu

    private var toolbarMenu: some View {
        Menu {
            Button {
                Haptics.medium()
                dismiss()
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(0.3))
                    onPrintLabels?()
                }
            } label: {
                Label("Print Labels", systemImage: "printer")
            }

            Button {
                Haptics.light()
                dismiss()
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(0.3))
                    onShowDetail?()
                }
            } label: {
                Label("View Details", systemImage: "info.circle")
            }

            if product.hasCOA {
                Button {
                    if let url = product.coaUrl {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("Lab Results", systemImage: "testtube.2")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(Design.Typography.body)
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    // MARK: - Actions

    private func loadVariantSchema(schemaId: UUID) async {
        do {
            if let schema = try await ProductService.fetchPricingSchema(id: schemaId) {
                await MainActor.run {
                    variantTiers = schema.defaultTiers ?? []
                }
            }
        } catch {
            Log.network.error("⚠️ Failed to load variant schema \(schemaId): \(error.localizedDescription)")
        }
    }

    private func submitAudit() {
        guard let qty = Double(auditQuantity), qty >= 0 else {
            auditError = "Invalid quantity"
            return
        }
        guard let storeId = session.storeId, let locationId = session.selectedLocation?.id else {
            auditError = "No location selected"
            return
        }

        isSubmitting = true
        auditError = nil

        Task {
            do {
                _ = try await InventoryService.createAbsoluteAdjustment(
                    storeId: storeId,
                    productId: product.id,
                    locationId: locationId,
                    adjustmentType: auditReason.toAdjustmentType,
                    absoluteQuantity: qty,
                    reason: auditReason.displayName,
                    notes: "Quick audit from POS"
                )
                await MainActor.run {
                    localStock = Int(qty)
                    isSubmitting = false
                    showQuickAudit = false
                    onInventoryUpdated?(product.id, Int(qty))
                    Haptics.success()
                }
            } catch {
                await MainActor.run {
                    auditError = error.localizedDescription
                    isSubmitting = false
                    Haptics.error()
                }
            }
        }
    }

    private func formatStock(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
    }
}
