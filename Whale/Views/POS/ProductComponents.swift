//
//  ProductComponents.swift
//  Whale
//
//  Product UI components used in POSMainView - grid, list, cart items.
//

import SwiftUI

// MARK: - Grid Card Press Style

/// Native iOS-style press animation for grid cards
/// Provides subtle scale + opacity feedback like iOS app icons
struct GridCardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Native iOS-style press animation for list rows
/// Subtle scale + opacity with haptic feedback
struct ListRowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .background(
                configuration.isPressed ? Design.Colors.Glass.regular : Color.clear
            )
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed {
                    Haptics.light()
                }
            }
    }
}

// MARK: - Product Grid Card

struct ProductGridCard: View {
    @EnvironmentObject private var session: SessionObserver

    let product: Product
    let isSelected: Bool
    let isMultiSelectMode: Bool
    var showRightLine: Bool = true
    var showBottomLine: Bool = true
    let onTap: () -> Void
    let onShowTierSelector: (() -> Void)?
    let onLongPress: (() -> Void)?
    let onAddToCart: (() -> Void)?
    let onPrintLabels: (() -> Void)?
    let onSelectMultiple: (() -> Void)?
    let onShowDetail: (() -> Void)?

    private var hasTiers: Bool {
        product.hasTieredPricing
    }

    private var storeLogoUrl: URL? {
        session.store?.fullLogoUrl
    }

