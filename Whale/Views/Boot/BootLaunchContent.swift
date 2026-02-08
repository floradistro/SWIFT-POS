//
//  BootLaunchContent.swift
//  Whale
//
//  Start shift, launching state, and option row
//  components for BootSheet.
//

import SwiftUI

// MARK: - Start Shift Content

struct BootStartShiftContent: View {
    @EnvironmentObject private var session: SessionObserver
    let onStartShift: (Decimal, String) -> Void
    let onBack: () -> Void

    @State private var openingAmount: String = ""
    @State private var notes: String = ""

    private var amountValue: Decimal {
        Decimal(string: openingAmount) ?? 0
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text("Start Shift")
                    .font(Design.Typography.title2).fontWeight(.bold)
                    .foregroundStyle(Design.Colors.Text.primary)

                Text("Opening Cash Drawer")
                    .font(Design.Typography.footnote)
                    .foregroundStyle(Design.Colors.Text.subtle)

                HStack(spacing: 6) {
                    if let location = session.selectedLocation {
                        Text(location.name)
                            .font(Design.Typography.caption2).fontWeight(.medium)
                    }

                    Text("•")

                    if let register = session.selectedRegister {
                        Text(register.displayName)
                            .font(Design.Typography.caption2).fontWeight(.medium)
                    }
                }
                .foregroundStyle(Design.Colors.Text.placeholder)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Design.Colors.Border.subtle))
            }
            .padding(.bottom, 20)

            VStack(spacing: 14) {
                HStack {
                    Text("$")
                        .font(Design.Typography.title1).fontWeight(.bold)
                        .foregroundStyle(Design.Colors.Text.subtle)

                    TextField("0", text: $openingAmount)
                        .font(Design.Typography.title1).fontWeight(.bold)
                        .foregroundStyle(Design.Colors.Text.primary)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.leading)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Design.Colors.Border.subtle)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Design.Colors.Border.regular, lineWidth: 1)
                )

                HStack(spacing: 8) {
                    ForEach(["100", "200", "300", "500"], id: \.self) { amount in
                        Button {
                            Haptics.light()
                            openingAmount = amount
                        } label: {
                            Text("$\(amount)")
                                .font(Design.Typography.subhead).fontWeight(.semibold)
                                .foregroundStyle(openingAmount == amount ? Design.Colors.Text.primary : Design.Colors.Text.disabled)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .contentShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(ScaleButtonStyle())
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
                    }
                }
            }
            .padding(.horizontal, 24)

            Button {
                Haptics.medium()
                onStartShift(amountValue, notes)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "play.fill")
                        .font(Design.Typography.footnote)
                    Text("Start Shift")
                        .font(Design.Typography.callout).fontWeight(.semibold)
                }
                .foregroundStyle(Design.Colors.Text.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Design.Colors.Glass.ultraThick)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(ScaleButtonStyle())
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
            .padding(.horizontal, 24)
            .padding(.top, 20)

            HStack(spacing: 24) {
                Button {
                    Haptics.light()
                    Task {
                        await session.clearRegisterSelection()
                        onBack()
                    }
                } label: {
                    Text("Change")
                        .font(Design.Typography.caption1).fontWeight(.medium)
                        .foregroundStyle(Design.Colors.Text.placeholder)
                }

                Button {
                    Haptics.light()
                    Task { await session.signOut() }
                } label: {
                    Text("Sign Out")
                        .font(Design.Typography.caption1).fontWeight(.medium)
                        .foregroundStyle(Design.Colors.Text.placeholder)
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
    }
}

// MARK: - Launching Content

struct BootLaunchingContent: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(Design.Colors.Text.disabled)
                .scaleEffect(1.2)

            Text("Starting...")
                .font(Design.Typography.subhead).fontWeight(.medium)
                .foregroundStyle(Design.Colors.Text.disabled)
        }
        .padding(.vertical, 50)
    }
}

// MARK: - Option Row

struct BootOptionRow: View {
    let icon: String
    let title: String
    let subtitle: String?
    var badges: [String] = []
    let delay: Double
    let isAnimated: Bool
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(Design.Typography.body).fontWeight(.medium)
                    .foregroundStyle(Design.Colors.Text.disabled)
                    .frame(width: 42, height: 42)
                    .background(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(Design.Colors.Glass.regular)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(Design.Typography.subhead).fontWeight(.semibold)
                        .foregroundStyle(Design.Colors.Text.primary)
                        .lineLimit(1)

                    if let subtitle = subtitle {
                        HStack(spacing: 6) {
                            Text(subtitle)
                                .font(Design.Typography.caption2)
                                .foregroundStyle(Design.Colors.Text.subtle)
                                .lineLimit(1)

                            ForEach(badges, id: \.self) { badge in
                                Text(badge)
                                    .font(Design.Typography.caption2).fontWeight(.medium)
                                    .foregroundStyle(Design.Colors.Text.disabled)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Design.Colors.Glass.thick))
                            }
                        }
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(Design.Typography.caption2).fontWeight(.semibold)
                    .foregroundStyle(Design.Colors.Text.ghost)
            }
            .padding(11)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(isPressed ? Design.Colors.Glass.thick : Design.Colors.Glass.thin)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(Design.Colors.Border.regular, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .opacity(isAnimated ? 1 : 0)
        .offset(y: isAnimated ? 0 : 12)
        .animation(.spring(response: 0.35, dampingFraction: 0.75).delay(delay), value: isAnimated)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !isPressed { isPressed = true } }
                .onEnded { _ in isPressed = false }
        )
    }
}
