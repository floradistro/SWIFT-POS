//
//  ScannerCustomerModal.swift
//  Whale
//
//  Streamlined modal for customer selection/creation after ID scan.
//  Flow: ID scan > show matches OR auto-create > confirm > add to sale
//

import SwiftUI
import os

struct ScannerCustomerModal: View {
    let scannedID: ScannedID
    let matches: [CustomerMatch]
    let storeId: UUID
    let onComplete: (Customer) -> Void
    let onCancel: () -> Void

    enum ModalState { case selecting, creating, done }

    @State private var isPresented = true
    @State private var state: ModalState = .selecting
    @State private var showConfirmCreate = false
    @State private var pendingCustomer: Customer?
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        // Direct content - no ScrollView to avoid gesture blocking
        VStack(spacing: 0) {
            switch state {
            case .selecting: selectionContent
            case .creating: loadingContent
            case .done: EmptyView()
            }
        }
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onChange(of: isPresented) { _, newValue in if !newValue { onCancel() } }
        .onAppear {
            // If exact match found, show it immediately
            // If no matches, prompt to create
            if matches.isEmpty {
                showConfirmCreate = true
            }
        }
        .alert("Create New Customer?", isPresented: $showConfirmCreate) {
            Button("Create") {
                createNewCustomer()
            }
            Button("Cancel", role: .cancel) {
                // Stay on modal to let them cancel out
            }
        } message: {
            Text("No existing customer found for \(scannedID.fullDisplayName). Create a new profile?")
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "Failed to create customer")
        }
    }

    // MARK: - Selection Content

    private var selectionContent: some View {
        VStack(spacing: 0) {
            // Header
            ModalHeader(scannedID.fullDisplayName, subtitle: headerSubtitle, onClose: { isPresented = false }) {
                if let age = scannedID.age {
                    Text("\(age)")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Design.Colors.Semantic.success)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Design.Colors.Semantic.success.opacity(0.15)))
                }
            }

            VStack(spacing: 16) {
                // License info
                if let licenseState = scannedID.state {
                    HStack(spacing: 10) {
                        Image(systemName: "car.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.4))
                        Text("\(licenseState) Driver's License")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                        if scannedID.isExpired {
                            Text("EXPIRED")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Design.Colors.Semantic.error))
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 4)
                }

                // Matches list
                if !matches.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        ModalSectionLabel(matches.count == 1 ? "Existing Customer" : "Select Customer")

                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 10) {
                                ForEach(matches, id: \.id) { match in
                                    Button {
                                        Haptics.medium()
                                        selectMatch(match)
                                    } label: {
                                        customerMatchRow(match)
                                    }
                                    .buttonStyle(ScaleButtonStyle())
                                }
                            }
                        }
                        .frame(maxHeight: min(CGFloat(matches.count) * 100, 300))
                    }
                }

                // Create new button
                ModalActionButton(
                    matches.isEmpty ? "Create Customer" : "Create New Instead",
                    icon: "person.badge.plus",
                    style: matches.isEmpty ? .success : .primary
                ) {
                    createNewCustomer()
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Loading Content

    private var loadingContent: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.04))
                    .frame(width: 80, height: 80)

                ProgressView()
                    .scaleEffect(1.3)
                    .tint(.white.opacity(0.6))
            }

            Text("Creating Customer...")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    // MARK: - Match Row

    private func customerMatchRow(_ match: CustomerMatch) -> some View {
        HStack(spacing: 14) {
            // Avatar with match indicator
            ZStack {
                Circle()
                    .stroke(matchColor(for: match.matchType).opacity(0.3), lineWidth: 3)
                    .frame(width: 52, height: 52)
                Circle()
                    .fill(loyaltyGradient(for: match.customer.loyaltyTier))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Text(match.customer.initials)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                    )
            }

            // Info
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(match.customer.displayName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if match.matchType == .exact {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Design.Colors.Semantic.success)
                    }
                }

                HStack(spacing: 10) {
                    if let email = match.customer.email, !email.isEmpty {
                        Text(truncateEmail(email))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                    } else if let phone = match.customer.formattedPhone {
                        Text(phone)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                    }

                    if let points = match.customer.loyaltyPoints, points > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10))
                            Text("\(points)")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(.orange)
                    }
                }
            }

            Spacer(minLength: 4)

            // Stats + chevron
            VStack(alignment: .trailing, spacing: 3) {
                if let spent = match.customer.totalSpent, spent > 0 {
                    Text(match.customer.formattedTotalSpent)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                }
                if match.pendingOrderCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "bag.fill")
                            .font(.system(size: 10))
                        Text("\(match.pendingOrderCount)")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(Design.Colors.Semantic.warning)
                }
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.25))
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.1), lineWidth: 0.5))
    }

    // MARK: - Helpers

    private var headerSubtitle: String {
        if matches.isEmpty { return "New Customer" }
        else if matches.count == 1 { return "1 Match Found" }
        else { return "\(matches.count) Matches Found" }
    }

    private func truncateEmail(_ email: String) -> String {
        guard email.count > 22, let parts = email.split(separator: "@").first else { return email }
        return "\(String(parts.prefix(8)))...@\(email.split(separator: "@").last ?? "")"
    }

    private func matchColor(for matchType: CustomerMatch.MatchType) -> Color {
        switch matchType {
        case .exact: return Design.Colors.Semantic.success
        case .phoneDOB, .email, .high: return Color(red: 59/255, green: 130/255, blue: 246/255)
        case .phoneOnly, .nameOnly, .fuzzy: return Color(red: 245/255, green: 158/255, blue: 11/255)
        }
    }

    private func loyaltyGradient(for tier: String?) -> LinearGradient {
        let colors: [Color]
        switch tier?.lowercased() {
        case "gold": colors = [Color(red: 245/255, green: 158/255, blue: 11/255), Color(red: 217/255, green: 119/255, blue: 6/255)]
        case "platinum": colors = [Color(red: 161/255, green: 161/255, blue: 170/255), Color(red: 113/255, green: 113/255, blue: 122/255)]
        case "diamond": colors = [Color(red: 6/255, green: 182/255, blue: 212/255), Color(red: 8/255, green: 145/255, blue: 178/255)]
        default: colors = [.white.opacity(0.15), .white.opacity(0.1)]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: - Actions

    private func selectMatch(_ match: CustomerMatch) {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)

        // Update license number if customer doesn't have one
        if match.customer.driversLicenseNumber == nil, let license = scannedID.licenseNumber {
            Task { await CustomerService.updateCustomerLicense(match.customer.id, licenseNumber: license) }
        }

        ScanFeedback.shared.customerFound()
        state = .done
        isPresented = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { onComplete(match.customer) }
    }

    private func createNewCustomer() {
        withAnimation(.spring(response: 0.3)) { state = .creating }

        Task {
            let customerData = NewCustomerFromScan(from: scannedID)
            Log.scanner.info("Creating customer: \(customerData.firstName ?? "nil") \(customerData.lastName ?? "nil"), DOB: \(customerData.dateOfBirth ?? "nil"), License: \(customerData.driversLicenseNumber ?? "nil")")

            let result = await CustomerService.createCustomer(customerData, storeId: storeId)
            await MainActor.run {
                switch result {
                case .success(let customer):
                    ScanFeedback.shared.customerFound()
                    state = .done
                    isPresented = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { onComplete(customer) }
                case .failure(let error):
                    Log.scanner.error("Customer creation failed: \(error.localizedDescription)")
                    Haptics.error()
                    errorMessage = error.localizedDescription
                    showError = true
                    withAnimation { state = .selecting }
                }
            }
        }
    }
}
