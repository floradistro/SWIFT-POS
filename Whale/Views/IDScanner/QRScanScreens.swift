//
//  QRScanScreens.swift
//  Whale
//
//  Screen content views for QRCodeScanSheet:
//  receive, transfer, reprint, split, and success screens.
//

import SwiftUI

// MARK: - Receive Content

extension QRCodeScanSheet {

    @ViewBuilder
    var receiveContent: some View {
        summaryCard

        // Determine source location and whether to show transfer visual
        let currentLocationName = session.selectedLocation?.name ?? ""
        let fromLocation = pendingTransferSourceName ?? qrCode.locationName ?? "External"
        let sourceIsDifferent = pendingTransferSourceName != nil &&
            fromLocation.lowercased() != currentLocationName.lowercased()
        let greenColor = Color(red: 34/255, green: 197/255, blue: 94/255)

        // Only show transfer visual if source is different from current location
        if sourceIsDifferent {
            ModalSection {
                HStack(spacing: 0) {
                    // From location
                    VStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(greenColor.opacity(0.15))
                                .frame(width: 36, height: 36)
                            Image(systemName: "building.2.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(greenColor.opacity(0.7))
                        }
                        Text(fromLocation)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)

                    // Arrow
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(greenColor)
                        Text("Transfer")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(greenColor.opacity(0.6))
                    }
                    .frame(width: 60)

                    // To location (current)
                    VStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [greenColor, greenColor.opacity(0.8)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 36, height: 36)
                                .shadow(color: greenColor.opacity(0.4), radius: 6, y: 2)
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        Text(session.selectedLocation?.name ?? "Here")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 8)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Transfer from \(fromLocation) to \(session.selectedLocation?.name ?? "here")")
            }

            ModalActionButton("Receive from \(fromLocation)", icon: "tray.and.arrow.down.fill", isLoading: isLoading, style: .success) {
                performReceive()
            }
        } else {
            // Item is already at this location - show simple receive UI
            ModalSection {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [greenColor, greenColor.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 44, height: 44)
                            .shadow(color: greenColor.opacity(0.4), radius: 6, y: 2)
                        Image(systemName: "tray.and.arrow.down.fill")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add to Inventory")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(session.selectedLocation?.name ?? "Current Location")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.6))
                    }

                    Spacer()
                }
                .padding(.vertical, 4)
            }

            ModalActionButton("Receive Into Inventory", icon: "tray.and.arrow.down.fill", isLoading: isLoading, style: .success) {
                performReceive()
            }
        }
    }
}

// MARK: - Transfer Content

extension QRCodeScanSheet {

    /// Locations available for transfer (excludes current location)
    var transferDestinations: [Location] {
        availableLocations.filter { $0.id != session.selectedLocation?.id }
    }

    @ViewBuilder
    var transferContent: some View {
        summaryCard

        let blueColor = Color(red: 59/255, green: 130/255, blue: 246/255)

        // Transfer flow visualization
        ModalSection {
            HStack(spacing: 0) {
                // From location (current)
                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [blueColor, blueColor.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 36, height: 36)
                            .shadow(color: blueColor.opacity(0.4), radius: 6, y: 2)
                        Image(systemName: "building.2.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    Text(session.selectedLocation?.name ?? "Here")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)

                // Arrow
                VStack(spacing: 4) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(blueColor)
                    Text("Transfer")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(blueColor.opacity(0.6))
                }
                .frame(width: 60)

                // To location (destination) - shows selected or placeholder
                VStack(spacing: 6) {
                    ZStack {
                        if selectedTransferDestination != nil {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [blueColor, blueColor.opacity(0.8)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 36, height: 36)
                                .shadow(color: blueColor.opacity(0.4), radius: 6, y: 2)
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                        } else {
                            Circle()
                                .fill(blueColor.opacity(0.15))
                                .frame(width: 36, height: 36)
                            Circle()
                                .stroke(blueColor.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                                .frame(width: 36, height: 36)
                            Image(systemName: "questionmark")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(blueColor.opacity(0.6))
                        }
                    }
                    Text(selectedTransferDestination?.name ?? "Select")
                        .font(.system(size: 11, weight: selectedTransferDestination != nil ? .semibold : .medium))
                        .foregroundStyle(selectedTransferDestination != nil ? .white : .white.opacity(0.5))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 8)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Transfer from \(session.selectedLocation?.name ?? "here") to \(selectedTransferDestination?.name ?? "not selected")")
        }

        // Location picker - scrollable for many locations
        ModalSection {
            VStack(spacing: 8) {
                HStack {
                    Text("Select Destination")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                }

                if transferDestinations.isEmpty {
                    Text("No other locations available")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(.vertical, 8)
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(transferDestinations) { location in
                                transferLocationRow(location, color: blueColor)
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                }
            }
        }

        // Transfer button
        if let destination = selectedTransferDestination {
            ModalActionButton("Transfer to \(destination.name)", icon: "arrow.up.forward.square.fill", isLoading: isLoading) {
                performTransfer()
            }
        } else {
            // Disabled state
            HStack(spacing: 10) {
                Image(systemName: "arrow.up.forward.square.fill")
                    .font(.system(size: 17, weight: .semibold))
                Text("Select a destination")
                    .font(.system(size: 17, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(0.3))
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.ultraThinMaterial))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.1), lineWidth: 0.5))
        }
    }

