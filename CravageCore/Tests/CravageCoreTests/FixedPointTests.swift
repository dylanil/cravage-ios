import XCTest
@testable import CravageCore

/// Contract pins for FixedPoint, carried from the SMPC web repo (tests_numeric.js at the pinned
/// commit in Tools/check_verifier_sync.sh). Any vector marked "divergence" is a deliberate
/// difference from the JS, always in the direction of rejecting input the phone cannot represent.
final class FixedPointTests: XCTestCase {

    // MARK: - Domain constants (SPEC section 1)

    func testDomainConstantsAreTheSpecValues() {
        XCTAssertEqual(FixedPoint.scale, 1_000_000)
        XCTAssertEqual(FixedPoint.scaleDecimalPlaces, 6)
        XCTAssertEqual(FixedPoint.cap, 1_000_000_000_000_000_000)
        XCTAssertEqual(FixedPoint.maxParties, 8)
        XCTAssertEqual(FixedPoint.maxMagnitude, 999_999_999_999_999_999)
    }

    /// SPEC section 1 required test: maxParties x cap must stay below 2^63 so the wrapped sum of
    /// N in-domain figures is the exact signed true sum. Fails loudly if either constant moves.
    func testEightCapsFitBelowTwoToTheSixtyThree() {
        let product = Int64(FixedPoint.maxParties).multipliedReportingOverflow(by: FixedPoint.cap)
        XCTAssertFalse(product.overflow, "maxParties x cap overflowed Int64")
        XCTAssertLessThan(product.partialValue, Int64.max, "maxParties x cap must be < 2^63")
        XCTAssertTrue(FixedPoint.sumOfMaxPartiesAtCapFitsInt64)
    }

    func testEightMaximalFiguresSumExactlyWithWrappingArithmetic() {
        var sum: Int64 = 0
        for _ in 0..<FixedPoint.maxParties { sum = sum &+ FixedPoint.maxMagnitude }
        XCTAssertEqual(sum, 7_999_999_999_999_999_992)
        var negative: Int64 = 0
        for _ in 0..<FixedPoint.maxParties { negative = negative &+ (-FixedPoint.maxMagnitude) }
        XCTAssertEqual(negative, -7_999_999_999_999_999_992)
    }

    // MARK: - parseDecimalToFixed: pinned SMPC vectors

    func testParsePinnedVectors() throws {
        XCTAssertEqual(try FixedPoint.parseDecimalToFixed("-12.345678"), -12_345_678)
        XCTAssertEqual(try FixedPoint.parseDecimalToFixed("1.2345678"), 1_234_568)
        XCTAssertEqual(try FixedPoint.parseDecimalToFixed("0.0000005"), 1)
        XCTAssertEqual(try FixedPoint.parseDecimalToFixed("-0.0000005"), -1)
    }

    func testParseRejectsPinnedInputs() {
        for input in ["1e6", "12abc", "1,000", "Infinity", "   ", "\u{0661}\u{0660}"] {
            assertInvalidFormat(input)
        }
    }

    /// Divergence: the JS accepts 9007199254740993 (its test is about Number precision); the phone
    /// rejects it because it exceeds the 10^18 fixed-unit domain. Pinned as out-of-domain, not as
    /// a format error, so the user sees the plain "figures up to" message.
    func testParseDivergenceLargeIntegerIsOutOfDomain() {
        assertOutOfDomain("9007199254740993")
    }

    // MARK: - parseDecimalToFixed: grammar

