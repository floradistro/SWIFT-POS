//
//  CheckoutPromotionsSection.swift
//  Whale
//
//  Promotions section for checkout: coupon codes, deal selection, and affiliate codes.
//

import SwiftUI
import os.log

// MARK: - Promotions Section

struct CheckoutPromotionsSection: View {
    @ObservedObject var dealStore: DealStore
    let storeId: UUID
    let locationId: UUID?
    let subtotal: Decimal

    // Coupon code
    @Binding var couponCode: String
    @Binding var appliedDeal: Deal?
    @Binding var campaignDiscount: Decimal

    // Affiliate code
    @Binding var affiliateCode: String
    @Binding var affiliateResult: AffiliateCodeResult?
    @Binding var affiliateDiscount: Decimal

    @State private var isValidatingCoupon = false
    @State private var couponError: String?
    @State private var isValidatingAffiliate = false
    @State private var affiliateError: String?
    @State private var showDeals = false

    var body: some View {
        VStack(spacing: 10) {
            // Coupon Code Input
            couponSection

            // Available Deals (manual select)
            if !dealStore.availableDeals.isEmpty {
                dealSelectionSection
            }

            // Affiliate Code Input
            affiliateSection
        }
        .task {
            await dealStore.loadDeals(storeId: storeId, locationId: locationId)
        }
    }

    // MARK: - Coupon Section

