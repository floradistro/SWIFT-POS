//
//  SheetContainer.swift
//  Whale
//
//  Resolves SheetType to actual SwiftUI views.
//  Single place to configure all sheet presentations.
//

import SwiftUI
import Supabase

struct SheetContainer: View {
    let sheetType: SheetType
    @EnvironmentObject private var session: SessionObserver

    var body: some View {
        sheetContent
            .presentationDetents(detentsForType)
            .presentationDragIndicator(.visible)
            .preferredColorScheme(.dark)
    }

    // MARK: - Sheet Content

    @ViewBuilder
    private var sheetContent: some View {
        switch sheetType {

        // MARK: Location & Store
        case .locationPicker:
            LocationPickerSheet()

        case .registerPicker:
            RegisterPickerSheet()

        // MARK: Customer
        case .customerSearch(let storeId):
            ManualCustomerEntrySheet(
                storeId: storeId,
                onCustomerCreated: { customer in
                    NotificationCenter.default.post(
                        name: .sheetCustomerSelected,
                        object: customer
                    )
                    SheetCoordinator.shared.dismiss()
                },
                onCancel: {
                    SheetCoordinator.shared.dismiss()
                }
            )

        case .customerDetail(let customer):
            CustomerDetailSheet(customer: customer, store: CustomerStore.shared)

        case .idScanner(let storeId):
            IDScannerView(
                storeId: storeId,
                onCustomerSelected: { customer in
                    NotificationCenter.default.post(
                        name: .sheetCustomerSelected,
                        object: customer
                    )
                    SheetCoordinator.shared.dismiss()
                },
                onDismiss: {
                    SheetCoordinator.shared.dismiss()
                }
            )

        case .customerScanned(let storeId, let scannedID, let matches):
            ManualCustomerEntrySheet(
                storeId: storeId,
                onCustomerCreated: { customer in
                    NotificationCenter.default.post(
                        name: .sheetCustomerSelected,
                        object: customer
                    )
                    SheetCoordinator.shared.dismiss()
                },
                onCancel: {
                    SheetCoordinator.shared.dismiss()
                },
                scannedID: scannedID,
                scannedMatches: matches
            )
            .onAppear {
                print("📋 SheetContainer creating customerScanned sheet - scannedID: \(scannedID.fullDisplayName), matches: \(matches.count)")
            }

        // MARK: Orders
        case .orderDetail(let order):
            OrderDetailSheet(order: order)

        case .orderFilters:
            AdvancedOrderFiltersSheet(
                store: OrderStore.shared,
                isPresented: .constant(true)
            )

        case .invoiceDetail(let order):
            InvoiceDetailSheetWrapper(order: order)

        // MARK: Cart & Checkout
        case .checkout(let totals, let sessionInfo):
            CheckoutSheetWrapper(totals: totals, sessionInfo: sessionInfo)

        case .tierSelector(let product, let storeId, let locationId):
            TierSelectorSheetWrapper(product: product, storeId: storeId, locationId: locationId)

        // MARK: Cash Management
        case .safeDrop(let posSession):
            SafeDropSheet(posSession: posSession)

        case .openCashDrawer:
            OpenCashDrawerSheet()

        // MARK: Inventory & Transfer
        case .createTransfer(let storeId, let sourceLocation):
            CreateTransferSheet(
                storeId: storeId,
                sourceLocation: sourceLocation,
                onDismiss: { SheetCoordinator.shared.dismiss() },
                onTransferCreated: { _ in SheetCoordinator.shared.dismiss() }
            )

        case .packageReceive(let transfer, let items, let storeId):
            PackageReceiveSheet(
                transfer: transfer,
                items: items,
                storeId: storeId,
                onDismiss: { SheetCoordinator.shared.dismiss() }
            )

        case .inventoryUnitScan(let unit, let lookupResult, let storeId):
            InventoryUnitScanSheet(
                unit: unit,
                lookupResult: lookupResult,
                storeId: storeId,
                onDismiss: { SheetCoordinator.shared.dismiss() },
                onAction: { _ in }
            )

        case .qrCodeScan(let qrCode, let storeId):
            QRCodeScanSheet(
                qrCode: qrCode,
                storeId: storeId,
                onDismiss: { SheetCoordinator.shared.dismiss() }
            )

        // MARK: Labels & Printing
        case .labelTemplate(let products):
            LabelTemplateSheetWrapper(products: products)

        case .orderLabelTemplate(let orders):
            OrderLabelTemplateSheetWrapper(orders: orders)

        case .bulkProductLabels(let products):
            BulkProductLabelSheet(products: products)

        case .printerSettings:
            PrinterSettingsSheet()

        case .posSettings:
            POSSettingsSheet()

        case .errorAlert(let title, let message):
            ErrorAlertSheet(title: title, message: message)
        }
    }

