//
//  IDScannerView.swift
//  Whale
//
//  Native iOS VisionKit scanner with modals for customer/inventory selection.
//

import SwiftUI
import VisionKit
import Vision
import AudioToolbox
import os.log

// MARK: - ID Scanner View

struct IDScannerView: View {
    let storeId: UUID
    let onCustomerSelected: (Customer) -> Void
    let onDismiss: () -> Void
    /// Optional callback for when ID is scanned with matches - if set, caller handles UI instead of SheetCoordinator
    var onScannedIDWithMatches: ((ScannedID, [CustomerMatch]) -> Void)? = nil

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            NativeScannerView(
                storeId: storeId,
                onCustomerSelected: onCustomerSelected,
                onDismiss: onDismiss,
                onScannedIDWithMatches: onScannedIDWithMatches
            )
            .ignoresSafeArea()
        }
    }
}

// MARK: - Native Scanner (UIKit)

struct NativeScannerView: UIViewControllerRepresentable {
    let storeId: UUID
    let onCustomerSelected: (Customer) -> Void
    let onDismiss: () -> Void
    var onScannedIDWithMatches: ((ScannedID, [CustomerMatch]) -> Void)? = nil

    func makeUIViewController(context: Context) -> UINavigationController {
        let coordinator = context.coordinator

        if DataScannerViewController.isSupported {
            let scanner = DataScannerViewController(
                recognizedDataTypes: [.barcode(symbologies: [.pdf417, .qr])],
                qualityLevel: .accurate,
                recognizesMultipleItems: false,
                isHighFrameRateTrackingEnabled: true,
                isPinchToZoomEnabled: true,
                isGuidanceEnabled: true,
                isHighlightingEnabled: true
            )
            scanner.delegate = coordinator
            scanner.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: coordinator, action: #selector(Coordinator.dismissScanner))
            scanner.navigationItem.title = "Scan ID"

            let nav = UINavigationController(rootViewController: scanner)
            nav.navigationBar.prefersLargeTitles = false
            nav.modalPresentationStyle = .fullScreen

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { try? scanner.startScanning() }
            return nav
        } else {
            let fallback = UIHostingController(rootView: UnsupportedScannerView(onDismiss: onDismiss))
            return UINavigationController(rootViewController: fallback)
        }
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(
            storeId: storeId,
            onCustomerSelected: onCustomerSelected,
            onDismiss: onDismiss,
            onScannedIDWithMatches: onScannedIDWithMatches
        )
    }

    class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let storeId: UUID
        let onCustomerSelected: (Customer) -> Void
        let onDismiss: () -> Void
        let onScannedIDWithMatches: ((ScannedID, [CustomerMatch]) -> Void)?
        private var isProcessing = false

        init(storeId: UUID, onCustomerSelected: @escaping (Customer) -> Void, onDismiss: @escaping () -> Void, onScannedIDWithMatches: ((ScannedID, [CustomerMatch]) -> Void)? = nil) {
            self.storeId = storeId
            self.onCustomerSelected = onCustomerSelected
            self.onDismiss = onDismiss
            self.onScannedIDWithMatches = onScannedIDWithMatches
        }

