//
//  CustomerComponents.swift
//  Whale
//
//  Reusable customer-related UI components.
//  Extracted from ManualCustomerEntrySheet for Apple engineering standards compliance.
//

import SwiftUI

// MARK: - CRM Stat Box (Monochrome Professional)

struct CRMStatBox: View {
    let title: String
    let value: String
    let icon: String
    var iconColor: Color = Design.Colors.Text.subtle

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(Design.Typography.callout).fontWeight(.semibold)
                .foregroundStyle(iconColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(value)
                    .font(Design.Typography.bodyRounded).fontWeight(.bold)
                    .foregroundStyle(Design.Colors.Text.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(title)
                    .font(Design.Typography.caption2).fontWeight(.medium)
                    .foregroundStyle(Design.Colors.Text.disabled)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(value)")
    }
}

// MARK: - Editable Loyalty Stat Box (with long-press)

struct EditableLoyaltyStatBox: View {
    let value: String
    var isAdjusting: Bool = false
    let onLongPress: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "star.fill")
                .font(Design.Typography.callout).fontWeight(.semibold)
                .foregroundStyle(.yellow.opacity(0.8))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                if isAdjusting {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(Design.Colors.Text.primary)
                } else {
                    Text(value)
                        .font(Design.Typography.bodyRounded).fontWeight(.bold)
                        .foregroundStyle(Design.Colors.Text.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                HStack(spacing: 4) {
                    Text("Loyalty Points")
                        .font(Design.Typography.caption2).fontWeight(.medium)
                        .foregroundStyle(Design.Colors.Text.disabled)
                    Text("• Hold")
                        .font(Design.Typography.caption2).fontWeight(.medium)
                        .foregroundStyle(Design.Colors.Text.placeholder)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
        .onLongPressGesture(minimumDuration: 0.5) {
            onLongPress()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loyalty Points: \(value)")
        .accessibilityHint("Long press to adjust points")
    }
}

// MARK: - Contact Info Row

struct ContactInfoRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(Design.Typography.footnote).fontWeight(.medium)
                .foregroundStyle(Design.Colors.Text.placeholder)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased())
                    .font(Design.Typography.caption2).fontWeight(.semibold)
                    .foregroundStyle(Design.Colors.Text.placeholder)
                    .tracking(0.5)

                Text(value)
                    .font(Design.Typography.footnote).fontWeight(.medium)
                    .foregroundStyle(Design.Colors.Text.tertiary)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value)")
    }
}

// MARK: - Order Row Compact (for Customer Detail - clickable)

struct OrderRowCompact: View {
    let order: Order
    let onTap: () -> Void

    var body: some View {
        Button {
            onTap()
        } label: {
            HStack(spacing: 12) {
                // Order number
                Text("#\(order.shortOrderNumber)")
                    .font(Design.Typography.footnoteMono).fontWeight(.bold)
                    .foregroundStyle(Design.Colors.Text.tertiary)

                // Order type icon
                Image(systemName: order.orderType.icon)
                    .font(Design.Typography.caption2).fontWeight(.medium)
                    .foregroundStyle(Design.Colors.Text.subtle)

                Spacer()

                // Date
                Text(formatOrderDate(order.createdAt))
                    .font(Design.Typography.caption1).fontWeight(.medium)
                    .foregroundStyle(Design.Colors.Text.disabled)

                // Amount
                Text(formatAmount(order.totalAmount))
                    .font(Design.Typography.footnoteRounded).fontWeight(.bold)
                    .foregroundStyle(Design.Colors.Text.primary)

                // Status text (monochrome)
                Text(order.status.displayName)
                    .font(Design.Typography.caption2).fontWeight(.semibold)
                    .foregroundStyle(Design.Colors.Text.disabled)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Design.Colors.Glass.thick, in: .capsule)

                // Chevron to indicate tappable
                Image(systemName: "chevron.right")
                    .font(Design.Typography.caption2).fontWeight(.semibold)
                    .foregroundStyle(Design.Colors.Text.placeholder)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(OrderRowButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Order \(order.shortOrderNumber), \(formatAmount(order.totalAmount)), \(order.status.displayName)")
    }

    private func formatOrderDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }

    private func formatAmount(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 2
        return formatter.string(from: amount as NSDecimalNumber) ?? "$0"
    }
}

// MARK: - Order Row Button Style (subtle highlight on press)

struct OrderRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Design.Colors.Glass.thin : .clear)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Customer Row (Monochrome Liquid Glass)

