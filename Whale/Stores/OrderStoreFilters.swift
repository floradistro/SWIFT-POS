//
//  OrderStoreFilters.swift
//  Whale
//
//  Date range presets for order filtering.
//

import Foundation

// MARK: - Date Range Preset

extension OrderStore {

    enum DateRangePreset {
        case today
        case yesterday
        case last7Days
        case last30Days
        case thisMonth
        case lastMonth
        case custom
        case all
    }
}