    @ViewBuilder
    func transferLocationRow(_ location: Location, color: Color) -> some View {
        let isSelected = selectedTransferDestination?.id == location.id

        Button {
            Haptics.light()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedTransferDestination = location
            }
        } label: {
            HStack(spacing: 12) {
                // Selection indicator
                ZStack {
                    Circle()
                        .stroke(isSelected ? color : .white.opacity(0.2), lineWidth: 2)
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle()
                            .fill(color)
                            .frame(width: 14, height: 14)
                    }
                }

                // Location icon
                Image(systemName: location.isWarehouse ? "shippingbox.fill" : "building.2.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? color : .white.opacity(0.5))
                    .frame(width: 20)

                // Location name
                Text(location.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)

                Spacer()

                // Location type badge
                Text(location.type.capitalized)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isSelected ? color : .white.opacity(0.4))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(.ultraThinMaterial))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.ultraThinMaterial))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(isSelected ? color.opacity(0.3) : .white.opacity(0.1), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(location.name), \(location.type)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Reprint Content

extension QRCodeScanSheet {

    @ViewBuilder
    var reprintContent: some View {
        summaryCard

        ModalActionButton("Print Label", icon: "printer.fill", isLoading: isPrinting) {
            reprintLabel()
        }
    }
}

// MARK: - Split Content

extension QRCodeScanSheet {

    @ViewBuilder
    var splitContent: some View {
        let purpleColor = Color(red: 168/255, green: 85/255, blue: 247/255)

        // Current package info
        summaryCard

        // Split visualization
        ModalSection {
            VStack(spacing: 16) {
                // Current tier at top
                HStack(spacing: 0) {
                    VStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [purpleColor, purpleColor.opacity(0.8)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 44, height: 44)
                                .shadow(color: purpleColor.opacity(0.4), radius: 6, y: 2)
                            Image(systemName: "shippingbox.fill")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(.white)
                        }
                        Text(qrCode.tierLabel ?? "Package")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }

                // Arrow down
                Image(systemName: "arrow.down")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(purpleColor)

                // Split options
                if splitOptions.isEmpty {
                    Text("No split options available")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 8) {
                        ForEach(splitOptions) { option in
                            splitOptionRow(option, color: purpleColor)
                        }
                    }
                }
            }
            .padding(.vertical, 8)
        }

        // Split button
        if let selected = selectedSplitOption {
            Button {
                Haptics.medium()
                performSplit()
            } label: {
                HStack(spacing: 10) {
                    if isPrinting {
                        ProgressView()
                            .tint(.black)
                            .scaleEffect(0.9)
                    } else {
                        Image(systemName: "square.split.2x2.fill")
                            .font(.system(size: 17, weight: .semibold))
                        Text("Split into \(selected.displayLabel)")
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .contentShape(RoundedRectangle(cornerRadius: 16))
                .background(Color.white.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isPrinting)
        } else {
            // Disabled state
            HStack(spacing: 10) {
                Image(systemName: "square.split.2x2.fill")
                    .font(.system(size: 17, weight: .semibold))
                Text("Select a split option")
                    .font(.system(size: 17, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(0.3))
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.ultraThinMaterial))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.1), lineWidth: 0.5))
        }
    }

    @ViewBuilder
    func splitOptionRow(_ option: SplitOption, color: Color) -> some View {
        let isSelected = selectedSplitOption?.id == option.id

        Button {
            Haptics.light()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedSplitOption = option
            }
        } label: {
            HStack(spacing: 12) {
                // Selection indicator
                ZStack {
                    Circle()
                        .stroke(isSelected ? color : .white.opacity(0.2), lineWidth: 2)
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle()
                            .fill(color)
                            .frame(width: 14, height: 14)
                    }
                }

                // Count badge
                Text("\(option.count)x")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(isSelected ? color : .white.opacity(0.7))
                    .frame(width: 36)

                // Tier label
                Text(option.tier.label)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)

                Spacer()

                // Small icons showing the split
                HStack(spacing: 3) {
                    ForEach(0..<min(option.count, 6), id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(isSelected ? color.opacity(0.6) : .white.opacity(0.15))
                            .frame(width: 12, height: 12)
                    }
                    if option.count > 6 {
                        Text("+\(option.count - 6)")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.ultraThinMaterial))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(isSelected ? color.opacity(0.3) : .white.opacity(0.1), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(option.count) times \(option.tier.label)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Success Content

extension QRCodeScanSheet {

    @ViewBuilder
    var successContent: some View {
        VStack(spacing: 20) {
            // Animated checkmark circle
            ZStack {
                // Outer glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(red: 34/255, green: 197/255, blue: 94/255).opacity(0.3), .clear],
                            center: .center,
                            startRadius: 20,
                            endRadius: 60
                        )
                    )
                    .frame(width: 100, height: 100)

                // Background circle
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 34/255, green: 197/255, blue: 94/255),
                                Color(red: 22/255, green: 163/255, blue: 74/255)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 64, height: 64)
                    .shadow(color: Color(red: 34/255, green: 197/255, blue: 94/255).opacity(0.4), radius: 12, y: 4)

                // Animated checkmark path
                AnimatedCheckmark(trimEnd: checkmarkTrimEnd)
                    .stroke(.white, style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                    .frame(width: 28, height: 28)
            }
            .scaleEffect(successScale)
            .opacity(successOpacity)
            .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text("Success")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text(successMessage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
            .opacity(successOpacity)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)

        // Done button
        Button {
            Haptics.medium()
            dismiss(); onDismiss()
        } label: {
            Text("Done")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .contentShape(RoundedRectangle(cornerRadius: 14))
                .background(Color.white.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sale Detail Helpers

extension QRCodeScanSheet {

    func detailRow(_ label: String, value: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 20)
                .accessibilityHidden(true)

            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.5))

            Spacer()

            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value)")
    }

    func formatSoldDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
