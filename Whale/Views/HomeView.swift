//
//  HomeView.swift
//  Whale
//
//  Main app view after authentication and selection complete.
//  Entry point to POS - shows "Open Cash Drawer" to start.
//

import SwiftUI
import os.log
import Supabase

struct HomeView: View {
    @EnvironmentObject private var session: SessionObserver

    // POS State
    @State private var showCashDrawerModal = false

    var body: some View {
        ZStack {
            Design.Colors.backgroundPrimary.ignoresSafeArea()

            if session.activePOSSession != nil {
                // Active POS session - show main POS interface
                // NOTE: In launcher architecture, this path is deprecated
                // BootModal goes directly to StageManagerRoot
                POSMainView()
                    .transition(.opacity)
            } else {
                // No active session - show start screen
                startSessionView
                    .transition(.opacity)
            }

            // Cash drawer modal overlay
            if showCashDrawerModal {
                OpenCashDrawerModal(isPresented: $showCashDrawerModal) { amount, notes in
                    startSession(openingCash: amount, notes: notes)
                }
                .transition(.opacity)
            }
        }
        .preferredColorScheme(.dark)
        .animation(Design.Animation.modalSpring, value: session.activePOSSession != nil)
        .animation(Design.Animation.modalSpring, value: showCashDrawerModal)
    }

    // MARK: - Start Session View

    private var startSessionView: some View {
        VStack(spacing: Design.Spacing.xl) {
            Spacer()

            // Welcome section
            VStack(spacing: Design.Spacing.md) {
                StoreLogo(
                    url: session.store?.fullLogoUrl,
                    size: 100,
                    storeName: session.store?.businessName
                )

                if let storeName = session.store?.businessName {
                    Text(storeName)
                        .font(Design.Typography.title2)
                        .foregroundStyle(Design.Colors.Text.primary)
                }

                // Location & Register info
                VStack(spacing: Design.Spacing.xs) {
                    if let location = session.selectedLocation {
                        HStack(spacing: Design.Spacing.xs) {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundStyle(Design.Colors.Text.subtle)
                            Text(location.name)
                                .font(Design.Typography.subhead)
                                .foregroundStyle(Design.Colors.Text.secondary)
                        }
                        .glassPill()
                    }

                    if let register = session.selectedRegister {
                        HStack(spacing: Design.Spacing.xs) {
                            Image(systemName: "desktopcomputer")
                                .foregroundStyle(Design.Colors.Text.subtle)
                            Text(register.displayName)
                                .font(Design.Typography.subhead)
                                .foregroundStyle(Design.Colors.Text.secondary)
                        }
                        .glassPill()
                    }
                }

                if let email = session.userEmail {
                    Text(email)
                        .font(Design.Typography.caption1)
                        .foregroundStyle(Design.Colors.Text.ghost)
                        .padding(.top, Design.Spacing.xs)
                }
            }

            Spacer()

            // Open Cash Drawer button (main CTA)
            openCashDrawerButton
                .padding(.horizontal, Design.Spacing.xl)

            // Secondary actions
            secondaryActions
                .padding(.horizontal, Design.Spacing.xl)
                .padding(.bottom, Design.Spacing.xxl)
        }
        .task {
            // Fetch store details when home screen appears
            await session.fetchStore()
        }
    }

    // MARK: - Open Cash Drawer Button

    private var openCashDrawerButton: some View {
        Button {
            Haptics.medium()
            showCashDrawerModal = true
        } label: {
            VStack(spacing: Design.Spacing.xs) {
                Image(systemName: "dollarsign.square.fill")
                    .font(.system(size: 32))

                Text("OPEN CASH DRAWER")
                    .font(Design.Typography.buttonLarge)
                    .tracking(-0.2)

                Text("Count cash to start your shift")
                    .font(Design.Typography.caption1)
                    .foregroundStyle(Design.Colors.Text.tertiary)
            }
            .foregroundStyle(Design.Colors.Text.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Design.Spacing.xl)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.xxl, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.xxl, style: .continuous)
                    .fill(Design.Colors.Glass.thick)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Design.Radius.xxl, style: .continuous)
                    .stroke(Design.Colors.Border.emphasis, lineWidth: 1)
            )
        }
        .buttonStyle(LiquidPressStyle())
    }

    // MARK: - Secondary Actions

    private var secondaryActions: some View {
        VStack(spacing: Design.Spacing.sm) {
            // Change register
            Button {
                Haptics.light()
                Task {
                    await session.clearRegisterSelection()
                }
            } label: {
                HStack {
                    Image(systemName: "desktopcomputer")
                    Text("Change Register")
                }
                .font(Design.Typography.subhead)
                .foregroundStyle(Design.Colors.Text.tertiary)
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

            HStack(spacing: Design.Spacing.sm) {
                // Change location
                Button {
                    Haptics.light()
                    Task {
                        await session.clearLocationSelection()
                    }
                } label: {
                    HStack {
                        Image(systemName: "mappin.circle")
                        Text("Location")
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

                // Sign out
                Button {
                    Haptics.light()
                    Task {
                        await session.signOut()
                    }
                } label: {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                        Text("Sign Out")
                    }
                    .font(Design.Typography.subhead)
                    .foregroundStyle(Design.Colors.Text.ghost)
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
    }

    // MARK: - Session Management

    private func startSession(openingCash: Decimal, notes: String) {
        guard let locationId = session.selectedLocation?.id,
              let registerId = session.selectedRegister?.id else {
            Log.session.error("Cannot start session: missing location or register")
            return
        }

        let newSession = POSSession.create(
            locationId: locationId,
            registerId: registerId,
            userId: session.publicUserId,  // Use public.users.id for FK constraint
            openingCash: openingCash,
            notes: notes.isEmpty ? nil : notes
        )

        Log.session.info("Starting POS session: \(newSession.id), opening cash: \(openingCash)")

        // Save session to database and persist locally via SessionObserver
        Task {
            do {
                try await session.startPOSSession(newSession)
                Haptics.success()
            } catch {
                Log.session.error("Failed to start POS session: \(error.localizedDescription)")
                // Show error to user?
            }
        }
    }

    private func endSession() {
        Log.session.info("Ending POS session")

        Task {
            await session.endPOSSession()
        }
    }
}

#Preview {
    HomeView()
        .environmentObject(SessionObserver.shared)
}
