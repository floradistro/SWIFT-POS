//
//  LabelPrinterSetupView.swift
//  Whale
//
//  Printer setup modal - extracted from LabelPrintService.
//

import SwiftUI

struct LabelPrinterSetupView: View {
    @Binding var isPresented: Bool
    @StateObject private var settings = LabelPrinterSettings.shared
    @State private var isSelectingPrinter = false

    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }

            // Centered modal
            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Printer Setup")
                            .font(Design.Typography.headline).fontWeight(.bold)
                            .foregroundStyle(.white)
                        Text("Configure label printing")
                            .font(Design.Typography.footnote)
                            .foregroundStyle(.white.opacity(0.5))
                    }

                    Spacer()

                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(Design.Typography.footnote).fontWeight(.semibold)
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(.white.opacity(0.1)))
                    }
                }
                .padding(20)

                // Content
                VStack(spacing: 12) {
                    // Printer selection
                    Button {
                        isSelectingPrinter = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "printer.fill")
                                .font(Design.Typography.callout).fontWeight(.medium)
                                .foregroundStyle(settings.printerName != nil ? Design.Colors.Semantic.accent : .white.opacity(0.5))
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Printer")
                                    .font(Design.Typography.footnote).fontWeight(.medium)
                                    .foregroundStyle(.white)
                                if let name = settings.printerName {
                                    Text(name)
                                        .font(Design.Typography.caption1)
                                        .foregroundStyle(.white.opacity(0.5))
                                } else {
                                    Text("Not selected")
                                        .font(Design.Typography.caption1)
                                        .foregroundStyle(.white.opacity(0.4))
                                }
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(Design.Typography.caption1).fontWeight(.medium)
                                .foregroundStyle(.white.opacity(0.3))
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.white.opacity(0.06))
                        )
                    }

                    // Auto-print toggle
                    HStack(spacing: 12) {
                        Image(systemName: settings.isAutoPrintEnabled ? "bolt.fill" : "bolt")
                            .font(Design.Typography.callout).fontWeight(.medium)
                            .foregroundStyle(settings.isAutoPrintEnabled ? .yellow : .white.opacity(0.5))
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Auto-Print Labels")
                                .font(Design.Typography.footnote).fontWeight(.medium)
                                .foregroundStyle(.white)
                            Text("Print after each sale")
                                .font(Design.Typography.caption1)
                                .foregroundStyle(.white.opacity(0.5))
                        }

                        Spacer()

                        Toggle("", isOn: $settings.isAutoPrintEnabled)
                            .labelsHidden()
                            .tint(Design.Colors.Semantic.accent)
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.white.opacity(0.06))
                    )

                    // Start position picker
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            Image(systemName: "rectangle.grid.2x2")
                                .font(Design.Typography.callout).fontWeight(.medium)
                                .foregroundStyle(.white.opacity(0.5))
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Label Start Position")
                                    .font(Design.Typography.footnote).fontWeight(.medium)
                                    .foregroundStyle(.white)
                                Text("Avery 5163 • 2×4\" • 10 per sheet")
                                    .font(Design.Typography.caption1)
                                    .foregroundStyle(.white.opacity(0.5))
                            }

                            Spacer()
                        }

                        // 5 rows x 2 cols grid visualization
                        HStack(spacing: 16) {
                            // Sheet preview
                            VStack(spacing: 3) {
                                ForEach(0..<5, id: \.self) { row in
                                    HStack(spacing: 3) {
                                        ForEach(0..<2, id: \.self) { col in
                                            let position = row * 2 + col
                                            let isSelected = settings.startPosition == position

                                            Button {
                                                Haptics.light()
                                                settings.startPosition = position
                                            } label: {
                                                Text("\(position + 1)")
                                                    .font(Design.Typography.caption2).fontWeight(isSelected ? .bold : .medium)
                                                    .foregroundStyle(isSelected ? .black : .white.opacity(0.5))
                                                    .frame(width: 32, height: 20)
                                                    .background(
                                                        RoundedRectangle(cornerRadius: 4)
                                                            .fill(isSelected ? .white : .white.opacity(0.1))
                                                    )
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(.white.opacity(0.15), lineWidth: 1)
                            )

                            // Description
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Position \(settings.startPosition + 1)")
                                    .font(Design.Typography.footnote).fontWeight(.semibold)
                                    .foregroundStyle(.white)
                                Text("Labels will print starting from this position on the sheet")
                                    .font(Design.Typography.caption2)
                                    .foregroundStyle(.white.opacity(0.5))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.white.opacity(0.06))
                    )

                    // Status
                    if settings.printerName != nil {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(Design.Typography.callout).fontWeight(.medium)
                                .foregroundStyle(Design.Colors.Semantic.success)
                                .frame(width: 24)

                            Text("Printer Ready")
                                .font(Design.Typography.footnote).fontWeight(.medium)
                                .foregroundStyle(.white)

                            Spacer()

                            Text("Connected")
                                .font(Design.Typography.caption1).fontWeight(.medium)
                                .foregroundStyle(Design.Colors.Semantic.success)
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Design.Colors.Semantic.success.opacity(0.1))
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(.white.opacity(0.15), lineWidth: 0.5)
            )
            .frame(maxWidth: 380)
            .padding(40)
        }
        .onChange(of: isSelectingPrinter) { _, selecting in
            if selecting {
                Task {
                    _ = await LabelPrintService.selectPrinter()
                    isSelectingPrinter = false
                }
            }
        }
    }
}
