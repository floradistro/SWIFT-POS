//  TierSelectorSheet.swift - Pricing tier selector with variant support

import SwiftUI

struct TierSelectorModal: View {
    @Binding var isPresented: Bool
    @EnvironmentObject private var session: SessionObserver
    @EnvironmentObject private var posStore: POSStore
    let product: Product
    let onSelectTier: (PricingTier) -> Void
    let onSelectVariantTier: ((PricingTier, ProductVariant) -> Void)?
    let onInventoryUpdated: ((UUID, Int) -> Void)?
    let onPrintLabels: (() -> Void)?
    let onViewCOA: (() -> Void)?

    @State private var localStock: Int
    @State private var selectedVariant: ProductVariant? = nil
    @State private var variantTiers: [PricingTier] = []
    @State private var variantInventories: [VariantInventoryData] = []
    @State private var localVariantInventories: [UUID: Int] = [:]
    @State private var showProductDetails = false

    // Quick audit state
    @State private var showQuickAudit = false
    @State private var auditQuantity: String = ""
    @State private var auditReason: QuickAuditReason = .count
    @State private var isSubmittingAudit = false
    @State private var auditError: String?
    @State private var auditSuccess = false

    // Print menu state
    @State private var showPrintMenu = false

    @Namespace private var tabAnimation

    init(
        isPresented: Binding<Bool>,
        product: Product,
        onSelectTier: @escaping (PricingTier) -> Void,
        onSelectVariantTier: ((PricingTier, ProductVariant) -> Void)? = nil,
        onInventoryUpdated: ((UUID, Int) -> Void)? = nil,
        onPrintLabels: (() -> Void)? = nil,
        onViewCOA: (() -> Void)? = nil
    ) {
        self._isPresented = isPresented
        self.product = product
        self.onSelectTier = onSelectTier
        self._localStock = State(initialValue: product.availableStock)
        self.onSelectVariantTier = onSelectVariantTier
        self.onInventoryUpdated = onInventoryUpdated
        self.onPrintLabels = onPrintLabels
        self.onViewCOA = onViewCOA
    }

    private var currentTiers: [PricingTier] {
        if selectedVariant != nil && !variantTiers.isEmpty {
            return variantTiers.sorted { ($0.sortOrder ?? 0) < ($1.sortOrder ?? 0) }
        }
        return product.allTiers.sorted { ($0.sortOrder ?? 0) < ($1.sortOrder ?? 0) }
    }

    private var variants: [ProductVariant] { product.enabledVariants }
    private var hasVariants: Bool { !variants.isEmpty }
    private var parentStock: Double { Double(localStock) }

