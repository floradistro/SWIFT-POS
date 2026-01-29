//
//  POSSettingsMenu.swift
//  Whale
//
//  Hierarchical settings menu with breadcrumb navigation using native SwiftUI.
//

import SwiftUI
import Supabase

// MARK: - Menu Navigation

enum POSMenuDestination: Hashable {
    case settings
    case printer
    case register
}

struct POSSettingsMenu: View {
    @Binding var isPresented: Bool
    @EnvironmentObject private var session: SessionObserver
    @Environment(\.posWindowSession) private var windowSession: POSWindowSession?

    // Callbacks
    var onScanID: () -> Void
    var onFindCustomer: () -> Void
    var onSafeDrop: () -> Void
    var onTransfer: () -> Void
    var onRefresh: () -> Void
    var onEndSession: () -> Void
    var onSelectPrinter: (() -> Void)?

    @State private var path: [POSMenuDestination] = []

    private var isMultiWindowSession: Bool {
        windowSession?.location != nil
    }

    private var currentLocation: Location? {
        windowSession?.location ?? session.selectedLocation
    }

    private var currentRegister: Register? {
        windowSession?.register ?? session.selectedRegister
    }

    var body: some View {
        NavigationStack(path: $path) {
            mainMenuList
                .navigationDestination(for: POSMenuDestination.self) { destination in
                    switch destination {
                    case .settings:
                        settingsMenuList
                    case .printer:
                        printerSettingsList
                    case .register:
                        registerPickerList
                    }
                }
        }
        .tint(.primary)
        .frame(width: 340, height: 500)
        .preferredColorScheme(.dark)
    }

    // MARK: - Main Menu

