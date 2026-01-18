//
//  LocationSelectorView.swift
//  Whale
//
//  Location selection - full screen liquid glass.
//  Clean, minimal, Apple-quality.
//

import SwiftUI

struct LocationSelectorView: View {
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

                // Location list
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: Design.Spacing.sm) {
                        if session.isLoading {
                            loadingState
                        } else if let error = session.errorMessage {
                            errorState(error)
                        } else if session.locations.isEmpty {
                            emptyState
                        } else {
                            ForEach(Array(session.locations.enumerated()), id: \.element.id) { index, location in
                                LocationRow(location: location) {
                                    Haptics.medium()
                                    Task {
                                        await session.selectLocation(location)
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

                // Sign out button at bottom
                signOutButton
                    .padding(.horizontal, Design.Spacing.lg)
                    .padding(.bottom, Design.Spacing.xxl)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            // Fetch store and locations in parallel
            async let store = session.fetchStore()
            async let locations = session.fetchLocations()

            await store
            await locations

            withAnimation {
                appearAnimation = true
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: Design.Spacing.md) {
            // Store logo
            StoreLogo(
                url: session.store?.fullLogoUrl,
                size: 72,
                storeName: session.store?.businessName
            )
            .opacity(appearAnimation ? 1 : 0)
            .scaleEffect(appearAnimation ? 1 : 0.8)
            .animation(Design.Animation.springBouncy, value: appearAnimation)

            // Title
            Text("Select Location")
                .font(Design.Typography.largeTitle)
                .foregroundStyle(Design.Colors.Text.primary)
                .opacity(appearAnimation ? 1 : 0)
                .animation(Design.Animation.springSnappy.delay(0.1), value: appearAnimation)

            // Subtitle
            if let email = session.userEmail {
                Text(email)
                    .font(Design.Typography.subhead)
                    .foregroundStyle(Design.Colors.Text.subtle)
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

            Text("Loading locations...")
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
                Task { await session.fetchLocations() }
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
            Image(systemName: "mappin.slash")
                .font(.system(size: 40))
                .foregroundStyle(Design.Colors.Text.ghost)

            Text("No locations found")
                .font(Design.Typography.headline)
                .foregroundStyle(Design.Colors.Text.secondary)

            Text("Add locations in the admin panel")
                .font(Design.Typography.subhead)
                .foregroundStyle(Design.Colors.Text.subtle)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Design.Spacing.huge)
    }

    // MARK: - Sign Out

    private var signOutButton: some View {
        Button {
            Haptics.light()
            Task { await session.signOut() }
        } label: {
            HStack(spacing: Design.Spacing.xs) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                Text("Sign Out")
            }
            .font(Design.Typography.subhead)
            .foregroundStyle(Design.Colors.Text.ghost)
        }
        .buttonStyle(LiquidPressStyle())
    }
}

// MARK: - Location Row

struct LocationRow: View {
    let location: Location
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Design.Spacing.md) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: Design.Radius.md, style: .continuous)
                        .fill(Design.Colors.Glass.regular)
                        .frame(width: 48, height: 48)

                    Image(systemName: iconForType(location.type))
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Design.Colors.Text.tertiary)
                }

                // Info
                VStack(alignment: .leading, spacing: Design.Spacing.xxxs) {
                    Text(location.name)
                        .font(Design.Typography.headline)
                        .foregroundStyle(Design.Colors.Text.primary)
                        .lineLimit(1)

                    if let address = location.displayAddress {
                        Text(address)
                            .font(Design.Typography.caption1)
                            .foregroundStyle(Design.Colors.Text.subtle)
                            .lineLimit(1)
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

    private func iconForType(_ type: String) -> String {
        switch type.lowercased() {
        case "warehouse": return "shippingbox.fill"
        case "store", "retail": return "storefront.fill"
        case "office": return "building.2.fill"
        default: return "mappin.circle.fill"
        }
    }
}

#Preview {
    LocationSelectorView()
        .environmentObject(SessionObserver.shared)
}