    func testParseGrammarAcceptsTheSameShapesAsTheJavaScript() throws {
        XCTAssertEqual(try FixedPoint.parseDecimalToFixed("0"), 0)
        XCTAssertEqual(try FixedPoint.parseDecimalToFixed("+5"), 5_000_000)
        XCTAssertEqual(try FixedPoint.parseDecimalToFixed("-5"), -5_000_000)
        XCTAssertEqual(try FixedPoint.parseDecimalToFixed(".5"), 500_000)
        XCTAssertEqual(try FixedPoint.parseDecimalToFixed("-.5"), -500_000)
        XCTAssertEqual(try FixedPoint.parseDecimalToFixed("5."), 5_000_000)
        XCTAssertEqual(try FixedPoint.parseDecimalToFixed("007"), 7_000_000)
        XCTAssertEqual(try FixedPoint.parseDecimalToFixed("  12  "), 12_000_000)
        XCTAssertEqual(try FixedPoint.parseDecimalToFixed("\n12\t"), 12_000_000)
        XCTAssertEqual(try FixedPoint.parseDecimalToFixed("-0"), 0)
        XCTAssertEqual(try FixedPoint.parseDecimalToFixed("-0.0000004"), 0)
        XCTAssertEqual(try FixedPoint.parseDecimalToFixed("1.0000004"), 1_000_000)
        XCTAssertEqual(try FixedPoint.parseDecimalToFixed("1.00000049999"), 1_000_000)
        XCTAssertEqual(try FixedPoint.parseDecimalToFixed("1.0000005"), 1_000_001)
        XCTAssertEqual(try FixedPoint.parseDecimalToFixed("1.000000500000"), 1_000_001)
        XCTAssertEqual(try FixedPoint.parseDecimalToFixed("1.999999"), 1_999_999)
        XCTAssertEqual(try FixedPoint.parseDecimalToFixed("1.9999995"), 2_000_000)
        XCTAssertEqual(try FixedPoint.parseDecimalToFixed("123456.789"), 123_456_789_000)
    }

    func testParseGrammarRejectsWhatTheJavaScriptRejects() {
        for input in ["", "-", "+", ".", "+-1", "1.2.3", "1 000", "1_000", "0x10", "NaN", "1e-6",
                      "1.5e2", "one", "1..2", "--1", "1-", "\u{FF11}", "１２", "12.5.", " . "] {
            assertInvalidFormat(input)
        }
    }

    // MARK: - parseDecimalToFixed: domain boundary

    func testParseAcceptsTheLargestInDomainFigures() throws {
        XCTAssertEqual(try FixedPoint.parseDecimalToFixed("999999999999.999999"), FixedPoint.maxMagnitude)
        XCTAssertEqual(try FixedPoint.parseDecimalToFixed("-999999999999.999999"), -FixedPoint.maxMagnitude)
        XCTAssertEqual(try FixedPoint.parseDecimalToFixed("999999999999.9999994"), FixedPoint.maxMagnitude)
        XCTAssertEqual(try FixedPoint.parseDecimalToFixed("000999999999999.999999"), FixedPoint.maxMagnitude)
        XCTAssertEqual(try FixedPoint.parseDecimalToFixed("999999999999"), 999_999_999_999_000_000)
    }

    func testParseRejectsOneMicroUnitAboveTheCap() {
        assertOutOfDomain("1000000000000")
        assertOutOfDomain("-1000000000000")
        assertOutOfDomain("1000000000000.000000")
        assertOutOfDomain("999999999999.9999995")
        assertOutOfDomain("-999999999999.9999995")
        assertOutOfDomain("0001000000000000")
        assertOutOfDomain("99999999999999999999999999999999999999999999")
        assertOutOfDomain("9223372036854775807")
        assertOutOfDomain("9223372036854775808")
        assertOutOfDomain("18446744073709551616")
    }

    func testOutOfDomainMessageIsThePlainOne() {
        XCTAssertThrowsError(try FixedPoint.parseDecimalToFixed("1000000000000")) { error in
            guard let e = error as? FixedPointError else { return XCTFail("wrong error type \(error)") }
            XCTAssertEqual(e, .outOfDomain)
            XCTAssertTrue(e.message.contains("999,999,999,999.99"), e.message)
        }
    }

    // MARK: - formatFixed and formatAverageFixed: pinned SMPC vectors

    func testFormatPinnedVectors() {
        XCTAssertEqual(FixedPoint.formatFixed(12_345_000), "12.35")
        XCTAssertEqual(FixedPoint.formatFixed(-1), "0")
        XCTAssertEqual(FixedPoint.formatAverageFixed(1_000_000, count: 3), "0.33")
        XCTAssertEqual(FixedPoint.formatAverageFixed(6_000_000, count: 3), "2")
    }

