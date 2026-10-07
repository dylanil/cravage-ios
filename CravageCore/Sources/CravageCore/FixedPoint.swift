// FixedPoint: the numeric domain of a round (docs/SPEC.md section 1).
//
// Exact ports of parseDecimalToFixed / formatFixed / formatAverageFixed from the SMPC web repo's
// public/static/smpc-core.js (pinned commit in Tools/check_verifier_sync.sh), on Int64 instead of
// BigInt, plus the domain check the phone needs because Int64 is finite. No Double, no BigInt,
// nowhere in this file; every intermediate is Int64 or UInt64 and every step is checked for the
// range it can reach.

/// Errors from parsing a user-entered figure. Both carry a plain-English message for the UI.
public enum FixedPointError: Error, Equatable, Sendable {
    /// Not a plain ASCII decimal: exponent notation, grouping separators, non-ASCII digits, blank.
    case invalidFormat
    /// A well-formed decimal whose magnitude reaches 10^18 fixed units (SPEC section 1 cap).
    case outOfDomain

    public var message: String {
        switch self {
        case .invalidFormat:
            return "Enter a plain decimal number using digits 0-9, with no commas, spaces or exponent notation."
        case .outOfDomain:
            return "Figures up to 999,999,999,999.99 are supported."
        }
    }
}

public enum FixedPoint {
    /// Figures cross the wire as decimal-string integers scaled by 10^6. Must match the web app.
    public static let scale: Int64 = 1_000_000
    public static let scaleDecimalPlaces = 6

    /// Magnitude cap in fixed units: a figure is in domain when |fixed| < cap. This is a sum-
    /// correctness requirement, not a secrecy one: masks cancel mod 2^64, and the residual is the
    /// exact signed true sum only while |true sum| < 2^63. Never raise `cap` or `maxParties`
    /// without re-checking `maxParties x cap < 2^63` (pinned by `sumOfMaxPartiesAtCapFitsInt64`).
    public static let cap: Int64 = 1_000_000_000_000_000_000
    public static let maxParties = 8
    /// Largest in-domain magnitude: 999,999,999,999.999999 in the user's units.
    public static let maxMagnitude: Int64 = cap - 1

    /// SPEC section 1 required assertion, evaluated with overflow reporting so that a change to
    /// either constant turns this false instead of trapping or wrapping.
    public static let sumOfMaxPartiesAtCapFitsInt64: Bool = {
        let product = Int64(maxParties).multipliedReportingOverflow(by: cap)
        return !product.overflow && product.partialValue < Int64.max
    }()

    // MARK: - Parsing

    /// Parse a user-entered ASCII decimal string into the 10^6 fixed-point integer used on the
    /// wire. Grammar, byte for byte the JS regular expression after trimming:
    /// `^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)$`. More than six decimal places round to the
    /// nearest micro-unit, half away from zero, judged on the seventh digit alone (as the JS does).
    /// Rejects anything whose magnitude reaches `cap`, including a value that reaches it only
    /// through that rounding.
    public static func parseDecimalToFixed(_ raw: String) throws -> Int64 {
        let bytes = Array(trimmedLikeJavaScript(raw).utf8)
        var index = 0
        var negative = false
        if index < bytes.count, bytes[index] == UInt8(ascii: "+") || bytes[index] == UInt8(ascii: "-") {
            negative = bytes[index] == UInt8(ascii: "-")
            index += 1
        }
        var wholeDigits: [UInt8] = []
        while index < bytes.count, isAsciiDigit(bytes[index]) {
            wholeDigits.append(bytes[index] - UInt8(ascii: "0"))
            index += 1
        }
        var fracDigits: [UInt8] = []
        if index < bytes.count, bytes[index] == UInt8(ascii: ".") {
            index += 1
            while index < bytes.count, isAsciiDigit(bytes[index]) {
                fracDigits.append(bytes[index] - UInt8(ascii: "0"))
                index += 1
            }
            // ".5" is allowed, "." and "5." need at least one digit somewhere: `[0-9]+(\.[0-9]*)?`
            // covers "5.", `\.[0-9]+` covers ".5", nothing covers ".".
            if wholeDigits.isEmpty && fracDigits.isEmpty { throw FixedPointError.invalidFormat }
        } else if wholeDigits.isEmpty {
            throw FixedPointError.invalidFormat
        }
        if index != bytes.count { throw FixedPointError.invalidFormat }

        // Domain: strip leading zeros, then the whole part must have at most 12 significant digits
        // (whole < 10^12 so whole x 10^6 < 10^18). Checked on digit count before any arithmetic so
        // an arbitrarily long input can never overflow.
        var firstSignificant = 0
        while firstSignificant < wholeDigits.count, wholeDigits[firstSignificant] == 0 { firstSignificant += 1 }
        let significant = wholeDigits[firstSignificant...]
        if significant.count > 12 { throw FixedPointError.outOfDomain }

        var fixed: Int64 = 0
        for digit in significant { fixed = fixed * 10 + Int64(digit) }   // < 10^12
        fixed *= scale                                                     // < 10^18
        var micros: Int64 = 0
        for position in 0..<scaleDecimalPlaces {
            let digit: Int64 = position < fracDigits.count ? Int64(fracDigits[position]) : 0
            micros = micros * 10 + digit
        }
        fixed += micros                                                    // <= 10^18 - 1
        if fracDigits.count > scaleDecimalPlaces, fracDigits[scaleDecimalPlaces] >= 5 {
            fixed += 1                                                     // <= 10^18
        }
        if fixed >= cap { throw FixedPointError.outOfDomain }
        return negative ? -fixed : fixed
    }

