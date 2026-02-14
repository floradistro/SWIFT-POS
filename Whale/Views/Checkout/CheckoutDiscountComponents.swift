//
//  CheckoutDiscountComponents.swift
//  Whale
//
//  Line item discount overlay and related components for checkout.
//  Extracted from CheckoutSheet for Apple engineering standards compliance.
//

import SwiftUI

// MARK: - Line Item Discount Overlay

struct LineItemDiscountOverlay: View {
    let item: CartItem?
    @Binding var isPresented: Bool
    let isMultiWindowSession: Bool
    let windowSession: POSWindowSession?
    let posStore: POSStore
    let onRemoveItem: (CartItem) async -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.3)) {
                        isPresented = false
                    }
                }

            // Glass menu
            if let item = item {
                discountMenu(for: item)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isPresented)
    }

    private func discountMenu(for item: CartItem) -> some View {
        VStack(spacing: 0) {
            // Header with item info
            VStack(spacing: 4) {
                Text(item.productName)
                    .font(Design.Typography.subhead).fontWeight(.semibold)
                    .foregroundStyle(Design.Colors.Text.primary)
                    .lineLimit(1)

                Text(CurrencyFormatter.format(item.originalLineTotal))
                    .font(Design.Typography.footnoteRounded).fontWeight(.medium)
                    .foregroundStyle(Design.Colors.Text.disabled)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider().background(Design.Colors.Border.strong)

            // Discount options
            VStack(spacing: 0) {
                // Custom Price
                discountMenuRow(
                    icon: "dollarsign",
                    title: "Set Price",
                    subtitle: "Custom amount"
                ) {
                    showDiscountInput(type: .customPrice, for: item)
                }

                Divider().background(Design.Colors.Border.regular).padding(.leading, 48)

                // Percentage Off
                discountMenuRow(
                    icon: "percent",
                    title: "Percentage Off",
                    subtitle: "e.g. 10%, 20%"
                ) {
                    showDiscountInput(type: .percentage, for: item)
                }

                Divider().background(Design.Colors.Border.regular).padding(.leading, 48)

                // Flat Amount Off
                discountMenuRow(
                    icon: "minus.circle",
                    title: "Amount Off",
                    subtitle: "e.g. $5, $10"
                ) {
                    showDiscountInput(type: .flatAmount, for: item)
                }
            }

            // Remove discount (if exists)
            if item.discountAmount > 0 {
                Divider().background(Design.Colors.Border.strong)

                Button {
                    removeLineItemDiscount(for: item)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(Design.Typography.footnote).fontWeight(.medium)
                            .frame(width: 20)

                        Text("Remove Discount")
                            .font(Design.Typography.subhead).fontWeight(.medium)

                        Spacer()

                        Text("+\(CurrencyFormatter.format(item.discountAmount))")
                            .font(Design.Typography.footnoteRounded).fontWeight(.medium)
                    }
                    .foregroundStyle(Design.Colors.Semantic.warning)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            // Remove from cart
            Divider().background(Design.Colors.Border.strong)

            Button {
                Task {
                    await onRemoveItem(item)
                }
                withAnimation(.spring(response: 0.3)) {
                    isPresented = false
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "trash")
                        .font(Design.Typography.footnote).fontWeight(.medium)
                        .frame(width: 20)

                    Text("Remove from Cart")
                        .font(Design.Typography.subhead).fontWeight(.medium)

                    Spacer()
                }
                .foregroundStyle(Design.Colors.Semantic.error)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(width: sizeClass == .compact ? min(280, UIScreen.main.bounds.width - 48) : 280)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
    }

    private func discountMenuRow(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(Design.Typography.footnote).fontWeight(.medium)
                    .foregroundStyle(Design.Colors.Text.quaternary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Design.Typography.subhead).fontWeight(.medium)
                        .foregroundStyle(Design.Colors.Text.primary)

                    Text(subtitle)
                        .font(Design.Typography.caption2)
                        .foregroundStyle(Design.Colors.Text.subtle)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(Design.Typography.caption1).fontWeight(.semibold)
                    .foregroundStyle(Design.Colors.Text.placeholder)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(subtitle)")
    }

    private enum DiscountInputType {
        case customPrice, percentage, flatAmount
    }

    private func showDiscountInput(type: DiscountInputType, for item: CartItem) {
        withAnimation(.spring(response: 0.3)) {
            isPresented = false
        }

        Task { @MainActor in try? await Task.sleep(for: .seconds(0.15));
            let (title, placeholder, message): (String, String, String) = {
                switch type {
                case .customPrice:
                    return ("Set Price", "Enter price", "New price for \(item.productName)")
                case .percentage:
                    return ("Percentage Off", "Enter %", "Discount for \(item.productName)")
                case .flatAmount:
                    return ("Amount Off", "Enter $", "Discount for \(item.productName)")
                }
            }()

            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)

            alert.addTextField { textField in
                textField.placeholder = placeholder
                textField.keyboardType = .decimalPad
                textField.font = .systemFont(ofSize: 24, weight: .semibold)
                textField.textAlignment = .center
            }

            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            alert.addAction(UIAlertAction(title: "Apply", style: .default) { _ in
                guard let text = alert.textFields?.first?.text,
                      let value = Decimal(string: text), value > 0 else { return }

                Task {
                    switch type {
                    case .customPrice:
                        // Calculate discount as difference from original
                        let discount = item.originalLineTotal - value
                        if discount > 0 {
                            await applyDiscount(itemId: item.id, type: .fixed, value: discount)
                        }
                    case .percentage:
                        await applyDiscount(itemId: item.id, type: .percentage, value: value)
                    case .flatAmount:
                        await applyDiscount(itemId: item.id, type: .fixed, value: value)
                    }
                }
            })

            presentAlert(alert)
        }
    }

    private func applyDiscount(itemId: UUID, type: DiscountType, value: Decimal) async {
        if isMultiWindowSession {
            await windowSession?.applyManualDiscount(itemId: itemId, type: type, value: value)
        } else {
            posStore.applyManualDiscount(itemId: itemId, type: ManualDiscountType(rawValue: type.rawValue) ?? .fixed, value: value)
        }
    }

    private func presentAlert(_ alert: UIAlertController) {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            var topVC = rootVC
            while let presented = topVC.presentedViewController {
                topVC = presented
            }
            topVC.present(alert, animated: true)
        }
    }

    private func removeLineItemDiscount(for item: CartItem) {
        Task {
            if isMultiWindowSession {
                await windowSession?.applyManualDiscount(itemId: item.id, type: .fixed, value: 0)
            } else {
                posStore.removeManualDiscount(itemId: item.id)
            }
            withAnimation(.spring(response: 0.3)) {
                isPresented = false
            }
        }
    }
}

