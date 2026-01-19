//
//  TierSelectorSheet.swift
//  Whale
//
//  Product tier selector - liquid glass design.
//

import SwiftUI

struct TierSelectorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SessionObserver

    let product: Product
    let onSelectTier: (PricingTier) -> Void
    let onSelectVariantTier: ((PricingTier, ProductVariant) -> Void)?
    let onInventoryUpdated: ((UUID, Int) -> Void)?
    let onPrintLabels: (() -> Void)?
    let onViewCOA: (() -> Void)?

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
        onViewCOA: (() -> Void)? = nil
    ) {
        self.product = product
        self.onSelectTier = onSelectTier
        self.onSelectVariantTier = onSelectVariantTier
        self.onInventoryUpdated = onInventoryUpdated
        self.onPrintLabels = onPrintLabels
        self.onViewCOA = onViewCOA
        self._localStock = State(initialValue: product.availableStock)
    }

    // Clean init
    init(
        product: Product,
        onSelectTier: @escaping (PricingTier) -> Void,
        onSelectVariantTier: ((PricingTier, ProductVariant) -> Void)? = nil,
        onInventoryUpdated: ((UUID, Int) -> Void)? = nil,
        onPrintLabels: (() -> Void)? = nil,
        onViewCOA: (() -> Void)? = nil
    ) {
        self.product = product
        self.onSelectTier = onSelectTier
        self.onSelectVariantTier = onSelectVariantTier
        self.onInventoryUpdated = onInventoryUpdated
        self.onPrintLabels = onPrintLabels
        self.onViewCOA = onViewCOA
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
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.4))
                            Spacer()
                            if let cat = product.categoryName {
                                Text(cat)
                                    .font(.system(size: 11, weight: .medium))
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
                    toolbarMenu
                }
            }
            }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }

    // MARK: - Stock Section

    private var stockSection: some View {
        ModalSection {
            if showQuickAudit {
                auditEditor
            } else {
                stockDisplay
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
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
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
                    .font(.system(size: 18, weight: .semibold))
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
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(.white.opacity(0.1)))
                    }

                    Button { submitAudit() } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.black)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(.white))
                    }
                }
            }

            // Reason chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(QuickAuditReason.allCases, id: \.self) { reason in
                        Button {
                            Haptics.light()
                            auditReason = reason
                        } label: {
                            Text(reason.displayName)
                                .font(.system(size: 12, weight: auditReason == reason ? .semibold : .medium))
                                .foregroundStyle(auditReason == reason ? .white : .white.opacity(0.5))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(.white.opacity(auditReason == reason ? 0.2 : 0.06)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if let error = auditError {
                Text(error)
                    .font(.system(size: 11))
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
                    }
                }
            }
        }
    }

    private func variantChip(name: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(name)
                .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? .white : .white.opacity(0.6))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
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
                    .font(.system(size: 14))
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
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text(CurrencyFormatter.format(tier.defaultPrice))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
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
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    onPrintLabels?()
                }
            } label: {
                Label("Print Labels", systemImage: "printer")
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
                .font(.system(size: 17))
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    // MARK: - Actions

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
                _ = try await InventoryService.createAdjustment(
                    storeId: storeId,
                    productId: product.id,
                    locationId: locationId,
                    adjustmentType: auditReason.toAdjustmentType,
                    newQuantity: qty,
                    currentQuantity: Double(localStock),
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
