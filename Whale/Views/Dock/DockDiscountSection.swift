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
        VStack(spacing: 8) {
            // Points info row
            HStack(spacing: 0) {
                // Available balance
                HStack(spacing: 4) {
                    Text("Balance")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))

                    Text("\(customer.loyaltyPoints ?? 0)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                }

                Spacer()

                // Redeeming (center)
                if pointsToRedeem > 0 {
                    HStack(spacing: 4) {
                        Text("Using")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.4))

                        Text("\(pointsToRedeem)")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                    }

                    Spacer()
                }

                // Remaining or discount
                if pointsToRedeem > 0 {
                    HStack(spacing: 4) {
                        Text("-\(CurrencyFormatter.format(loyaltyDiscount))")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                    }
                } else {
                    Text("pts")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }

            // Slider
            if maxRedeemablePoints > 0 {
                Slider(
                    value: Binding(
                        get: { Double(pointsToRedeem) },
                        set: { pointsToRedeem = Int($0) }
                    ),
                    in: 0...Double(maxRedeemablePoints),
                    step: 1
                )
                .tint(.white.opacity(0.7))
            }
        }
        .padding(10)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
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
            // Preview with points
            DockDiscountSection(
                customer: Customer(
                    id: UUID(),
                    platformUserId: UUID(),
                    storeId: UUID(),
                    firstName: "Fahad",
                    middleName: nil,
                    lastName: "Khan",
                    email: "fahad@cwscommercial.com",
                    phone: "8283204633",
                    dateOfBirth: "1990-01-15",
                    avatarUrl: nil,
                    streetAddress: "310 Ogdon Dr",
                    city: "Hendersonville",
                    state: "NC",
                    postalCode: "287925861",
                    driversLicenseNumber: "000038472511",
                    idVerified: true,
                    isActive: true,
                    loyaltyPoints: 25000,
                    loyaltyTier: "bronze",
                    totalSpent: Decimal(24218.56),
                    totalOrders: 726,
                    lifetimeValue: Decimal(24218.56),
                    emailConsent: false,
                    smsConsent: false,
                    createdAt: Date(),
                    updatedAt: Date()
                ),
                subtotal: Decimal(100.00),
                pointsToRedeem: .constant(0),
                pointValue: Decimal(0.01),
                dealStore: DealStore.shared
            )
            .padding()
        }
    }
}