    // MARK: - Detents

    private var detentsForType: Set<PresentationDetent> {
        let isCompact = UIScreen.main.bounds.width < 500  // iPhone portrait

        switch sheetType.detents {
        case .small:
            return [.fraction(0.25)]
        case .medium:
            return [.medium]
        case .mediumLarge:
            return [.medium, .large]
        case .large:
            // On iPhone, also allow medium to avoid empty space
            return isCompact ? [.medium, .large] : [.large]
        case .fitted:
            // Content-fitted - on iPhone use smaller sizes first
            return isCompact ? [.height(350), .medium, .large] : [.medium, .large]
        case .full:
            return [.large]
        }
    }
}

// MARK: - Sheet Notifications

extension Notification.Name {
    static let sheetCustomerSelected = Notification.Name("sheetCustomerSelected")
    static let sheetOrderCompleted = Notification.Name("sheetOrderCompleted")
    static let sheetDismissed = Notification.Name("sheetDismissed")
}

// MARK: - Wrapper Views (for sheets that need special handling)

/// Wrapper for CheckoutSheet to handle its callbacks
private struct CheckoutSheetWrapper: View {
    let totals: CheckoutTotals
    let sessionInfo: SessionInfo
    @EnvironmentObject private var session: SessionObserver
    @Environment(\.posWindowSession) private var windowSession: POSWindowSession?
    @StateObject private var paymentStore = PaymentStore()
    @ObservedObject private var dealStore = DealStore.shared

    private var posStore: POSStore {
        POSStore.shared
    }

    var body: some View {
        CheckoutSheet(
            posStore: posStore,
            paymentStore: paymentStore,
            dealStore: dealStore,
            totals: totals,
            sessionInfo: sessionInfo,
            loyaltyProgram: session.loyaltyProgram,
            onScanID: {
                // Present scanner sheet
                if let storeId = session.storeId {
                    SheetCoordinator.shared.present(.idScanner(storeId: storeId))
                }
            },
            onComplete: { saleCompletion in
                NotificationCenter.default.post(
                    name: .sheetOrderCompleted,
                    object: saleCompletion
                )
                SheetCoordinator.shared.dismiss()
            }
        )
    }
}

/// Wrapper for TierSelector
private struct TierSelectorSheetWrapper: View {
    let product: Product
    let storeId: UUID
    let locationId: UUID
    @EnvironmentObject private var session: SessionObserver
    @Environment(\.posWindowSession) private var windowSession: POSWindowSession?

    var body: some View {
        TierSelectorSheet(
            isPresented: .constant(true),
            product: product,
            onSelectTier: { tier in
                NotificationCenter.default.post(
                    name: .init("tierSelected"),
                    object: (product, tier)
                )
                SheetCoordinator.shared.dismiss()
            },
            onSelectVariantTier: { tier, variant in
                NotificationCenter.default.post(
                    name: .init("variantTierSelected"),
                    object: (product, tier, variant)
                )
                SheetCoordinator.shared.dismiss()
            },
            onInventoryUpdated: nil,
            onPrintLabels: {
                // Present label template sheet for this product
                SheetCoordinator.shared.present(.labelTemplate(products: [product]))
            },
            onViewCOA: nil
        )
        .environmentObject(POSStore.shared)
    }
}

