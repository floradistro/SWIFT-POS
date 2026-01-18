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
/// More subtle than grid cards - just opacity dimming
struct ListRowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .background(
                configuration.isPressed ? Color.white.opacity(0.08) : Color.clear
            )
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
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
                                .fill(isSelected ? Design.Colors.Semantic.accent : Color.black.opacity(0.5))
                                .frame(width: 24, height: 24)

                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .padding(8)
                        .scaleEffect(isSelected ? 1.0 : 0.9)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
                    } else if hasTiers {
                        Image(systemName: "square.stack.3d.up.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(5)
                            .background(Circle().fill(Color.black.opacity(0.6)))
                            .padding(8)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(product.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(product.categoryName ?? " ")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                .padding(10)
                .background(Color.black.opacity(0.7))
            }
            .overlay(alignment: .trailing) {
                if showRightLine {
                    Rectangle()
                        .fill(Color.white.opacity(0.15))
                        .frame(width: 0.5)
                }
            }
            .overlay(alignment: .bottom) {
                if showBottomLine {
                    Rectangle()
                        .fill(Color.white.opacity(0.15))
                        .frame(height: 0.5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(GridCardPressStyle())
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
        if quantity <= 5 { return Color(red: 1, green: 0.4, blue: 0.3) }
        if quantity <= 15 { return Design.Colors.Semantic.warning }
        return .white.opacity(0.5)
    }

    private var isLow: Bool {
        quantity <= 15
    }

    var body: some View {
        HStack(spacing: 4) {
            if quantity <= 0 {
                Text("OUT")
                    .font(.system(size: 10, weight: .bold))
            } else {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 9))
                Text("\(quantity)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
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

// MARK: - Product Analytics Inline

/// Beautiful inline analytics with sparkline and stock indicator
private struct ProductAnalyticsInline: View {
    let product: Product
    @ObservedObject private var velocityService = VelocityService.shared
    @Environment(\.horizontalSizeClass) var sizeClass

    private var isCompact: Bool { sizeClass == .compact }

    private var velocity: ProductVelocity? {
        velocityService.velocity(for: product.id)
    }

    private var trendDirection: TrendDirection {
        guard let vel = velocity, vel.normalizedDaily.count >= 2 else { return .flat }
        let recent = vel.normalizedDaily.suffix(3)
        let older = vel.normalizedDaily.prefix(3)
        let recentAvg = recent.reduce(0, +) / Double(max(1, recent.count))
        let olderAvg = older.reduce(0, +) / Double(max(1, older.count))
        if recentAvg > olderAvg * 1.2 { return .up }
        if recentAvg < olderAvg * 0.8 { return .down }
        return .flat
    }

    enum TrendDirection {
        case up, down, flat

        var icon: String {
            switch self {
            case .up: return "arrow.up.right"
            case .down: return "arrow.down.right"
            case .flat: return "arrow.right"
            }
        }

        var color: Color {
            switch self {
            case .up: return Color(hex: "22C55E")
            case .down: return Color(hex: "EF4444")
            case .flat: return .white.opacity(0.4)
            }
        }
    }

    private var stockStatus: StockStatus {
        let stock = product.availableStock
        let days = daysOfStock
        if stock <= 0 { return .out }
        if days > 0 && days < 7 { return .low }
        if stock < 10 { return .low }
        return .good
    }

    enum StockStatus {
        case good, low, out

        var color: Color {
            switch self {
            case .good: return Color(hex: "22C55E")
            case .low: return Color(hex: "F59E0B")
            case .out: return Color(hex: "EF4444")
            }
        }
    }

    private var daysOfStock: Int {
        guard let vel = velocity, vel.avgPerDay > 0 else { return 0 }
        return Int(Double(product.availableStock) / vel.avgPerDay)
    }

    var body: some View {
        HStack(spacing: isCompact ? 12 : 16) {
            // Sparkline with sales count
            HStack(spacing: 8) {
                SparklineChart(
                    data: velocity?.normalizedDaily ?? [],
                    trend: trendDirection
                )
                .frame(width: isCompact ? 40 : 48, height: isCompact ? 20 : 24)

                VStack(alignment: .leading, spacing: 0) {
                    Text("\(Int(velocity?.totalUnits ?? 0))")
                        .font(.system(size: isCompact ? 14 : 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)

                    HStack(spacing: 2) {
                        Image(systemName: trendDirection.icon)
                            .font(.system(size: 8, weight: .bold))
                        Text("7d")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundStyle(trendDirection.color)
                }
            }

            // Stock pill
            StockPill(
                quantity: product.availableStock,
                daysSupply: daysOfStock,
                status: stockStatus,
                isCompact: isCompact
            )
        }
    }
}

// MARK: - Sparkline Chart

/// Smooth line chart showing 7-day trend
private struct SparklineChart: View {
    let data: [Double]
    let trend: ProductAnalyticsInline.TrendDirection

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let points = normalizedPoints(width: width, height: height)

            ZStack {
                // Gradient fill under the line
                if points.count >= 2 {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: height))
                        path.addLine(to: points[0])
                        for point in points.dropFirst() {
                            path.addLine(to: point)
                        }
                        path.addLine(to: CGPoint(x: width, y: height))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [trend.color.opacity(0.2), trend.color.opacity(0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }

                // The line itself
                if points.count >= 2 {
                    Path { path in
                        path.move(to: points[0])
                        for point in points.dropFirst() {
                            path.addLine(to: point)
                        }
                    }
                    .stroke(trend.color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }

                // Dot on the last point
                if let lastPoint = points.last {
                    Circle()
                        .fill(trend.color)
                        .frame(width: 4, height: 4)
                        .position(lastPoint)
                }
            }
        }
    }

    private func normalizedPoints(width: CGFloat, height: CGFloat) -> [CGPoint] {
        guard !data.isEmpty else { return [] }

        let maxVal = max(data.max() ?? 1, 0.01)
        let padding: CGFloat = 2

        return data.enumerated().map { index, value in
            let x = data.count == 1 ? width / 2 : (CGFloat(index) / CGFloat(data.count - 1)) * width
            let y = padding + (1 - CGFloat(value / maxVal)) * (height - padding * 2)
            return CGPoint(x: x, y: y)
        }
    }
}

// MARK: - Stock Pill

/// Compact stock indicator pill
private struct StockPill: View {
    let quantity: Int
    let daysSupply: Int
    let status: ProductAnalyticsInline.StockStatus
    let isCompact: Bool

    var body: some View {
        HStack(spacing: 4) {
            // Stock count
            Text("\(quantity)")
                .font(.system(size: isCompact ? 13 : 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)

            // Status indicator dot
            Circle()
                .fill(status.color)
                .frame(width: 6, height: 6)

            // Days supply (if available)
            if daysSupply > 0 && !isCompact {
                Text("\(daysSupply)d")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, isCompact ? 8 : 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(.white.opacity(0.06))
        )
        .overlay(
            Capsule()
                .stroke(status.color.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Daily Bar Chart (for legacy ProductInsightsPanel)

/// Simple bar chart for 7-day sales data
private struct DailyBarChart: View {
    let data: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let maxVal = data.max() ?? 1
            let barWidth = max(4, geo.size.width / CGFloat(max(1, data.count)) - 2)

            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(data.enumerated()), id: \.offset) { _, value in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(color.opacity(0.8))
                        .frame(width: barWidth, height: max(3, CGFloat(value / maxVal) * geo.size.height))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }
}

// MARK: - Stock Level Bar (for legacy ProductInsightsPanel)

/// Vertical bar showing relative stock level
private struct StockLevelBar: View {
    let quantity: Int
    let daysSupply: Int
    let color: Color

    private var fillLevel: CGFloat {
        // Use days supply as indicator, capped at 30 days = full
        if daysSupply <= 0 { return 0.1 }
        return min(1.0, CGFloat(daysSupply) / 30.0)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(.white.opacity(0.1))

                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(color)
                    .frame(height: fillLevel * geo.size.height)
            }
        }
    }
}

// MARK: - Shimmer Effect

extension View {
    func shimmering() -> some View {
        self.modifier(ShimmerModifier())
    }
}

private struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        colors: [
                            .clear,
                            .white.opacity(0.1),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.6)
                    .offset(x: -geo.size.width * 0.3 + phase * geo.size.width * 1.6)
                }
            )
            .clipped()
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

// MARK: - Product Insights Panel (Legacy - keeping for compatibility)

/// Futuristic analytics panel showing stock health and sales velocity
/// Now replaced by ProductAnalyticsBar in list rows
struct ProductInsightsPanel: View {
    let product: Product
    @ObservedObject private var velocityService = VelocityService.shared

    private var velocity: ProductVelocity? {
        velocityService.velocity(for: product.id)
    }

    private var velocityColor: Color {
        guard let health = velocity?.health else { return .white.opacity(0.3) }
        switch health {
        case .hot: return Design.Colors.Semantic.success
        case .good: return Design.Colors.Semantic.info
        case .slow: return Design.Colors.Semantic.warning
        case .stale: return Design.Colors.Semantic.error
        }
    }

    private var stockColor: Color {
        let stock = product.availableStock
        if stock <= 0 { return Design.Colors.Semantic.error }
        if stock < 10 { return Design.Colors.Semantic.warning }
        if stock < 50 { return Design.Colors.Semantic.info }
        return Design.Colors.Semantic.success
    }

    private var daysOfStock: Int {
        guard let vel = velocity, vel.avgPerDay > 0 else { return 0 }
        return Int(Double(product.availableStock) / vel.avgPerDay)
    }

    var body: some View {
        HStack(spacing: 0) {
            // LEFT: Sales velocity
            HStack(spacing: 12) {
                DailyBarChart(
                    data: velocity?.normalizedDaily ?? [],
                    color: velocityColor
                )
                .frame(width: 56, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(Int(velocity?.totalUnits ?? 0))")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        Text("sold")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                    }

                    HStack(spacing: 4) {
                        Text("7 days")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.4))

                        if let vel = velocity {
                            Text("·")
                                .foregroundStyle(.white.opacity(0.3))
                            Text(vel.health.label)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(velocityColor)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)

            // Divider
            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(width: 1, height: 32)
                .padding(.horizontal, 14)

            // RIGHT: Stock
            HStack(spacing: 12) {
                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(product.availableStock)")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        Text("units")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                    }

                    if daysOfStock > 0 {
                        Text("~\(daysOfStock)d supply")
                            .font(.system(size: 11))
                            .foregroundStyle(stockColor)
                    } else {
                        Text("in stock")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }

                StockLevelBar(
                    quantity: product.availableStock,
                    daysSupply: daysOfStock,
                    color: stockColor
                )
                .frame(width: 8, height: 28)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(0.04))
        )
    }
}


// MARK: - Health Enums

private enum StockHealth {
    case outOfStock, critical, low, moderate, healthy

    var color: Color {
        switch self {
        case .outOfStock: return Design.Colors.Semantic.error
        case .critical: return Color(red: 1, green: 0.4, blue: 0.3)
        case .low: return Design.Colors.Semantic.warning
        case .moderate: return Design.Colors.Semantic.info
        case .healthy: return Design.Colors.Semantic.success
        }
    }
}

private enum VelocityTrendIcon {
    case rising, steady, falling

    var icon: String {
        switch self {
        case .rising: return "arrow.up.right"
        case .steady: return "arrow.right"
        case .falling: return "arrow.down.right"
        }
    }
}

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
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Design.Colors.Semantic.warning.opacity(0.4)))
                    }

                    if let tierLabel = item.tierLabel {
                        Text(tierLabel)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
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
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Design.Colors.Text.tertiary)
                        .frame(width: 28, height: 28)
                        .background(Design.Colors.Glass.thin)
                        .clipShape(Circle())
                }
                .buttonStyle(LiquidPressStyle())

                Text("\(item.quantity)")
                    .font(Design.Typography.subhead)
                    .foregroundStyle(Design.Colors.Text.primary)
                    .frame(width: 24)

                Button {
                    Haptics.light()
                    onUpdateQuantity(item.quantity + 1)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Design.Colors.Text.tertiary)
                        .frame(width: 28, height: 28)
                        .background(Design.Colors.Glass.thin)
                        .clipShape(Circle())
                }
                .buttonStyle(LiquidPressStyle())
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
                .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? .white : .white.opacity(0.7))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
        }
        .tint(.white)
        .glassEffect(.regular.interactive(), in: .capsule)
    }
}
