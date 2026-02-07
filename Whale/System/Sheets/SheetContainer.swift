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

        case .storePicker:
            StorePickerSheet()

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

        // MARK: Product Detail
        case .productDetail(let product):
            ProductDetailSheetWrapper(product: product)

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
            initialTotals: totals,
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
            onViewCOA: nil,
            onShowDetail: {
                SheetCoordinator.shared.present(.productDetail(product: product))
            }
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

/// OrderDetail as sheet - uses shared OrderDetailContentView
private struct OrderDetailSheet: View {
    let order: Order
    @State private var fullOrder: Order?
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Done") {
                    SheetCoordinator.shared.dismiss()
                }
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))

                Spacer()

                Text("Order #\(order.shortOrderNumber)")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)

                Spacer()

                // Invisible spacer for centering
                Text("Done")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.clear)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            // Show content - use full order if available, otherwise show passed order with loading
            if isLoading {
                VStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.2)
                        .tint(.white.opacity(0.6))
                    Text("Loading order details...")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(.top, 12)
                    Spacer()
                }
            } else {
                OrderDetailContentView(order: fullOrder ?? order, showCustomerInfo: true)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task {
            await loadFullOrder()
        }
    }

    private func loadFullOrder() async {
        // If order already has items, use it directly
        if let items = order.items, !items.isEmpty {
            print("📋 OrderDetailSheet: Order already has \(items.count) items")
            fullOrder = order
            isLoading = false
            return
        }

        // Fetch complete order with items
        print("📋 OrderDetailSheet: Fetching full order \(order.id) with items...")
        do {
            if let fetched = try await OrderService.fetchOrder(orderId: order.id) {
                print("📋 OrderDetailSheet: Loaded order with \(fetched.items?.count ?? 0) items")
                fullOrder = fetched
            } else {
                print("📋 OrderDetailSheet: Order not found, using passed order")
                fullOrder = order
            }
        } catch {
            print("📋 OrderDetailSheet: Fetch failed: \(error), using passed order")
            fullOrder = order
        }
        isLoading = false
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
/// Product detail sheet
private struct ProductDetailSheetWrapper: View {
    let product: Product

    var body: some View {
        NavigationStack {
            ProductDetailsCard(product: product)
                .navigationTitle(product.name)
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
            onDismiss: { SheetCoordinator.shared.dismiss() }
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
            onDismiss: { SheetCoordinator.shared.dismiss() }
        )
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
        .background(Color(.secondarySystemGroupedBackground))
        .preferredColorScheme(.dark)
    }
}
