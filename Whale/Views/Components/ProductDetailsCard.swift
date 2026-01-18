//  ProductDetailsCard.swift - Product details display for modals

import SwiftUI

struct ProductDetailsCard: View {
    let product: Product

    // Known fields to exclude from custom fields display (already shown elsewhere)
    private let excludedFields: Set<String> = [
        "strain_type", "strainType", "strain",
        "thca_percentage", "thc_total", "thcTotal", "total_thc", "thc", "THC",
        "thca", "THCA", "thca_percent", "THCa",
        "d9_thc", "d9Thc", "delta9_thc", "delta9", "d9", "d9_percentage",
        "cbd_total", "cbdTotal", "total_cbd", "cbd", "CBD", "cbd_percentage"
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                productImage
                statsRow
                customFieldsSection
                descriptionSection
                coaSection
                metadataSection
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

    // MARK: - Product Image

    private var productImage: some View {
        CachedAsyncImage(url: product.fullImageUrl ?? product.thumbnailUrl)
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        HStack(spacing: 12) {
            if let strain = product.strainType {
                StatPill(label: "Strain", value: strain)
            }
            if let thc = product.thcPercentage {
                StatPill(label: "THC", value: String(format: "%.1f%%", thc))
            }
            if let cbd = product.cbdPercentage, cbd > 0 {
                StatPill(label: "CBD", value: String(format: "%.1f%%", cbd))
            }
        }
    }

    // MARK: - Custom Fields

    @ViewBuilder
    private var customFieldsSection: some View {
        let displayableFields = getDisplayableCustomFields()
        if !displayableFields.isEmpty {
            VStack(spacing: 6) {
                ForEach(displayableFields, id: \.key) { field in
                    DetailRow(label: formatFieldLabel(field.key), value: field.value)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.03)))
        }
    }

    private func getDisplayableCustomFields() -> [(key: String, value: String)] {
        guard let fields = product.customFields else { return [] }

        return fields.compactMap { key, anyCodable -> (key: String, value: String)? in
            // Skip excluded fields
            guard !excludedFields.contains(key) else { return nil }

            // Convert value to displayable string
            let value: String
            if let stringVal = anyCodable.value as? String, !stringVal.isEmpty {
                value = stringVal
            } else if let doubleVal = anyCodable.value as? Double {
                value = formatNumber(doubleVal)
            } else if let intVal = anyCodable.value as? Int {
                value = String(intVal)
            } else if let boolVal = anyCodable.value as? Bool {
                value = boolVal ? "Yes" : "No"
            } else {
                return nil
            }

            return (key: key, value: value)
        }
        .sorted { $0.key < $1.key }
    }

    private func formatFieldLabel(_ key: String) -> String {
        key.replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }

    private func formatNumber(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.2f", value)
    }

    // MARK: - Description

    @ViewBuilder
    private var descriptionSection: some View {
        if let description = product.description, !description.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Description")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                Text(description)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.03)))
        }
    }

    // MARK: - COA Section

    @ViewBuilder
    private var coaSection: some View {
        if product.hasCOA, let coa = product.coa {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "doc.badge.checkmark")
                        .foregroundStyle(Design.Colors.Semantic.success)
                    Text("Certificate of Analysis")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                    Spacer()
                }

                if let labName = coa.labName {
                    DetailRow(label: "Lab", value: labName)
                }
                if let batch = coa.batchNumber {
                    DetailRow(label: "Batch", value: batch)
                }
                if let testDate = coa.testDate {
                    DetailRow(label: "Tested", value: testDate.formatted(date: .abbreviated, time: .omitted))
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.03)))
        }
    }

    // MARK: - Metadata

    private var metadataSection: some View {
        VStack(spacing: 6) {
            if let sku = product.sku {
                DetailRow(label: "SKU", value: sku)
            }
            if let category = product.categoryName {
                DetailRow(label: "Category", value: category)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.03)))
    }
}
