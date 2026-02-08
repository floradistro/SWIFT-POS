//
//  ProductInsightsComponents.swift
//  Whale
//
//  Product analytics and insights components:
//  sparkline charts, stock indicators, and insights panels.
//

import SwiftUI

// MARK: - Product Analytics Inline

/// Beautiful inline analytics with sparkline and stock indicator
struct ProductAnalyticsInline: View {
    let product: Product
    @StateObject private var velocityService = VelocityService.shared
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
            case .flat: return Design.Colors.Text.subtle
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
            HStack(spacing: 8) {
                SparklineChart(
                    data: velocity?.normalizedDaily ?? [],
                    trend: trendDirection
                )
                .frame(width: isCompact ? 40 : 48, height: isCompact ? 20 : 24)

                VStack(alignment: .leading, spacing: 0) {
                    Text("\(Int(velocity?.totalUnits ?? 0))")
                        .font(isCompact ? Design.Typography.footnoteRounded : Design.Typography.calloutRounded).fontWeight(.semibold)
                        .foregroundStyle(Design.Colors.Text.primary)

                    HStack(spacing: 2) {
                        Image(systemName: trendDirection.icon)
                            .font(Design.Typography.caption2).fontWeight(.bold)
                        Text("7d")
                            .font(Design.Typography.caption2).fontWeight(.medium)
                    }
                    .foregroundStyle(trendDirection.color)
                }
            }

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
struct SparklineChart: View {
    let data: [Double]
    let trend: ProductAnalyticsInline.TrendDirection

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let points = normalizedPoints(width: width, height: height)

            ZStack {
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

                if points.count >= 2 {
                    Path { path in
                        path.move(to: points[0])
                        for point in points.dropFirst() {
                            path.addLine(to: point)
                        }
                    }
                    .stroke(trend.color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }

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
struct StockPill: View {
    let quantity: Int
    let daysSupply: Int
    let status: ProductAnalyticsInline.StockStatus
    let isCompact: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text("\(quantity)")
                .font(Design.Typography.footnoteRounded).fontWeight(.semibold)
                .foregroundStyle(Design.Colors.Text.primary)

            Circle()
                .fill(status.color)
                .frame(width: 6, height: 6)

            if daysSupply > 0 && !isCompact {
                Text("\(daysSupply)d")
                    .font(Design.Typography.caption2).fontWeight(.medium)
                    .foregroundStyle(Design.Colors.Text.disabled)
            }
        }
        .padding(.horizontal, isCompact ? 8 : 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Design.Colors.Border.subtle)
        )
        .overlay(
            Capsule()
                .stroke(status.color.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Daily Bar Chart (legacy)

/// Simple bar chart for 7-day sales data
struct DailyBarChart: View {
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

// MARK: - Stock Level Bar (legacy)

/// Vertical bar showing relative stock level
struct StockLevelBar: View {
    let quantity: Int
    let daysSupply: Int
    let color: Color

    private var fillLevel: CGFloat {
        if daysSupply <= 0 { return 0.1 }
        return min(1.0, CGFloat(daysSupply) / 30.0)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Design.Colors.Glass.thick)

                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(color)
                    .frame(height: fillLevel * geo.size.height)
            }
        }
    }
}

// MARK: - Product Insights Panel (Legacy)

/// Futuristic analytics panel showing stock health and sales velocity
/// Now replaced by ProductAnalyticsBar in list rows
struct ProductInsightsPanel: View {
    let product: Product
    @StateObject private var velocityService = VelocityService.shared

    private var velocity: ProductVelocity? {
        velocityService.velocity(for: product.id)
    }

    private var velocityColor: Color {
        guard let health = velocity?.health else { return Design.Colors.Text.placeholder }
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
            HStack(spacing: 12) {
                DailyBarChart(
                    data: velocity?.normalizedDaily ?? [],
                    color: velocityColor
                )
                .frame(width: 56, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(Int(velocity?.totalUnits ?? 0))")
                            .font(Design.Typography.title3Rounded).fontWeight(.bold)
                            .foregroundStyle(Design.Colors.Text.primary)

                        Text("sold")
                            .font(Design.Typography.caption2).fontWeight(.medium)
                            .foregroundStyle(Design.Colors.Text.disabled)
                    }

                    HStack(spacing: 4) {
                        Text("7 days")
                            .font(Design.Typography.caption2)
                            .foregroundStyle(Design.Colors.Text.subtle)

                        if let vel = velocity {
                            Text("·")
                                .foregroundStyle(Design.Colors.Text.placeholder)
                            Text(vel.health.label)
                                .font(Design.Typography.caption2).fontWeight(.semibold)
                                .foregroundStyle(velocityColor)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)

            Rectangle()
                .fill(Design.Colors.Glass.regular)
                .frame(width: 1, height: 32)
                .padding(.horizontal, 14)

            HStack(spacing: 12) {
                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(product.availableStock)")
                            .font(Design.Typography.title3Rounded).fontWeight(.bold)
                            .foregroundStyle(Design.Colors.Text.primary)

                        Text("units")
                            .font(Design.Typography.caption2).fontWeight(.medium)
                            .foregroundStyle(Design.Colors.Text.disabled)
                    }

                    if daysOfStock > 0 {
                        Text("~\(daysOfStock)d supply")
                            .font(Design.Typography.caption2)
                            .foregroundStyle(stockColor)
                    } else {
                        Text("in stock")
                            .font(Design.Typography.caption2)
                            .foregroundStyle(Design.Colors.Text.subtle)
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
                .fill(Design.Colors.Glass.thin)
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