    // MARK: - Display

    /// Render a fixed-point integer for display at up to `maxDecimalPlaces` decimal places,
    /// stripping trailing zeros and never rendering "-0". Total over Int64.
    public static func formatFixed(_ fixed: Int64, maxDecimalPlaces: Int = 2) -> String {
        displayUnitsToString(roundedDisplayUnits(fixed, denominator: 1, maxDecimalPlaces: maxDecimalPlaces),
                             maxDecimalPlaces: maxDecimalPlaces)
    }

    /// Render `sumFixed / count` exactly, rounding only once at the display precision.
    public static func formatAverageFixed(_ sumFixed: Int64, count: Int, maxDecimalPlaces: Int = 2) -> String {
        displayUnitsToString(roundedDisplayUnits(sumFixed, denominator: count, maxDecimalPlaces: maxDecimalPlaces),
                             maxDecimalPlaces: maxDecimalPlaces)
    }

    /// `round_half_away_from_zero(fixed x 10^maxDp / (denominator x scale))` as a signed count of
    /// display units. The JS computes `abs x 10^maxDp` directly in BigInt; here the division is
    /// done in two exact steps (whole part first, then the remainder scaled) so nothing exceeds
    /// UInt64 for any Int64 input and any denominator up to `maxParties`.
    private static func roundedDisplayUnits(_ fixed: Int64, denominator: Int, maxDecimalPlaces: Int) -> (negative: Bool, units: UInt64) {
        precondition((0...scaleDecimalPlaces).contains(maxDecimalPlaces), "maxDecimalPlaces must be 0...6")
        precondition(denominator > 0, "denominator must be positive")
        let magnitude = fixed.magnitude                                   // UInt64, total over Int64
        let divisor = UInt64(denominator) * UInt64(scale)
        let displayScale = pow10(maxDecimalPlaces)
        let whole = magnitude / divisor
        let remainder = magnitude % divisor                               // < divisor
        let scaledRemainder = remainder * displayScale                    // < divisor x 10^6
        var units = whole * displayScale + scaledRemainder / divisor
        let rest = scaledRemainder % divisor
        if rest * 2 >= divisor { units += 1 }                             // half away from zero
        return (fixed < 0, units)
    }

    private static func displayUnitsToString(_ value: (negative: Bool, units: UInt64), maxDecimalPlaces: Int) -> String {
        if value.units == 0 { return "0" }
        let displayScale = pow10(maxDecimalPlaces)
        let whole = value.units / displayScale
        var frac = String(value.units % displayScale)
        if frac.count < maxDecimalPlaces { frac = String(repeating: "0", count: maxDecimalPlaces - frac.count) + frac }
        while frac.hasSuffix("0") { frac.removeLast() }
        return (value.negative ? "-" : "") + String(whole) + (frac.isEmpty ? "" : "." + frac)
    }

    // MARK: - Helpers

    private static func pow10(_ n: Int) -> UInt64 {
        var result: UInt64 = 1
        for _ in 0..<n { result *= 10 }
        return result
    }

    private static func isAsciiDigit(_ byte: UInt8) -> Bool {
        byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9")
    }

    /// JavaScript's String.prototype.trim strips Unicode White_Space plus line terminators from
    /// both ends. Anything it would leave behind that is not ASCII fails the grammar anyway.
    private static func trimmedLikeJavaScript(_ s: String) -> Substring {
        let isTrimmable: (Character) -> Bool = { character in
            character.unicodeScalars.allSatisfy { scalar in
                scalar.properties.isWhitespace || scalar == "\u{FEFF}"
            }
        }
        var slice = Substring(s)
        while let first = slice.first, isTrimmable(first) { slice.removeFirst() }
        while let last = slice.last, isTrimmable(last) { slice.removeLast() }
        return slice
    }
}