        @objc func dismissScanner() { onDismiss() }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            processBarcode(from: items, scanner: scanner)
        }

        func dataScanner(_ scanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            processBarcode(from: [item], scanner: scanner)
        }

        private func processBarcode(from items: [RecognizedItem], scanner: DataScannerViewController) {
            guard !isProcessing else { return }

            for item in items {
                guard case .barcode(let barcode) = item, let payload = barcode.payloadStringValue, !payload.isEmpty else { continue }

                isProcessing = true
                scanner.stopScanning()
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                AudioServicesPlaySystemSound(1111)

                Task { @MainActor in
                    await self.handleBarcode(payload, symbology: barcode.observation.symbology, scanner: scanner)
                }
                return
            }
        }

        @MainActor
        private func handleBarcode(_ payload: String, symbology: VNBarcodeSymbology, scanner: DataScannerViewController) async {
            if symbology == .pdf417 {
                await processDriversLicense(payload, scanner: scanner)
            } else if symbology == .qr {
                await processQRCode(payload, scanner: scanner)
            } else {
                isProcessing = false
                try? scanner.startScanning()
            }
        }

        @MainActor
        private func processDriversLicense(_ data: String, scanner: DataScannerViewController) async {
            do {
                let parsed = try AAMVAParser.parse(data)

                if let dob = parsed.dateOfBirth, !AgeCalculator.isLegalAge(dob) {
                    let age = AgeCalculator.calculateAge(from: dob) ?? 0
                    ScanFeedback.shared.ageRejected()
                    showAlert(on: scanner, title: "Under 21", message: "Age: \(age)") {
                        self.isProcessing = false
                        try? scanner.startScanning()
                    }
                    return
                }

                ScanFeedback.shared.ageVerified()
                let matches = await CustomerService.findMatches(for: parsed, storeId: storeId)
                showCustomerSheet(on: scanner, scannedID: parsed, matches: matches)
            } catch {
                ScanFeedback.shared.error()
                showAlert(on: scanner, title: "Scan Error", message: "Could not read ID. Try again.") {
                    self.isProcessing = false
                    try? scanner.startScanning()
                }
            }
        }

        @MainActor
        private func processQRCode(_ payload: String, scanner: DataScannerViewController) async {
            let code: String
            if payload.contains("floradistro.com/qr/"), let range = payload.range(of: "/qr/") {
                code = String(payload[range.upperBound...])
            } else if payload.hasPrefix("http"), let url = URL(string: payload) {
                code = url.lastPathComponent
            } else {
                code = payload
            }

            let prefix = String(code.prefix(1)).uppercased()

            // Check for transfer package codes (PKG prefix)
            if code.uppercased().hasPrefix("PKG") {
                await processPackageQRCode(code, scanner: scanner)
                return
            }

            // Product, Bulk, Distribution, Sale, Inventory unit codes
            if ["P", "B", "D", "S", "I"].contains(prefix) {
                await processInventoryQRCode(code, scanner: scanner)
                return
            }

            guard let uuid = UUID(uuidString: code) else {
                ScanFeedback.shared.error()
                showAlert(on: scanner, title: "Invalid QR", message: "Not a valid QR code.") {
                    self.isProcessing = false
                    try? scanner.startScanning()
                }
                return
            }

            if let customer = await CustomerService.fetchCustomer(id: uuid) {
                ScanFeedback.shared.customerFound()
                onCustomerSelected(customer)
                onDismiss()
            } else {
                ScanFeedback.shared.customerNotFound()
                showAlert(on: scanner, title: "Not Found", message: "Customer not found in system.") {
                    self.isProcessing = false
                    try? scanner.startScanning()
                }
            }
        }

        @MainActor
        private func processInventoryQRCode(_ code: String, scanner: DataScannerViewController) async {
            do {
                // First try inventory_units table
                let result = try await InventoryUnitService.shared.lookup(qrCode: code, storeId: storeId)
                if result.success, result.found, let unit = result.unit {
                    ScanFeedback.shared.customerFound()
                    showInventoryUnitSheet(on: scanner, unit: unit, lookupResult: result)
                    return
                }

                // Fallback: check qr_codes table (for sale/product labels)
                let qrResult = try await QRCodeLookupService.lookup(code: code, storeId: storeId)
                if let scannedQR = qrResult {
                    ScanFeedback.shared.customerFound()
                    showQRCodeSheet(on: scanner, qrCode: scannedQR)
                    return
                }

                ScanFeedback.shared.error()
                showAlert(on: scanner, title: "Not Found", message: "QR code not found in system.") {
                    self.isProcessing = false
                    try? scanner.startScanning()
                }
            } catch {
                ScanFeedback.shared.error()
                showAlert(on: scanner, title: "Lookup Error", message: error.localizedDescription) {
                    self.isProcessing = false
                    try? scanner.startScanning()
                }
            }
        }

        @MainActor
        private func showQRCodeSheet(on scanner: DataScannerViewController, qrCode: ScannedQRCode) {
            // Disable scanner touches FIRST to prevent gesture conflicts
            scanner.view.isUserInteractionEnabled = false
            try? scanner.stopScanning()

            weak var hostingRef: UIViewController?
            let modal = QRCodeScanSheet(qrCode: qrCode, storeId: storeId, onDismiss: { [weak self] in
                hostingRef?.dismiss(animated: false) {
                    scanner.view.isUserInteractionEnabled = true
                    self?.isProcessing = false
                    try? scanner.startScanning()
                }
            }).environmentObject(SessionObserver.shared)

            let host = UIHostingController(rootView: AnyView(modal))
            host.view.backgroundColor = .clear
            host.modalPresentationStyle = .overFullScreen
            host.modalTransitionStyle = .crossDissolve
            hostingRef = host

            // Small delay to ensure scanner is fully stopped before presenting
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                scanner.present(host, animated: false)
            }
        }

        @MainActor
        private func processPackageQRCode(_ code: String, scanner: DataScannerViewController) async {
            do {
                let result = try await InventoryUnitService.shared.lookupTransfer(qrCode: code, storeId: storeId)
                if result.success, result.found, let transfer = result.transfer {
                    ScanFeedback.shared.customerFound()
                    showPackageSheet(on: scanner, transfer: transfer, items: result.items ?? [])
                } else {
                    ScanFeedback.shared.error()
                    showAlert(on: scanner, title: "Not Found", message: result.error ?? "Transfer package not found.") {
                        self.isProcessing = false
                        try? scanner.startScanning()
                    }
                }
            } catch {
                ScanFeedback.shared.error()
                showAlert(on: scanner, title: "Lookup Error", message: error.localizedDescription) {
                    self.isProcessing = false
                    try? scanner.startScanning()
                }
            }
        }

        @MainActor
        private func showPackageSheet(on scanner: DataScannerViewController, transfer: InventoryTransfer, items: [InventoryTransferItem]) {
            scanner.view.isUserInteractionEnabled = false
            try? scanner.stopScanning()

            weak var hostingRef: UIViewController?
            let modal = PackageReceiveSheet(transfer: transfer, items: items, storeId: storeId, onDismiss: { [weak self] in
                hostingRef?.dismiss(animated: false) {
                    scanner.view.isUserInteractionEnabled = true
                    self?.isProcessing = false
                    try? scanner.startScanning()
                }
            }).environmentObject(SessionObserver.shared)

            let host = UIHostingController(rootView: AnyView(modal))
            host.view.backgroundColor = .clear
            host.modalPresentationStyle = .overFullScreen
            host.modalTransitionStyle = .crossDissolve
            hostingRef = host

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                scanner.present(host, animated: false)
            }
        }

        @MainActor
        private func showInventoryUnitSheet(on scanner: DataScannerViewController, unit: InventoryUnit, lookupResult: LookupResult) {
            scanner.view.isUserInteractionEnabled = false
            try? scanner.stopScanning()

            weak var hostingRef: UIViewController?
            let modal = InventoryUnitScanSheet(unit: unit, lookupResult: lookupResult, storeId: storeId, onDismiss: { [weak self] in
                hostingRef?.dismiss(animated: false) {
                    scanner.view.isUserInteractionEnabled = true
                    self?.isProcessing = false
                    try? scanner.startScanning()
                }
            }, onAction: { _ in }).environmentObject(SessionObserver.shared)

            let host = UIHostingController(rootView: AnyView(modal))
            host.view.backgroundColor = .clear
            host.modalPresentationStyle = .overFullScreen
            host.modalTransitionStyle = .crossDissolve
            hostingRef = host

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                scanner.present(host, animated: false)
            }
        }

        @MainActor
        private func showCustomerSheet(on scanner: DataScannerViewController, scannedID: ScannedID, matches: [CustomerMatch]) {
            Log.scanner.debug("Scanned ID - name: \(scannedID.fullDisplayName), matches: \(matches.count)")

            // If callback provided, use it instead of SheetCoordinator (for embedded scanner)
            if let callback = onScannedIDWithMatches {
                callback(scannedID, matches)
                onDismiss()
                return
            }

            // Default behavior: dismiss scanner and present customer sheet via SheetCoordinator
            onDismiss()

            let capturedStoreId = self.storeId
            let capturedScannedID = scannedID
            let capturedMatches = matches

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                SheetCoordinator.shared.present(.customerScanned(storeId: capturedStoreId, scannedID: capturedScannedID, matches: capturedMatches))
            }
        }

        @MainActor
        private func showAlert(on vc: UIViewController, title: String, message: String, onDismiss: @escaping () -> Void) {
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in onDismiss() })
            vc.present(alert, animated: true)
        }
    }
}

// MARK: - Unsupported Device View

struct UnsupportedScannerView: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.fill").font(.system(size: 60)).foregroundStyle(.secondary)
            Text("Scanner Not Available").font(.title2.bold())
            Text("This device doesn't support barcode scanning.").foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Close") { onDismiss() }.buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