/// SafeDrop converted to sheet
private struct SafeDropSheet: View {
    let posSession: POSSession
    @EnvironmentObject private var session: SessionObserver
    @Environment(\.posWindowSession) private var windowSession: POSWindowSession?
    @Environment(\.dismiss) private var dismiss

    @State private var amount: String = ""
    @State private var notes: String = ""
    @FocusState private var amountFocused: Bool

    private var displayLocation: Location? {
        windowSession?.location ?? session.selectedLocation
    }

    private var displayRegister: Register? {
        windowSession?.register ?? session.selectedRegister
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("$")
                            .foregroundStyle(.secondary)
                        TextField("0.00", text: $amount)
                            .keyboardType(.decimalPad)
                            .focused($amountFocused)
                    }
                } header: {
                    Text("Amount")
                }

                Section {
                    TextField("Optional notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("Notes")
                }

                if let location = displayLocation {
                    Section {
                        LabeledContent("Location", value: location.name)
                        if let register = displayRegister {
                            LabeledContent("Register", value: register.registerName)
                        }
                    } header: {
                        Text("Details")
                    }
                }
            }
            .navigationTitle("Safe Drop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        SheetCoordinator.shared.dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        submitDrop()
                    }
                    .disabled(amount.isEmpty)
                }
            }
            .onAppear {
                amountFocused = true
            }
        }
    }

    private func submitDrop() {
        guard let amountValue = Decimal(string: amount), amountValue > 0 else { return }

        Task {
            // Update window session if available
            if let ws = windowSession {
                try? await ws.performSafeDrop(amount: amountValue, notes: notes.isEmpty ? nil : notes)
            }

            await MainActor.run {
                Haptics.success()
                SheetCoordinator.shared.dismiss()
            }
        }
    }
}

/// OpenCashDrawer converted to sheet
private struct OpenCashDrawerSheet: View {
    @EnvironmentObject private var session: SessionObserver
    @Environment(\.dismiss) private var dismiss

    @State private var amount: String = ""
    @State private var notes: String = ""
    @FocusState private var amountFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("$")
                            .foregroundStyle(.secondary)
                        TextField("0.00", text: $amount)
                            .keyboardType(.decimalPad)
                            .focused($amountFocused)
                    }
                } header: {
                    Text("Opening Cash")
                } footer: {
                    Text("Enter the amount of cash in the drawer")
                }

                Section {
                    TextField("Optional notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("Notes")
                }
            }
            .navigationTitle("Open Cash Drawer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        SheetCoordinator.shared.dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        submitOpen()
                    }
                    .disabled(amount.isEmpty)
                }
            }
            .onAppear {
                amountFocused = true
            }
        }
    }

    private func submitOpen() {
        guard let amountValue = Decimal(string: amount) else { return }

        NotificationCenter.default.post(
            name: .init("cashDrawerOpened"),
            object: ["amount": amountValue, "notes": notes]
        )

        Haptics.success()
        SheetCoordinator.shared.dismiss()
    }
}

/// OrderDetail as sheet
private struct OrderDetailSheet: View {
    let order: Order
    @ObservedObject private var store = OrderStore.shared

    var body: some View {
        NavigationStack {
            OrderDetailContent(order: order, store: store)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") {
                            SheetCoordinator.shared.dismiss()
                        }
                    }
                }
        }
    }
}

/// Order detail content (extracted from OrderDetailModal)
private struct OrderDetailContent: View {
    let order: Order
    @ObservedObject var store: OrderStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Order header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Order #\(order.orderNumber ?? "—")")
                        .font(.title2.bold())

                    Text(order.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)

                // Status
                HStack {
                    Text(order.status.displayName)
                        .font(.caption.bold())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(statusColor.opacity(0.2), in: Capsule())
                        .foregroundStyle(statusColor)
                }
                .padding(.horizontal)

                Divider()

                // Items
                VStack(alignment: .leading, spacing: 12) {
                    Text("Items")
                        .font(.headline)
                        .padding(.horizontal)

                    ForEach(order.items ?? []) { item in
                        HStack {
                            Text("\(item.quantity)x")
                                .foregroundStyle(.secondary)
                                .frame(width: 40, alignment: .leading)

                            Text(item.productName)

                            Spacer()

                            Text(CurrencyFormatter.format(item.lineTotal))
                                .monospacedDigit()
                        }
                        .padding(.horizontal)
                    }
                }

