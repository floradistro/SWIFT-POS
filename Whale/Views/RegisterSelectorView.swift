//
//  RegisterSelectorView.swift
//  Whale
//
//  Register selection - liquid glass iOS design.
//  Staggered animations, haptics, clean hierarchy.
//

import SwiftUI

struct RegisterSelectorView: View {
    @EnvironmentObject private var session: SessionObserver
    @State private var appearAnimation = false

    var body: some View {
        ZStack {
            // Pure black background
            Design.Colors.backgroundPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                header
                    .padding(.top, Design.Spacing.xxl)
                    .padding(.bottom, Design.Spacing.xl)

                // Register grid
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: Design.Spacing.sm) {
                        if session.isLoading {
                            loadingState
                        } else if let error = session.errorMessage {
                            errorState(error)
                        } else if session.registers.isEmpty {
                            emptyState
                        } else {
                            ForEach(Array(session.registers.enumerated()), id: \.element.id) { index, register in
                                RegisterRow(register: register) {
                                    Haptics.medium()
                                    Task {
                                        await session.selectRegister(register)
                                    }
                                }
                                .opacity(appearAnimation ? 1 : 0)
                                .offset(y: appearAnimation ? 0 : 20)
                                .animation(
                                    Design.Animation.springSnappy.delay(Double(index) * 0.05),
                                    value: appearAnimation
                                )
                            }
                        }
                    }
                    .padding(.horizontal, Design.Spacing.lg)
                    .padding(.bottom, Design.Spacing.huge)
                }

                // Back button
                backButton
                    .padding(.horizontal, Design.Spacing.lg)
                    .padding(.bottom, Design.Spacing.xxl)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await session.fetchRegisters()
            withAnimation {
                appearAnimation = true
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: Design.Spacing.md) {
            // Location icon
            ZStack {
                Circle()
                    .fill(Design.Colors.Glass.regular)
                    .frame(width: 72, height: 72)

                Image(systemName: "desktopcomputer")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(Design.Colors.Text.tertiary)
            }
            .opacity(appearAnimation ? 1 : 0)
            .scaleEffect(appearAnimation ? 1 : 0.8)
            .animation(Design.Animation.springBouncy, value: appearAnimation)

            // Title
            Text("Select Register")
                .font(Design.Typography.largeTitle)
                .foregroundStyle(Design.Colors.Text.primary)
                .opacity(appearAnimation ? 1 : 0)
                .animation(Design.Animation.springSnappy.delay(0.1), value: appearAnimation)

            // Location name pill
            if let location = session.selectedLocation {
                HStack(spacing: Design.Spacing.xs) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 12))
                    Text(location.name)
                }
                .font(Design.Typography.caption1)
                .foregroundStyle(Design.Colors.Text.subtle)
                .padding(.horizontal, Design.Spacing.sm)
                .padding(.vertical, Design.Spacing.xxs)
                .background(
                    Capsule()
                        .fill(Design.Colors.Glass.thin)
                )
                .overlay(
                    Capsule()
                        .stroke(Design.Colors.Border.subtle, lineWidth: 1)
                )
                .opacity(appearAnimation ? 1 : 0)
                .animation(Design.Animation.springSnappy.delay(0.15), value: appearAnimation)
            }
        }
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: Design.Spacing.lg) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: Design.Colors.Text.subtle))
                .scaleEffect(1.2)

            Text("Loading registers...")
                .font(Design.Typography.subhead)
                .foregroundStyle(Design.Colors.Text.subtle)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Design.Spacing.huge)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: Design.Spacing.lg) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(Design.Colors.Semantic.warning)

            Text(message)
                .font(Design.Typography.subhead)
                .foregroundStyle(Design.Colors.Text.secondary)
                .multilineTextAlignment(.center)

            Button {
                Haptics.light()
                Task { await session.fetchRegisters() }
            } label: {
                Text("Try Again")
                    .font(Design.Typography.button)
                    .foregroundStyle(Design.Colors.Text.primary)
                    .padding(.horizontal, Design.Spacing.xl)
                    .padding(.vertical, Design.Spacing.sm)
                    .background(
                        Capsule()
                            .fill(Design.Colors.Glass.regular)
                    )
                    .overlay(
                        Capsule()
                            .stroke(Design.Colors.Border.regular, lineWidth: 1)
                    )
            }
            .buttonStyle(LiquidPressStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Design.Spacing.huge)
    }

    private var emptyState: some View {
        VStack(spacing: Design.Spacing.lg) {
            Image(systemName: "desktopcomputer.trianglebadge.exclamationmark")
                .font(.system(size: 40))
                .foregroundStyle(Design.Colors.Text.ghost)

            Text("No registers found")
                .font(Design.Typography.headline)
                .foregroundStyle(Design.Colors.Text.secondary)

            Text("Add registers in the admin panel")
                .font(Design.Typography.subhead)
                .foregroundStyle(Design.Colors.Text.subtle)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Design.Spacing.huge)
    }

    // MARK: - Back Button

    private var backButton: some View {
        Button {
            Haptics.light()
            Task { await session.clearLocationSelection() }
        } label: {
            HStack(spacing: Design.Spacing.xs) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                Text("Change Location")
            }
            .font(Design.Typography.subhead)
            .foregroundStyle(Design.Colors.Text.subtle)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Design.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.lg, style: .continuous)
                    .fill(Design.Colors.Glass.ultraThin)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Design.Radius.lg, style: .continuous)
                    .stroke(Design.Colors.Border.subtle, lineWidth: 1)
            )
        }
        .buttonStyle(LiquidPressStyle())
    }
}

