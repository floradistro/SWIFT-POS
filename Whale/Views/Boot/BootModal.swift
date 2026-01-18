//
//  BootModal.swift
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

struct BootModal: View {
    @EnvironmentObject private var session: SessionObserver

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
            Color.black.ignoresSafeArea()

            switch currentStep {
            case .splash:
                // Simple native loading screen
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white.opacity(0.6))
                    .scaleEffect(1.2)

            case .login:
                modalView

            case .authenticated:
                // Show Stage Manager - user launches POS windows from here
                StageManagerRoot {
                    // This content is used for POS windows
                    // POSMainView no longer needs posSession - it uses windowSession
                    POSMainView()
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            startBootSequence()
        }
        .onChange(of: session.hasCheckedSession) { _, hasChecked in
            if hasChecked {
                onSessionReady()
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
            LoginContent(
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
        // Logo and modal are already visible (set in @State initial values)
        // This ensures the splash appears on the VERY FIRST FRAME
        // No animation needed here - just wait for session to be ready

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

// MARK: - Login Content

private struct LoginContent: View {
    @EnvironmentObject private var session: SessionObserver
    @Binding var isAuthenticating: Bool
    @Binding var email: String
    @Binding var password: String
    let onSignIn: () -> Void
    let onFaceID: () -> Void

    @FocusState private var focusedField: Field?
    @State private var appearAnimation = false

    private enum Field { case email, password }

    private var biometricType: BiometricType {
        BiometricAuthService.availableBiometricType
    }

    private var canUseFaceID: Bool {
        biometricType != .none && BiometricAuthService.isBiometricEnabled
    }

    private var isFormValid: Bool {
        !email.isEmpty && !password.isEmpty && email.contains("@") && password.count >= 6
    }

    var body: some View {
        VStack(spacing: 0) {
            // Form
            VStack(spacing: 14) {
                // Email
                HStack(spacing: 12) {
                    Image(systemName: "envelope.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(width: 20)

                    TextField("Email", text: $email)
                        .font(.system(size: 15))
                        .foregroundStyle(.white)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .email)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.white.opacity(focusedField == .email ? 0.3 : 0.1), lineWidth: 1)
                )
                .opacity(appearAnimation ? 1 : 0)
                .offset(y: appearAnimation ? 0 : 10)

                // Password
                HStack(spacing: 12) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(width: 20)

                    SecureField("Password", text: $password)
                        .font(.system(size: 15))
                        .foregroundStyle(.white)
                        .textContentType(.password)
                        .focused($focusedField, equals: .password)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.white.opacity(focusedField == .password ? 0.3 : 0.1), lineWidth: 1)
                )
                .opacity(appearAnimation ? 1 : 0)
                .offset(y: appearAnimation ? 0 : 10)
                .animation(.spring(response: 0.4, dampingFraction: 0.8).delay(0.05), value: appearAnimation)

                // Error
                if let error = session.errorMessage {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(Design.Colors.Semantic.error)
                        .padding(.top, 4)
                }

                // Sign In Button (with Face ID option)
                HStack(spacing: 10) {
                    // Main sign in button - primary CTA with glass + white fill
                    Button {
                        focusedField = nil
                        onSignIn()
                    } label: {
                        HStack {
                            if isAuthenticating {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                    .scaleEffect(0.9)
                            } else {
                                Text("Sign In")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                        }
                        .foregroundStyle(isFormValid ? .black : .white.opacity(0.4))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(isFormValid ? Color.white : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
                    .disabled(!isFormValid || isAuthenticating)

                    // Face ID button (only if available and previously enabled)
                    if canUseFaceID {
                        Button {
                            focusedField = nil
                            onFaceID()
                        } label: {
                            Image(systemName: biometricType.iconName)
                                .font(.system(size: 22, weight: .light))
                                .foregroundStyle(.white)
                                .frame(width: 50, height: 50)
                                .contentShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(ScaleButtonStyle())
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
                        .disabled(isAuthenticating)
                    }
                }
                .padding(.top, 8)
                .opacity(appearAnimation ? 1 : 0)
                .offset(y: appearAnimation ? 0 : 10)
                .animation(.spring(response: 0.4, dampingFraction: 0.8).delay(0.1), value: appearAnimation)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                appearAnimation = true
            }
        }
    }
}

// MARK: - Location Content

private struct LocationContent: View {
    @EnvironmentObject private var session: SessionObserver
    let onSelected: (Location) -> Void

    @State private var appearAnimation = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 6) {
                Text("Select Location")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)

                if let email = session.userEmail {
                    Text(email)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
            .padding(.bottom, 20)

            // Locations - elegant cards with store logo
            VStack(spacing: 10) {
                if session.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white.opacity(0.5)))
                        .padding(.vertical, 40)
                } else {
                    ForEach(Array(session.locations.enumerated()), id: \.element.id) { index, location in
                        LocationCard(
                            location: location,
                            storeLogoUrl: session.store?.fullLogoUrl,
                            storeName: session.store?.businessName,
                            delay: Double(index) * 0.06,
                            isAnimated: appearAnimation
                        ) {
                            Haptics.medium()
                            Task {
                                await session.selectLocation(location)
                                onSelected(location)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)

            // Sign out
            Button {
                Haptics.light()
                Task { await session.signOut() }
            } label: {
                Text("Sign Out")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
        .task {
            await session.fetchStore()
            await session.fetchLocations()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                appearAnimation = true
            }
        }
    }
}

// MARK: - Location Card (Premium design with store logo)

private struct LocationCard: View {
    let location: Location
    let storeLogoUrl: URL?
    let storeName: String?
    let delay: Double
    let isAnimated: Bool
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                // Store logo
                StoreLogo(
                    url: storeLogoUrl,
                    size: 44,
                    storeName: storeName
                )

                // Location info
                VStack(alignment: .leading, spacing: 3) {
                    Text(location.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if let address = location.displayAddress, !address.isEmpty {
                        Text(address)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.45))
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.25))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.white.opacity(isPressed ? 0.12 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .opacity(isAnimated ? 1 : 0)
        .offset(y: isAnimated ? 0 : 12)
        .animation(.spring(response: 0.4, dampingFraction: 0.75).delay(delay), value: isAnimated)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !isPressed { isPressed = true } }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - Register Content

private struct RegisterContent: View {
    @EnvironmentObject private var session: SessionObserver
    let onSelected: (Register) -> Void
    let onBack: () -> Void

    @State private var appearAnimation = false

    var body: some View {
        VStack(spacing: 0) {
            // Header with back button
            HStack {
                Button {
                    Haptics.light()
                    Task {
                        await session.clearLocationSelection()
                        onBack()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Back")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(.white.opacity(0.5))
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            // Title with location badge
            VStack(spacing: 8) {
                Text("Select Register")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)

                if let location = session.selectedLocation {
                    Text(location.name)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(.white.opacity(0.08)))
                }
            }
            .padding(.bottom, 20)

            // Registers - elegant cards with store logo
            VStack(spacing: 10) {
                if session.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white.opacity(0.5)))
                        .padding(.vertical, 40)
                } else {
                    ForEach(Array(session.registers.enumerated()), id: \.element.id) { index, register in
                        RegisterCard(
                            register: register,
                            storeLogoUrl: session.store?.fullLogoUrl,
                            storeName: session.store?.businessName,
                            delay: Double(index) * 0.06,
                            isAnimated: appearAnimation
                        ) {
                            Haptics.medium()
                            Task {
                                await session.selectRegister(register)
                                onSelected(register)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .task {
            await session.fetchRegisters()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                appearAnimation = true
            }
        }
    }
}

// MARK: - Register Card (Premium design with store logo)

private struct RegisterCard: View {
    let register: Register
    let storeLogoUrl: URL?
    let storeName: String?
    let delay: Double
    let isAnimated: Bool
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                // Store logo
                StoreLogo(
                    url: storeLogoUrl,
                    size: 44,
                    storeName: storeName
                )

                // Register info
                VStack(alignment: .leading, spacing: 3) {
                    Text(register.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text("Register #\(register.registerNumber)")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.45))
                }

                Spacer()

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.25))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.white.opacity(isPressed ? 0.12 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .opacity(isAnimated ? 1 : 0)
        .offset(y: isAnimated ? 0 : 12)
        .animation(.spring(response: 0.4, dampingFraction: 0.75).delay(delay), value: isAnimated)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !isPressed { isPressed = true } }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - Start Shift Content

private struct StartShiftContent: View {
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
            // Header (no icon - store logo is already at top)
            VStack(spacing: 8) {
                Text("Start Shift")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)

                Text("Opening Cash Drawer")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.4))

                // Location & Register pill
                HStack(spacing: 6) {
                    if let location = session.selectedLocation {
                        Text(location.name)
                            .font(.system(size: 11, weight: .medium))
                    }

                    Text("•")

                    if let register = session.selectedRegister {
                        Text(register.displayName)
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .foregroundStyle(.white.opacity(0.35))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(.white.opacity(0.06)))
            }
            .padding(.bottom, 20)

            // Amount input
            VStack(spacing: 14) {
                HStack {
                    Text("$")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white.opacity(0.4))

                    TextField("0", text: $openingAmount)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.leading)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(.white.opacity(0.1), lineWidth: 1)
                )

                // Quick amounts
                HStack(spacing: 8) {
                    ForEach(["100", "200", "300", "500"], id: \.self) { amount in
                        Button {
                            Haptics.light()
                            openingAmount = amount
                        } label: {
                            Text("$\(amount)")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(openingAmount == amount ? .white : .white.opacity(0.6))
                                .frame(maxWidth: .infinity)
                                .frame(height: 38)
                                .contentShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(ScaleButtonStyle())
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 10))
                    }
                }
            }
            .padding(.horizontal, 24)

            // Start button - primary CTA with glass + white fill
            Button {
                Haptics.medium()
                onStartShift(amountValue, notes)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 14))
                    Text("Start Shift")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(ScaleButtonStyle())
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
            .padding(.horizontal, 24)
            .padding(.top, 20)

