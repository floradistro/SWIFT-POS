//
//  BulkOrderLabelSheet.swift
//  Whale
//
//  Bulk order label sheet - extracted from LabelPrintService.
//

import SwiftUI

struct BulkOrderLabelSheet: View {
    let orders: [Order]
    let onDismiss: () -> Void

    @State private var isPrinting = false

    var body: some View {
        OrderLabelTemplateSheet(
            orders: orders,
            store: nil,
            location: nil,
            isPrinting: $isPrinting,
            onDismiss: onDismiss
        )
    }
}
