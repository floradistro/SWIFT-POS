//
//  DockDiscountSection.swift
//  Whale
//
//  Discount and loyalty redemption UI for the dock checkout.
//  Includes deal pills and loyalty points slider.
//  Backend-driven: ALL calculations come from server-side Edge Function.
//

import SwiftUI
import os.log

// MARK: - Discount Section

struct DockDiscountSection: View {
    let customer: Customer?
    let subtotal: Decimal
    @Binding var pointsToRedeem: Int
    let pointValue: Decimal
    @ObservedObject var dealStore: DealStore

    // Backend-driven state
    @State private var maxRedeemablePoints: Int = 0
    @State private var loyaltyDiscount: Decimal = 0

    private let logger = Logger(subsystem: "com.whale.pos", category: "DockDiscount")

    var body: some View {
        VStack(spacing: 10) {
            // Deal pills (if any available)
            if !dealStore.availableDeals.isEmpty {
                dealPillsSection
            }

            // Loyalty slider (if customer has points)
            if let customer = customer, maxRedeemablePoints > 0 {
                loyaltySliderSection(customer: customer)
            }
        }
        .onAppear {
            Task { await loadLoyaltyCalculation() }
        }
        .onChange(of: subtotal) { _, _ in
            Task { await loadLoyaltyCalculation() }
        }
        .onChange(of: pointsToRedeem) { _, newValue in
            Task { await updateLoyaltyDiscount(points: newValue) }
        }
    }

    // MARK: - Backend Loyalty Calculation

    private func loadLoyaltyCalculation() async {
        guard let customer = customer else {
            await MainActor.run {
                maxRedeemablePoints = 0
                loyaltyDiscount = 0
            }
            return
        }

        do {
            let result = try await PaymentCalculatorService.shared.calculateLoyalty(
                total: subtotal,
                availablePoints: customer.loyaltyPoints ?? 0,
                pointValue: pointValue,
                pointsToRedeem: pointsToRedeem
            )
            await MainActor.run {
                maxRedeemablePoints = result.maxRedeemablePoints
                loyaltyDiscount = result.redemptionValue
            }
        } catch {
            logger.error("Failed to load loyalty calculation: \(error.localizedDescription)")
            await MainActor.run {
                maxRedeemablePoints = 0
                loyaltyDiscount = 0
            }
        }
    }

    private func updateLoyaltyDiscount(points: Int) async {
        guard let customer = customer else { return }

        do {
            let result = try await PaymentCalculatorService.shared.calculateLoyalty(
                total: subtotal,
                availablePoints: customer.loyaltyPoints ?? 0,
                pointValue: pointValue,
                pointsToRedeem: points
            )
            await MainActor.run {
                loyaltyDiscount = result.redemptionValue
            }
        } catch {
            logger.error("Failed to update loyalty discount: \(error.localizedDescription)")
        }
    }

    // MARK: - Deal Pills

