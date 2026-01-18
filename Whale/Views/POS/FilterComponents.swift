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
                        .font(.system(size: 10, weight: .semibold))
                }

                Text(label)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))

                if let count = count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.fill.tertiary, in: .capsule)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .tint(.white)
        .glassEffect(.regular.interactive(), in: .capsule)
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
                    .font(.system(size: 10, weight: .semibold))

                Text(displayText)
                    .font(.system(size: 12, weight: hasDateFilter ? .semibold : .medium))

                if hasDateFilter {
                    Button {
                        withAnimation {
                            startDate = nil
                            endDate = nil
                        }
                        Haptics.light()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .tint(.white)
        .glassEffect(.regular.interactive(), in: .capsule)
    }
}

// MARK: - Date Range Picker Modal

struct DateRangePickerModal: View {
    @Binding var startDate: Date?
    @Binding var endDate: Date?
    @Binding var isPresented: Bool

    @State private var selectedStart: Date = Date()
    @State private var selectedEnd: Date = Date()
    @State private var selectedPreset: DatePreset? = nil
    @State private var isSelectingStart = true
    @State private var animationProgress: CGFloat = 0

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
        GeometryReader { geometry in
            let modalWidth = min(360, geometry.size.width - 48)

            ZStack {
                Color.black.opacity(animationProgress * 0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        dismiss()
                    }

                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                        }
                        .tint(.white)
                        .glassEffect(.regular.interactive(), in: .circle)

                        Spacer()

                        Text("Select Date Range")
                            .font(.system(size: 17, weight: .semibold))

                        Spacer()

                        Color.clear.frame(width: 44, height: 44)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                    // Quick presets
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(DatePreset.allCases, id: \.self) { preset in
                                LiquidGlassPill(
                                    preset.rawValue,
                                    isSelected: selectedPreset == preset
                                ) {
                                    let dates = preset.apply()
                                    selectedStart = dates.start
                                    selectedEnd = dates.end
                                    selectedPreset = preset
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.bottom, 10)

                    // Date range tabs
                    HStack(spacing: 10) {
                        Button {
                            isSelectingStart = true
                            Haptics.light()
                        } label: {
                            VStack(spacing: 4) {
                                Text("START")
                                    .font(.system(size: 10, weight: .semibold))
                                    .tracking(0.5)
                                    .foregroundStyle(.secondary)
                                Text(selectedStart, format: .dateTime.month(.abbreviated).day().year())
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(isSelectingStart ? Design.Colors.Semantic.accent : .primary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        }
                        .tint(.white)
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))

                        Button {
                            isSelectingStart = false
                            Haptics.light()
                        } label: {
                            VStack(spacing: 4) {
                                Text("END")
                                    .font(.system(size: 10, weight: .semibold))
                                    .tracking(0.5)
                                    .foregroundStyle(.secondary)
                                Text(selectedEnd, format: .dateTime.month(.abbreviated).day().year())
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(!isSelectingStart ? Design.Colors.Semantic.accent : .primary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        }
                        .tint(.white)
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)

                    // Native iOS DatePicker
                    DatePicker(
                        "",
                        selection: isSelectingStart ? $selectedStart : $selectedEnd,
                        in: ...Date(),
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .tint(Design.Colors.Semantic.accent)
                    .labelsHidden()
                    .frame(width: modalWidth - 32)
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

                    // Actions
                    HStack(spacing: 12) {
                        Button {
                            Haptics.light()
                            startDate = nil
                            endDate = nil
                            dismiss()
                        } label: {
                            Text("Clear")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .tint(.white)
                        .glassEffect(.regular.interactive(), in: .capsule)

                        Button {
                            Haptics.medium()
                            startDate = selectedStart
                            endDate = selectedEnd
                            dismiss()
                        } label: {
                            Text("Apply")
                                .font(.system(size: 15, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.white)
                        .foregroundStyle(.black)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 16)
                }
                .frame(width: modalWidth)
                .glassEffect(.regular, in: .rect(cornerRadius: 32))
                .scaleEffect(0.9 + (0.1 * animationProgress))
                .opacity(animationProgress)
            }
        }
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

            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                animationProgress = 1
            }
        }
    }

    private func dismiss() {
        Haptics.light()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            animationProgress = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            isPresented = false
        }
    }
}