                Divider()

                // Totals
                VStack(spacing: 8) {
                    HStack {
                        Text("Subtotal")
                        Spacer()
                        Text(CurrencyFormatter.format(order.subtotal))
                            .monospacedDigit()
                    }

                    if order.taxAmount > 0 {
                        HStack {
                            Text("Tax")
                            Spacer()
                            Text(CurrencyFormatter.format(order.taxAmount))
                                .monospacedDigit()
                        }
                    }

                    if order.discountAmount > 0 {
                        HStack {
                            Text("Discount")
                            Spacer()
                            Text("-\(CurrencyFormatter.format(order.discountAmount))")
                                .monospacedDigit()
                                .foregroundStyle(.green)
                        }
                    }

                    Divider()

                    HStack {
                        Text("Total")
                            .font(.headline)
                        Spacer()
                        Text(CurrencyFormatter.format(order.totalAmount))
                            .font(.headline)
                            .monospacedDigit()
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .navigationTitle("Order Details")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var statusColor: Color {
        switch order.status {
        case .completed, .delivered: return .green
        case .pending, .preparing: return .orange
        case .cancelled: return .red
        default: return .secondary
        }
    }
}

/// Register picker sheet
private struct RegisterPickerSheet: View {
    @EnvironmentObject private var session: SessionObserver
    @State private var registers: [Register] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            List {
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding()
                } else if registers.isEmpty {
                    ContentUnavailableView(
                        "No Registers",
                        systemImage: "desktopcomputer",
                        description: Text("No registers configured for this location")
                    )
                } else {
                    ForEach(registers) { register in
                        Button {
                            Task {
                                await session.selectRegister(register)
                                SheetCoordinator.shared.dismiss()
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(register.registerName)
                                    Text("Register #\(register.registerNumber)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if session.selectedRegister?.id == register.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
            .navigationTitle("Select Register")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        SheetCoordinator.shared.dismiss()
                    }
                }
            }
            .task {
                await loadRegisters()
            }
        }
    }

    private func loadRegisters() async {
        guard let locationId = session.selectedLocation?.id else {
            isLoading = false
            return
        }

        do {
            let response: [Register] = try await supabase
                .from("pos_registers")
                .select()
                .eq("location_id", value: locationId.uuidString.lowercased())
                .eq("status", value: "active")
                .order("register_name")
                .execute()
                .value
            registers = response
        } catch {
            print("Failed to load registers: \(error)")
        }
        isLoading = false
    }
}

/// Printer settings sheet
private struct PrinterSettingsSheet: View {
    @ObservedObject private var settings = LabelPrinterSettings.shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Label("Printer", systemImage: "printer")
                        Spacer()
                        Text(settings.printerName ?? "Not Set")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Toggle("Auto-Print Labels", isOn: $settings.isAutoPrintEnabled)
                } footer: {
                    Text("Automatically print labels after each sale")
                }
            }
            .navigationTitle("Printer Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        SheetCoordinator.shared.dismiss()
                    }
                }
            }
        }
    }
}

/// Placeholder for bulk product labels
private struct BulkProductLabelSheet: View {
    let products: [Product]

    var body: some View {
        NavigationStack {
            Text("Bulk label printing for \(products.count) products")
                .navigationTitle("Print Labels")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") {
                            SheetCoordinator.shared.dismiss()
                        }
                    }
                }
        }
    }
}

