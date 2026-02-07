//
//  BootLoginContent.swift
//  Whale
//
//  Login form, location selection, and register selection
//  content views for BootSheet.
//

import SwiftUI

// MARK: - Login Content

struct BootLoginContent: View {
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

struct BootLocationContent: View {
    @EnvironmentObject private var session: SessionObserver
    let onSelected: (Location) -> Void

    @State private var appearAnimation = false
    @State private var selectedId: UUID?

    var body: some View {
        VStack(spacing: 0) {
            Text("Select Location")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.bottom, 24)

            VStack(spacing: 0) {
                if session.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white.opacity(0.5)))
                        .padding(.vertical, 40)
                } else {
                    ForEach(Array(session.locations.enumerated()), id: \.element.id) { index, location in
                        BootLocationRow(
                            location: location,
                            isSelected: selectedId == location.id,
                            delay: Double(index) * 0.05,
                            isAnimated: appearAnimation
                        ) {
                            Haptics.medium()
                            selectedId = location.id
                            Task {
                                await session.selectLocation(location)
                                try? await Task.sleep(nanoseconds: 100_000_000)
                                onSelected(location)
                            }
                        }

                        if index < session.locations.count - 1 {
                            Rectangle()
                                .fill(.white.opacity(0.06))
                                .frame(height: 1)
                                .padding(.leading, 16)
                                .opacity(appearAnimation ? 1 : 0)
                                .animation(.easeOut(duration: 0.3).delay(Double(index) * 0.05), value: appearAnimation)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.white.opacity(0.04))
            )
            .padding(.horizontal, 20)

            Button {
                Haptics.light()
                Task { await session.signOut() }
            } label: {
                Text("Sign Out")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.25))
            }
            .padding(.top, 24)
            .padding(.bottom, 28)
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

// MARK: - Location Row

struct BootLocationRow: View {
    let location: Location
    let isSelected: Bool
    let delay: Double
    let isAnimated: Bool
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(location.name)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if let address = location.displayAddress, !address.isEmpty {
                        Text(address)
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.4))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 12)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
            .background(isPressed ? Color.white.opacity(0.06) : Color.clear)
        }
        .buttonStyle(.plain)
        .opacity(isAnimated ? 1 : 0)
        .offset(y: isAnimated ? 0 : 8)
        .animation(.spring(response: 0.35, dampingFraction: 0.8).delay(delay), value: isAnimated)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !isPressed { isPressed = true } }
                .onEnded { _ in isPressed = false }
        )
        .animation(.easeOut(duration: 0.1), value: isPressed)
    }
}

// MARK: - Register Content

struct BootRegisterContent: View {
    @EnvironmentObject private var session: SessionObserver
    let onSelected: (Register) -> Void
    let onBack: () -> Void

    @State private var appearAnimation = false
    @State private var selectedId: UUID?

    var body: some View {
        VStack(spacing: 0) {
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
                            .font(.system(size: 13, weight: .semibold))
                        Text("Back")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundStyle(.white.opacity(0.4))
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            VStack(spacing: 6) {
                Text("Select Register")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)

                if let location = session.selectedLocation {
                    Text(location.name)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
            .padding(.bottom, 24)

            VStack(spacing: 0) {
                if session.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white.opacity(0.5)))
                        .padding(.vertical, 40)
                } else {
                    ForEach(Array(session.registers.enumerated()), id: \.element.id) { index, register in
                        BootRegisterRow(
                            register: register,
                            isSelected: selectedId == register.id,
                            delay: Double(index) * 0.05,
                            isAnimated: appearAnimation
                        ) {
                            Haptics.medium()
                            selectedId = register.id
                            Task {
                                await session.selectRegister(register)
                                try? await Task.sleep(nanoseconds: 100_000_000)
                                onSelected(register)
                            }
                        }

                        if index < session.registers.count - 1 {
                            Rectangle()
                                .fill(.white.opacity(0.06))
                                .frame(height: 1)
                                .padding(.leading, 16)
                                .opacity(appearAnimation ? 1 : 0)
                                .animation(.easeOut(duration: 0.3).delay(Double(index) * 0.05), value: appearAnimation)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.white.opacity(0.04))
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .task {
            await session.fetchRegisters()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                appearAnimation = true
            }
        }
    }
}

// MARK: - Register Row

struct BootRegisterRow: View {
    let register: Register
    let isSelected: Bool
    let delay: Double
    let isAnimated: Bool
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(register.displayName)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text("Register \(register.registerNumber)")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.4))
                }

                Spacer(minLength: 12)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
            .background(isPressed ? Color.white.opacity(0.06) : Color.clear)
        }
        .buttonStyle(.plain)
        .opacity(isAnimated ? 1 : 0)
        .offset(y: isAnimated ? 0 : 8)
        .animation(.spring(response: 0.35, dampingFraction: 0.8).delay(delay), value: isAnimated)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !isPressed { isPressed = true } }
                .onEnded { _ in isPressed = false }
        )
        .animation(.easeOut(duration: 0.1), value: isPressed)
    }
}