    private var mainMenuList: some View {
        List {
            // Location header
            if let location = currentLocation {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(location.name)
                                .font(.headline)
                            if let register = currentRegister {
                                Text("\(register.registerName) #\(register.registerNumber)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "storefront.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Customer
            Section("Customer") {
                Button {
                    isPresented = false
                    onScanID()
                } label: {
                    Label("Scan ID", systemImage: "person.text.rectangle")
                }
                .foregroundStyle(.primary)

                Button {
                    isPresented = false
                    onFindCustomer()
                } label: {
                    Label("Find Customer", systemImage: "magnifyingglass")
                }
                .foregroundStyle(.primary)
            }

            // Drawer
            if currentRegister != nil {
                Section("Drawer") {
                    Button {
                        isPresented = false
                        onSafeDrop()
                    } label: {
                        Label("Safe Drop", systemImage: "banknote")
                    }
                    .foregroundStyle(.primary)

                    if let ws = windowSession {
                        HStack {
                            Label("Balance", systemImage: "dollarsign.circle")
                            Spacer()
                            Text(CurrencyFormatter.format(ws.drawerBalance))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // Tools
            Section("Tools") {
                Button {
                    isPresented = false
                    onTransfer()
                } label: {
                    Label("Transfer", systemImage: "arrow.left.arrow.right")
                }
                .foregroundStyle(.primary)

                Button {
                    isPresented = false
                    onRefresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .foregroundStyle(.primary)
            }

            // Settings
            Section("Settings") {
                NavigationLink(value: POSMenuDestination.settings) {
                    Label("Settings", systemImage: "gearshape")
                }
                .foregroundStyle(.primary)
            }

            // Window
            Section("Window") {
                Button {
                    isPresented = false
                    StageManagerStore.shared.show()
                } label: {
                    Label("Stage Manager", systemImage: "rectangle.on.rectangle")
                }
                .foregroundStyle(.primary)

                Button {
                    StageManagerStore.shared.isScreenLocked.toggle()
                    isPresented = false
                } label: {
                    Label(
                        StageManagerStore.shared.isScreenLocked ? "Unlock Screen" : "Lock Screen",
                        systemImage: StageManagerStore.shared.isScreenLocked ? "lock.open" : "lock"
                    )
                }
                .foregroundStyle(.primary)

                Button {
                    isPresented = false
                    onEndSession()
                } label: {
                    Label("Close Window", systemImage: "xmark.circle")
                }
                .foregroundStyle(.red)
            }
        }
        .navigationTitle("Menu")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Settings Submenu

    private var settingsMenuList: some View {
        List {
            Section("Hardware") {
                NavigationLink(value: POSMenuDestination.printer) {
                    HStack {
                        Label("Printer", systemImage: "printer")
                        Spacer()
                        if let name = LabelPrinterSettings.shared.printerName {
                            Text(name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Not Set")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .foregroundStyle(.primary)
            }

            Section("Register") {
                NavigationLink(value: POSMenuDestination.register) {
                    HStack {
                        Label("Select Register", systemImage: "desktopcomputer")
                        Spacer()
                        if let register = currentRegister {
                            Text(register.registerName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .foregroundStyle(.primary)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Printer Settings

    private var printerSettingsList: some View {
        EmbeddedPrinterSettings(
            onSelectPrinter: {
                onSelectPrinter?()
                isPresented = false
            }
        )
        .navigationTitle("Printer")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Register Picker

    private var registerPickerList: some View {
        EmbeddedRegisterPicker(onDismiss: { path.removeLast() })
            .navigationTitle("Register")
            .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Embedded Printer Settings

private struct EmbeddedPrinterSettings: View {
    @ObservedObject private var settings = LabelPrinterSettings.shared
    var onSelectPrinter: () -> Void

    var body: some View {
        List {
            // Printer selection
            Section {
                Button {
                    onSelectPrinter()
                } label: {
                    HStack {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Printer")
                                if let name = settings.printerName {
                                    Text(name)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("Tap to select")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } icon: {
                            Image(systemName: "printer")
                        }

                        Spacer()

                        if settings.printerName != nil {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .foregroundStyle(.primary)
            } header: {
                Text("Printer")
            }

            // Options
            Section {
                Toggle(isOn: $settings.isAutoPrintEnabled) {
                    Label("Auto-Print Labels", systemImage: "bolt")
                }
                .tint(.white)
            } header: {
                Text("Options")
            } footer: {
                Text("Automatically print labels after each sale")
            }

            // Start position
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Starting at position \(settings.startPosition + 1)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    // Full width grid - 2 columns x 5 rows
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                        ForEach(0..<10, id: \.self) { position in
                            let isSelected = settings.startPosition == position

                            Button {
                                Haptics.light()
                                settings.startPosition = position
                            } label: {
                                Text("\(position + 1)")
                                    .font(.system(size: 14, weight: isSelected ? .bold : .medium))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 36)
                                    .background(isSelected ? Color.white.opacity(0.25) : Color(.tertiarySystemFill))
                                    .foregroundStyle(.primary)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Label Start Position")
            } footer: {
                Text("Avery 5163 • 2x4\" • 10 labels per sheet")
            }
        }
    }
}

// MARK: - Embedded Register Picker

private struct EmbeddedRegisterPicker: View {
    @EnvironmentObject private var session: SessionObserver
    @Environment(\.posWindowSession) private var windowSession: POSWindowSession?
    var onDismiss: () -> Void

    @State private var isLoading = true
    @State private var registers: [Register] = []

    private var currentRegisterId: UUID? {
        windowSession?.register?.id ?? session.selectedRegister?.id
    }

    private var effectiveLocationId: UUID? {
        windowSession?.location?.id ?? session.selectedLocation?.id
    }

    var body: some View {
        List {
            if isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding(.vertical, 20)
                }
            } else if registers.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No Registers", systemImage: "desktopcomputer")
                    } description: {
                        Text("No registers configured")
                    }
                }
            } else {
                Section {
                    ForEach(registers) { register in
                        let isSelected = register.id == currentRegisterId

                        Button {
                            Haptics.light()
                            Task {
                                await session.selectRegister(register)
                            }
                            onDismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(register.registerName)
                                    Text("Register #\(register.registerNumber)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if isSelected {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
        }
        .task {
            await loadRegisters()
        }
    }

    private func loadRegisters() async {
        guard let locationId = effectiveLocationId else {
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

// MARK: - Preview

#Preview {
    POSSettingsMenu(
        isPresented: .constant(true),
        onScanID: {},
        onFindCustomer: {},
        onSafeDrop: {},
        onTransfer: {},
        onRefresh: {},
        onEndSession: {}
    )
    .environmentObject(SessionObserver.shared)
}