/// Invoice detail wrapper that loads invoice for an order
private struct InvoiceDetailSheetWrapper: View {
    let order: Order
    @State private var invoice: Invoice?
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading invoice...")
                } else if let invoice = invoice {
                    InvoiceDetailSheet(invoice: invoice) {
                        SheetCoordinator.shared.dismiss()
                    }
                } else {
                    ContentUnavailableView(
                        "No Invoice",
                        systemImage: "doc.text",
                        description: Text(error ?? "No invoice found for this order")
                    )
                }
            }
            .navigationTitle("Invoice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        SheetCoordinator.shared.dismiss()
                    }
                }
            }
        }
        .task {
            await loadInvoice()
        }
    }

    private func loadInvoice() async {
        isLoading = true
        do {
            invoice = try await InvoiceService.fetchInvoiceByOrder(orderId: order.id)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

/// Label template wrapper
private struct LabelTemplateSheetWrapper: View {
    let products: [Product]
    @EnvironmentObject private var session: SessionObserver
    @State private var isPrinting = false

    var body: some View {
        LabelTemplateSheet(
            products: products,
            store: session.store,
            location: session.selectedLocation,
            isPrinting: $isPrinting,
            onDismiss: { SheetCoordinator.shared.dismiss() },
            embedded: true
        )
    }
}

/// Order label template wrapper
private struct OrderLabelTemplateSheetWrapper: View {
    let orders: [Order]
    @EnvironmentObject private var session: SessionObserver
    @State private var isPrinting = false

    var body: some View {
        OrderLabelTemplateSheet(
            orders: orders,
            store: session.store,
            location: session.selectedLocation,
            isPrinting: $isPrinting,
            onDismiss: { SheetCoordinator.shared.dismiss() },
            embedded: true
        )
    }
}

// MARK: - POS Settings Sheet

private struct POSSettingsSheet: View {
    @EnvironmentObject private var session: SessionObserver
    @Environment(\.posWindowSession) private var windowSession: POSWindowSession?
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var printerSettings = LabelPrinterSettings.shared

    private var currentLocation: Location? {
        windowSession?.location ?? session.selectedLocation
    }

    private var currentRegister: Register? {
        windowSession?.register ?? session.selectedRegister
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    // Location Section
                    locationSection

                    // Printer Section
                    printerSection

                    // Label Position Section
                    labelPositionSection

                    // Cash Drawer Section (if available)
                    if currentRegister != nil, windowSession?.posSession != nil {
                        drawerSection
                    }

                    // Actions Section
                    actionsSection

                    // End Session
                    endSessionButton
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }

    // MARK: - Location Section

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ModalSectionLabel("Location")

            ModalSection {
                VStack(spacing: 0) {
                    if let location = currentLocation {
                        HStack(spacing: 12) {
                            Image(systemName: "storefront.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.white.opacity(0.6))
                                .frame(width: 32)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(location.name)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(.white)
                                if let register = currentRegister {
                                    Text("\(register.registerName) #\(register.registerNumber)")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.white.opacity(0.5))
                                }
                            }
                            Spacer()
                        }
                        .padding(.bottom, 12)

                        Divider().background(.white.opacity(0.1))

                        settingsRow(icon: "desktopcomputer", title: "Change Register") {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                SheetCoordinator.shared.present(.registerPicker)
                            }
                        }
                        .padding(.top, 12)
                    } else {
                        settingsRow(icon: "storefront", title: "Select Location") {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                SheetCoordinator.shared.present(.locationPicker)
                            }
                        }
                    }
                }
            }
        }
    }

    @State private var showPrinterPicker = false

    // MARK: - Printer Section

    private var printerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ModalSectionLabel("Printer")

            ModalSection {
                VStack(spacing: 0) {
                    // Printer Selection
                    Button {
                        Haptics.light()
                        showPrinterPicker = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "printer.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.white.opacity(0.6))
                                .frame(width: 32)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Label Printer")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(.white)
                                Text(printerSettings.printerName ?? "Tap to select")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.5))
                            }

                            Spacer()

                            if printerSettings.printerName != nil {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(Design.Colors.Semantic.success)
                            } else {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.3))
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(PrinterPickerPresenter(isPresented: $showPrinterPicker, printerSettings: printerSettings))

                    Divider().background(.white.opacity(0.1)).padding(.vertical, 12)

                    // Auto-Print Toggle
                    HStack(spacing: 12) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(width: 32)

                        Text("Auto-Print Labels")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white)

                        Spacer()

                        Toggle("", isOn: $printerSettings.isAutoPrintEnabled)
                            .labelsHidden()
                            .tint(Design.Colors.Semantic.success)
                    }
                }
            }

            Text("Auto-print creates labels after each sale")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.horizontal, 4)
        }
    }

    // MARK: - Label Position Section

    private var labelPositionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ModalSectionLabel("Label Start Position")

            ModalSection {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Start at position \(printerSettings.startPosition + 1)")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.6))

                    // 2 columns × 5 rows to match Avery 5163 label sheet layout
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 6) {
                        ForEach(0..<10, id: \.self) { position in
                            let isSelected = printerSettings.startPosition == position
                            Button {
                                Haptics.light()
                                printerSettings.startPosition = position
                            } label: {
                                Text("\(position + 1)")
                                    .font(.system(size: 14, weight: isSelected ? .bold : .medium))
                                    .foregroundStyle(isSelected ? .white : .white.opacity(0.6))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 32)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(isSelected ? .white.opacity(0.2) : .white.opacity(0.06))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(isSelected ? .white.opacity(0.3) : .clear, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Text("Avery 5163 • 2×4\" • 10 labels per sheet")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.horizontal, 4)
        }
    }

    // MARK: - Drawer Section

    private var drawerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ModalSectionLabel("Cash Drawer")

            ModalSection {
                VStack(spacing: 0) {
                    settingsRow(icon: "banknote", title: "Safe Drop") {
                        if let posSession = windowSession?.posSession {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                SheetCoordinator.shared.present(.safeDrop(session: posSession))
                            }
                        }
                    }

                    Divider().background(.white.opacity(0.1)).padding(.vertical, 12)

                    HStack(spacing: 12) {
                        Image(systemName: "dollarsign.circle")
                            .font(.system(size: 16))
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(width: 32)

                        Text("Drawer Balance")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white)

                        Spacer()

                        Text(CurrencyFormatter.format(windowSession?.drawerBalance ?? 0))
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ModalSectionLabel("Actions")

            ModalSection {
                VStack(spacing: 0) {
                    settingsRow(icon: "arrow.clockwise", title: "Refresh Products") {
                        dismiss()
                        Task {
                            if let ws = windowSession {
                                await ws.refresh()
                            } else {
                                await POSStore.shared.refresh()
                            }
                        }
                    }

                    if let storeId = session.storeId, let location = currentLocation {
                        Divider().background(.white.opacity(0.1)).padding(.vertical, 12)

                        settingsRow(icon: "arrow.left.arrow.right", title: "Create Transfer") {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                SheetCoordinator.shared.present(.createTransfer(storeId: storeId, sourceLocation: location))
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - End Session

    private var endSessionButton: some View {
        Button {
            Haptics.medium()
            dismiss()
            Task {
                try? await session.signOut()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "power")
                    .font(.system(size: 14, weight: .semibold))
                Text("End Session")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(Design.Colors.Semantic.error)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Design.Colors.Semantic.error.opacity(0.15))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func settingsRow(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.light()
            action()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 32)

                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Printer Picker Presenter

/// UIViewControllerRepresentable that presents UIPrinterPickerController properly
private struct PrinterPickerPresenter: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    @ObservedObject var printerSettings: LabelPrinterSettings

    func makeUIViewController(context: Context) -> PrinterPickerHostController {
        let controller = PrinterPickerHostController()
        controller.printerSettings = printerSettings
        controller.onDismiss = {
            DispatchQueue.main.async {
                self.isPresented = false
            }
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: PrinterPickerHostController, context: Context) {
        if isPresented && !uiViewController.isShowingPicker {
            uiViewController.showPrinterPicker()
        }
    }
}

private class PrinterPickerHostController: UIViewController {
    var printerSettings: LabelPrinterSettings?
    var onDismiss: (() -> Void)?
    var isShowingPicker = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
    }

    func showPrinterPicker() {
        guard !isShowingPicker else { return }
        isShowingPicker = true

        // Get existing printer if saved
        var existingPrinter: UIPrinter? = nil
        if let printerUrl = printerSettings?.printerUrl {
            existingPrinter = UIPrinter(url: printerUrl)
        }

        let picker = UIPrinterPickerController(initiallySelectedPrinter: existingPrinter)

        // Set delegate for additional control
        picker.delegate = self

        // Use a slight delay to ensure view hierarchy is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self = self, let view = self.view else {
                self?.finishPicking()
                return
            }

            // Present from center of this view controller's view
            let sourceRect = CGRect(x: view.bounds.midX - 1, y: view.bounds.midY - 1, width: 2, height: 2)

            let presented = picker.present(from: sourceRect, in: view, animated: true) { [weak self] controller, selected, error in
                print("🖨️ Picker completion: selected=\(selected), error=\(error?.localizedDescription ?? "none")")
                if selected, let printer = controller.selectedPrinter {
                    DispatchQueue.main.async {
                        self?.printerSettings?.printerUrl = printer.url
                        self?.printerSettings?.printerName = printer.displayName
                        print("🖨️ Saved printer: \(printer.displayName)")
                    }
                }
                self?.finishPicking()
            }

            print("🖨️ picker.present returned: \(presented)")
            if !presented {
                print("🖨️ Failed to present - trying alternative method")
                // Try presenting from the view controller itself
                self.tryAlternativePresentation(picker: picker)
            }
        }
    }

    private func tryAlternativePresentation(picker: UIPrinterPickerController) {
        // Try to find the topmost view controller and present from there
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow }) ?? windowScene.windows.first,
              let rootVC = window.rootViewController else {
            print("🖨️ Could not find root view controller")
            finishPicking()
            return
        }

        // Find topmost presented controller
        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }

        print("🖨️ Trying to present from topVC: \(type(of: topVC))")

        // Present from the top view controller's view
        let sourceRect = CGRect(x: topVC.view.bounds.midX - 1, y: 100, width: 2, height: 2)

        let presented = picker.present(from: sourceRect, in: topVC.view, animated: true) { [weak self] controller, selected, error in
            print("🖨️ Alt picker completion: selected=\(selected)")
            if selected, let printer = controller.selectedPrinter {
                DispatchQueue.main.async {
                    self?.printerSettings?.printerUrl = printer.url
                    self?.printerSettings?.printerName = printer.displayName
                }
            }
            self?.finishPicking()
        }

        print("🖨️ Alt present returned: \(presented)")
        if !presented {
            finishPicking()
        }
    }

    private func finishPicking() {
        isShowingPicker = false
        onDismiss?()
    }
}

