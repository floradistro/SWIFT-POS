//  DockTypes.swift - Shared types and enums for Dock components

import SwiftUI

// MARK: - Dock State

enum DockExpansion: Equatable {
    case collapsed      // Minimal idle state
    case idleExpanded   // Expanded idle with quick actions
    case standard       // Cart with items
    case checkout       // Full checkout flow
    case processing     // Payment in progress
    case success        // Payment complete
}

// MARK: - Payment Method

enum DockPaymentMethod: String, CaseIterable {
    case card, cash, split, multiCard, invoice

    var icon: String {
        switch self {
        case .card: return "creditcard.fill"
        case .cash: return "banknote.fill"
        case .split: return "square.split.1x2.fill"
        case .multiCard: return "creditcard.and.123"
        case .invoice: return "paperplane.fill"
        }
    }

    var label: String {
        switch self {
        case .card: return "Card"
        case .cash: return "Cash"
        case .split: return "Split"
        case .multiCard: return "2 Cards"
        case .invoice: return "Invoice"
        }
    }
}

// MARK: - Dock Sizing

struct DockSizing {
    static let tabBarHeight: CGFloat = 80
    static let cartContentHeight: CGFloat = 80
    static let customerContentHeight: CGFloat = 72  // Customer info when no items yet
    static let idleDockHeight: CGFloat = 80

    static func baseWidth() -> CGFloat {
        min(520, UIScreen.main.bounds.width - 32)
    }

    static func checkoutHeight(for paymentMethod: DockPaymentMethod, itemCount: Int, hasDeals: Bool, hasLoyalty: Bool) -> CGFloat {
        // Base height for header + payment selector + action button
        var height: CGFloat = 280

        // Add space for items (compact rows)
        let itemHeight: CGFloat = 28
        height += CGFloat(min(itemCount, 5)) * itemHeight + 20 // items container + padding

        // Add space for deals/loyalty if present
        if hasDeals || hasLoyalty {
            height += 60
        }

        // Add space for payment-specific inputs
        switch paymentMethod {
        case .card:
            height += 40
        case .cash:
            height += 100  // Cash input + suggestions
        case .split:
            height += 100
        case .multiCard:
            height += 80
        case .invoice:
            height += 160  // Email, date, notes
        }

        // Cap at reasonable screen percentage
        return min(height, UIScreen.main.bounds.height * 0.75)
    }
}

// MARK: - Scale Button Style

struct ScaleButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            // CRITICAL: Do NOT add .contentShape() here - it overrides the contentShape
            // set inside the button label and breaks hit testing in modals/sheets
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Animated Total

struct AnimatedTotal: View {
    let value: Decimal

    var body: some View {
        Text(CurrencyFormatter.format(value))
            .font(.system(size: 18, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .contentTransition(.numericText(value: Double(truncating: value as NSNumber)))
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: value)
    }
}

// MARK: - Item Chip

struct ItemChip: View {
    let item: CartItem
    let index: Int

    private var chipColor: Color {
        let colors: [Color] = [
            Design.Colors.Semantic.accent,
            Design.Colors.Semantic.success,
            Design.Colors.Semantic.warning,
            Design.Colors.Semantic.info
        ]
        return colors[index % colors.count]
    }

    var body: some View {
        Text("\(item.quantity)")
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .glassEffect(.regular, in: .circle)
    }
}

// MARK: - Bulk Action Button

struct BulkActionButton: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Button {
                Haptics.medium()
                action()
            } label: {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
            }
            .tint(.white)
            .glassEffect(.regular.interactive(), in: .circle)

            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
        }
    }
}

// MARK: - Checkout Item Row

struct CheckoutItemRow: View {
    let item: CartItem
    @ObservedObject var posStore: POSStore

    var body: some View {
        HStack {
            Text("\(item.quantity)×")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 24, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.productName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)

                if let discountText = item.discountDisplayText {
                    HStack(spacing: 4) {
                        Image(systemName: "tag.fill")
                            .font(.system(size: 8))
                        Text(discountText)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(Design.Colors.Semantic.success)
                }
            }

            if let tier = item.tierLabel {
                Text(tier)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.white.opacity(0.05), in: Capsule())
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if item.hasManualDiscount {
                    Text(CurrencyFormatter.format(item.originalLineTotal))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.4))
                        .strikethrough()
                }

                Text(CurrencyFormatter.format(item.lineTotal))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(item.hasManualDiscount ? Design.Colors.Semantic.success : .white.opacity(0.8))
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            Menu {
                ForEach([5, 10, 15, 20, 25, 30, 50], id: \.self) { percent in
                    Button {
                        Haptics.medium()
                        posStore.applyManualDiscount(itemId: item.id, type: .percentage, value: Decimal(percent))
                    } label: {
                        Label("\(percent)% off", systemImage: "percent")
                    }
                }
            } label: {
                Label("Percentage Discount", systemImage: "percent")
            }

            Menu {
                ForEach([1, 2, 5, 10, 20], id: \.self) { amount in
                    Button {
                        Haptics.medium()
                        posStore.applyManualDiscount(itemId: item.id, type: .fixed, value: Decimal(amount))
                    } label: {
                        Label("$\(amount) off", systemImage: "dollarsign")
                    }
                }
            } label: {
                Label("Fixed Discount", systemImage: "dollarsign.circle")
            }

            if item.hasManualDiscount {
                Divider()
                Button(role: .destructive) {
                    Haptics.medium()
                    posStore.removeManualDiscount(itemId: item.id)
                } label: {
                    Label("Remove Discount", systemImage: "xmark.circle")
                }
            }

            Divider()

            Button(role: .destructive) {
                Haptics.medium()
                posStore.removeFromCart(item.id)
            } label: {
                Label("Remove Item", systemImage: "trash")
            }
        }
    }
}
