//
//  ContentView.swift
//  Whale
//
//  Login screen - auth gate only.
//  No business logic. No backend decisions.
//

import SwiftUI
import os.log

struct ContentView: View {
    @EnvironmentObject private var session: SessionObserver
    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false
    @State private var showBiometricSetup = false
    @State private var stayLoggedIn = true

    private var biometricType: BiometricType {
        BiometricAuthService.availableBiometricType
    }

    init() {
        Log.session.debug("ContentView init")
    }

    var body: some View {
        Log.ui.debug("ContentView body evaluated - login screen rendering")
        return ZStack {
            Design.Colors.backgroundPrimary.ignoresSafeArea()

            ScrollView {
                VStack(spacing: Design.Spacing.xl) {
                    Spacer()
                        .frame(height: 60)

                    // Logo/Title
                    VStack(spacing: Design.Spacing.xs) {
                        Image(systemName: "person.circle.fill")
                            .resizable()
                            .frame(width: 80, height: 80)
                            .foregroundStyle(Design.Colors.Text.subtle)

                        Text(isSignUp ? "Create Account" : "Welcome Back")
                            .font(Design.Typography.largeTitle)
                            .foregroundStyle(Design.Colors.Text.primary)

                        Text(isSignUp ? "Sign up to get started" : "Sign in to continue")
                            .font(Design.Typography.subhead)
                            .foregroundStyle(Design.Colors.Text.disabled)
                    }
                    .padding(.bottom, Design.Spacing.xxl)

                    // Glass card form
                    VStack(spacing: Design.Spacing.lg) {
                        // Email field
                        HStack {
                            Image(systemName: "envelope.fill")
                                .foregroundStyle(Design.Colors.Text.subtle)
                                .frame(width: 24)
                            TextField("Email", text: $email)
                                .foregroundStyle(Design.Colors.Text.primary)
                                .keyboardType(.emailAddress)
                                .textContentType(.emailAddress)
                                .autocapitalization(.none)
                                .autocorrectionDisabled()
                        }
                        .padding(Design.Spacing.md)
                        .glassBackground(intensity: .medium, cornerRadius: Design.Radius.md)

                        // Password field
                        HStack {
                            Image(systemName: "lock.fill")
                                .foregroundStyle(Design.Colors.Text.subtle)
                                .frame(width: 24)
                            SecureField("Password", text: $password)
                                .foregroundStyle(Design.Colors.Text.primary)
                                .textContentType(isSignUp ? .newPassword : .password)
                        }
                        .padding(Design.Spacing.md)
                        .glassBackground(intensity: .medium, cornerRadius: Design.Radius.md)

                        // Stay logged in toggle (with biometric)
                        if !isSignUp && biometricType != .none {
                            Toggle(isOn: $stayLoggedIn) {
                                HStack(spacing: 8) {
                                    Image(systemName: biometricType.iconName)
                                        .font(.system(size: 16))
                                        .foregroundStyle(Design.Colors.Text.subtle)
                                    Text("Stay logged in with \(biometricType.displayName)")
                                        .font(Design.Typography.footnote)
                                        .foregroundStyle(Design.Colors.Text.secondary)
                                }
                            }
                            .toggleStyle(SwitchToggleStyle(tint: Design.Colors.Semantic.accent))
                            .padding(.horizontal, 4)
                        }

                        // Error message
                        if let error = session.errorMessage {
                            Text(error)
                                .font(Design.Typography.caption1)
                                .foregroundStyle(Design.Colors.Semantic.error)
                                .padding(.horizontal)
                        }

                        // Forgot Password
                        if !isSignUp {
                            HStack {
                                Spacer()
                                Button("Forgot Password?") {
                                    // TODO: Handle forgot password
                                }
                                .font(Design.Typography.footnote)
                                .foregroundStyle(Design.Colors.Text.disabled)
                            }
                        }

                        // Login/Signup Button
                        Button(action: handleAuth) {
                            HStack {
                                if session.isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                } else {
                                    Text(isSignUp ? "Sign Up" : "Sign In")
                                        .font(Design.Typography.buttonLarge)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Design.Spacing.md)
                            .background(
                                RoundedRectangle(cornerRadius: Design.Radius.md, style: .continuous)
                                    .fill(isFormValid ? Color.white : Design.Colors.Glass.regular)
                            )
                            .foregroundStyle(isFormValid ? .black : Design.Colors.Text.subtle)
                        }
                        .buttonStyle(LiquidPressStyle())
                        .disabled(!isFormValid || session.isLoading)
                        .padding(.top, Design.Spacing.xs)
                    }
                    .padding(Design.Spacing.xl)
                    .glassBackground(intensity: .medium, cornerRadius: Design.Radius.xxl)
                    .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 10)
                    .padding(.horizontal, Design.Spacing.xl)

                    Spacer()
                        .frame(height: Design.Spacing.xxl)

                    // Toggle Sign Up / Sign In
                    HStack {
                        Text(isSignUp ? "Already have an account?" : "Don't have an account?")
                            .foregroundStyle(Design.Colors.Text.disabled)
                        Button(isSignUp ? "Sign In" : "Sign Up") {
                            Haptics.light()
                            withAnimation(Design.Animation.springSnappy) {
                                isSignUp.toggle()
                            }
                        }
                        .fontWeight(.semibold)
                        .foregroundStyle(Design.Colors.Text.primary)
                    }
                    .font(Design.Typography.footnote)
                    .padding(.bottom, Design.Spacing.xxl)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var isFormValid: Bool {
        !email.isEmpty && !password.isEmpty && email.contains("@") && password.count >= 6
    }

    private func handleAuth() {
        Haptics.medium()
        Task {
            let success = await session.signIn(email: email, password: password)

            if success && stayLoggedIn && biometricType != .none {
                // Enable biometric for future logins
                session.enableBiometric()
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(SessionObserver.shared)
}
