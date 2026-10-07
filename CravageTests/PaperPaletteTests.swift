import XCTest
import SwiftUI
import UIKit
@testable import Cravage

/// The Paper palette in both appearances: light (the 2026-09-14 look) and Night (chosen
/// 2026-10-04). Every pairing of text and the ground it sits on must stay readable in both.
final class PaperPaletteTests: XCTestCase {
    private func rgb(_ color: Color, _ style: UIUserInterfaceStyle) -> (Double, Double, Double) {
        let resolved = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b))
    }

    /// WCAG relative luminance and contrast ratio.
    private func contrast(_ a: Color, _ b: Color, _ style: UIUserInterfaceStyle) -> Double {
        func luminance(_ c: (Double, Double, Double)) -> Double {
            func channel(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
            return 0.2126 * channel(c.0) + 0.7152 * channel(c.1) + 0.0722 * channel(c.2)
        }
        let (x, y) = (luminance(rgb(a, style)), luminance(rgb(b, style)))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    func testNightIsTheChosenDarkPalette() {
        XCTAssertEqual(hex(Paper.paper, .dark), "11141A")
        XCTAssertEqual(hex(Paper.ink, .dark), "ECEEF2")
        XCTAssertEqual(hex(Paper.paper, .light), "FBF6EE", "the light look is unchanged")
        XCTAssertEqual(hex(Paper.ink, .light), "1F1A17")
    }

    /// Text on its ground, in Night: every pairing at least 4.5:1 (WCAG AA for body text).
    func testEveryTextPairingIsReadableInNight() {
        let pairs: [(String, Color, Color)] = [
            ("ink on paper", Paper.ink, Paper.paper), ("muted on paper", Paper.muted, Paper.paper),
            ("accent on paper", Paper.accent, Paper.paper), ("danger on paper", Paper.danger, Paper.paper),
            ("success on paper", Paper.success, Paper.paper), ("ink on card", Paper.ink, Paper.card),
            ("muted on card", Paper.muted, Paper.card), ("white on accent fill", .white, Paper.accentFill),
            ("on-ink on ink", Paper.onInk, Paper.ink),
        ]
        for (name, text, ground) in pairs {
            XCTAssertGreaterThanOrEqual(contrast(text, ground, .dark), 4.5, name)
        }
    }

    /// The badge and size-picker text sits on an ink circle; ink turns light in Night, so the text
    /// colour has to turn with it rather than stay white.
    func testTextOnAnInkCircleIsReadableInBothAppearances() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            XCTAssertGreaterThanOrEqual(contrast(Paper.onInk, Paper.ink, style), 4.5, "\(style.rawValue)")
        }
    }

    private func hex(_ color: Color, _ style: UIUserInterfaceStyle) -> String {
        let (r, g, b) = rgb(color, style)
        return String(format: "%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }
}

/// Accessibility pass 2026-10-04: every Paper font used a fixed size, so text ignored the phone's
/// Text Size setting. Sizes are now design sizes at the default ("Large") that follow it.
final class PaperTypeTests: XCTestCase {
    func testFontsFollowThePhonesTextSize() {
        XCTAssertEqual(Paper.scaled(17, for: .large), 17, accuracy: 0.01, "the default size is the design size")
        XCTAssertGreaterThan(Paper.scaled(17, for: .xxxLarge), 17)
        XCTAssertGreaterThan(Paper.scaled(17, for: .accessibility3), 34, "body text reaches twice its size")
        XCTAssertLessThan(Paper.scaled(17, for: .xSmall), 17)
    }

    func testHeadingsGrowLessThanBodyText() {
        let body = Paper.scaled(17, for: .accessibility5) / 17
        let heading = Paper.scaled(34, for: .accessibility5) / 34
        XCTAssertLessThan(heading, body, "a 34pt heading tripled would not fit a phone's width")
    }
}