    var body: some View {
        UnifiedModal(isPresented: $isPresented, id: "tier-selector", maxWidth: .infinity) {
            VStack(spacing: 0) {
                modalHeader

                if showProductDetails {
                    ProductDetailsCard(product: product)
                } else {
                    tierSelectorContent
                }

                ModalSecondaryButton(title: showProductDetails ? "Back to Sizes" : "Cancel") {
                    if showProductDetails {
                        withAnimation(.spring(response: 0.3)) { showProductDetails = false }
                    } else {
                        isPresented = false
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
        }
        .onAppear { loadVariantInventory() }
    }

    // MARK: - Header

    private var modalHeader: some View {
        HStack(alignment: .center) {
            ModalCloseButton(action: { isPresented = false })
            Spacer()

            VStack(spacing: 4) {
                Text(showProductDetails ? "PRODUCT DETAILS" : (selectedVariant != nil ? "SELECT \(selectedVariant!.variantName.uppercased()) SIZE" : "SELECT SIZE"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
                    .tracking(0.5)

                Text(product.name)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Spacer()

            HStack(spacing: 8) {
                // Print menu button with liquid glass
                printMenuButton

                // Info/details toggle button
                LiquidGlassIconButton(
                    icon: showProductDetails ? "list.bullet" : "info.circle",
                    isSelected: showProductDetails,
                    tintColor: .white.opacity(0.6)
                ) {
                    withAnimation(.spring(response: 0.3)) { showProductDetails.toggle() }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 16)
    }

    // MARK: - Print Menu Button

    private var printMenuButton: some View {
        Menu {
            // Print Labels option
            Button {
                Haptics.medium()
                isPresented = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    onPrintLabels?()
                }
            } label: {
                Label("Print Labels", systemImage: "printer.fill")
            }

            // View COA option (only if product has COA)
            if product.hasCOA {
                Button {
                    Haptics.medium()
                    if let coaUrl = product.coaUrl {
                        UIApplication.shared.open(coaUrl)
                    } else {
                        onViewCOA?()
                    }
                } label: {
                    Label("View Lab Results", systemImage: "testtube.2")
                }
            }
        } label: {
            Image(systemName: "printer")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(LiquidPressStyle())
        .glassEffect(.regular.interactive(), in: .circle)
    }

    // MARK: - Tier Selector Content

    private var tierSelectorContent: some View {
        VStack(spacing: 16) {
            skuRow
            stockBarsSection

            if hasVariants {
                variantTabsSection
            }

            tiersSection
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    private var skuRow: some View {
        Group {
            if let sku = product.sku {
                HStack {
                    Text(sku)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                    Spacer()
                    if let category = product.categoryName {
                        Text(category)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }

    private var stockBarsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            StockBarRow(
                value: parentStock,
                maxValue: max(100, parentStock),
                label: "g available",
                color: Design.Colors.Semantic.success,
                isEditing: showQuickAudit,
                isSubmitting: isSubmittingAudit,
                isSuccess: auditSuccess,
                errorMessage: auditError,
                editValue: $auditQuantity,
                auditReason: $auditReason,
                onTapToEdit: {
                    Haptics.light()
                    auditQuantity = formatStock(parentStock)
                    auditError = nil
                    showQuickAudit = true
                },
                onSave: { submitAudit() },
                onCancel: {
                    Haptics.light()
                    auditError = nil
                    showQuickAudit = false
                }
            )

            if hasVariants && !variantInventories.isEmpty {
                ForEach(variantInventories, id: \.variantTemplateId) { inv in
                    let displayQty = localVariantInventories[inv.variantTemplateId] ?? Int(inv.quantity)
                    StockBarRow(
                        value: Double(displayQty),
                        maxValue: max(50, Double(displayQty)),
                        label: inv.variantName,
                        color: .blue,
                        isEditing: false,
                        isSubmitting: false,
                        isSuccess: false,
                        errorMessage: nil,
                        editValue: .constant(""),
                        auditReason: .constant(.count),
                        onTapToEdit: {},
                        onSave: {},
                        onCancel: {}
                    )
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.03)))
    }

    private var variantTabsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                VariantTab(name: "Base", isSelected: selectedVariant == nil, namespace: tabAnimation) {
                    Haptics.light()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        selectedVariant = nil
                        variantTiers = []
                    }
                }

                ForEach(variants) { variant in
                    VariantTab(name: variant.variantName, isSelected: selectedVariant?.id == variant.id, namespace: tabAnimation) {
                        Haptics.light()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            selectedVariant = variant
                        }
                        variantTiers = variant.pricingTiers
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private var tiersSection: some View {
        VStack(spacing: 8) {
            if currentTiers.isEmpty {
                Text("No pricing tiers available")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(height: 60)
            } else {
                ForEach(currentTiers, id: \.id) { tier in
                    TierButton(tier: tier) {
                        Haptics.medium()
                        if let variant = selectedVariant, let callback = onSelectVariantTier {
                            callback(tier, variant)
                        } else {
                            onSelectTier(tier)
                        }
                        isPresented = false
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func loadVariantInventory() {
        guard hasVariants, let locationId = session.selectedLocation?.id else { return }
        Task {
            if let inventories = try? await ProductService.fetchVariantInventory(productId: product.id, locationId: locationId) {
                await MainActor.run { variantInventories = inventories }
            }
        }
    }

    private func submitAudit() {
        guard let qty = Double(auditQuantity), qty >= 0 else {
            auditError = "Invalid quantity"
            return
        }
        guard let storeId = session.storeId, let locationId = session.selectedLocation?.id else {
            auditError = "No store/location selected"
            return
        }

        isSubmittingAudit = true
        auditError = nil

        Task {
            do {
                _ = try await InventoryService.createAdjustment(
                    storeId: storeId,
                    productId: product.id,
                    locationId: locationId,
                    adjustmentType: auditReason.toAdjustmentType,
                    newQuantity: qty,
                    currentQuantity: parentStock,
                    reason: auditReason.displayName,
                    notes: "Quick audit from POS"
                )
                await MainActor.run {
                    localStock = Int(qty)
                    auditSuccess = true
                    isSubmittingAudit = false
                    onInventoryUpdated?(product.id, Int(qty))
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        showQuickAudit = false
                        auditSuccess = false
                    }
                }
            } catch {
                await MainActor.run {
                    auditError = error.localizedDescription
                    isSubmittingAudit = false
                }
            }
        }
    }

    private func formatStock(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }
}
