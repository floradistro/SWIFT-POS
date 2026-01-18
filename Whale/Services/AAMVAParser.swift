//
//  AAMVAParser.swift
//  Whale
//
//  Parser for AAMVA PDF-417 barcodes on US/Canadian driver's licenses.
//  Extracts personal information from standardized barcode format.
//
//  Reference: AAMVA DL/ID Card Design Standard (CDS)
//

import Foundation

// MARK: - AAMVA Parser

enum AAMVAParser {

    // MARK: - Parse

    /// Parse a PDF-417 barcode string into structured ID data
    /// - Parameter barcodeData: Raw string from PDF-417 barcode
    /// - Returns: Parsed ScannedID or nil if invalid format
    static func parse(_ barcodeData: String) throws -> ScannedID {
        guard !barcodeData.isEmpty else {
            throw AAMVAError.emptyData
        }

        // Validate AAMVA format - must contain ANSI header
        guard barcodeData.contains("ANSI") else {
            throw AAMVAError.invalidFormat
        }

        // Extract fields using AAMVA data element identifiers
        return ScannedID(
            fullName: extractField(.fullName, from: barcodeData).map { normalizeName($0) },
            firstName: extractFirstName(from: barcodeData),
            middleName: extractField(.middleName, from: barcodeData).map { normalizeName($0) },
            lastName: extractLastName(from: barcodeData),
            licenseNumber: extractField(.licenseNumber, from: barcodeData),
            dateOfBirth: extractDate(.dateOfBirth, from: barcodeData),
            streetAddress: extractField(.streetAddress, from: barcodeData).map { normalizeAddress($0) },
            city: extractField(.city, from: barcodeData).map { normalizeCity($0) },
            state: extractField(.state, from: barcodeData).map { $0.uppercased() },
            zipCode: extractField(.zipCode, from: barcodeData).map { normalizeZip($0) },
            height: extractField(.height, from: barcodeData),
            eyeColor: extractField(.eyeColor, from: barcodeData),
            issueDate: extractDate(.issueDate, from: barcodeData),
            expirationDate: extractDate(.expirationDate, from: barcodeData),
            rawData: barcodeData
        )
    }

    // MARK: - Data Element Identifiers

    /// AAMVA Data Element Identifiers
    private enum DataElement: String, CaseIterable {
        // Name fields
        case fullName = "DAA"           // Full name (Last,First,Middle or Last,First Middle)
        case lastName = "DCS"           // Family name
        case lastNameAlt = "DAB"        // Last name (alternative)
        case firstName = "DAC"          // First name
        case firstNameAlt = "DCT"       // First name (alternative - truncation indicator)
        case middleName = "DAD"         // Middle name(s)

        // Identification
        case licenseNumber = "DAQ"      // Customer ID Number

        // Dates
        case dateOfBirth = "DBB"        // Date of Birth
        case expirationDate = "DBA"     // Document Expiration Date
        case issueDate = "DBD"          // Document Issue Date

        // Address
        case streetAddress = "DAG"      // Street Address
        case city = "DAI"               // City
        case state = "DAJ"              // Jurisdiction Code (State)
        case zipCode = "DAK"            // Postal Code

        // Physical
        case height = "DAU"             // Height
        case eyeColor = "DAY"           // Eye Color

        var pattern: String {
            // Match the element ID followed by content until next element or end
            return "\(rawValue)([^\r\n]+)"
        }
    }

    // MARK: - Field Extraction

    private static func extractField(_ element: DataElement, from data: String) -> String? {
        let pattern = element.pattern
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: data, options: [], range: NSRange(data.startIndex..., in: data)),
              let range = Range(match.range(at: 1), in: data) else {
            return nil
        }