// MARK: - Checkout Cart Item Row

struct CheckoutCartItemRow: View {
    let item: CartItem
    let index: Int
    let isMultiWindowSession: Bool
    let windowSession: POSWindowSession?
    let posStore: POSStore
    let onLongPress: (CartItem) -> Void
    let onRemoveItem: (CartItem) async -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text("\(item.quantity)×")
                .font(Design.Typography.caption1Rounded).fontWeight(.bold)
                .foregroundStyle(Design.Colors.Text.subtle)
                .frame(width: 24, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.productName)
                    .font(Design.Typography.footnote).fontWeight(.medium)
                    .foregroundStyle(Design.Colors.Text.primary)
                    .lineLimit(1)

                // Show discount badge if item has discount
                if item.discountAmount > 0 {
                    Text("-\(CurrencyFormatter.format(item.discountAmount))")
                        .font(Design.Typography.caption2).fontWeight(.semibold)
                        .foregroundStyle(Design.Colors.Semantic.success)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(CurrencyFormatter.format(item.lineTotal))
                    .font(Design.Typography.footnoteRounded).fontWeight(.semibold)
                    .foregroundStyle(Design.Colors.Text.disabled)

                // Show original price if discounted
                if item.discountAmount > 0 {
                    Text(CurrencyFormatter.format(item.originalLineTotal))
                        .font(Design.Typography.caption2).fontWeight(.medium)
                        .foregroundStyle(Design.Colors.Text.placeholder)
                        .strikethrough()
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.quantity) times \(item.productName), \(CurrencyFormatter.format(item.lineTotal))\(item.discountAmount > 0 ? ", discounted" : "")")
        .accessibilityHint("Long press for discount options")
        .onLongPressGesture(minimumDuration: 0.4, maximumDistance: 10) {
            Haptics.medium()
            onLongPress(item)
        }
        .contextMenu {
            contextMenuContent
        }
    }

    @ViewBuilder
    private var contextMenuContent: some View {
        // Percentage discounts
        Menu {
            ForEach([5, 10, 15, 20, 25, 30, 50], id: \.self) { percent in
                Button {
                    Task {
                        await applyDiscount(itemId: item.id, type: .percentage, value: Decimal(percent))
                    }
                } label: {
                    Label("\(percent)% off", systemImage: "percent")
                }
            }
        } label: {
            Label("Percentage Off", systemImage: "percent")
        }

        // Fixed amount discounts
        Menu {
            ForEach([1, 2, 5, 10, 20], id: \.self) { amount in
                Button {
                    Task {
                        await applyDiscount(itemId: item.id, type: .fixed, value: Decimal(amount))
                    }
                } label: {
                    Label("$\(amount) off", systemImage: "dollarsign")
                }
            }
        } label: {
            Label("Amount Off", systemImage: "dollarsign.circle")
        }

        // Custom price
        Button {
            onLongPress(item)
        } label: {
            Label("Set Custom Price", systemImage: "dollarsign.square")
        }

        // Remove discount (if exists)
        if item.discountAmount > 0 {
            Divider()
            Button(role: .destructive) {
                Task {
                    if isMultiWindowSession {
                        await windowSession?.applyManualDiscount(itemId: item.id, type: .fixed, value: 0)
                    } else {
                        posStore.removeManualDiscount(itemId: item.id)
                    }
                }
            } label: {
                Label("Remove Discount", systemImage: "xmark.circle")
            }
        }

        Divider()

        // Remove item from cart
        Button(role: .destructive) {
            Haptics.medium()
            Task {
                await onRemoveItem(item)
            }
        } label: {
            Label("Remove from Cart", systemImage: "trash")
        }
    }

    private func applyDiscount(itemId: UUID, type: DiscountType, value: Decimal) async {
        if isMultiWindowSession {
            await windowSession?.applyManualDiscount(itemId: itemId, type: type, value: value)
        } else {
            posStore.applyManualDiscount(itemId: itemId, type: ManualDiscountType(rawValue: type.rawValue) ?? .fixed, value: value)
        }
    }
}