    /// Divergence: the JS pins 9007199254740993000000n and 27021597764222979000000n, which do not
    /// fit Int64. The phone never holds such values (parse rejects them), so the equivalent
    /// precision pins are the largest in-domain figure and the largest possible 8-party sum.
    func testFormatDivergencePrecisionPinsWithinInt64() {
        XCTAssertEqual(FixedPoint.formatFixed(FixedPoint.maxMagnitude, maxDecimalPlaces: 6), "999999999999.999999")
        XCTAssertEqual(FixedPoint.formatFixed(FixedPoint.maxMagnitude), "1000000000000")
        XCTAssertEqual(FixedPoint.formatFixed(-FixedPoint.maxMagnitude, maxDecimalPlaces: 6), "-999999999999.999999")
        XCTAssertEqual(FixedPoint.formatAverageFixed(7_999_999_999_999_999_992, count: 8, maxDecimalPlaces: 6),
                       "999999999999.999999")
        XCTAssertEqual(FixedPoint.formatAverageFixed(7_999_999_999_999_999_992, count: 8), "1000000000000")
        XCTAssertEqual(FixedPoint.formatAverageFixed(-7_999_999_999_999_999_992, count: 8, maxDecimalPlaces: 6),
                       "-999999999999.999999")
        XCTAssertEqual(FixedPoint.formatFixed(7_999_999_999_999_999_992, maxDecimalPlaces: 6),
                       "7999999999999.999992")
    }

    func testFormatRoundsHalfAwayFromZeroAtDisplayPrecision() {
        XCTAssertEqual(FixedPoint.formatFixed(125_000), "0.13")
        XCTAssertEqual(FixedPoint.formatFixed(-125_000), "-0.13")
        XCTAssertEqual(FixedPoint.formatFixed(124_999), "0.12")
        XCTAssertEqual(FixedPoint.formatFixed(-124_999), "-0.12")
        XCTAssertEqual(FixedPoint.formatFixed(5_000), "0.01")
        XCTAssertEqual(FixedPoint.formatFixed(4_999), "0")
        XCTAssertEqual(FixedPoint.formatFixed(-4_999), "0")
        XCTAssertEqual(FixedPoint.formatFixed(-5_000), "-0.01")
        XCTAssertEqual(FixedPoint.formatFixed(999_995_000), "1000")
        XCTAssertEqual(FixedPoint.formatFixed(500_000, maxDecimalPlaces: 0), "1")
        XCTAssertEqual(FixedPoint.formatFixed(499_999, maxDecimalPlaces: 0), "0")
        XCTAssertEqual(FixedPoint.formatFixed(-500_000, maxDecimalPlaces: 0), "-1")
    }

    func testFormatStripsTrailingZerosAndNeverShowsMinusZero() {
        XCTAssertEqual(FixedPoint.formatFixed(0), "0")
        XCTAssertEqual(FixedPoint.formatFixed(-0), "0")
        XCTAssertEqual(FixedPoint.formatFixed(1_000_000), "1")
        XCTAssertEqual(FixedPoint.formatFixed(1_100_000), "1.1")
        XCTAssertEqual(FixedPoint.formatFixed(1_100_000, maxDecimalPlaces: 6), "1.1")
        XCTAssertEqual(FixedPoint.formatFixed(1_000_001, maxDecimalPlaces: 6), "1.000001")
        XCTAssertEqual(FixedPoint.formatFixed(-1, maxDecimalPlaces: 6), "-0.000001")
        XCTAssertEqual(FixedPoint.formatFixed(-4_999, maxDecimalPlaces: 6), "-0.004999")
        XCTAssertEqual(FixedPoint.formatFixed(-4_999, maxDecimalPlaces: 2), "0")
    }