struct CustomerRow: View {
    let customer: Customer
    let onSelect: () -> Void
    var onViewProfile: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            // Main content - tappable to view profile (or select if no profile handler)
            Button {
                Haptics.light()
                if let viewProfile = onViewProfile {
                    viewProfile()
                } else {
                    onSelect()
                }
            } label: {
                HStack(spacing: 12) {
                    // Monochrome avatar
                    ZStack {
                        Circle()
                            .fill(Design.Colors.Glass.thick)
                            .frame(width: 44, height: 44)

                        Text(customer.initials)
                            .font(Design.Typography.subhead).fontWeight(.bold)
                            .foregroundStyle(Design.Colors.Text.tertiary)
                    }

                    // Customer info
                    VStack(alignment: .leading, spacing: 3) {
                        Text(customer.displayName)
                            .font(Design.Typography.subhead).fontWeight(.semibold)
                            .foregroundStyle(Design.Colors.Text.primary)
                            .lineLimit(1)

                        HStack(spacing: 8) {
                            if let phone = customer.formattedPhone {
                                Text(phone)
                                    .font(Design.Typography.caption1).fontWeight(.medium)
                                    .foregroundStyle(Design.Colors.Text.subtle)
                            } else if let email = customer.email, !email.isEmpty {
                                Text(email)
                                    .font(Design.Typography.caption1).fontWeight(.medium)
                                    .foregroundStyle(Design.Colors.Text.subtle)
                                    .lineLimit(1)
                            }
                        }
                    }

                    Spacer(minLength: 4)

                    // Stats badges
                    HStack(spacing: 6) {
                        // Loyalty points badge (always show if customer has points field)
                        if let points = customer.loyaltyPoints {
                            HStack(spacing: 2) {
                                Image(systemName: "star.fill")
                                    .font(Design.Typography.caption2).fontWeight(.bold)
                                Text("\(points)")
                                    .font(Design.Typography.caption2Rounded).fontWeight(.bold)
                            }
                            .foregroundStyle(points >= 0 ? .yellow.opacity(0.8) : .red.opacity(0.7))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Design.Colors.Glass.regular, in: .capsule)
                        }

                        if let orders = customer.totalOrders, orders > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: "bag.fill")
                                    .font(Design.Typography.caption2).fontWeight(.bold)
                                Text("\(orders)")
                                    .font(Design.Typography.caption2Rounded).fontWeight(.bold)
                            }
                            .foregroundStyle(Design.Colors.Text.disabled)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Design.Colors.Glass.regular, in: .capsule)
                        }
                    }

                    // Quick select button (only if profile view is available)
                    if onViewProfile != nil {
                        Button {
                            Haptics.medium()
                            onSelect()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(Design.Typography.title2).fontWeight(.medium)
                                .foregroundStyle(Design.Colors.Text.disabled)
                                .frame(width: 44, height: 44)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Select \(customer.displayName)")
                    }

                    // Chevron inline with the row
                    Image(systemName: "chevron.right")
                        .font(Design.Typography.footnote).fontWeight(.semibold)
                        .foregroundStyle(Design.Colors.Text.placeholder)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                // CRITICAL: contentShape INSIDE the label makes entire row tappable
                .contentShape(RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(ScaleButtonStyle())
            // iOS 26: .glassEffect provides proper interactive hit testing in sheets
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
        }
    }
}

// MARK: - ScannedID Extensions

extension ScannedID {
    var initials: String {
        let first = firstName?.first.map(String.init) ?? ""
        let last = lastName?.first.map(String.init) ?? ""
        return (first + last).uppercased()
    }
}
