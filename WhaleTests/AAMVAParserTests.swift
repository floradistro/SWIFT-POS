//
//  AAMVAParserTests.swift
//  WhaleTests
//
//  Tests for AAMVA PDF-417 barcode parser.
//

import Testing
@testable import Whale

struct AAMVAParserTests {

    // MARK: - Basic Parsing

    @Test func parseValidBarcode() throws {
        let barcode = "@\n\u{1E}\rANSI 636045090002DL00410278ZC03200024DL\rDCSJOHNSON\rDACJOHN\rDADMICHAEL\rDBB01151990\rDAG123 MAIN ST\rDAISAN FRANCISCO\rDAJCA\rDAK941100000\rDAQ12345678\rDBA01152030\rDBD01152020\r"
        let result = try AAMVAParser.parse(barcode)

        #expect(result.lastName == "Johnson")
        #expect(result.firstName == "John")
        #expect(result.middleName == "Michael")
        #expect(result.dateOfBirth == "1990-01-15")
        #expect(result.streetAddress == "123 Main St")
        #expect(result.city == "San Francisco")
        #expect(result.state == "CA")
        #expect(result.zipCode == "941100000")
        #expect(result.licenseNumber == "12345678")
    }

    @Test func emptyDataThrows() {
        #expect(throws: AAMVAError.self) {
            _ = try AAMVAParser.parse("")
        }
    }

    @Test func invalidFormatThrows() {
        #expect(throws: AAMVAError.self) {
            _ = try AAMVAParser.parse("this is not a barcode")
        }
    }

    // MARK: - Name Normalization

    @Test func normalizesAllCapsNames() throws {
        let barcode = "@\n\u{1E}\rANSI 636045090002DL\rDCSSMITH\rDACJANE\rDADMARIE\rDBB05201985\rDAQ99999999\r"
        let result = try AAMVAParser.parse(barcode)

        #expect(result.lastName == "Smith")
        #expect(result.firstName == "Jane")
        #expect(result.middleName == "Marie")
    }

    @Test func normalizesMcName() throws {
        let barcode = "@\n\u{1E}\rANSI 636045090002DL\rDCSMCDONALD\rDACRONALD\rDBB03101970\rDAQ88888888\r"
        let result = try AAMVAParser.parse(barcode)

        #expect(result.lastName == "McDonald")
    }

    @Test func normalizesApostropheName() throws {
        let barcode = "@\n\u{1E}\rANSI 636045090002DL\rDCSO'BRIEN\rDACSEAN\rDBB07041980\rDAQ77777777\r"
        let result = try AAMVAParser.parse(barcode)

        #expect(result.lastName == "O'Brien")
    }

    // MARK: - Date Parsing

    @Test func parsesMMDDCCYYDate() throws {
        let barcode = "@\n\u{1E}\rANSI 636045090002DL\rDCSDOE\rDACJANE\rDBB12251995\rDAQ11111111\r"
        let result = try AAMVAParser.parse(barcode)

        #expect(result.dateOfBirth == "1995-12-25")
    }

    @Test func parsesCCYYMMDDDate() throws {
        // Some states use CCYYMMDD format
        let barcode = "@\n\u{1E}\rANSI 636045090002DL\rDCSDOE\rDACJOHN\rDBB19950101\rDAQ22222222\r"
        let result = try AAMVAParser.parse(barcode)

        // Parser tries MMDDCCYY first; 19/95 would fail month check, so falls through to CCYYMMDD
        #expect(result.dateOfBirth == "1995-01-01")
    }

    // MARK: - Full Name Fallback (DAA)

    @Test func parsesFromFullNameField() throws {
        let barcode = "@\n\u{1E}\rANSI 636045090002DL\rDAAJOHNSON,JOHN,MICHAEL\rDBB01011990\rDAQ33333333\r"
        let result = try AAMVAParser.parse(barcode)

        #expect(result.firstName == "John")
        #expect(result.lastName == "Johnson")
    }

    // MARK: - Address Normalization

    @Test func normalizesZipCode() throws {
        let barcode = "@\n\u{1E}\rANSI 636045090002DL\rDCSDOE\rDACJOHN\rDBB01011990\rDAQ44444444\rDAK941102345 \r"
        let result = try AAMVAParser.parse(barcode)

        #expect(result.zipCode == "941102345")
    }

    // MARK: - Missing Fields

    @Test func handlesMissingOptionalFields() throws {
        let barcode = "@\n\u{1E}\rANSI 636045090002DL\rDCSDOE\rDACJOHN\rDBB01011990\rDAQ55555555\r"
        let result = try AAMVAParser.parse(barcode)

        #expect(result.firstName == "John")
        #expect(result.lastName == "Doe")
        #expect(result.streetAddress == nil)
        #expect(result.city == nil)
        #expect(result.state == nil)
        #expect(result.height == nil)
        #expect(result.eyeColor == nil)
    }
}