    private var dealPillsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DISCOUNTS")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.horizontal, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(dealStore.availableDeals) { deal in
                        DealPill(
                            deal: deal,
                            isSelected: dealStore.selectedDealId == deal.id,
                            onTap: { dealStore.selectDeal(deal) }
                        )
                    }
                }
            }
        }
        .padding(10)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Loyalty Slider

    private func loyaltySliderSection(customer: Customer) -> some View {
        VStack(spacing: 12) {
            // Header row
            HStack {
                // Points info
                HStack(spacing: 8) {
                    Image(systemName: "star.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(tierColor(for: customer))

                    Text("\(customer.formattedLoyaltyPoints) pts")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }

                Spacer()

                // Current redemption value
                if pointsToRedeem > 0 {
                    Text("-\(CurrencyFormatter.format(loyaltyDiscount))")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Design.Colors.Semantic.success)
                        .contentTransition(.numericText())
                }
            }

            // Native iOS Slider
            if maxRedeemablePoints > 0 {
                VStack(spacing: 8) {
                    // Slider with manual labels for better rendering
                    HStack(spacing: 12) {
                        Text("0")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.5))
                            .frame(width: 24, alignment: .trailing)

                        Slider(
                            value: Binding(
                                get: { Double(pointsToRedeem) },
                                set: { pointsToRedeem = Int($0) }
                            ),
                            in: 0...Double(maxRedeemablePoints),
                            step: 1
                        )
                        .tint(tierColor(for: customer))

                        Text("\(maxRedeemablePoints)")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.5))
                            .frame(width: 40, alignment: .leading)
                    }

                    // Quick action buttons
                    HStack(spacing: 8) {
                        QuickPointsButton(
                            title: "None",
                            isSelected: pointsToRedeem == 0,
                            color: tierColor(for: customer)
                        ) {
                            withAnimation(.spring(response: 0.3)) {
                                pointsToRedeem = 0
                            }
                            Haptics.light()
                        }

                        QuickPointsButton(
                            title: "Half",
                            isSelected: pointsToRedeem == maxRedeemablePoints / 2,
                            color: tierColor(for: customer)
                        ) {
                            withAnimation(.spring(response: 0.3)) {
                                pointsToRedeem = maxRedeemablePoints / 2
                            }
                            Haptics.light()
                        }

                        QuickPointsButton(
                            title: "All",
                            isSelected: pointsToRedeem == maxRedeemablePoints,
                            color: tierColor(for: customer)
                        ) {
                            withAnimation(.spring(response: 0.3)) {
                                pointsToRedeem = maxRedeemablePoints
                            }
                            Haptics.light()
                        }

                        Spacer()

                        // Points being used
                        Text("\(pointsToRedeem) pts")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(tierColor(for: customer))
                            .contentTransition(.numericText())
                    }
                }
            }
        }
        .padding(12)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Helpers

    private func tierColor(for customer: Customer) -> Color {
        switch customer.loyaltyTier?.lowercased() {
        case "gold": return Color(red: 255/255, green: 215/255, blue: 0/255)
        case "platinum": return Color(red: 180/255, green: 180/255, blue: 200/255)
        case "diamond": return Color(red: 185/255, green: 242/255, blue: 255/255)
        default: return Design.Colors.Semantic.accent
        }
    }
}

// MARK: - Quick Points Button

private struct QuickPointsButton: View {
    let title: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isSelected ? .white : .white.opacity(0.6))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isSelected ? color.opacity(0.4) : Color.white.opacity(0.1))
                )
                .overlay(
                    Capsule()
                        .strokeBorder(isSelected ? color.opacity(0.6) : Color.clear, lineWidth: 1)
                )
                .contentShape(Capsule())
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - Deal Pill

struct DealPill: View {
    let deal: Deal
    let isSelected: Bool
    let onTap: () -> Void

    private var pillColor: Color {
        switch deal.discountType {
        case .percentage: return Color(red: 124/255, green: 58/255, blue: 237/255)  // Purple
        case .fixed: return Color(red: 16/255, green: 185/255, blue: 129/255)       // Green
        case .bogo: return Color(red: 245/255, green: 158/255, blue: 11/255)        // Amber
        }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                // Checkmark when selected
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Design.Colors.Semantic.success)
                }

                // Deal name
                Text(deal.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                // Badge with discount value
                Text(deal.badgeText)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(isSelected ? .white : pillColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(isSelected ? pillColor : pillColor.opacity(0.2))
                    )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isSelected ? .white.opacity(0.15) : .white.opacity(0.05), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack(spacing: 20) {
            DockDiscountSection(
                customer: Customer(
                    id: UUID(),
                    platformUserId: UUID(),
                    storeId: UUID(),
                    firstName: "John",
                    middleName: nil,
                    lastName: "Smith",
                    email: "john@example.com",
                    phone: "5551234567",
                    dateOfBirth: "1990-01-15",
                    avatarUrl: nil,
                    streetAddress: "123 Main St",
                    city: "Denver",
                    state: "CO",
                    postalCode: "80202",
                    driversLicenseNumber: "123456789",
                    idVerified: true,
                    isActive: true,
                    loyaltyPoints: 1500,
                    loyaltyTier: "gold",
                    totalSpent: Decimal(2500),
                    totalOrders: 25,
                    lifetimeValue: Decimal(2500),
                    emailConsent: true,
                    smsConsent: true,
                    createdAt: Date(),
                    updatedAt: Date()
                ),
                subtotal: Decimal(85.50),
                pointsToRedeem: .constant(500),
                pointValue: Decimal(0.01),
                dealStore: DealStore.shared
            )
            .padding()
        }
    }
}
