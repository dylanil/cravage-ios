import SwiftUI
import UIKit

/// The "Paper" look chosen on 2026-09-14: editorial serif headings, hairline rules,
/// numbered steps, drawn illustrations. Values were read off the approved step 4
/// mockups, retired on 2026-10-04 once every screen was built (they remain in git history); this
/// file is now the reference for the look.
///
/// Each colour has a light value (the approved look) and a dark one, "Night", which was chosen
/// on 2026-10-04 from three dark looks on the design canvas. The app follows the phone's setting
/// unless Settings' Appearance switch picks one (`Appearance`).
enum Paper {
    // MARK: Colour
    static let paper = adaptive(light: 0xFBF6EE, dark: 0x11141A)
    static let ink = adaptive(light: 0x1F1A17, dark: 0xECEEF2)
    static let muted = adaptive(light: 0x6F625A, dark: 0x9AA3B2)
    static let hairline = adaptive(light: 0xE6DACB, dark: 0x2A303B)
    static let card = adaptive(light: 0xFFFDF9, dark: 0x1A1E26)
    /// Eyebrows, links and glyph strokes.
    static let accent = adaptive(light: 0xC2410C, dark: 0xF58A4B)
    /// Filled buttons and the step numerals. White text sits on it in both appearances.
    static let accentFill = adaptive(light: 0xD9480F, dark: 0xC2410C)
    static let success = adaptive(light: 0x2F8F4E, dark: 0x5FC98A)
    static let danger = adaptive(light: 0xC62828, dark: 0xFF7A7A)
    /// Text on an ink-filled shape (a selected size, a filled letter badge): white on dark ink in
    /// the light look, the dark ground on light ink in Night.
    static let onInk = adaptive(light: 0xFFFFFF, dark: 0x11141A)
    /// The body of the phones drawn in the Home illustrations.
    static let phoneBody = adaptive(light: 0xFFFFFF, dark: 0x1A1E26)

    private static func adaptive(light: Int, dark: Int) -> Color {
        Color(UIColor { traits in rgb(traits.userInterfaceStyle == .dark ? dark : light) })
    }

    private static func rgb(_ hex: Int) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    // MARK: Metric
    /// Side margin for body content.
    static let gutter: CGFloat = 26
    /// Side margin for the bottom button stack, which sits slightly wider than the text.
    static let buttonGutter: CGFloat = 22
    static let bottomInset: CGFloat = 34
    static let buttonHeight: CGFloat = 54
    static let corner: CGFloat = 14

    // MARK: Type
    static func serif(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    enum Face { case serif, mono, sans }

    /// A design size at the phone's text size. The sizes above are read at the default ("Large");
    /// each follows the curve of the nearest iOS text style, so body text grows the most and
    /// headings, already large, grow less.
    static func scaled(_ size: CGFloat, for typeSize: DynamicTypeSize) -> CGFloat {
        let style: UIFont.TextStyle
        switch size {
        case ..<14: style = .footnote
        case ..<19: style = .body
        case ..<24: style = .title3
        case ..<30: style = .title1
        default: style = .largeTitle
        }
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(typeSize))
        return UIFontMetrics(forTextStyle: style).scaledValue(for: size, compatibleWith: traits)
    }

    static func font(_ face: Face, _ size: CGFloat, weight: Font.Weight?) -> Font {
        switch face {
        case .serif: return serif(size, weight: weight ?? .semibold)
        case .mono: return mono(size, weight: weight ?? .bold)
        case .sans: return sans(size, weight: weight ?? .regular)
        }
    }
}

/// Sets a Paper font that follows the phone's text size, and updates when it changes.
private struct PaperFont: ViewModifier {
    @Environment(\.dynamicTypeSize) private var typeSize
    let face: Paper.Face
    let size: CGFloat
    let weight: Font.Weight?

    func body(content: Content) -> some View {
        content.font(Paper.font(face, Paper.scaled(size, for: typeSize), weight: weight))
    }
}

extension View {
    /// A Paper face at a design size, scaled to the phone's text size (Settings, Accessibility,
    /// Display and Text Size). Every text in the app uses this rather than a fixed size.
    func paperFont(_ face: Paper.Face, _ size: CGFloat, weight: Font.Weight? = nil) -> some View {
        modifier(PaperFont(face: face, size: size, weight: weight))
    }

    /// The page ground every screen sits on.
    func paperBackground() -> some View {
        background(Paper.paper.ignoresSafeArea())
    }
}
