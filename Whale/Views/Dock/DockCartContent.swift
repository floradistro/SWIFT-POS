//  DockCartContent.swift - Cart display and idle states

import SwiftUI
import Combine
import Supabase

// MARK: - Idle Content (Per-Window Info + Menu)

struct DockIdleContent: View {
    @Environment(\.posWindowSession) private var windowSession: POSWindowSession?

    let storeLogoUrl: URL?
    let onScanID: () -> Void
    let onFindCustomer: (() -> Void)?
    let onSafeDrop: (() -> Void)?
    let onCreateTransfer: (() -> Void)?
    let onPrinterSettings: (() -> Void)?
    let onAskLisa: (() -> Void)?
    let onEndSession: () -> Void
    @Binding var showRegisterPicker: Bool

    /// True when we have a proper window session with location/register
    private var isIsolatedWindow: Bool {
        windowSession?.location != nil
    }

    var body: some View {
        menuButton
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: value as NSDecimalNumber) ?? "$0.00"
    }

    // MARK: - Menu Button

    private var menuButton: some View {
        Menu {
            // Header section with location/register/drawer stats
            if isIsolatedWindow, let ws = windowSession, let location = ws.location {
                Section {
                    // Location
                    Label(location.name, systemImage: "storefront")

                    // Register (tappable to change)
                    if let register = ws.register {
                        Button {
                            Haptics.light()
                            showRegisterPicker = true
                        } label: {
                            Label("\(register.registerName) (#\(register.registerNumber))", systemImage: "desktopcomputer")
                        }

                        // Drawer balance
                        Label("Drawer: \(formatCurrency(ws.drawerBalance))", systemImage: "dollarsign.circle")
                    } else {
                        Button {
                            Haptics.light()
                            showRegisterPicker = true
                        } label: {
                            Label("Select Register", systemImage: "exclamationmark.triangle")
                        }
                    }
                }
            }

            // Customer actions
            Section {
                Button {
                    Haptics.light()
                    onScanID()
                } label: {
                    Label("Scan ID", systemImage: "person.text.rectangle")
                }

                Button {
                    Haptics.light()
                    onFindCustomer?()
                } label: {
                    Label("Find Customer", systemImage: "magnifyingglass")
                }
            }

            // Drawer actions (only when register is selected)
            if windowSession?.register != nil {
                Section {
                    Button {
                        Haptics.light()
                        onSafeDrop?()
                    } label: {
                        Label("Safe Drop", systemImage: "banknote")
                    }
                }
            }

            // Tools
            Section {
                Button {
                    Haptics.light()
                    onCreateTransfer?()
                } label: {
                    Label("Transfer", systemImage: "arrow.left.arrow.right")
                }

                Button {
                    Haptics.light()
                    onPrinterSettings?()
                } label: {
                    Label("Printer Settings", systemImage: "printer")
                }
            }

            // Window actions
            Section {
                Button {
                    Haptics.light()
                    onAskLisa?()
                } label: {
                    Label("Ask Lisa", systemImage: "sparkles")
                }

                Button {
                    Haptics.light()
                    StageManagerStore.shared.show()
                } label: {
                    Label("Switch Window", systemImage: "rectangle.on.rectangle")
                }

                Button(role: .destructive) {
                    Haptics.light()
                    onEndSession()
                } label: {
                    Label("Close Window", systemImage: "xmark.circle")
                }
            }
        } label: {
            AsyncImage(url: storeLogoUrl) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 44, height: 44)
            } placeholder: {
                Image(systemName: "storefront")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 44, height: 44)
            }
            .frame(width: 56, height: 56)
            .contentShape(Rectangle())
        }
        .menuStyle(.automatic)
    }
}

// MARK: - Register Picker Sheet Content

struct RegisterPickerSheetContent: View {
    @Binding var isPresented: Bool
    let windowSession: POSWindowSession?

    @State private var registers: [Register] = []
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            // Header
            ModalHeader("Select Register", subtitle: windowSession?.location?.name, onClose: {
                isPresented = false
            })

            // Content
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Loading registers...")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            } else if registers.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "desktopcomputer.trianglebadge.exclamationmark")
                        .font(.system(size: 48))
                        .foregroundStyle(.orange)
                    Text("No Registers")
                        .font(.system(size: 18, weight: .semibold))
                    Text("Add registers for this location in admin.")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                VStack(spacing: 10) {
                    ForEach(registers, id: \.id) { register in
                        registerRow(register)
                    }
                }
                .padding(.horizontal, 16)
            }

            Spacer(minLength: 20)

            // Cancel button
            ModalSecondaryButton(title: "Cancel") {
                isPresented = false
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            await loadRegisters()
        }
    }

    private func registerRow(_ register: Register) -> some View {
        let isSelected = windowSession?.register?.id == register.id

        return Button {
            Haptics.medium()
            windowSession?.setRegister(register)
            isPresented = false
        } label: {
            HStack(spacing: 14) {
                // Icon
                Image(systemName: iconForDevice(register.deviceName))
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(isSelected ? Color.green : .primary)
                    .frame(width: 40)

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(register.registerName)
                        .font(.system(size: 16, weight: .semibold))
                    HStack(spacing: 8) {
                        Text("#\(register.registerNumber)")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        if register.allowCash {
                            badgeView("Cash", color: .green)
                        }
                        if register.allowCard {
                            badgeView("Card", color: .blue)
                        }
                    }
                }

                Spacer()

                // Checkmark
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.green)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(minHeight: 60)
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(ScaleButtonStyle())
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isSelected ? Color.green.opacity(0.5) : Color.clear, lineWidth: 2)
        )
    }

    private func badgeView(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.15)))
    }

    private func loadRegisters() async {
        guard let locationId = windowSession?.location?.id else {
            isLoading = false
            return
        }

        do {
            let client = await supabaseAsync()
            let response: [Register] = try await client
                .from("pos_registers")
                .select("*")
                .eq("location_id", value: locationId.uuidString.lowercased())
                .eq("status", value: "active")
                .order("register_number", ascending: true)
                .execute()
                .value

            await MainActor.run {
                registers = response
                isLoading = false
            }
        } catch {
            print("Failed to load registers: \(error)")
            await MainActor.run {
                isLoading = false
            }
        }
    }

    private func iconForDevice(_ deviceName: String?) -> String {
        guard let name = deviceName?.lowercased() else {
            return "desktopcomputer"
        }
        if name.contains("ipad") { return "ipad.landscape" }
        if name.contains("iphone") { return "iphone" }
        if name.contains("mac") { return "macbook" }
        return "desktopcomputer"
    }
}