    func testFormatAverageDividesExactlyBeforeRounding() {
        XCTAssertEqual(FixedPoint.formatAverageFixed(2_000_000, count: 3), "0.67")
        XCTAssertEqual(FixedPoint.formatAverageFixed(-2_000_000, count: 3), "-0.67")
        XCTAssertEqual(FixedPoint.formatAverageFixed(1_000_000, count: 3, maxDecimalPlaces: 6), "0.333333")
        XCTAssertEqual(FixedPoint.formatAverageFixed(2_000_000, count: 3, maxDecimalPlaces: 6), "0.666667")
        XCTAssertEqual(FixedPoint.formatAverageFixed(1_000_000, count: 8), "0.13")
        XCTAssertEqual(FixedPoint.formatAverageFixed(60_000_000, count: 3), "20")
        XCTAssertEqual(FixedPoint.formatAverageFixed(0, count: 8), "0")
        XCTAssertEqual(FixedPoint.formatAverageFixed(5_000, count: 1), "0.01")
        XCTAssertEqual(FixedPoint.formatAverageFixed(10_000, count: 2), "0.01")
        XCTAssertEqual(FixedPoint.formatAverageFixed(9_999, count: 2), "0")
    }

    /// formatFixed is total over Int64: shares are uniform over the whole range and a diagnostics
    /// view must never trap on one. Int64.min is the value whose magnitude does not fit Int64.
    func testFormatIsTotalOverInt64() {
        XCTAssertEqual(FixedPoint.formatFixed(Int64.min, maxDecimalPlaces: 6), "-9223372036854.775808")
        XCTAssertEqual(FixedPoint.formatFixed(Int64.max, maxDecimalPlaces: 6), "9223372036854.775807")
        XCTAssertEqual(FixedPoint.formatFixed(Int64.min), "-9223372036854.78")
        XCTAssertEqual(FixedPoint.formatAverageFixed(Int64.min, count: 8, maxDecimalPlaces: 6), "-1152921504606.846976")
    }

    // MARK: - Round trips

    func testParseThenFormatRoundTripsAtSixPlaces() throws {
        for text in ["0", "1", "-1", "12.5", "-12.5", "0.000001", "-0.000001", "123456.789012",
                     "999999999999.999999", "-999999999999.999999", "42.1"] {
            let fixed = try FixedPoint.parseDecimalToFixed(text)
            XCTAssertEqual(FixedPoint.formatFixed(fixed, maxDecimalPlaces: 6), text, "round trip of \(text)")
        }
    }

    func testRandomInDomainFiguresRoundTripAgainstAnIntegerOracle() throws {
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<2000 {
            let magnitude = Int64.random(in: 0...FixedPoint.maxMagnitude, using: &generator)
            let value = Bool.random(using: &generator) ? magnitude : -magnitude
            let whole = magnitude / FixedPoint.scale
            let frac = magnitude % FixedPoint.scale
            let fracText = String(frac).leftPadded(to: 6)
            let text = (value < 0 ? "-" : "") + String(whole) + "." + fracText
            XCTAssertEqual(try FixedPoint.parseDecimalToFixed(text), value, text)
            var expected = text
            while expected.hasSuffix("0") { expected.removeLast() }
            if expected.hasSuffix(".") { expected.removeLast() }
            if expected == "-0" { expected = "0" }
            XCTAssertEqual(FixedPoint.formatFixed(value, maxDecimalPlaces: 6), expected, text)
        }
    }

    // MARK: - Helpers

    private func assertInvalidFormat(_ input: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try FixedPoint.parseDecimalToFixed(input), "accepted \(input.debugDescription)",
                             file: file, line: line) { error in
            XCTAssertEqual(error as? FixedPointError, .invalidFormat, "wrong error for \(input.debugDescription)",
                           file: file, line: line)
        }
    }

    private func assertOutOfDomain(_ input: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try FixedPoint.parseDecimalToFixed(input), "accepted \(input.debugDescription)",
                             file: file, line: line) { error in
            XCTAssertEqual(error as? FixedPointError, .outOfDomain, "wrong error for \(input.debugDescription)",
                           file: file, line: line)
        }
    }
}

private extension String {
    func leftPadded(to width: Int) -> String {
        count >= width ? self : String(repeating: "0", count: width - count) + self
    }
}
