//
//  FilterComponents.swift
//  Whale
//
//  Filter chips and date range picker for orders.
//  Uses native iOS liquid glass effects.
//

import SwiftUI

// MARK: - Filter Chip

struct FilterChip: View {
    let label: String
    var icon: String? = nil
    var count: Int? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.light()
            action()
        } label: {
            HStack(spacing: 4) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(Design.Typography.caption2).fontWeight(.semibold)
                }

                Text(label)
                    .font(Design.Typography.caption1).fontWeight(isSelected ? .semibold : .medium)

                if let count = count, count > 0 {
                    Text("\(count)")
                        .font(Design.Typography.caption2Rounded).fontWeight(.bold)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Design.Colors.Glass.regular, in: .capsule)
                }
            }
            .foregroundStyle(isSelected ? Design.Colors.Text.primary : Design.Colors.Text.disabled)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                isSelected ? Design.Colors.Glass.ultraThick : Color.clear,
                in: .capsule
            )
        }
        .tint(Design.Colors.Text.primary)
        .glassEffect(.regular.interactive(), in: .capsule)
        .accessibilityLabel(count.map { "\(label), \($0)" } ?? label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Date Filter Chip

struct DateFilterChip: View {
    @Binding var startDate: Date?
    @Binding var endDate: Date?
    @Binding var showPicker: Bool

    private var hasDateFilter: Bool {
        startDate != nil || endDate != nil
    }

    private var displayText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"

        if let start = startDate, let end = endDate {
            if Calendar.current.isDate(start, inSameDayAs: end) {
                return formatter.string(from: start)
            }
            return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
        } else if let start = startDate {
            return "From \(formatter.string(from: start))"
        } else if let end = endDate {
            return "Until \(formatter.string(from: end))"
        }
        return "Date"
    }

    var body: some View {
        Button {
            showPicker = true
            Haptics.light()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                    .font(Design.Typography.caption2).fontWeight(.semibold)

                Text(displayText)
                    .font(Design.Typography.caption1).fontWeight(hasDateFilter ? .semibold : .medium)

                if hasDateFilter {
                    Button {
                        withAnimation {
                            startDate = nil
                            endDate = nil
                        }
                        Haptics.light()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(Design.Typography.caption2)
                            .foregroundStyle(Design.Colors.Text.disabled)
                    }
                    .accessibilityLabel("Clear date filter")
                }
            }
            .foregroundStyle(Design.Colors.Text.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .tint(Design.Colors.Text.primary)
        .glassEffect(.regular.interactive(), in: .capsule)
    }
}

// MARK: - Date Range Picker Sheet

struct DateRangePickerSheet: View {
    @Binding var startDate: Date?
    @Binding var endDate: Date?
    @Environment(\.dismiss) private var dismiss

    @State private var selectedStart: Date = Date()
    @State private var selectedEnd: Date = Date()
    @State private var selectedPreset: DatePreset? = nil
    @State private var isSelectingStart = true

    enum DatePreset: String, CaseIterable {
        case today = "Today"
        case yesterday = "Yesterday"
        case last7Days = "Last 7 Days"
        case last30Days = "Last 30 Days"
        case thisMonth = "This Month"

        func apply() -> (start: Date, end: Date) {
            let calendar = Calendar.current
            let now = Date()

            switch self {
            case .today:
                return (calendar.startOfDay(for: now), now)
            case .yesterday:
                let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
                return (calendar.startOfDay(for: yesterday), calendar.startOfDay(for: now))
            case .last7Days:
                return (calendar.date(byAdding: .day, value: -7, to: now)!, now)
            case .last30Days:
                return (calendar.date(byAdding: .day, value: -30, to: now)!, now)
            case .thisMonth:
                let firstOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
                return (firstOfMonth, now)
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Quick presets
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(DatePreset.allCases, id: \.self) { preset in
                                Button {
                                    let dates = preset.apply()
                                    selectedStart = dates.start
                                    selectedEnd = dates.end
                                    selectedPreset = preset
                                    Haptics.light()
                                } label: {
                                    Text(preset.rawValue)
                                        .font(Design.Typography.footnote).fontWeight(selectedPreset == preset ? .semibold : .medium)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(selectedPreset == preset ? Design.Colors.Semantic.accent : Design.Colors.Glass.regular)
                                        .foregroundStyle(selectedPreset == preset ? Design.Colors.Text.primary : .primary)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }

                    // Date range tabs
                    HStack(spacing: 12) {
                        Button {
                            isSelectingStart = true
                            Haptics.light()
                        } label: {
                            VStack(spacing: 4) {
                                Text("START")
                                    .font(Design.Typography.caption2).fontWeight(.semibold)
                                    .foregroundStyle(.secondary)
                                Text(selectedStart, format: .dateTime.month(.abbreviated).day().year())
                                    .font(Design.Typography.subhead).fontWeight(.semibold)
                                    .foregroundStyle(isSelectingStart ? Design.Colors.Semantic.accent : .primary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Design.Colors.Glass.regular, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(isSelectingStart ? Design.Colors.Semantic.accent : .clear, lineWidth: 2)
                            )
                        }
                        .buttonStyle(.plain)

                        Button {
                            isSelectingStart = false
                            Haptics.light()
                        } label: {
                            VStack(spacing: 4) {
                                Text("END")
                                    .font(Design.Typography.caption2).fontWeight(.semibold)
                                    .foregroundStyle(.secondary)
                                Text(selectedEnd, format: .dateTime.month(.abbreviated).day().year())
                                    .font(Design.Typography.subhead).fontWeight(.semibold)
                                    .foregroundStyle(!isSelectingStart ? Design.Colors.Semantic.accent : .primary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Design.Colors.Glass.regular, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(!isSelectingStart ? Design.Colors.Semantic.accent : .clear, lineWidth: 2)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)

                    // Native iOS DatePicker
                    DatePicker(
                        "",
                        selection: isSelectingStart ? $selectedStart : $selectedEnd,
                        in: ...Date(),
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding(.horizontal, 16)
                    .onChange(of: selectedStart) { _, newValue in
                        selectedPreset = nil
                        if newValue > selectedEnd {
                            selectedEnd = newValue
                        }
                    }
                    .onChange(of: selectedEnd) { _, newValue in
                        selectedPreset = nil
                        if newValue < selectedStart {
                            selectedStart = newValue
                        }
                    }
                }
                .padding(.top, 16)
            }
            .navigationTitle("Date Range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Apply") {
                        Haptics.medium()
                        startDate = selectedStart
                        endDate = selectedEnd
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if startDate != nil || endDate != nil {
                    Button {
                        Haptics.light()
                        startDate = nil
                        endDate = nil
                        dismiss()
                    } label: {
                        Text("Clear Filter")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 8)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            selectedStart = startDate ?? Date()
            selectedEnd = endDate ?? Date()

            if startDate != nil && endDate != nil {
                for preset in DatePreset.allCases {
                    let dates = preset.apply()
                    if Calendar.current.isDate(selectedStart, inSameDayAs: dates.start) &&
                       Calendar.current.isDate(selectedEnd, inSameDayAs: dates.end) {
                        selectedPreset = preset
                        break
                    }
                }
            }
        }
    }
}