// MARK: - Cart Content (Items + Total + Pay)

struct DockCartContent: View {
    @ObservedObject var posStore: POSStore
    @Environment(\.posWindowSession) private var windowSession: POSWindowSession?
    let onCheckout: () -> Void

    // Trigger re-render when windowSession publishes changes
    @State private var windowSessionUpdateTrigger = UUID()

    // MARK: - Session Accessors
    // Use windowSession ONLY when it has a location (multi-window mode)

    /// True only when this is a multi-window session with its own location
    private var isMultiWindowSession: Bool {
        windowSession?.location != nil
    }

    private var cartTotal: Decimal {
        isMultiWindowSession ? (windowSession?.cartTotal ?? 0) : posStore.cartTotal
    }

    private var cartItems: [CartItem] {
        isMultiWindowSession ? (windowSession?.cartItems ?? []) : posStore.cartItems
    }

    private var itemCount: Int {
        cartItems.reduce(0) { $0 + $1.quantity }
    }

    var body: some View {
        GeometryReader { geo in
            let isCompact = geo.size.width < 340

            HStack(spacing: 10) {
                // Cart pill - liquid glass style
                cartPill(compact: isCompact)

                Spacer(minLength: 0)

                // Total display
                AnimatedTotal(value: cartTotal)
                    .fixedSize()

                // Pay button - liquid glass style
                payButton(compact: isCompact)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onReceive(windowSession?.objectWillChange.eraseToAnyPublisher() ?? Empty().eraseToAnyPublisher()) { _ in
            if isMultiWindowSession {
                windowSessionUpdateTrigger = UUID()
            }
        }
    }

    // MARK: - Cart Pill (Liquid Glass)

    private func cartPill(compact: Bool) -> some View {
        Button {
            Haptics.light()
            onCheckout()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "cart.fill")
                    .font(.system(size: 18, weight: .semibold))

                Text("\(itemCount)")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .contentTransition(.numericText(value: Double(itemCount)))

                if !compact {
                    Text(itemCount == 1 ? "item" : "items")
                        .font(.system(size: 15, weight: .medium))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(height: 44)
        }
        .tint(.white)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    // MARK: - Pay Button (Liquid Glass)

    private func payButton(compact: Bool) -> some View {
        Button {
            Haptics.medium()
            onCheckout()
        } label: {
            HStack(spacing: 8) {
                Text("Pay")
                    .font(.system(size: 17, weight: .semibold))

                Image(systemName: "arrow.right")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .frame(height: 44)
        }
        .tint(.white)
        .glassEffect(.regular.interactive(), in: .capsule)
    }
}

// MARK: - Customer Only Content

struct DockCustomerOnlyContent: View {
    let customer: Customer
    let onScanID: () -> Void
    let onRemoveCustomer: () -> Void

    private var customerColor: Color {
        let colors: [Color] = [
            Color(red: 34/255, green: 197/255, blue: 94/255),   // Green
            Color(red: 59/255, green: 130/255, blue: 246/255),  // Blue
            Color(red: 168/255, green: 85/255, blue: 247/255),  // Purple
            Color(red: 236/255, green: 72/255, blue: 153/255),  // Pink
            Color(red: 245/255, green: 158/255, blue: 11/255),  // Amber
        ]
        return colors[abs(customer.id.hashValue) % colors.count]
    }

    var body: some View {
        HStack(spacing: 12) {
            // Customer pill
            customerPill

            Spacer(minLength: 0)

            // Action buttons
            HStack(spacing: 12) {
                // Scan button
                Button {
                    Haptics.light()
                    onScanID()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "qrcode.viewfinder")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Scan")
                            .font(.system(size: 16, weight: .medium))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(height: 44)
                }
                .tint(.white)
                .glassEffect(.regular.interactive(), in: .capsule)

                // Close button
                Button {
                    Haptics.light()
                    onRemoveCustomer()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 40, height: 40)
                }
                .tint(.white)
                .glassEffect(.regular.interactive(), in: .circle)
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var customerPill: some View {
        HStack(spacing: 10) {
            // Color dot
            Circle()
                .fill(customerColor)
                .frame(width: 12, height: 12)

            Text(customer.initials)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)

            Text(customer.firstName ?? "Guest")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 18)
        .frame(height: 52)
        .glassEffect(.regular, in: .capsule)
    }
}

// MARK: - Cart Item Chips (stacked preview)

struct CartItemChips: View {
    let items: [CartItem]

    var body: some View {
        HStack(spacing: -6) {
            ForEach(Array(items.prefix(4).enumerated()), id: \.element.id) { index, item in
                ItemChip(item: item, index: index)
                    .zIndex(Double(10 - index))
            }

            if items.count > 4 {
                Text("+\(items.count - 4)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .glassEffect(.regular, in: .circle)
            }
        }
    }
}
