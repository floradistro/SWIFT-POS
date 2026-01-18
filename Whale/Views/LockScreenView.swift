//
//  LockScreenView.swift
//  Whale
//
//  Face ID / Touch ID lock screen - unified modal design.
//  Matches the boot modal aesthetic for seamless experience.
//

import SwiftUI

struct LockScreenView: View {
    @EnvironmentObject private var session: SessionObserver
    @State private var isAuthenticating = false
    @State private var showSignOutConfirm = false
    @State private var animationProgress: CGFloat = 0
    @State private var pulseAnimation = false

    private var biometricType: BiometricType {
        BiometricAuthService.availableBiometricType
    }

    private var displayEmail: String {
        BiometricAuthService.lastAuthEmail ?? session.userEmail ?? "User"
    }

    var body: some View {
        ZStack {
            // Background
            Design.Colors.backgroundPrimary.ignoresSafeArea()

            // Centered modal
            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 0) {
                    // Biometric icon with pulse
                    ZStack {
                        // Pulse rings
                        ForEach(0..<3) { i in
                            Circle()
                                .stroke(.white.opacity(0.1), lineWidth: 1)
                                .frame(width: 100 + CGFloat(i) * 30, height: 100 + CGFloat(i) * 30)
                                .scaleEffect(pulseAnimation ? 1.1 : 1.0)
                                .opacity(pulseAnimation ? 0 : 0.5)
                                .animation(
                                    .easeOut(duration: 2)
                                    .repeatForever(autoreverses: false)
                                    .delay(Double(i) * 0.3),
                                    value: pulseAnimation
                                )
                        }

                        // Main icon
                        Image(systemName: biometricType.iconName)
                            .font(.system(size: 48, weight: .light))
                            .foregroundStyle(.white)
                            .frame(width: 100, height: 100)
                            .background(
                                Circle()
                                    .fill(.white.opacity(0.1))
                            )
                    }
                    .padding(.top, 40)
                    .padding(.bottom, 24)

                    // Title
                    Text("Whale POS")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)

                    // Email
                    Text(displayEmail)
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.top, 6)
                        .padding(.bottom, 32)

                    // Unlock button - primary CTA with glass + white fill
                    Button {
                        authenticate()
                    } label: {
                        HStack(spacing: 10) {
                            if isAuthenticating {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                    .scaleEffect(0.9)
                            } else {
                                Image(systemName: biometricType.iconName)
                                    .font(.system(size: 18, weight: .medium))
                                Text("Unlock with \(biometricType.displayName)")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                        }
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.roundedRectangle(radius: 14))
                    .disabled(isAuthenticating)
                    .padding(.horizontal, 24)

                    // Sign out option
                    Button {
                        showSignOutConfirm = true
                    } label: {
                        Text("Use different account")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.4))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .padding(.top, 16)
                    .padding(.bottom, 28)
                }
                .frame(maxWidth: 380)
                .background(modalBackground)
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                .shadow(color: .black.opacity(0.6), radius: 40, y: 15)
                .padding(.horizontal, 32)
                .scaleEffect(0.92 + (0.08 * animationProgress))
                .opacity(animationProgress)

                Spacer()
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) {
                animationProgress = 1
            }
            pulseAnimation = true

            // Auto-trigger biometric
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                authenticate()
            }
        }
        .alert("Sign Out?", isPresented: $showSignOutConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Sign Out", role: .destructive) {
                Task { await session.signOut() }
            }
        } message: {
            Text("You'll need to sign in again with your email and password.")
        }
    }

    // MARK: - Modal Background

    private var modalBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(.ultraThinMaterial)

            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.08),
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
                            Color.white.opacity(0.2),
                            Color.white.opacity(0.08),
                            Color.white.opacity(0.12)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
    }

    // MARK: - Authentication

    private func authenticate() {
        guard !isAuthenticating else { return }

        isAuthenticating = true
        Haptics.light()

        Task {
            _ = await session.unlockWithBiometric()
            isAuthenticating = false
        }
    }
}

#Preview {
    LockScreenView()
        .environmentObject(SessionObserver.shared)
}