extension PrinterPickerHostController: UIPrinterPickerControllerDelegate {
    func printerPickerControllerDidDismiss(_ printerPickerController: UIPrinterPickerController) {
        print("🖨️ Printer picker dismissed by user")
        finishPicking()
    }

    func printerPickerControllerDidSelectPrinter(_ printerPickerController: UIPrinterPickerController) {
        print("🖨️ Printer selected via delegate")
    }

    func printerPickerControllerParentViewController(_ printerPickerController: UIPrinterPickerController) -> UIViewController? {
        print("🖨️ Delegate asked for parent view controller")
        return self
    }
}

// MARK: - Error Alert Sheet

/// Standardized error sheet that matches the app's liquid glass design
private struct ErrorAlertSheet: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 0) {
            // Drag indicator
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.white.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 20)

            VStack(spacing: 16) {
                // Error icon
                ZStack {
                    Circle()
                        .fill(Design.Colors.Semantic.error.opacity(0.15))
                        .frame(width: 64, height: 64)

                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Design.Colors.Semantic.error)
                }

                // Title
                Text(title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                // Message
                Text(message)
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
            }
            .padding(.horizontal, 24)

            Spacer().frame(height: 32)

            // Dismiss button
            Button {
                Haptics.light()
                SheetCoordinator.shared.dismiss()
            } label: {
                Text("Dismiss")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.white.opacity(0.15))
                    )
            }
            .buttonStyle(ScaleButtonStyle())
            .padding(.horizontal, 24)

            Spacer().frame(height: 24)
        }
        .frame(maxWidth: .infinity)
        .background(Color.black)
        .preferredColorScheme(.dark)
    }
}
