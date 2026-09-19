import SwiftUI

/// The three drawn illustrations beside the numbered steps on Home, ported from the approved
/// mockup SVGs. Each is authored in the mockups' 104x80 viewBox and scaled to the frame it is
/// given, so the geometry can be compared against `design/mockups/Main.dc.html` line by line.
private enum Ink {
    static let blush = Color(red: 1.0, green: 0.922, blue: 0.867)       // #FFEBDD
    static let blushLine = Color(red: 0.953, green: 0.788, blue: 0.667) // #F3C9AA
    static let amber = Color(red: 0.965, green: 0.698, blue: 0.290)     // #F6B24A
    static let orange = Color(red: 0.949, green: 0.420, blue: 0.129)    // #F26B21
    static let coral = Color(red: 0.961, green: 0.545, blue: 0.420)     // #F58B6B
    static let curve = Color(red: 0.914, green: 0.722, blue: 0.584)     // #E9B895
}

private let viewBox = CGSize(width: 104, height: 80)

/// A phone body drawn about its own centre, as the mockup's `<g>` transforms do.
private func phone(in context: inout GraphicsContext, at point: CGPoint, rotation: Angle,
                   screen: Color, width: CGFloat = 18, height: CGFloat = 30, corner: CGFloat = 4.5,
                   screenInset: CGSize = CGSize(width: 6, height: 11), screenSize: CGSize = CGSize(width: 12, height: 17)) {
    var layer = context
    layer.translateBy(x: point.x, y: point.y)
    layer.rotate(by: rotation)
    let body = Path(roundedRect: CGRect(x: -width / 2, y: -height / 2, width: width, height: height), cornerRadius: corner)
    layer.fill(body, with: .color(.white))
    layer.stroke(body, with: .color(Paper.ink), lineWidth: 1.6)
    let glass = Path(roundedRect: CGRect(x: -screenInset.width, y: -screenInset.height,
                                         width: screenSize.width, height: screenSize.height), cornerRadius: 2)
    layer.fill(glass, with: .color(screen))
    var bar = Path()
    bar.move(to: CGPoint(x: -2.5, y: 10.5))
    bar.addLine(to: CGPoint(x: 2.5, y: 10.5))
    layer.stroke(bar, with: .color(Paper.ink), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
}

/// Step 1: three phones around a room.
struct GatherIllustration: View {
    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / viewBox.width, y: size.height / viewBox.height)
            let rug = Path(ellipseIn: CGRect(x: 12, y: 32, width: 80, height: 36))
            context.fill(rug, with: .color(Ink.blush))
            let rugLine = Path(ellipseIn: CGRect(x: 12, y: 30, width: 80, height: 36))
            context.stroke(rugLine, with: .color(Ink.blushLine), lineWidth: 1.4)
            phone(in: &context, at: CGPoint(x: 22, y: 42), rotation: .degrees(-16), screen: Ink.amber)
            phone(in: &context, at: CGPoint(x: 52, y: 30), rotation: .degrees(0), screen: Ink.orange)
            phone(in: &context, at: CGPoint(x: 82, y: 42), rotation: .degrees(16), screen: Ink.coral)
        }
        .accessibilityHidden(true)
    }
}

/// Step 2: two phones showing the same code, with a tick between them.
struct MatchCodeIllustration: View {
    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / viewBox.width, y: size.height / viewBox.height)
            for centre in [CGPoint(x: 26, y: 40), CGPoint(x: 78, y: 40)] {
                var layer = context
                layer.translateBy(x: centre.x, y: centre.y)
                let body = Path(roundedRect: CGRect(x: -15, y: -26, width: 30, height: 52), cornerRadius: 7)
                layer.fill(body, with: .color(.white))
                layer.stroke(body, with: .color(Paper.ink), lineWidth: 1.6)
                for (y, width, colour) in [(-12.0, 20.0, Paper.ink), (-3.0, 20.0, Paper.ink), (6.0, 12.0, Ink.orange)] {
                    let line = Path(roundedRect: CGRect(x: -10, y: y, width: width, height: 5), cornerRadius: 2.5)
                    layer.fill(line, with: .color(colour))
                }
            }
            var arc = Path()
            arc.move(to: CGPoint(x: 41, y: 26))
            arc.addQuadCurve(to: CGPoint(x: 63, y: 26), control: CGPoint(x: 52, y: 14))
            context.stroke(arc, with: .color(Paper.success),
                           style: StrokeStyle(lineWidth: 1.8, dash: [3, 3]))
            context.fill(Path(ellipseIn: CGRect(x: 43, y: 8, width: 18, height: 18)), with: .color(Paper.success))
            var tick = Path()
            tick.move(to: CGPoint(x: 47.5, y: 17.2))
            tick.addLine(to: CGPoint(x: 50.8, y: 20.3))
            tick.addLine(to: CGPoint(x: 56.5, y: 14))
            context.stroke(tick, with: .color(.white),
                           style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

/// Step 3: three masked shares flowing into one average.
struct MaskedShareIllustration: View {
    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / viewBox.width, y: size.height / viewBox.height)
            for (y, colour) in [(10.0, Ink.amber), (32.0, Ink.orange), (54.0, Ink.coral)] {
                let pill = Path(roundedRect: CGRect(x: 8, y: y, width: 34, height: 16), cornerRadius: 8)
                context.fill(pill, with: .color(colour))
                var hatch = Path()
                for x in [7.0, 14.0, 21.0] {
                    hatch.move(to: CGPoint(x: 8 + x, y: y + 11))
                    hatch.addLine(to: CGPoint(x: 8 + x + 5, y: y + 5))
                }
                context.stroke(hatch, with: .color(.white.opacity(0.85)),
                               style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
            var funnel = Path()
            funnel.move(to: CGPoint(x: 44, y: 18))
            funnel.addCurve(to: CGPoint(x: 70, y: 40), control1: CGPoint(x: 58, y: 18), control2: CGPoint(x: 60, y: 40))
            funnel.move(to: CGPoint(x: 44, y: 40))
            funnel.addLine(to: CGPoint(x: 70, y: 40))
            funnel.move(to: CGPoint(x: 44, y: 62))
            funnel.addCurve(to: CGPoint(x: 70, y: 40), control1: CGPoint(x: 58, y: 62), control2: CGPoint(x: 60, y: 40))
            context.stroke(funnel, with: .color(Ink.curve),
                           style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            let dial = CGRect(x: 69, y: 25, width: 30, height: 30)
            context.fill(Path(ellipseIn: dial), with: .color(Ink.orange))
            context.stroke(Path(ellipseIn: dial), with: .color(.white.opacity(0.5)), lineWidth: 2)
            var divide = Path()
            divide.move(to: CGPoint(x: 77, y: 40))
            divide.addLine(to: CGPoint(x: 91, y: 40))
            context.stroke(divide, with: .color(.white), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
            context.fill(Path(ellipseIn: CGRect(x: 82, y: 32, width: 4, height: 4)), with: .color(.white))
            context.fill(Path(ellipseIn: CGRect(x: 82, y: 44, width: 4, height: 4)), with: .color(.white))
        }
        .accessibilityHidden(true)
    }
}