        let value = String(data[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func extractFirstName(from data: String) -> String? {
        // Try DAC first, then DCT
        if let name = extractField(.firstName, from: data) ?? extractField(.firstNameAlt, from: data) {
            return normalizeName(name)
        }

        // Fall back to parsing from full name (DAA)
        if let fullName = extractField(.fullName, from: data) {
            return parseFirstNameFromFull(fullName)
        }

        return nil
    }

    private static func extractLastName(from data: String) -> String? {
        // Try DCS first, then DAB
        if let name = extractField(.lastName, from: data) ?? extractField(.lastNameAlt, from: data) {
            return normalizeName(name)
        }

        // Fall back to parsing from full name (DAA)
        if let fullName = extractField(.fullName, from: data) {
            return parseLastNameFromFull(fullName)
        }

        return nil
    }

    private static func parseFirstNameFromFull(_ fullName: String) -> String? {
        // DAA format is typically: LAST,FIRST,MIDDLE or LAST,FIRST MIDDLE
        let parts = fullName.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 2 else { return nil }

        // First name is second part, possibly with middle name appended
        let firstPart = parts[1]
        let nameParts = firstPart.split(separator: " ")
        guard let firstName = nameParts.first else { return nil }

        return normalizeName(String(firstName))
    }

    private static func parseLastNameFromFull(_ fullName: String) -> String? {
        // DAA format is typically: LAST,FIRST,MIDDLE
        let parts = fullName.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        guard let lastName = parts.first else { return nil }

        return normalizeName(lastName)
    }

    // MARK: - Date Extraction

    private static func extractDate(_ element: DataElement, from data: String) -> String? {
        guard let dateStr = extractField(element, from: data) else { return nil }
        return parseDate(dateStr)
    }

    /// Parse AAMVA date formats to YYYY-MM-DD
    /// Supports: MMDDCCYY, CCYYMMDD
    private static func parseDate(_ dateStr: String) -> String? {
        let digits = dateStr.filter { $0.isNumber }

        guard digits.count == 8 else { return nil }

        // Try MMDDCCYY format first (most common in US)
        if let month = Int(digits.prefix(2)),
           let day = Int(digits.dropFirst(2).prefix(2)),
           month >= 1 && month <= 12,
           day >= 1 && day <= 31 {
            let year = String(digits.suffix(4))
            return "\(year)-\(String(format: "%02d", month))-\(String(format: "%02d", day))"
        }

        // Try CCYYMMDD format
        if let month = Int(digits.dropFirst(4).prefix(2)),
           let day = Int(digits.suffix(2)),
           month >= 1 && month <= 12,
           day >= 1 && day <= 31 {
            let year = String(digits.prefix(4))
            return "\(year)-\(String(format: "%02d", month))-\(String(format: "%02d", day))"
        }

        return nil
    }

    // MARK: - Normalization

    /// Convert name to title case with special handling
    private static func normalizeName(_ name: String) -> String {
        let lowercased = name.lowercased()

        // Special prefixes that should remain lowercase
        let prefixes = ["de", "la", "van", "von", "del", "der"]

        // Special suffixes
        let suffixes = ["ii", "iii", "iv", "jr", "sr"]

        let words = lowercased.split(separator: " ").map { word -> String in
            let wordStr = String(word)

            // Check for special prefixes
            if prefixes.contains(wordStr) {
                return wordStr
            }

            // Check for suffixes (keep uppercase)
            if suffixes.contains(wordStr) {
                return wordStr.uppercased()
            }

            // Handle apostrophe names (O'Brien, McDonald)
            if wordStr.contains("'") {
                return wordStr.split(separator: "'").map { part in
                    part.prefix(1).uppercased() + part.dropFirst()
                }.joined(separator: "'")
            }

            // Handle Mc/Mac names
            if wordStr.hasPrefix("mc") && wordStr.count > 2 {
                return "Mc" + wordStr.dropFirst(2).prefix(1).uppercased() + wordStr.dropFirst(3)
            }
            if wordStr.hasPrefix("mac") && wordStr.count > 3 {
                return "Mac" + wordStr.dropFirst(3).prefix(1).uppercased() + wordStr.dropFirst(4)
            }

            // Standard title case
            return wordStr.prefix(1).uppercased() + wordStr.dropFirst()
        }

        return words.joined(separator: " ")
    }

    /// Normalize street address
    private static func normalizeAddress(_ address: String) -> String {
        var result = address.lowercased()

        // Common abbreviations to keep uppercase
        let abbreviations = [
            "st": "St", "ave": "Ave", "blvd": "Blvd", "dr": "Dr",
            "ln": "Ln", "rd": "Rd", "ct": "Ct", "pl": "Pl",
            "cir": "Cir", "way": "Way", "pkwy": "Pkwy", "hwy": "Hwy",
            "apt": "Apt", "ste": "Ste", "fl": "Fl", "unit": "Unit",
            "n": "N", "s": "S", "e": "E", "w": "W",
            "ne": "NE", "nw": "NW", "se": "SE", "sw": "SW"
        ]

        let words = result.split(separator: " ").map { word -> String in
            let wordStr = String(word).replacingOccurrences(of: ".", with: "")

            if let abbr = abbreviations[wordStr] {
                return abbr
            }

            // Title case for other words
            return wordStr.prefix(1).uppercased() + wordStr.dropFirst()
        }

        return words.joined(separator: " ")
    }

    /// Normalize city name
    private static func normalizeCity(_ city: String) -> String {
        let words = city.lowercased().split(separator: " ").map { word in
            String(word).prefix(1).uppercased() + String(word).dropFirst()
        }
        return words.joined(separator: " ")
    }

    /// Normalize zip code (digits only, max 10 chars)
    private static func normalizeZip(_ zip: String) -> String {
        let digits = zip.filter { $0.isNumber }
        return String(digits.prefix(10))
    }
}

// MARK: - Errors

enum AAMVAError: LocalizedError, Sendable {
    case emptyData
    case invalidFormat
    case parsingFailed(field: String)

    var errorDescription: String? {
        switch self {
        case .emptyData:
            return "No barcode data provided"
        case .invalidFormat:
            return "Invalid AAMVA barcode format - missing ANSI header"
        case .parsingFailed(let field):
            return "Failed to parse field: \(field)"
        }
    }
}