// MARK: - Register Row

struct RegisterRow: View {
    let register: Register
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Design.Spacing.md) {
                // Device icon
                ZStack {
                    RoundedRectangle(cornerRadius: Design.Radius.md, style: .continuous)
                        .fill(Design.Colors.Glass.regular)
                        .frame(width: 48, height: 48)

                    Image(systemName: iconForDevice(register.deviceName))
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Design.Colors.Text.tertiary)
                }

                // Info
                VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
                    Text(register.displayName)
                        .font(Design.Typography.headline)
                        .foregroundStyle(Design.Colors.Text.primary)
                        .lineLimit(1)

                    HStack(spacing: Design.Spacing.xs) {
                        // Register number
                        Text("#\(register.registerNumber)")
                            .font(Design.Typography.caption1)
                            .foregroundStyle(Design.Colors.Text.ghost)

                        // Capabilities
                        if register.allowCash {
                            capabilityBadge("Cash")
                        }
                        if register.allowCard {
                            capabilityBadge("Card")
                        }
                    }
                }

                Spacer()

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Design.Colors.Text.ghost)
            }
            .padding(Design.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.lg, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.lg, style: .continuous)
                    .fill(Design.Colors.Glass.thick)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Design.Radius.lg, style: .continuous)
                    .stroke(Design.Colors.Border.subtle, lineWidth: 1)
            )
        }
        .buttonStyle(LiquidPressStyle())
    }

    private func capabilityBadge(_ text: String) -> some View {
        Text(text)
            .font(Design.Typography.caption2)
            .foregroundStyle(Design.Colors.Text.ghost)
            .padding(.horizontal, Design.Spacing.xs)
            .padding(.vertical, Design.Spacing.xxxs)
            .background(
                Capsule()
                    .fill(Design.Colors.Glass.thin)
            )
    }

    private func iconForDevice(_ deviceName: String?) -> String {
        guard let name = deviceName?.lowercased() else {
            return "desktopcomputer"
        }

        if name.contains("ipad") {
            return "ipad.landscape"
        } else if name.contains("iphone") {
            return "iphone"
        } else if name.contains("mac") {
            return "macbook"
        } else {
            return "desktopcomputer"
        }
    }
}

#Preview {
    RegisterSelectorView()
        .environmentObject(SessionObserver.shared)
}
