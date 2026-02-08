//
//  OrderComponents.swift
//  Whale
//
//  Shared order UI components used across OrdersView and POSMainView.
//

import SwiftUI

// MARK: - Order List Row

struct OrderListRow: View {
    let order: Order
    let isMultiSelected: Bool
    let isMultiSelectMode: Bool
    let isLast: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void
    let onOpenInDock: () -> Void
    let onViewDetails: () -> Void
    let onSelectMultiple: () -> Void

    @State private var isPressed = false
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// Horizontal padding - less on compact (iPhone), more on regular (iPad)
    private var horizontalPadding: CGFloat {
        sizeClass == .compact ? 16 : 40
    }

    private var needsAttention: Bool {
        order.status == .pending || order.status == .preparing || order.paymentStatus == .pending
    }

    private var isComplete: Bool {
        order.status == .completed || order.status == .delivered
    }

    /// Status color for the center line
    private var statusColor: Color {
        if order.paymentStatus == .pending {
            return Design.Colors.Semantic.warning
        } else if needsAttention {
            return Design.Colors.Semantic.warning
        } else if isComplete {
            return Design.Colors.Semantic.success
        } else {
            return Design.Colors.Glass.regular
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                onTap()  // Haptics handled by caller if needed
            } label: {
                ZStack {
                    // Status line - centered, fades at edges
                    statusLine

                    // Content
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(order.displayCustomerName)
                                .font(Design.Typography.body).fontWeight(.medium)
                                .foregroundStyle(Design.Colors.Text.primary)
                                .lineLimit(1)

                            HStack(spacing: 6) {
                                Text("#\(order.shortOrderNumber)")
                                    .font(Design.Typography.footnoteMono)
                                    .foregroundStyle(Design.Colors.Text.subtle)

                                Text("•")
                                    .font(Design.Typography.caption2)
                                    .foregroundStyle(Design.Colors.Text.ghost)

                                Text(order.orderType.displayName)
                                    .font(Design.Typography.footnote)
                                    .foregroundStyle(Design.Colors.Text.subtle)

                                Text("•")
                                    .font(Design.Typography.caption2)
                                    .foregroundStyle(Design.Colors.Text.ghost)

                                Text(order.timeAgo)
                                    .font(Design.Typography.footnote)
                                    .foregroundStyle(Design.Colors.Text.subtle)
                            }
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            Text(order.formattedTotal)
                                .font(Design.Typography.headlineRounded)
                                .foregroundStyle(Design.Colors.Text.primary)

                            OrderListStatusPill(order: order)
                        }

                        if isMultiSelectMode {
                            Image(systemName: isMultiSelected ? "checkmark.circle.fill" : "circle")
                                .font(Design.Typography.title2)
                                .foregroundStyle(isMultiSelected ? Design.Colors.Semantic.accent : Design.Colors.Text.placeholder)
                                .scaleEffect(isMultiSelected ? 1.0 : 0.9)
                                .accessibilityHidden(true)
                        }
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.vertical, 14)
                }
                .background(isMultiSelected ? Design.Colors.Border.subtle : Color.clear)
            }
            .buttonStyle(OrderListRowButtonStyle(isPressed: $isPressed))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(order.displayCustomerName), order \(order.shortOrderNumber), \(order.formattedTotal), \(order.status.displayName)")
            .accessibilityAddTraits(isMultiSelected ? .isSelected : [])
            .contextMenu {
                Button {
                    onOpenInDock()
                } label: {
                    Label("Open in Dock", systemImage: "dock.arrow.down.rectangle")
                }

                Button {
                    onViewDetails()
                } label: {
                    Label("View Details", systemImage: "info.circle")
                }

                Divider()

                Button {
                    onSelectMultiple()
                } label: {
                    Label("Select Multiple", systemImage: "checkmark.circle")
                }
            }

            if !isLast {
                Rectangle()
                    .fill(Design.Colors.Glass.regular)
                    .frame(height: 0.5)
                    .padding(.horizontal, horizontalPadding)
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isMultiSelected)
    }

    /// Sleek status line that connects left and right content (iPad only)
    @ViewBuilder
    private var statusLine: some View {
        if sizeClass != .compact {
            GeometryReader { geo in
                let lineWidth = geo.size.width * 0.35

                Rectangle()
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: statusColor.opacity(0), location: 0),
                                .init(color: statusColor.opacity(0.4), location: 0.3),
                                .init(color: statusColor.opacity(0.4), location: 0.7),
                                .init(color: statusColor.opacity(0), location: 1)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: lineWidth, height: 1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
    }
}

// MARK: - Order List Row Button Style

struct OrderListRowButtonStyle: ButtonStyle {
    @Binding var isPressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                isPressed = pressed
            }
    }
}

// MARK: - Order List Status Pill

struct OrderListStatusPill: View {
    let order: Order

    private var needsAction: Bool {
        order.paymentStatus == .pending || order.status == .pending || order.status == .preparing
    }

    private var isComplete: Bool {
        order.status == .completed || order.status == .delivered
    }

    var body: some View {
        HStack(spacing: 5) {
            if needsAction {
                Circle()
                    .fill(Design.Colors.Semantic.warning)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
            } else if isComplete {
                Circle()
                    .fill(Design.Colors.Semantic.success)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
            }

            Text(statusText)
                .font(Design.Typography.caption2).fontWeight(.medium)
                .foregroundStyle(needsAction ? Design.Colors.Semantic.warning : (isComplete ? Design.Colors.Semantic.success : Design.Colors.Text.quaternary))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(needsAction || isComplete ? Design.Colors.Glass.thick : .clear, in: Capsule())
    }

    private var statusText: String {
        if order.paymentStatus == .pending {
            return "Unpaid"
        }
        return order.status.displayName
    }
}

// MARK: - Order Status Badge

struct OrderStatusBadge: View {
    let status: OrderStatus

    var body: some View {
        Text(status.displayName)
            .font(Design.Typography.caption2).fontWeight(.semibold)
            .foregroundStyle(statusColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor.opacity(0.2), in: Capsule())
    }

    private var statusColor: Color {
        switch status.color {
        case "amber": return Design.Colors.Semantic.warning
        case "blue": return Design.Colors.Semantic.accent
        case "green", "emerald": return Design.Colors.Semantic.success
        case "sky": return Design.Colors.Semantic.info
        case "red": return Design.Colors.Semantic.error
        default: return Design.Colors.Text.disabled
        }
    }
}

// MARK: - Payment Status Badge

struct PaymentStatusBadge: View {
    let status: PaymentStatus

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)

            Text(status.displayName)
                .font(Design.Typography.caption2).fontWeight(.medium)
                .foregroundStyle(Design.Colors.Text.quaternary)
        }
        .accessibilityElement(children: .combine)
    }

    private var statusColor: Color {
        switch status.color {
        case "green": return Design.Colors.Semantic.success
        case "amber", "orange": return Design.Colors.Semantic.warning
        case "red": return Design.Colors.Semantic.error
        default: return Design.Colors.Text.disabled
        }
    }
}

// MARK: - UUID Extension

extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}
