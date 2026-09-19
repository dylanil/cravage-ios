import SwiftUI

/// The "Paper" look the owner chose on 2026-09-14: editorial serif headings, hairline rules,
/// numbered steps, drawn illustrations. Values are read off the approved mockups in
/// `design/mockups/`; change them there first.
///
/// The palette is fixed rather than semantic because the dark variant of this look has not been
/// designed yet, and the app pins itself to the light appearance until it has.
enum Paper {
    // MARK: Colour
    static let paper = Color(red: 0.984, green: 0.965, blue: 0.933)      // #FBF6EE
    static let ink = Color(red: 0.122, green: 0.102, blue: 0.090)        // #1F1A17
    static let muted = Color(red: 0.435, green: 0.384, blue: 0.353)      // #6F625A
    static let hairline = Color(red: 0.902, green: 0.855, blue: 0.796)   // #E6DACB
    static let card = Color(red: 1.0, green: 0.992, blue: 0.976)         // #FFFDF9
    /// Eyebrows, links and glyph strokes.
    static let accent = Color(red: 0.761, green: 0.255, blue: 0.047)     // #C2410C
    /// Filled buttons and the step numerals.
    static let accentFill = Color(red: 0.851, green: 0.282, blue: 0.059) // #D9480F
    static let success = Color(red: 0.184, green: 0.561, blue: 0.306)    // #2F8F4E
    static let danger = Color(red: 0.776, green: 0.157, blue: 0.157)     // #C62828

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
}

extension View {
    /// The page ground every screen sits on.
    func paperBackground() -> some View {
        background(Paper.paper.ignoresSafeArea())
    }
}
