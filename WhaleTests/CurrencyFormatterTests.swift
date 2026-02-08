//
//  CurrencyFormatterTests.swift
//  WhaleTests
//
//  Tests for USD currency formatting.
//

import Foundation
import Testing
@testable import Whale

struct CurrencyFormatterTests {

    // MARK: - Decimal Formatting

    @Test func formatsWholeNumber() {
        let result = CurrencyFormatter.format(Decimal(100))
        #expect(result == "$100.00")
    }

    @Test func formatsDecimalAmount() {
        let result = CurrencyFormatter.format(Decimal(string: "49.99")!)
        #expect(result == "$49.99")
    }

    @Test func formatsZero() {
        let result = CurrencyFormatter.format(Decimal(0))
        #expect(result == "$0.00")
    }

    @Test func formatsLargeAmount() {
        let result = CurrencyFormatter.format(Decimal(string: "1234.56")!)
        #expect(result == "$1,234.56")
    }

    @Test func formatsSingleCent() {
        let result = CurrencyFormatter.format(Decimal(string: "0.01")!)
        #expect(result == "$0.01")
    }

    // MARK: - Double Formatting

    @Test func formatsDoubleAmount() {
        let result = CurrencyFormatter.format(29.99)
        #expect(result == "$29.99")
    }

    @Test func formatsDoubleZero() {
        let result = CurrencyFormatter.format(0.0)
        #expect(result == "$0.00")
    }

    @Test func formatsLargeDouble() {
        let result = CurrencyFormatter.format(9999.99)
        #expect(result == "$9,999.99")
    }
}