    var body: some View {
        Button {
            Haptics.light()
            onTap()
        } label: {
            VStack(spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    CachedAsyncImage(
                        url: product.iconUrl,
                        placeholderLogoUrl: storeLogoUrl,
                        dimAmount: 0
                    )
                    .aspectRatio(1, contentMode: .fill)
                    .overlay(Color.black.opacity(0.15))

                    if isMultiSelectMode {
                        ZStack {
                            Circle()
                                .fill(isSelected ? Design.Colors.Semantic.accent : Design.Colors.backgroundPrimary.opacity(0.5))
                                .frame(width: 24, height: 24)

                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(Design.Typography.caption1).fontWeight(.bold)
                                    .foregroundStyle(Design.Colors.Text.primary)
                            }
                        }
                        .padding(8)
                        .scaleEffect(isSelected ? 1.0 : 0.9)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(product.name)
                        .font(Design.Typography.footnote).fontWeight(.medium)
                        .foregroundStyle(Design.Colors.Text.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(product.categoryName ?? " ")
                        .font(Design.Typography.caption2)
                        .foregroundStyle(Design.Colors.Text.disabled)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                .padding(10)
                .background(Design.Colors.backgroundPrimary.opacity(0.7))
            }
            .overlay(alignment: .trailing) {
                if showRightLine {
                    Rectangle()
                        .fill(Design.Colors.Glass.ultraThick)
                        .frame(width: 0.5)
                }
            }
            .overlay(alignment: .bottom) {
                if showBottomLine {
                    Rectangle()
                        .fill(Design.Colors.Glass.ultraThick)
                        .frame(height: 0.5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(GridCardPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(product.name), \(product.categoryName ?? ""), \(product.inStock ? "in stock" : "out of stock")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(isMultiSelectMode ? "Double tap to toggle selection" : (hasTiers ? "Double tap to select size" : "Double tap to add to cart"))
        .contextMenu {
            Button {
                Haptics.light()
                onAddToCart?()
            } label: {
                Label("Add to Cart", systemImage: "cart.badge.plus")
            }

            if hasTiers {
                Button {
                    Haptics.light()
                    onShowTierSelector?()
                } label: {
                    Label("Select Size", systemImage: "scalemass")
                }
            }

            Divider()

            Button {
                Haptics.light()
                onPrintLabels?()
            } label: {
                Label("Print Labels", systemImage: "printer.fill")
            }

            Button {
                Haptics.light()
                onShowDetail?()
            } label: {
                Label("View Details", systemImage: "info.circle")
            }

            Button {
                Haptics.light()
                onSelectMultiple?()
            } label: {
                Label("Select Multiple", systemImage: "checkmark.circle")
            }
        }
    }
}

// MARK: - Stock Badge

/// Compact stock indicator badge
private struct StockBadge: View {
    let quantity: Int

    private var color: Color {
        if quantity <= 0 { return Design.Colors.Semantic.error }
        if quantity <= 5 { return Design.Colors.Semantic.error }
        if quantity <= 15 { return Design.Colors.Semantic.warning }
        return Design.Colors.Text.disabled
    }

    private var isLow: Bool {
        quantity <= 15
    }

    var body: some View {
        HStack(spacing: 4) {
            if quantity <= 0 {
                Text("OUT")
                    .font(Design.Typography.caption2).fontWeight(.bold)
            } else {
                Image(systemName: "shippingbox.fill")
                    .font(Design.Typography.caption2)
                Text("\(quantity)")
                    .font(Design.Typography.caption1Rounded).fontWeight(.semibold)
            }
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(color.opacity(isLow ? 0.15 : 0.08))
        )
    }
}

// Note: ProductAnalyticsInline, SparklineChart, StockPill, DailyBarChart,
// StockLevelBar, ProductInsightsPanel, ShimmerModifier moved to ProductInsightsComponents.swift

// MARK: - Cart Item Row

struct CartItemRow: View {
    let item: CartItem
    let onRemove: () -> Void
    let onUpdateQuantity: (Int) -> Void

    var body: some View {
        HStack(spacing: Design.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.productName)
                    .font(Design.Typography.subhead)
                    .foregroundStyle(Design.Colors.Text.primary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    if let variantName = item.variantName {
                        Text(variantName)
                            .font(Design.Typography.caption2).fontWeight(.bold)
                            .foregroundStyle(Design.Colors.Text.primary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Design.Colors.Semantic.warning.opacity(0.4)))
                    }

                    if let tierLabel = item.tierLabel {
                        Text(tierLabel)
                            .font(Design.Typography.caption2).fontWeight(.semibold)
                            .foregroundStyle(Design.Colors.Text.primary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Design.Colors.Semantic.accent.opacity(0.3)))
                    }

                    if let sku = item.sku {
                        Text(sku)
                            .font(Design.Typography.caption2)
                            .foregroundStyle(Design.Colors.Text.ghost)
                    }
                }
            }

            Spacer()

            HStack(spacing: Design.Spacing.xs) {
                Button {
                    Haptics.light()
                    onUpdateQuantity(item.quantity - 1)
                } label: {
                    Image(systemName: "minus")
                        .font(Design.Typography.caption1).fontWeight(.semibold)
                        .foregroundStyle(Design.Colors.Text.tertiary)
                        .frame(width: 28, height: 28)
                        .background(Design.Colors.Glass.thin)
                        .clipShape(Circle())
                        .padding(8)
                        .contentShape(Circle())
                }
                .buttonStyle(LiquidPressStyle())
                .accessibilityLabel("Decrease quantity")

                Text("\(item.quantity)")
                    .font(Design.Typography.subhead)
                    .foregroundStyle(Design.Colors.Text.primary)
                    .frame(width: 24)

                Button {
                    Haptics.light()
                    onUpdateQuantity(item.quantity + 1)
                } label: {
                    Image(systemName: "plus")
                        .font(Design.Typography.caption1).fontWeight(.semibold)
                        .foregroundStyle(Design.Colors.Text.tertiary)
                        .frame(width: 28, height: 28)
                        .background(Design.Colors.Glass.thin)
                        .clipShape(Circle())
                        .padding(8)
                        .contentShape(Circle())
                }
                .buttonStyle(LiquidPressStyle())
                .accessibilityLabel("Increase quantity")
            }

            Text(formatCurrency(item.lineTotal))
                .font(Design.Typography.subhead)
                .foregroundStyle(Design.Colors.Text.secondary)
                .frame(width: 70, alignment: .trailing)
        }
        .padding(Design.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.md, style: .continuous)
                .fill(Design.Colors.Glass.ultraThin)
        )
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Haptics.light()
                onRemove()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: value as NSDecimalNumber) ?? "$0.00"
    }
}

