//
//  CheckoutPromotionsSection.swift
//  Whale
//
//  Promotions section for checkout: coupon code picker, deal selection, and affiliate codes.
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
    @State private var showCouponPicker = false
    @State private var manualCouponEntry = false

    var body: some View {
        VStack(spacing: 10) {
            // Coupon / Promo Code Section
            couponSection

            // Available Deals (manual select by staff)
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
            if appliedDeal != nil {
                // Applied coupon badge
                appliedCouponBadge
            } else if manualCouponEntry {
                // Manual code entry
                manualCouponInput
            } else {
                // Coupon picker + manual entry toggle
                couponPickerRow
            }

            if let error = couponError {
                Text(error)
                    .font(Design.Typography.caption2)
                    .foregroundStyle(Design.Colors.Semantic.error)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
            }
        }
    }

    // Picker row: tap to open coupon list or type manually
    @ViewBuilder
    private var couponPickerRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "ticket")
                .font(Design.Typography.footnote)
                .foregroundStyle(Design.Colors.Semantic.accent)
                .accessibilityHidden(true)

            if dealStore.couponDeals.isEmpty {
                // No coupon deals available — just show text field
                TextField("Promo code", text: $couponCode)
                    .font(Design.Typography.footnote)
                    .textInputAutocapitalization(.characters)
                    .submitLabel(.go)
                    .onSubmit { Task { await applyCoupon() } }

                applyButton
            } else {
                // Show picker button
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        showCouponPicker.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text("Apply Promo Code")
                            .font(Design.Typography.footnote).fontWeight(.medium)
                            .foregroundStyle(Design.Colors.Text.primary)

                        Spacer()

                        Text("\(dealStore.couponDeals.count)")
                            .font(Design.Typography.caption2Rounded).fontWeight(.bold)
                            .foregroundStyle(Design.Colors.Text.disabled)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Design.Colors.Glass.thin, in: Capsule())

                        Image(systemName: showCouponPicker ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Design.Colors.Text.placeholder)
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))

        // Expandable coupon list
        if showCouponPicker {
            VStack(spacing: 4) {
                ForEach(dealStore.couponDeals) { deal in
                    couponDealRow(deal)
                }

                // Manual entry option
                Button {
                    withAnimation(.spring(response: 0.25)) {
                        manualCouponEntry = true
                        showCouponPicker = false
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "keyboard")
                            .font(.system(size: 14))
                            .foregroundStyle(Design.Colors.Text.placeholder)

                        Text("Enter code manually")
                            .font(Design.Typography.caption1).fontWeight(.medium)
                            .foregroundStyle(Design.Colors.Text.disabled)

                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private func couponDealRow(_ deal: Deal) -> some View {
        Button {
            Task { await selectCouponDeal(deal) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "ticket.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Design.Colors.Semantic.accent)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(deal.couponCode ?? deal.name)
                        .font(Design.Typography.footnote).fontWeight(.bold)
                        .foregroundStyle(Design.Colors.Text.primary)

                    if deal.couponCode != nil {
                        Text(deal.name)
                            .font(Design.Typography.caption2)
                            .foregroundStyle(Design.Colors.Text.disabled)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Text(deal.badgeText)
                    .font(Design.Typography.caption1Rounded).fontWeight(.bold)
                    .foregroundStyle(Design.Colors.Semantic.accent)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    // Applied coupon badge
    private var appliedCouponBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(Design.Colors.Semantic.success)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(appliedDeal?.couponCode ?? appliedDeal?.name ?? "Coupon")
                    .font(Design.Typography.footnote).fontWeight(.bold)
                    .foregroundStyle(Design.Colors.Text.primary)

                Text(appliedDeal?.discountDisplayValue ?? "")
                    .font(Design.Typography.caption2).fontWeight(.medium)
                    .foregroundStyle(Design.Colors.Semantic.success)
            }

            Spacer()

            Text("-\(CurrencyFormatter.format(campaignDiscount))")
                .font(Design.Typography.calloutRounded).fontWeight(.bold)
                .foregroundStyle(Design.Colors.Semantic.success)

            Button {
                removeCoupon()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Design.Colors.Text.placeholder)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove coupon")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
    }

    // Manual coupon code entry
    private var manualCouponInput: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.25)) {
                    manualCouponEntry = false
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Design.Colors.Text.placeholder)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to coupon list")

            TextField("Enter promo code", text: $couponCode)
                .font(Design.Typography.footnote)
                .textInputAutocapitalization(.characters)
                .submitLabel(.go)
                .onSubmit { Task { await applyCoupon() } }

            applyButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
    }

    private var applyButton: some View {
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

                    Text("Staff Discounts")
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

    private func selectCouponDeal(_ deal: Deal) async {
        guard let code = deal.couponCode else { return }
        couponCode = code

        isValidatingCoupon = true
        couponError = nil

        do {
            let discount = try await DealService.calculateDiscount(dealId: deal.id, subtotal: subtotal)
            appliedDeal = deal
            campaignDiscount = discount
            withAnimation(.spring(response: 0.25)) {
                showCouponPicker = false
            }
            Haptics.success()
        } catch {
            couponError = "Failed to apply coupon"
            Haptics.error()
        }

        isValidatingCoupon = false
    }

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
                withAnimation(.spring(response: 0.25)) {
                    manualCouponEntry = false
                }
                Haptics.success()
            } else {
                couponError = "Invalid promo code"
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
        manualCouponEntry = false
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