            // Secondary actions
            HStack(spacing: 24) {
                Button {
                    Haptics.light()
                    Task {
                        await session.clearRegisterSelection()
                        onBack()
                    }
                } label: {
                    Text("Change")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.3))
                }

                Button {
                    Haptics.light()
                    Task { await session.signOut() }
                } label: {
                    Text("Sign Out")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
    }
}

// MARK: - Launching Content

private struct LaunchingContent: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white.opacity(0.6))
                .scaleEffect(1.2)

            Text("Starting...")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.vertical, 50)
    }
}

// MARK: - Option Row

private struct OptionRow: View {
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
                // Icon
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 42, height: 42)
                    .background(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(.white.opacity(0.08))
                    )

                // Info
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if let subtitle = subtitle {
                        HStack(spacing: 6) {
                            Text(subtitle)
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.4))
                                .lineLimit(1)

                            ForEach(badges, id: \.self) { badge in
                                Text(badge)
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.5))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(.white.opacity(0.1)))
                            }
                        }
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.25))
            }
            .padding(11)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(.white.opacity(isPressed ? 0.1 : 0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
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

// MARK: - End Session Modal

struct EndSessionModal: View {
    @EnvironmentObject private var session: SessionObserver
    @Environment(\.posWindowSession) private var windowSession: POSWindowSession?

    let posSession: POSSession
    let onDismiss: () -> Void
    let onEndShift: (Decimal) -> Void
    let onChangeRegister: () -> Void
    let onChangeLocation: () -> Void
    let onSignOut: () -> Void

    // Use window session's location/register if available, otherwise fall back to global
    private var displayLocation: Location? {
        windowSession?.location ?? session.selectedLocation
    }

    private var displayRegister: Register? {
        windowSession?.register ?? session.selectedRegister
    }

    enum ModalMode {
        case main
        case safeDrop
    }

    @State private var mode: ModalMode = .main
    @State private var closingCash = ""
    @State private var safeDropAmount = ""
    @State private var safeDropNotes = ""
    @State private var cashDrops: [CashDrop] = []
    @State private var modalScale: CGFloat = 0.9
    @State private var modalOpacity: CGFloat = 0
    @State private var contentOpacity: CGFloat = 0

    private var closingAmount: Decimal {
        Decimal(string: closingCash) ?? 0
    }

    private var safeDropDecimal: Decimal {
        Decimal(string: safeDropAmount) ?? 0
    }

    private var totalDropped: Decimal {
        cashDrops.reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.85)
                .ignoresSafeArea()
                .onTapGesture {
                    if mode == .safeDrop {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            mode = .main
                        }
                    } else {
                        onDismiss()
                    }
                }

            // Centered modal
            VStack {
                Spacer()

                VStack(spacing: 0) {
                    // Store logo at top
                    StoreLogo(
                        url: session.store?.fullLogoUrl,
                        size: 72,
                        storeName: session.store?.businessName
                    )
                    .padding(.top, 28)
                    .padding(.bottom, 16)

                    // Content based on mode
                    Group {
                        switch mode {
                        case .main:
                            mainContent
                        case .safeDrop:
                            safeDropContent
                        }
                    }
                    .opacity(contentOpacity)
                }
                .frame(maxWidth: 380)
                .background(modalBackground)
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                .shadow(color: .black.opacity(0.8), radius: 50, y: 20)
                .padding(.horizontal, 32)
                .scaleEffect(modalScale)
                .opacity(modalOpacity)

                Spacer()
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                modalScale = 1.0
                modalOpacity = 1.0
            }
            withAnimation(.easeOut(duration: 0.3).delay(0.1)) {
                contentOpacity = 1
            }
        }
    }

    // MARK: - Modal Background

    private var modalBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(Color(white: 0.08))

            RoundedRectangle(cornerRadius: 32, style: .continuous)
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

            RoundedRectangle(cornerRadius: 32, style: .continuous)
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

    // MARK: - Main Content

    private var mainContent: some View {
        VStack(spacing: 0) {
            // Session info - uses window-specific location/register when available
            HStack(spacing: 6) {
                if let location = displayLocation {
                    Text(location.name)
                        .font(.system(size: 12, weight: .medium))
                }
                Text("•")
                if let register = displayRegister {
                    Text(register.displayName)
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .foregroundStyle(.white.opacity(0.4))
            .padding(.bottom, 8)

            // Show total dropped if any
            if totalDropped > 0 {
                Text("\(CurrencyFormatter.format(totalDropped)) dropped to safe")
                    .font(.system(size: 11))
                    .foregroundStyle(Design.Colors.Semantic.success.opacity(0.8))
                    .padding(.bottom, 16)
            } else {
                Spacer().frame(height: 12)
            }

            // Closing cash section
            VStack(spacing: 12) {
                Text("Closing Cash")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))

                // Amount input
                HStack {
                    Text("$")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.white.opacity(0.4))

                    TextField("0", text: $closingCash)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.white)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .frame(width: 120)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.white.opacity(0.06))
                )

                // Quick amounts
                HStack(spacing: 8) {
                    ForEach(["100", "200", "300", "500"], id: \.self) { amount in
                        Button {
                            Haptics.light()
                            closingCash = amount
                        } label: {
                            Text("$\(amount)")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(closingCash == amount ? .white : .white.opacity(0.6))
                                .frame(maxWidth: .infinity)
                                .frame(height: 34)
                                .contentShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(ScaleButtonStyle())
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 10))
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)

            // Action buttons
            HStack(spacing: 10) {
                // Drop to Safe button
                Button {
                    Haptics.light()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        mode = .safeDrop
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.to.line.compact")
                            .font(.system(size: 14, weight: .medium))
                        Text("Safe")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .contentShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(ScaleButtonStyle())
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))

                // End Shift button - primary CTA with glass + white fill
                Button {
                    Haptics.medium()
                    onEndShift(closingAmount)
                } label: {
                    Text("End Shift")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(ScaleButtonStyle())
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)

            // Divider
            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 1)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)

            // Options
            VStack(spacing: 0) {
                sessionOptionButton(title: "Change Register") {
                    onChangeRegister()
                }

                sessionOptionButton(title: "Change Location") {
                    onChangeLocation()
                }

                sessionOptionButton(title: "Sign Out", isDestructive: true) {
                    onSignOut()
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            // Cancel
            Button {
                onDismiss()
            } label: {
                Text("Cancel")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .padding(.bottom, 20)
        }
    }

    // MARK: - Safe Drop Content

    private var safeDropContent: some View {
        VStack(spacing: 0) {
            // Back button
            HStack {
                Button {
                    Haptics.light()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        mode = .main
                        safeDropAmount = ""
                        safeDropNotes = ""
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Back")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            // Title
            Text("Drop to Safe")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .padding(.bottom, 20)

            // Amount input
            VStack(spacing: 12) {
                HStack {
                    Text("$")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.white.opacity(0.4))

                    TextField("0", text: $safeDropAmount)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.white)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .frame(width: 120)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.white.opacity(0.06))
                )

                // Quick amounts
                HStack(spacing: 8) {
                    ForEach(["100", "200", "500", "1000"], id: \.self) { amount in
                        Button {
                            Haptics.light()
                            safeDropAmount = amount
                        } label: {
                            Text("$\(amount)")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(safeDropAmount == amount ? .white : .white.opacity(0.6))
                                .frame(maxWidth: .infinity)
                                .frame(height: 34)
                                .contentShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(ScaleButtonStyle())
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 10))
                    }
                }

                // Notes (optional)
                TextField("Notes (optional)", text: $safeDropNotes)
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .glassEffect(.regular, in: .rect(cornerRadius: 12))
                    .padding(.top, 4)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)

            // Drop button - primary CTA with glass + white fill
            Button {
                Haptics.success()
                performSafeDrop()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.to.line.compact")
                        .font(.system(size: 14, weight: .medium))
                    Text("Drop \(safeDropDecimal > 0 ? CurrencyFormatter.format(safeDropDecimal) : "$0.00")")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(safeDropDecimal > 0 ? .black : .white.opacity(0.4))
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(safeDropDecimal > 0 ? Color.white : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(ScaleButtonStyle())
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
            .disabled(safeDropDecimal <= 0)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Actions

    private func performSafeDrop() {
        guard safeDropDecimal > 0 else { return }

        let drop = CashDrop.create(
            sessionId: posSession.id,
            locationId: posSession.locationId,
            registerId: posSession.registerId,
            userId: session.userId,
            amount: safeDropDecimal,
            notes: safeDropNotes.isEmpty ? nil : safeDropNotes
        )

        cashDrops.append(drop)

        // TODO: Save to database
        // Task { await CashDropService.save(drop) }

        // Reset and go back
        safeDropAmount = ""
        safeDropNotes = ""

        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            mode = .main
        }
    }

    private func sessionOptionButton(
        title: String,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isDestructive ? Design.Colors.Semantic.error.opacity(0.8) : .white.opacity(0.5))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
        }
    }
}