// MARK: - Category Pill

struct CategoryPill: View {
    let name: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button {
            Haptics.light()
            onTap()
        } label: {
            Text(name)
                .font(Design.Typography.caption1).fontWeight(isSelected ? .semibold : .medium)
                .foregroundStyle(isSelected ? Design.Colors.Semantic.accentForeground : Design.Colors.Text.disabled)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    isSelected ? Design.Colors.Semantic.accent : Color.clear,
                    in: .capsule
                )
        }
        .tint(Design.Colors.Text.primary)
        .glassEffect(.regular.interactive(), in: .capsule)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Product List Row (iPhone)

/// Compact list row for products on iPhone (mobile-optimized)
struct ProductListRow: View {
    @EnvironmentObject private var session: SessionObserver

    let product: Product
    let isSelected: Bool
    let isMultiSelectMode: Bool
    let isLast: Bool
    let onTap: () -> Void
    let onLongPress: (() -> Void)?
    let onAddToCart: (() -> Void)?
    let onPrintLabels: (() -> Void)?
    let onSelectMultiple: (() -> Void)?
    let onShowDetail: (() -> Void)?

    private var storeLogoUrl: URL? {
        session.store?.fullLogoUrl
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                Haptics.light()
                onTap()
            } label: {
                HStack(spacing: 12) {
                    // Product image
                    CachedAsyncImage(
                        url: product.iconUrl,
                        placeholderLogoUrl: storeLogoUrl,
                        dimAmount: 0
                    )
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Design.Colors.Glass.regular, lineWidth: 0.5)
                    )

                    // Product info
                    VStack(alignment: .leading, spacing: 4) {
                        Text(product.name)
                            .font(Design.Typography.body).fontWeight(.medium)
                            .foregroundStyle(Design.Colors.Text.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        HStack(spacing: 6) {
                            if let category = product.categoryName {
                                Text(category)
                                    .font(Design.Typography.caption1)
                                    .foregroundStyle(Design.Colors.Text.secondary)
                            }

                            if !product.inStock {
                                Text("Out of stock")
                                    .font(Design.Typography.caption2).fontWeight(.medium)
                                    .foregroundStyle(Design.Colors.Semantic.error)
                            }
                        }
                    }

                    Spacer()

                    // Price and multi-select
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(formatPrice(product.displayPrice))
                            .font(Design.Typography.headlineRounded)
                            .foregroundStyle(Design.Colors.Text.primary)

                        if product.hasTieredPricing {
                            Text("Multiple sizes")
                                .font(Design.Typography.caption2)
                                .foregroundStyle(Design.Colors.Text.tertiary)
                        }
                    }

                    if isMultiSelectMode {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(Design.Typography.title2)
                            .foregroundStyle(isSelected ? Design.Colors.Semantic.accent : Design.Colors.Text.placeholder)
                            .scaleEffect(isSelected ? 1.0 : 0.9)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .buttonStyle(ListRowPressStyle())
            .background(isSelected ? Design.Colors.Border.subtle : Color.clear)
            .contextMenu {
                Button {
                    Haptics.light()
                    onAddToCart?()
                } label: {
                    Label("Add to Cart", systemImage: "cart.badge.plus")
                }

                Divider()

                Button {
                    Haptics.light()
                    onPrintLabels?()
                } label: {
                    Label("Print Labels", systemImage: "printer.fill")
                }

                Button {
                    Haptics.light()
                    onShowDetail?()
                } label: {
                    Label("View Details", systemImage: "info.circle")
                }

                Button {
                    Haptics.light()
                    onSelectMultiple?()
                } label: {
                    Label("Select Multiple", systemImage: "checkmark.circle")
                }
            }

            if !isLast {
                Rectangle()
                    .fill(Design.Colors.Glass.regular)
                    .frame(height: 0.5)
                    .padding(.leading, 84) // Align with text, past the image
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isSelected)
    }

    private func formatPrice(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: value as NSDecimalNumber) ?? "$0.00"
    }
}
