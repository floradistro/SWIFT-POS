//
//  POSSettingsSheet.swift
//  Whale
//
//  POS Settings panel with store info, printer config, and session controls.
//  Extracted from SheetContainer for Apple engineering standards compliance.
//

import SwiftUI
import UIKit
import os.log

// MARK: - POS Settings Sheet

struct POSSettingsSheet: View {
    @EnvironmentObject private var session: SessionObserver
    @Environment(\.posWindowSession) private var windowSession: POSWindowSession?
    @Environment(\.dismiss) private var dismiss
    @StateObject private var printerSettings = LabelPrinterSettings.shared
    @State private var showPrinterPicker = false

    private var currentLocation: Location? {
        windowSession?.location ?? session.selectedLocation
    }

    private var currentRegister: Register? {
        windowSession?.register ?? session.selectedRegister
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    // Store profile header
                    profileHeader

                    // Grouped sections
                    locationAndRegisterSection

                    printerSection

                    labelPositionSection

                    if currentRegister != nil, windowSession?.posSession != nil {
                        drawerSection
                    }

                    actionsSection

                    endSessionButton
                        .padding(.top, 8)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .scrollBounceBehavior(.basedOnSize)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }

    // MARK: - Profile Header

    private var profileHeader: some View {
        VStack(spacing: 12) {
            StoreLogo(
                url: session.store?.fullLogoUrl,
                size: 64,
                storeName: session.store?.businessName
            )

            VStack(spacing: 4) {
                Text(session.store?.businessName ?? "Store")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)

                if let location = currentLocation {
                    Text(location.name)
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Location & Register

    private var locationAndRegisterSection: some View {
        settingsGroup {
            if let location = currentLocation {
                settingsRow(
                    icon: "storefront.fill",
                    iconColor: .blue,
                    title: location.name,
                    subtitle: location.displayAddress
                ) {
                    dismiss()
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(0.3))
                        SheetCoordinator.shared.present(.locationPicker)
                    }
                }

                settingsDivider

                settingsRow(
                    icon: "desktopcomputer",
                    iconColor: .purple,
                    title: currentRegister.map { "\($0.registerName) #\($0.registerNumber)" } ?? "Select Register",
                    subtitle: currentRegister != nil ? "Change register" : nil
                ) {
                    dismiss()
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(0.3))
                        SheetCoordinator.shared.present(.registerPicker)
                    }
                }
            } else {
                settingsRow(
                    icon: "storefront.fill",
                    iconColor: .blue,
                    title: "Select Location"
                ) {
                    dismiss()
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(0.3))
                        SheetCoordinator.shared.present(.locationPicker)
                    }
                }
            }
        }
    }

    // MARK: - Printer Section

    private var printerSection: some View {
        settingsGroup {
            // Printer Selection
            Button {
                Haptics.light()
                showPrinterPicker = true
            } label: {
                HStack(spacing: 14) {
                    settingsIcon("printer.fill", color: .green)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Label Printer")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white)
                        Text(printerSettings.printerName ?? "Tap to select")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.4))
                    }

                    Spacer()

                    if printerSettings.printerName != nil {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Design.Colors.Semantic.success)
                    } else {
                        chevron
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(PrinterPickerPresenter(isPresented: $showPrinterPicker, printerSettings: printerSettings))

            settingsDivider

            // Auto-Print Toggle
            HStack(spacing: 14) {
                settingsIcon("bolt.fill", color: .yellow)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-Print Labels")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                    Text("Print after each sale")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.4))
                }

                Spacer()

                Toggle("", isOn: $printerSettings.isAutoPrintEnabled)
                    .labelsHidden()
                    .tint(Design.Colors.Semantic.success)
            }
        }
    }

    // MARK: - Label Position Section

    private var labelPositionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            settingsGroup {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 14) {
                        settingsIcon("rectangle.grid.2x2", color: .orange)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Label Start Position")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.white)
                            Text("Avery 5163 • Position \(printerSettings.startPosition + 1) of 10")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }

                    // 2 columns × 5 rows grid
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                        ForEach(0..<10, id: \.self) { position in
                            let isSelected = printerSettings.startPosition == position
                            Button {
                                Haptics.light()
                                printerSettings.startPosition = position
                            } label: {
                                Text("\(position + 1)")
                                    .font(.system(size: 14, weight: isSelected ? .bold : .medium, design: .rounded))
                                    .foregroundStyle(isSelected ? .white : .white.opacity(0.5))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 36)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(isSelected ? .white.opacity(0.15) : .white.opacity(0.04))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(isSelected ? .white.opacity(0.25) : .white.opacity(0.06), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Drawer Section

    private var drawerSection: some View {
        settingsGroup {
            settingsRow(
                icon: "banknote.fill",
                iconColor: .green,
                title: "Safe Drop",
                subtitle: "Record a cash drop"
            ) {
                if let posSession = windowSession?.posSession {
                    dismiss()
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(0.3))
                        SheetCoordinator.shared.present(.safeDrop(session: posSession))
                    }
                }
            }

            settingsDivider

            HStack(spacing: 14) {
                settingsIcon("dollarsign.circle.fill", color: .mint)

                Text("Drawer Balance")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)

                Spacer()

                Text(CurrencyFormatter.format(windowSession?.drawerBalance ?? 0))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
        }
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        settingsGroup {
            settingsRow(
                icon: "arrow.clockwise",
                iconColor: .cyan,
                title: "Refresh Products",
                subtitle: "Reload menu from server"
            ) {
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
                settingsDivider

                settingsRow(
                    icon: "arrow.left.arrow.right",
                    iconColor: .indigo,
                    title: "Create Transfer",
                    subtitle: "Move inventory between locations"
                ) {
                    dismiss()
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(0.3))
                        SheetCoordinator.shared.present(.createTransfer(storeId: storeId, sourceLocation: location))
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
            HStack(spacing: 10) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 15, weight: .semibold))
                Text("Sign Out")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(Design.Colors.Semantic.error)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Design.Colors.Semantic.error.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Design.Colors.Semantic.error.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Reusable Components

    private func settingsGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func settingsIcon(_ name: String, color: Color = .white) -> some View {
        Image(systemName: name)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.white.opacity(0.6))
            .frame(width: 32, height: 32)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(0.1), lineWidth: 1)
            )
    }

    private func settingsRow(
        icon: String,
        iconColor: Color = .white,
        title: String,
        subtitle: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.light()
            action()
        } label: {
            HStack(spacing: 14) {
                settingsIcon(icon, color: iconColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }

                Spacer()

                chevron
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var settingsDivider: some View {
        Divider()
            .background(.white.opacity(0.08))
            .padding(.leading, 60)
            .padding(.vertical, 4)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white.opacity(0.2))
    }
}