// MARK: - Safe Drop Modal (Standalone - for use during shift)

struct SafeDropModal: View {
    @EnvironmentObject private var session: SessionObserver
    @Environment(\.posWindowSession) private var windowSession: POSWindowSession?

    let posSession: POSSession
    @Binding var isPresented: Bool

    // Use window session's location/register if available, otherwise fall back to global
    private var displayLocation: Location? {
        windowSession?.location ?? session.selectedLocation
    }

    private var displayRegister: Register? {
        windowSession?.register ?? session.selectedRegister
    }

    @State private var amount = ""
    @State private var notes = ""
    @State private var modalScale: CGFloat = 0.9
    @State private var modalOpacity: CGFloat = 0
    @State private var contentOpacity: CGFloat = 0
    @State private var showSuccess = false

    private var amountDecimal: Decimal {
        Decimal(string: amount) ?? 0
    }

    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.85)
                .ignoresSafeArea()
                .onTapGesture {
                    dismiss()
                }

            // Centered modal
            VStack {
                Spacer()

                VStack(spacing: 0) {
                    // Store logo at top
                    StoreLogo(
                        url: session.store?.fullLogoUrl,
                        size: 72,
                        storeName: session.store?.businessName
                    )
                    .padding(.top, 28)
                    .padding(.bottom, 16)

                    // Content
                    if showSuccess {
                        successContent
                    } else {
                        dropContent
                    }
                }
                .frame(maxWidth: 380)
                .background(modalBackground)
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                .shadow(color: .black.opacity(0.8), radius: 50, y: 20)
                .padding(.horizontal, 32)
                .scaleEffect(modalScale)
                .opacity(modalOpacity)

                Spacer()
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                modalScale = 1.0
                modalOpacity = 1.0
            }
            withAnimation(.easeOut(duration: 0.3).delay(0.1)) {
                contentOpacity = 1
            }
        }
    }

    // MARK: - Modal Background

    private var modalBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(Color(white: 0.08))

            RoundedRectangle(cornerRadius: 32, style: .continuous)
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

            RoundedRectangle(cornerRadius: 32, style: .continuous)
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

    // MARK: - Drop Content

    private var dropContent: some View {
        VStack(spacing: 0) {
            // Title
            Text("Drop to Safe")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .padding(.bottom, 8)

            // Session info - uses window-specific location/register when available
            HStack(spacing: 6) {
                if let location = displayLocation {
                    Text(location.name)
                        .font(.system(size: 12, weight: .medium))
                }
                Text("•")
                if let register = displayRegister {
                    Text(register.displayName)
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .foregroundStyle(.white.opacity(0.4))
            .padding(.bottom, 24)

            // Amount input
            VStack(spacing: 12) {
                HStack {
                    Text("$")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(.white.opacity(0.4))

                    TextField("0", text: $amount)
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(.white)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .frame(width: 140)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.white.opacity(0.06))
                )

                // Quick amounts
                HStack(spacing: 10) {
                    ForEach(["100", "200", "500", "1000"], id: \.self) { quickAmount in
                        Button {
                            Haptics.light()
                            amount = quickAmount
                        } label: {
                            Text("$\(quickAmount)")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(amount == quickAmount ? .white : .white.opacity(0.6))
                                .frame(maxWidth: .infinity)
                                .frame(height: 38)
                                .contentShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(ScaleButtonStyle())
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 10))
                    }
                }

                // Notes (optional)
                TextField("Notes (optional)", text: $notes)
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .glassEffect(.regular, in: .rect(cornerRadius: 12))
                    .padding(.top, 4)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)

            // Drop button - primary CTA with glass + white fill
            Button {
                performDrop()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.to.line.compact")
                        .font(.system(size: 16, weight: .medium))
                    Text("Drop \(amountDecimal > 0 ? CurrencyFormatter.format(amountDecimal) : "$0")")
                        .font(.system(size: 17, weight: .semibold))
                }
                .foregroundStyle(amountDecimal > 0 ? .black : .white.opacity(0.4))
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(amountDecimal > 0 ? Color.white : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(ScaleButtonStyle())
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
            .disabled(amountDecimal <= 0)
            .padding(.horizontal, 24)
            .padding(.bottom, 16)

            // Cancel
            Button {
                dismiss()
            } label: {
                Text("Cancel")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .padding(.bottom, 24)
        }
        .opacity(contentOpacity)
    }

    // MARK: - Success Content

    private var successContent: some View {
        VStack(spacing: 20) {
            // Checkmark
            ZStack {
                Circle()
                    .fill(Design.Colors.Semantic.success.opacity(0.2))
                    .frame(width: 80, height: 80)

                Image(systemName: "checkmark")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(Design.Colors.Semantic.success)
            }

            Text("Dropped to Safe")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)

            Text(CurrencyFormatter.format(amountDecimal))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))

            if !notes.isEmpty {
                Text(notes)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(.vertical, 40)
        .padding(.horizontal, 24)
        .opacity(contentOpacity)
    }

    // MARK: - Actions

    private func performDrop() {
        guard amountDecimal > 0 else { return }

        Haptics.success()

        // Update window session drawer balance (isolated mode)
        if let ws = windowSession, ws.location != nil {
            Task {
                do {
                    try await ws.performSafeDrop(
                        amount: amountDecimal,
                        notes: notes.isEmpty ? nil : notes
                    )
                } catch {
                    print("Safe drop failed: \(error)")
                }
            }
        }

        // Also create legacy CashDrop record for database persistence
        _ = CashDrop.create(
            sessionId: posSession.id,
            locationId: posSession.locationId,
            registerId: posSession.registerId,
            userId: session.userId,
            amount: amountDecimal,
            notes: notes.isEmpty ? nil : notes
        )

        // TODO: Save to database
        // Task { await CashDropService.save(drop) }

        // Show success
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            showSuccess = true
        }

        // Dismiss after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            dismiss()
        }
    }

    private func dismiss() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            modalScale = 0.9
            modalOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            isPresented = false
        }
    }
}

// Note: TextSystemWarmupView removed - keyboard warmup now handled by SubsystemWarmup in WhaleApp.swift

#Preview {
    BootModal()
        .environmentObject(SessionObserver.shared)
}
