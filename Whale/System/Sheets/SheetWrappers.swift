//
//  SheetWrappers.swift
//  Whale
//
//  Private wrapper views used by SheetContainer to configure
//  sheet-specific logic (callbacks, data loading, environment).
//

import SwiftUI
import Supabase

// MARK: - Checkout

struct CheckoutSheetWrapper: View {
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

// MARK: - Tier Selector

struct TierSelectorSheetWrapper: View {
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

// MARK: - Safe Drop

struct SafeDropSheet: View {
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

// MARK: - Open Cash Drawer

struct OpenCashDrawerSheet: View {
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

// MARK: - Order Detail

struct OrderDetailSheet: View {
    let order: Order
    @State private var fullOrder: Order?
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
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

                Text("Done")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.clear)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

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
        if let items = order.items, !items.isEmpty {
            fullOrder = order
            isLoading = false
            return
        }

        do {
            if let fetched = try await OrderService.fetchOrder(orderId: order.id) {
                fullOrder = fetched
            } else {
                fullOrder = order
            }
        } catch {
            fullOrder = order
        }
        isLoading = false
    }
}

// MARK: - Register Picker

struct RegisterPickerSheet: View {
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

// MARK: - Printer Settings

struct PrinterSettingsSheet: View {
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

// MARK: - Bulk Product Labels

struct BulkProductLabelSheet: View {
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

// MARK: - Invoice Detail

struct InvoiceDetailSheetWrapper: View {
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

// MARK: - Product Detail

struct ProductDetailSheetWrapper: View {
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

// MARK: - Label Template

struct LabelTemplateSheetWrapper: View {
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

// MARK: - Order Label Template

struct OrderLabelTemplateSheetWrapper: View {
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

// MARK: - Error Alert

struct ErrorAlertSheet: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.white.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 20)

            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Design.Colors.Semantic.error.opacity(0.15))
                        .frame(width: 64, height: 64)

                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Design.Colors.Semantic.error)
                }

                Text(title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
            }
            .padding(.horizontal, 24)

            Spacer().frame(height: 32)

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
