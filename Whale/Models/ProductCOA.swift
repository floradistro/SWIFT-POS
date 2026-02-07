//
//  ProductCOA.swift
//  Whale
//
//  Certificate of Analysis models for product lab testing data.
//

import Foundation

// MARK: - Product COA

struct ProductCOA: Codable, Sendable, Identifiable {
    let id: UUID
    let productId: UUID?
    let fileUrl: String?
    let fileName: String?
    let labName: String?
    let testDate: Date?
    let expiryDate: Date?
    let batchNumber: String?
    let testResults: COATestResults?
    let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case productId = "product_id"
        case fileUrl = "file_url"
        case fileName = "file_name"
        case labName = "source_name"
        case testDate = "document_date"
        case expiryDate = "expiry_date"
        case batchNumber = "reference_number"
        case testResults = "data"
        case isActive = "is_active"
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        productId = try container.decodeIfPresent(UUID.self, forKey: .productId)
        fileUrl = try container.decodeIfPresent(String.self, forKey: .fileUrl)
        fileName = try container.decodeIfPresent(String.self, forKey: .fileName)
        labName = try container.decodeIfPresent(String.self, forKey: .labName)
        batchNumber = try container.decodeIfPresent(String.self, forKey: .batchNumber)
        isActive = (try? container.decodeIfPresent(Bool.self, forKey: .isActive)) ?? true

        if let dateString = try? container.decodeIfPresent(String.self, forKey: .testDate) {
            testDate = Self.parseDate(dateString)
        } else {
            testDate = try? container.decodeIfPresent(Date.self, forKey: .testDate)
        }

        if let dateString = try? container.decodeIfPresent(String.self, forKey: .expiryDate) {
            expiryDate = Self.parseDate(dateString)
        } else {
            expiryDate = try? container.decodeIfPresent(Date.self, forKey: .expiryDate)
        }

        testResults = try? container.decodeIfPresent(COATestResults.self, forKey: .testResults)
    }

    private static func parseDate(_ string: String) -> Date? {
        let formatters: [DateFormatter] = {
            let iso = DateFormatter()
            iso.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"

            let simple = DateFormatter()
            simple.dateFormat = "yyyy-MM-dd"

            return [iso, simple]
        }()

        for formatter in formatters {
            if let date = formatter.date(from: string) {
                return date
            }
        }
        return nil
    }

    var coaUrl: URL? {
        guard let fileUrl else { return nil }
        return URL(string: fileUrl)
    }
}

// MARK: - COA Test Results

struct COATestResults: Codable, Sendable {
    let thcTotal: Double?
    let thca: Double?
    let d9Thc: Double?
    let cbdTotal: Double?
    let cbda: Double?
    let strainType: String?
    let terpenes: [String: Double]?
    let contaminants: ContaminantResults?

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: FlexibleCodingKeys.self)

        thcTotal = Self.decodeDouble(from: container, keys: ["thc_total", "thcTotal", "total_thc", "totalThc", "THC", "thc"])
        thca = Self.decodeDouble(from: container, keys: ["thca", "THCA", "thca_percent", "thcaPercent"])
        d9Thc = Self.decodeDouble(from: container, keys: ["d9_thc", "d9Thc", "delta9_thc", "delta9Thc", "d9", "delta9"])
        cbdTotal = Self.decodeDouble(from: container, keys: ["cbd_total", "cbdTotal", "total_cbd", "totalCbd", "CBD", "cbd"])
        cbda = Self.decodeDouble(from: container, keys: ["cbda", "CBDA", "cbda_percent", "cbdaPercent"])
        strainType = Self.decodeString(from: container, keys: ["strain_type", "strainType", "strain", "type"])

        if let key = FlexibleCodingKeys(stringValue: "terpenes") {
            terpenes = try? container.decodeIfPresent([String: Double].self, forKey: key)
        } else {
            terpenes = nil
        }

        if let key = FlexibleCodingKeys(stringValue: "contaminants") {
            contaminants = try? container.decodeIfPresent(ContaminantResults.self, forKey: key)
        } else {
            contaminants = nil
        }
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: FlexibleCodingKeys.self)
        if let key = FlexibleCodingKeys(stringValue: "thc_total") { try container.encodeIfPresent(thcTotal, forKey: key) }
        if let key = FlexibleCodingKeys(stringValue: "thca") { try container.encodeIfPresent(thca, forKey: key) }
        if let key = FlexibleCodingKeys(stringValue: "d9_thc") { try container.encodeIfPresent(d9Thc, forKey: key) }
        if let key = FlexibleCodingKeys(stringValue: "cbd_total") { try container.encodeIfPresent(cbdTotal, forKey: key) }
        if let key = FlexibleCodingKeys(stringValue: "cbda") { try container.encodeIfPresent(cbda, forKey: key) }
        if let key = FlexibleCodingKeys(stringValue: "strain_type") { try container.encodeIfPresent(strainType, forKey: key) }
        if let key = FlexibleCodingKeys(stringValue: "terpenes") { try container.encodeIfPresent(terpenes, forKey: key) }
        if let key = FlexibleCodingKeys(stringValue: "contaminants") { try container.encodeIfPresent(contaminants, forKey: key) }
    }

    private static func decodeDouble(from container: KeyedDecodingContainer<FlexibleCodingKeys>, keys: [String]) -> Double? {
        for keyString in keys {
            guard let key = FlexibleCodingKeys(stringValue: keyString) else { continue }
            if let value = try? container.decodeIfPresent(Double.self, forKey: key) {
                return value
            }
            if let intValue = try? container.decodeIfPresent(Int.self, forKey: key) {
                return Double(intValue)
            }
            if let stringValue = try? container.decodeIfPresent(String.self, forKey: key),
               let doubleValue = Double(stringValue.replacingOccurrences(of: "%", with: "")) {
                return doubleValue
            }
        }
        return nil
    }

    private static func decodeString(from container: KeyedDecodingContainer<FlexibleCodingKeys>, keys: [String]) -> String? {
        for keyString in keys {
            guard let key = FlexibleCodingKeys(stringValue: keyString) else { continue }
            if let value = try? container.decodeIfPresent(String.self, forKey: key) {
                return value
            }
        }
        return nil
    }
}

// MARK: - Contaminant Results

struct ContaminantResults: Codable, Sendable {
    let pesticides: String?
    let heavyMetals: String?
    let microbials: String?
    let residualSolvents: String?

    enum CodingKeys: String, CodingKey {
        case pesticides
        case heavyMetals = "heavy_metals"
        case microbials
        case residualSolvents = "residual_solvents"
    }
}