    private var couponSection: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "ticket")
                    .font(Design.Typography.footnote)
                    .foregroundStyle(Design.Colors.Text.disabled)
                    .accessibilityHidden(true)

                TextField("Coupon code", text: $couponCode)
                    .font(Design.Typography.footnote)
                    .textInputAutocapitalization(.characters)
                    .submitLabel(.go)
                    .onSubmit { Task { await applyCoupon() } }

                if appliedDeal != nil {
                    // Applied badge
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                        Text(appliedDeal?.discountDisplayValue ?? "")
                            .font(Design.Typography.caption2).fontWeight(.bold)
                    }
                    .foregroundStyle(Design.Colors.Semantic.success)

                    Button {
                        removeCoupon()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Design.Colors.Text.placeholder)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove coupon")
                } else {
                    Button {
                        Task { await applyCoupon() }
                    } label: {
                        if isValidatingCoupon {
                            ProgressView()
                                .scaleEffect(0.6)
                        } else {
                            Text("Apply")
                                .font(Design.Typography.caption1).fontWeight(.semibold)
                                .foregroundStyle(Design.Colors.Semantic.accent)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(couponCode.isEmpty || isValidatingCoupon)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))

            if let error = couponError {
                Text(error)
                    .font(Design.Typography.caption2)
                    .foregroundStyle(Design.Colors.Semantic.error)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
            }
        }
    }

    // MARK: - Deal Selection

    private var dealSelectionSection: some View {
        VStack(spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.25)) {
                    showDeals.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "tag.fill")
                        .font(Design.Typography.footnote)
                        .foregroundStyle(Design.Colors.Semantic.accent)
                        .accessibilityHidden(true)

                    Text("Available Discounts")
                        .font(Design.Typography.footnote).fontWeight(.medium)
                        .foregroundStyle(Design.Colors.Text.primary)

                    Spacer()

                    Text("\(dealStore.availableDeals.count)")
                        .font(Design.Typography.caption2Rounded).fontWeight(.bold)
                        .foregroundStyle(Design.Colors.Text.disabled)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Design.Colors.Glass.thin, in: Capsule())

                    Image(systemName: showDeals ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Design.Colors.Text.placeholder)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
            }
            .buttonStyle(.plain)

            if showDeals {
                VStack(spacing: 4) {
                    ForEach(dealStore.availableDeals) { deal in
                        dealRow(deal)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func dealRow(_ deal: Deal) -> some View {
        let isSelected = dealStore.selectedDealId == deal.id

        return Button {
            dealStore.selectDeal(deal)
            Task { await updateCampaignDiscount() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? Design.Colors.Semantic.success : Design.Colors.Text.placeholder)

                VStack(alignment: .leading, spacing: 2) {
                    Text(deal.name)
                        .font(Design.Typography.footnote).fontWeight(.medium)
                        .foregroundStyle(Design.Colors.Text.primary)
                        .lineLimit(1)
                }

                Spacer()

                Text(deal.badgeText)
                    .font(Design.Typography.caption1Rounded).fontWeight(.bold)
                    .foregroundStyle(isSelected ? Design.Colors.Semantic.success : Design.Colors.Semantic.accent)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Design.Colors.Semantic.success.opacity(0.08))
                }
            }
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Affiliate Section

    private var affiliateSection: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "person.badge.key")
                    .font(Design.Typography.footnote)
                    .foregroundStyle(Design.Colors.Text.disabled)
                    .accessibilityHidden(true)

                TextField("Affiliate / referral code", text: $affiliateCode)
                    .font(Design.Typography.footnote)
                    .textInputAutocapitalization(.characters)
                    .submitLabel(.go)
                    .onSubmit { Task { await applyAffiliateCode() } }

                if affiliateResult != nil {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                        Text("-\(CurrencyFormatter.format(affiliateDiscount))")
                            .font(Design.Typography.caption2).fontWeight(.bold)
                    }
                    .foregroundStyle(Design.Colors.Semantic.success)

                    Button {
                        removeAffiliate()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Design.Colors.Text.placeholder)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove affiliate code")
                } else {
                    Button {
                        Task { await applyAffiliateCode() }
                    } label: {
                        if isValidatingAffiliate {
                            ProgressView()
                                .scaleEffect(0.6)
                        } else {
                            Text("Apply")
                                .font(Design.Typography.caption1).fontWeight(.semibold)
                                .foregroundStyle(Design.Colors.Semantic.accent)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(affiliateCode.isEmpty || isValidatingAffiliate)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))

            if let error = affiliateError {
                Text(error)
                    .font(Design.Typography.caption2)
                    .foregroundStyle(Design.Colors.Semantic.error)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
            }
        }
    }

    // MARK: - Actions

    private func applyCoupon() async {
        let code = couponCode.trimmingCharacters(in: .whitespaces)
        guard !code.isEmpty else { return }

        isValidatingCoupon = true
        couponError = nil

        do {
            if let deal = try await DealService.getDealByCode(code, storeId: storeId) {
                appliedDeal = deal
                let discount = try await DealService.calculateDiscount(dealId: deal.id, subtotal: subtotal)
                campaignDiscount = discount
                Haptics.success()
            } else {
                couponError = "Invalid coupon code"
                Haptics.error()
            }
        } catch {
            couponError = "Failed to validate code"
            Haptics.error()
        }

        isValidatingCoupon = false
    }

    private func removeCoupon() {
        appliedDeal = nil
        campaignDiscount = 0
        couponCode = ""
        couponError = nil
        dealStore.clearSelection()
        Haptics.light()
    }

    private func updateCampaignDiscount() async {
        if let deal = dealStore.selectedDeal {
            campaignDiscount = await dealStore.calculateDiscount(for: subtotal)
            appliedDeal = deal
        } else {
            campaignDiscount = 0
            appliedDeal = nil
        }
    }

    private func applyAffiliateCode() async {
        let code = affiliateCode.trimmingCharacters(in: .whitespaces)
        guard !code.isEmpty else { return }

        isValidatingAffiliate = true
        affiliateError = nil

        do {
            if let result = try await DealService.validateAffiliateCode(code, storeId: storeId) {
                affiliateResult = result
                affiliateDiscount = DealService.calculateAffiliateDiscount(
                    subtotal: subtotal,
                    rate: result.discountRate,
                    type: result.discountType
                )
                Haptics.success()
            } else {
                affiliateError = "Invalid affiliate code"
                Haptics.error()
            }
        } catch {
            affiliateError = "Failed to validate code"
            Haptics.error()
        }

        isValidatingAffiliate = false
    }

    private func removeAffiliate() {
        affiliateResult = nil
        affiliateDiscount = 0
        affiliateCode = ""
        affiliateError = nil
        Haptics.light()
    }
}
