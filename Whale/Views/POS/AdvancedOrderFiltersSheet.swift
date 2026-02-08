//
//  AdvancedOrderFiltersSheet.swift
//  Whale
//
//  Advanced filtering options for orders.
//

import SwiftUI

struct AdvancedOrderFiltersSheet: View {
    @ObservedObject var store: OrderStore
    @Binding var isPresented: Bool

    @State private var selectedDatePreset: OrderStore.DateRangePreset = .all
    @State private var customStartDate = Date()
    @State private var customEndDate = Date()
    @State private var minAmountText = ""
    @State private var maxAmountText = ""

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    dateRangeSection
                    amountRangeSection
                    paymentStatusSection
                    orderTypeSection
                    resultsCount
                }
                .padding(20)
            }
            .navigationTitle("Filter Orders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        store.clearFilters()
                        selectedDatePreset = .all
                        minAmountText = ""
                        maxAmountText = ""
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        isPresented = false
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            if let min = store.amountMin {
                minAmountText = "\(min)"
            }
            if let max = store.amountMax {
                maxAmountText = "\(max)"
            }
            if store.dateRangeStart != nil || store.dateRangeEnd != nil {
                selectedDatePreset = .custom
                customStartDate = store.dateRangeStart ?? Date()
                customEndDate = store.dateRangeEnd ?? Date()
            }
        }
    }

    // MARK: - Date Range Section

    private var dateRangeSection: some View {
        FilterSection(title: "Date Range", icon: "calendar") {
            VStack(spacing: 12) {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 8) {
                    datePresetButton(.today, "Today")
                    datePresetButton(.yesterday, "Yesterday")
                    datePresetButton(.last7Days, "Last 7 Days")
                    datePresetButton(.last30Days, "Last 30 Days")
                    datePresetButton(.thisMonth, "This Month")
                    datePresetButton(.lastMonth, "Last Month")
                    datePresetButton(.custom, "Custom")
                }

                if selectedDatePreset == .custom {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("From")
                                .font(Design.Typography.caption1).fontWeight(.medium)
                                .foregroundStyle(.secondary)
                            DatePicker("", selection: $customStartDate, displayedComponents: .date)
                                .labelsHidden()
                                .onChange(of: customStartDate) { _, newDate in
                                    store.dateRangeStart = newDate
                                }
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("To")
                                .font(Design.Typography.caption1).fontWeight(.medium)
                                .foregroundStyle(.secondary)
                            DatePicker("", selection: $customEndDate, displayedComponents: .date)
                                .labelsHidden()
                                .onChange(of: customEndDate) { _, newDate in
                                    store.dateRangeEnd = newDate
                                }
                        }
                    }
                    .padding(.top, 8)
                }

                if store.dateRangeStart != nil || store.dateRangeEnd != nil {
                    Button {
                        store.dateRangeStart = nil
                        store.dateRangeEnd = nil
                        selectedDatePreset = .all
                    } label: {
                        Text("Clear Date Filter")
                            .font(Design.Typography.footnote).fontWeight(.medium)
                            .foregroundStyle(Design.Colors.Semantic.error)
                    }
                }
            }
        }
    }

    // MARK: - Amount Range Section

    private var amountRangeSection: some View {
        FilterSection(title: "Order Amount", icon: "dollarsign.circle") {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Minimum")
                        .font(Design.Typography.caption1).fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    HStack {
                        Text("$")
                            .foregroundStyle(.secondary)
                        TextField("0.00", text: $minAmountText)
                            .keyboardType(.decimalPad)
                            .onChange(of: minAmountText) { _, newValue in
                                if let amount = Decimal(string: newValue) {
                                    store.amountMin = amount
                                } else if newValue.isEmpty {
                                    store.amountMin = nil
                                }
                            }
                    }
                    .padding(10)
                    .background(Design.Colors.Glass.regular, in: RoundedRectangle(cornerRadius: 8))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Maximum")
                        .font(Design.Typography.caption1).fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    HStack {
                        Text("$")
                            .foregroundStyle(.secondary)
                        TextField("Any", text: $maxAmountText)
                            .keyboardType(.decimalPad)
                            .onChange(of: maxAmountText) { _, newValue in
                                if let amount = Decimal(string: newValue) {
                                    store.amountMax = amount
                                } else if newValue.isEmpty {
                                    store.amountMax = nil
                                }
                            }
                    }
                    .padding(10)
                    .background(Design.Colors.Glass.regular, in: RoundedRectangle(cornerRadius: 8))
                }
            }

            HStack(spacing: 8) {
                amountPresetButton(min: nil, max: 50, label: "Under $50")
                amountPresetButton(min: 50, max: 100, label: "$50-$100")
                amountPresetButton(min: 100, max: nil, label: "$100+")
            }
            .padding(.top, 8)
        }
    }

    // MARK: - Payment Status Section

    private var paymentStatusSection: some View {
        FilterSection(title: "Payment Status", icon: "creditcard") {
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                paymentStatusButton(nil, "All Payments")
                paymentStatusButton(.paid, "Paid")
                paymentStatusButton(.pending, "Pending")
                paymentStatusButton(.failed, "Failed")
                paymentStatusButton(.refunded, "Refunded")
                paymentStatusButton(.partial, "Partial")
            }
        }
    }

    // MARK: - Order Type Section

    private var orderTypeSection: some View {
        FilterSection(title: "Order Type", icon: "tag") {
            VStack(spacing: 12) {
                Toggle(isOn: $store.showOnlineOrdersOnly) {
                    HStack {
                        Image(systemName: "globe")
                            .foregroundStyle(Design.Colors.Semantic.accent)
                        Text("Online Orders Only")
                            .font(Design.Typography.subhead).fontWeight(.medium)
                        Text("(Pickup, Shipping, Delivery)")
                            .font(Design.Typography.caption1)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: Design.Colors.Semantic.accent))

                if !store.showOnlineOrdersOnly {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 8) {
                        orderTypeButton(nil, "All Types", "tray.full")
                        ForEach(OrderType.allCases, id: \.self) { type in
                            orderTypeButton(type, type.displayName, type.icon)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Results Count

    private var resultsCount: some View {
        HStack {
            Spacer()
            Text("\(store.filteredOrders.count) orders match")
                .font(Design.Typography.footnote).fontWeight(.medium)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.top, 8)
    }

    // MARK: - Helper Views

    private func datePresetButton(_ preset: OrderStore.DateRangePreset, _ label: String) -> some View {
        Button {
            selectedDatePreset = preset
            store.setDateRange(preset)
            if preset == .custom {
                store.dateRangeStart = customStartDate
                store.dateRangeEnd = customEndDate
            }
        } label: {
            Text(label)
                .font(Design.Typography.footnote).fontWeight(selectedDatePreset == preset ? .semibold : .medium)
                .foregroundStyle(selectedDatePreset == preset ? Design.Colors.Semantic.accentForeground : .primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    selectedDatePreset == preset
                        ? AnyShapeStyle(Design.Colors.Semantic.accent)
                        : AnyShapeStyle(Design.Colors.Glass.thin),
                    in: RoundedRectangle(cornerRadius: 8)
                )
        }
    }

    private func amountPresetButton(min: Decimal?, max: Decimal?, label: String) -> some View {
        let isSelected = store.amountMin == min && store.amountMax == max
        return Button {
            store.amountMin = min
            store.amountMax = max
            minAmountText = min.map { "\($0)" } ?? ""
            maxAmountText = max.map { "\($0)" } ?? ""
        } label: {
            Text(label)
                .font(Design.Typography.caption1).fontWeight(isSelected ? .semibold : .medium)
                .foregroundStyle(isSelected ? Design.Colors.Semantic.accentForeground : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    isSelected
                        ? AnyShapeStyle(Design.Colors.Semantic.accent)
                        : AnyShapeStyle(Design.Colors.Glass.thin),
                    in: Capsule()
                )
        }
    }

    private func paymentStatusButton(_ status: PaymentStatus?, _ label: String) -> some View {
        let isSelected = store.selectedPaymentStatus == status
        return Button {
            store.selectedPaymentStatus = status
        } label: {
            HStack(spacing: 6) {
                if let status = status {
                    Circle()
                        .fill(paymentStatusColor(status))
                        .frame(width: 8, height: 8)
                }
                Text(label)
                    .font(Design.Typography.footnote).fontWeight(isSelected ? .semibold : .medium)
            }
            .foregroundStyle(isSelected ? Design.Colors.Semantic.accentForeground : .primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                isSelected
                    ? AnyShapeStyle(Design.Colors.Semantic.accent)
                    : AnyShapeStyle(Design.Colors.Glass.thin),
                in: RoundedRectangle(cornerRadius: 8)
            )
        }
    }

    private func orderTypeButton(_ type: OrderType?, _ label: String, _ icon: String) -> some View {
        let isSelected = store.selectedOrderType == type && !store.showOnlineOrdersOnly
        return Button {
            store.selectedOrderType = type
            store.showOnlineOrdersOnly = false
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(Design.Typography.caption1)
                Text(label)
                    .font(Design.Typography.footnote).fontWeight(isSelected ? .semibold : .medium)
            }
            .foregroundStyle(isSelected ? Design.Colors.Semantic.accentForeground : .primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                isSelected
                    ? AnyShapeStyle(Design.Colors.Semantic.accent)
                    : AnyShapeStyle(Design.Colors.Glass.thin),
                in: RoundedRectangle(cornerRadius: 8)
            )
        }
    }

    private func paymentStatusColor(_ status: PaymentStatus) -> Color {
        switch status {
        case .paid: return Design.Colors.Semantic.success
        case .pending: return Design.Colors.Semantic.warning
        case .failed: return Design.Colors.Semantic.error
        case .partial: return Design.Colors.Semantic.warning
        case .refunded, .partiallyRefunded: return Design.Colors.Text.disabled
        }
    }
}

// MARK: - Filter Section Container

private struct FilterSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(Design.Typography.footnote).fontWeight(.semibold)
                    .foregroundStyle(Design.Colors.Semantic.accent)
                Text(title)
                    .font(Design.Typography.callout).fontWeight(.semibold)
            }

            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Design.Colors.Glass.regular, in: RoundedRectangle(cornerRadius: 12))
    }
}
