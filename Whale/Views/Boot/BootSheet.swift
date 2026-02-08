//
//  BootSheet.swift
//  Whale
//
//  Simplified boot flow: splash → login → Stage Manager (launcher)
//  No more location/register/cash selection here - that's per-window now.
//

import SwiftUI
import Supabase
import os.log

// MARK: - Boot Step

enum BootStep: Equatable {
    case splash         // Loading/checking auth
    case login          // Email/password OR Face ID
    case authenticated  // Show Stage Manager
}

// MARK: - Boot Modal

struct BootSheet: View {
    @EnvironmentObject private var session: SessionObserver
    @EnvironmentObject private var themeManager: ThemeManager

    // Animation states
    @State private var contentOpacity: CGFloat = 0
    @State private var showContent = false

    // Flow state
    @State private var currentStep: BootStep = .splash

    // Auth state
    @State private var isAuthenticating = false
    @State private var email = ""
    @State private var password = ""

    private var biometricType: BiometricType {
        BiometricAuthService.availableBiometricType
    }

    var body: some View {
        ZStack {
            ThemeWallpaper()

            switch currentStep {
            case .splash:
                // Simple native loading screen
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(Design.Colors.Text.disabled)
                    .scaleEffect(1.2)

            case .login:
                modalView

            case .authenticated:
                // Show POS directly — .id() forces recreation when theme changes
                // so Design.Colors.* static properties re-evaluate with new values
                POSMainView()
                    .id(themeManager.themeVersion)
            }
        }
        .onAppear {
            startBootSequence()
        }
        .onChange(of: session.hasCheckedSession) { _, hasChecked in
            if hasChecked {
                onSessionReady()
            }
        }
        .onChange(of: session.isAuthenticated) { _, isAuthenticated in
            if !isAuthenticated {
                // User signed out - go back to login
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    currentStep = .login
                    showContent = true
                }
                withAnimation(.easeOut(duration: 0.3)) {
                    contentOpacity = 1
                }
            }
        }
    }

    // MARK: - Modal View

    private var modalView: some View {
        VStack {
            Spacer()

            VStack(spacing: 0) {
                // Store logo
                logoView
                    .padding(.top, 32)
                    .padding(.bottom, 20)

                // Content based on step
                if showContent {
                    stepContent
                        .opacity(contentOpacity)
                }
            }
            .frame(maxWidth: 400)
            .background(modalBackground)
            .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
            .shadow(color: .black.opacity(0.8), radius: 60, y: 25)
            .padding(.horizontal, 40)

            Spacer()
        }
    }

    // MARK: - Logo (Store logo after auth, nothing during splash)

    private var logoView: some View {
        Group {
            if currentStep != .splash {
                // Store logo after authentication
                StoreLogo(
                    url: session.store?.fullLogoUrl,
                    size: 88,
                    storeName: session.store?.businessName
                )
                .shadow(color: .white.opacity(0.08), radius: 20)
            }
        }
    }

    // MARK: - Step Content

    @ViewBuilder
    private var stepContent: some View {
        switch currentStep {
        case .splash, .authenticated:
            EmptyView()

        case .login:
            BootLoginContent(
                isAuthenticating: $isAuthenticating,
                email: $email,
                password: $password,
                onSignIn: { handleSignIn() },
                onFaceID: { handleFaceIDLogin() }
            )
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .move(edge: .bottom)),
                removal: .opacity
            ))
        }
    }

    // MARK: - Modal Background (Dark)

    private var modalBackground: some View {
        ZStack {
            // Dark base
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(Color(white: 0.08))

            // Subtle gradient overlay
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.06),
                            Color.white.opacity(0.02),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Border
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.15),
                            Color.white.opacity(0.05),
                            Color.white.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
    }

    // MARK: - Boot Sequence

    private func startBootSequence() {
        // NOTE: session.start() is called from RootView.task AFTER first frame
        // onSessionReady() is triggered by .onChange(of: hasCheckedSession)
    }

    /// Called when session has finished checking - triggered by onChange
    private func onSessionReady() {
        // Fetch store in background
        if session.isAuthenticated {
            Task {
                await session.fetchStore()
                await session.fetchLocations()
            }
        }

        // Determine initial step
        if session.isAuthenticated {
            // Already logged in - go directly to Stage Manager
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                currentStep = .authenticated
            }
        } else {
            // Need to log in - show login modal
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                showContent = true
                currentStep = .login
            }
            withAnimation(.easeOut(duration: 0.3).delay(0.1)) {
                contentOpacity = 1
            }
        }
    }

    private func advanceToStep(_ step: BootStep) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            currentStep = step
        }
    }

    // MARK: - Authentication

    private func handleSignIn() {
        guard !email.isEmpty && !password.isEmpty else { return }
        isAuthenticating = true
        Haptics.medium()

        Task {
            let success = await session.signIn(email: email, password: password)

            await MainActor.run {
                isAuthenticating = false

                if success {
                    Haptics.success()
                    // Enable biometric for future logins
                    if biometricType != .none {
                        session.enableBiometric()
                    }
                    // Fetch store data then go to Stage Manager
                    Task {
                        await session.fetchStore()
                        await session.fetchLocations()
                        await MainActor.run {
                            advanceToStep(.authenticated)
                        }
                    }
                } else {
                    Haptics.error()
                }
            }
        }
    }

    private func handleFaceIDLogin() {
        guard !isAuthenticating else { return }

        // Only allow Face ID login if biometric is enabled (user logged in before)
        guard BiometricAuthService.isBiometricEnabled else { return }

        isAuthenticating = true
        Haptics.light()

        Task {
            let success = await BiometricAuthService.authenticate(
                reason: "Sign in"
            )

            await MainActor.run {
                isAuthenticating = false

                if success {
                    // Restore the session
                    Task {
                        let restored = await session.unlockWithBiometric()
                        if restored {
                            Haptics.success()
                            await session.fetchStore()
                            await session.fetchLocations()
                            await MainActor.run {
                                advanceToStep(.authenticated)
                            }
                        } else {
                            Haptics.error()
                        }
                    }
                } else {
                    Haptics.warning()
                }
            }
        }
    }

    // MARK: - Sign Out (from Stage Manager)

    func handleSignOut() {
        Task {
            await session.signOut()
            await MainActor.run {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                    currentStep = .login
                    email = ""
                    password = ""
                    showContent = true
                    contentOpacity = 1
                }
            }
        }
    }
}

// Note: LoginContent moved to BootLoginContent.swift
// Note: LocationContent, RegisterContent moved to BootLoginContent.swift
// Note: StartShiftContent, LaunchingContent, OptionRow moved to BootLaunchContent.swift
// Note: BootEndSessionSheet and BootSafeDropSheet moved to BootSessionSheets.swift

#Preview {
    BootSheet()
        .environmentObject(SessionObserver.shared)
}
