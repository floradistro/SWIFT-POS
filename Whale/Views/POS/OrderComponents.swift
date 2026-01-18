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

    private var needsAttention: Bool {
        order.status == .pending || order.status == .preparing || order.paymentStatus == .pending
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                Haptics.light()
                onTap()
            } label: {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(order.displayCustomerName)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        HStack(spacing: 6) {
                            Text("#\(order.shortOrderNumber)")
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.4))

                            Text("•")
                                .font(.system(size: 8))
                                .foregroundStyle(.white.opacity(0.2))

                            Text(order.orderType.displayName)
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.4))

                            Text("•")
                                .font(.system(size: 8))
                                .foregroundStyle(.white.opacity(0.2))

                            Text(order.timeAgo)
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text(order.formattedTotal)
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)

                        OrderListStatusPill(order: order)
                    }

                    if isMultiSelectMode {
                        Image(systemName: isMultiSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 22))
                            .foregroundStyle(isMultiSelected ? Design.Colors.Semantic.accent : .white.opacity(0.3))
                            .scaleEffect(isMultiSelected ? 1.0 : 0.9)
                            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isMultiSelected)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(isMultiSelected ? Color.white.opacity(0.06) : Color.clear)
            }
            .buttonStyle(ListRowPressStyle())
            .contextMenu {
                Button {
                    Haptics.light()
                    onOpenInDock()
                } label: {
                    Label("Open in Dock", systemImage: "dock.arrow.down.rectangle")
                }

                Button {
                    Haptics.light()
                    onViewDetails()
                } label: {
                    Label("View Details", systemImage: "info.circle")
                }

                Divider()

                Button {
                    Haptics.light()
                    onSelectMultiple()
                } label: {
                    Label("Select Multiple", systemImage: "checkmark.circle")
                }
            }

            if !isLast {
                Rectangle()
                    .fill(Color.white.opacity(0.15))
                    .frame(height: 0.5)
                    .padding(.leading, 16)
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isMultiSelected)
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
                    .fill(Color.orange)
                    .frame(width: 6, height: 6)
            } else if isComplete {
                Circle()
                    .fill(Design.Colors.Semantic.success)
                    .frame(width: 6, height: 6)
            }

            Text(statusText)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(needsAction ? .orange : (isComplete ? Design.Colors.Semantic.success : .white.opacity(0.7)))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(needsAction || isComplete ? .white.opacity(0.1) : .clear, in: Capsule())
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
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(statusColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor.opacity(0.2), in: Capsule())
    }

    private var statusColor: Color {
        switch status.color {
        case "amber": return .yellow
        case "blue": return .blue
        case "green", "emerald": return .green
        case "sky": return .cyan
        case "red": return .red
        default: return .gray
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

            Text(status.displayName)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private var statusColor: Color {
        switch status.color {
        case "green": return .green
        case "amber", "orange": return .yellow
        case "red": return .red
        default: return .gray
        }
    }
}

// MARK: - UUID Extension

extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}