// MARK: - Printer Picker Presenter

/// UIViewControllerRepresentable that presents UIPrinterPickerController properly
struct PrinterPickerPresenter: UIViewControllerRepresentable {
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

class PrinterPickerHostController: UIViewController {
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
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.2))
            await MainActor.run {
                guard let self = self, let view = self.view else {
                    self?.finishPicking()
                    return
                }

                // Present from center of this view controller's view
                let sourceRect = CGRect(x: view.bounds.midX - 1, y: view.bounds.midY - 1, width: 2, height: 2)

                let presented = picker.present(from: sourceRect, in: view, animated: true) { [weak self] controller, selected, error in
                    Log.label.debug("Picker completion: selected=\(selected), error=\(error?.localizedDescription ?? "none")")
                    if selected, let printer = controller.selectedPrinter {
                        DispatchQueue.main.async {
                            self?.printerSettings?.printerUrl = printer.url
                            self?.printerSettings?.printerName = printer.displayName
                            Log.label.info("Saved printer: \(printer.displayName)")
                        }
                    }
                    self?.finishPicking()
                }

                Log.label.debug("picker.present returned: \(presented)")
                if !presented {
                    Log.label.debug("Failed to present - trying alternative method")
                    // Try presenting from the view controller itself
                    self.tryAlternativePresentation(picker: picker)
                }
            }
        }
    }

    private func tryAlternativePresentation(picker: UIPrinterPickerController) {
        // Try to find the topmost view controller and present from there
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow }) ?? windowScene.windows.first,
              let rootVC = window.rootViewController else {
            Log.label.error("Could not find root view controller")
            finishPicking()
            return
        }

        // Find topmost presented controller
        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }

        Log.label.debug("Trying to present from topVC: \(type(of: topVC))")

        // Present from the top view controller's view
        let sourceRect = CGRect(x: topVC.view.bounds.midX - 1, y: 100, width: 2, height: 2)

        let presented = picker.present(from: sourceRect, in: topVC.view, animated: true) { [weak self] controller, selected, error in
            Log.label.debug("Alt picker completion: selected=\(selected)")
            if selected, let printer = controller.selectedPrinter {
                DispatchQueue.main.async {
                    self?.printerSettings?.printerUrl = printer.url
                    self?.printerSettings?.printerName = printer.displayName
                }
            }
            self?.finishPicking()
        }

        Log.label.debug("Alt present returned: \(presented)")
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
        Log.label.debug("Printer picker dismissed by user")
        finishPicking()
    }

    func printerPickerControllerDidSelectPrinter(_ printerPickerController: UIPrinterPickerController) {
        Log.label.debug("Printer selected via delegate")
    }

    func printerPickerControllerParentViewController(_ printerPickerController: UIPrinterPickerController) -> UIViewController? {
        Log.label.debug("Delegate asked for parent view controller")
        return self
    }
}
