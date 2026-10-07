// Draws the app icon chosen on 2026-10-04: six phones, each linked to its neighbours and to
// the phones two along, which leaves a hexagon in the middle, filled orange with the formula for the
// mean, Σx/n, set like LaTeX maths (upright Σ, italic x and n, a thin rule) in STIX Two, the
// scientific-publishing typeface macOS ships. The links are pairwise secrets that cancel in the sum;
// the formula sits in the space the links make rather than in a node they run into, because nobody
// collects the figures. The three long diagonals are left out so no line crosses the formula.
//
//     swift Tools/gen_app_icon.swift
//
// Two looks of the same drawing (2026-10-05): light, a white ground with hollow ink phones, and
// dark, the original ink ground with paper phones. Each is written as the app icon (AppIcon.png,
// AppIcon-Dark.png) and as BrandMark for the Home top bar, so the home-screen icon and the Home
// logo follow light and dark together. 1024 x 1024, opaque, square (iOS rounds the corners).
// Geometry is in a 100-unit square with y running down, matching the design canvas.
import AppKit
import CoreText

let size = 1024
let unit = CGFloat(size) / 100

func color(_ hex: Int) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}
let orange = color(0xF26B21)

struct Look {
    let ground: CGColor, link: CGColor, phone: CGColor
    /// An outline drawn inside each phone circle, or nil for a solid phone.
    let phoneOutline: CGColor?
    /// The formula and its rule, on the orange hexagon.
    let formula: CGColor
    let files: [String]
}
let assets = "Cravage/Resources/Assets.xcassets"
let looks = [
    Look(ground: color(0xFFFFFF), link: color(0xC9BCAE), phone: color(0xFFFFFF), phoneOutline: color(0x1F1A17),
         formula: color(0xFFFFFF),
         files: ["\(assets)/AppIcon.appiconset/AppIcon.png", "\(assets)/BrandMark.imageset/BrandMark.png"]),
    Look(ground: color(0x1F1A17), link: color(0x6F625A), phone: color(0xFBF6EE), phoneOutline: nil,
         formula: color(0xFBF6EE),
         files: ["\(assets)/AppIcon.appiconset/AppIcon-Dark.png", "\(assets)/BrandMark.imageset/BrandMark-Dark.png"]),
]

/// A canvas point (y down) in Core Graphics space (y up).
func point(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * unit, y: (100 - y) * unit) }

func ring(_ count: Int, radius: Double, startDegrees: Double) -> [CGPoint] {
    (0..<count).map { index in
        let angle = (startDegrees + 360 / Double(count) * Double(index)) * Double.pi / 180
        return point(50 + radius * cos(angle), 50 + radius * sin(angle))
    }
}

func draw(_ look: Look) {
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.setFillColor(look.ground)
    context.fill(CGRect(x: 0, y: 0, width: size, height: size))

    let phones = ring(6, radius: 30, startDegrees: -90)
    context.setStrokeColor(look.link)
    context.setLineWidth(2 * unit)
    for index in 0..<6 {
        for step in [1, 2] {
            context.move(to: phones[index])
            context.addLine(to: phones[(index + step) % 6])
        }
    }
    context.strokePath()

    // The hexagon the links leave between the two triangles.
    let middle = ring(6, radius: 30 / 3.0.squareRoot(), startDegrees: -60)
    context.setFillColor(orange)
    context.addLines(between: middle)
    context.closePath()
    context.fillPath()

    context.setFillColor(look.phone)
    for phone in phones {
        let circle = CGRect(x: phone.x - 6 * unit, y: phone.y - 6 * unit, width: 12 * unit, height: 12 * unit)
        context.fillEllipse(in: circle)
        if let outline = look.phoneOutline {
            context.setStrokeColor(outline)
            context.setLineWidth(2 * unit)
            context.strokeEllipse(in: circle.insetBy(dx: unit, dy: unit))
        }
    }

    // The formula, Σx over n. STIX Two Text Medium: one weight above LaTeX's own, so it holds at
    // home-screen size (chosen over the lighter true-LaTeX weight).
    func setLine(_ runs: [(String, String)], size: Double, centreY: Double) {
        let text = NSMutableAttributedString()
        for (string, fontName) in runs {
            guard let font = NSFont(name: fontName, size: size * unit) else { fatalError("missing font \(fontName)") }
            text.append(NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: NSColor(cgColor: look.formula)!]))
        }
        let line = CTLineCreateWithAttributedString(text)
        // Image bounds are measured from the current text position, so measure from the origin.
        context.textPosition = .zero
        let bounds = CTLineGetImageBounds(line, context)
        let centre = point(50, centreY)
        context.textPosition = CGPoint(x: centre.x - bounds.midX, y: centre.y - bounds.midY)
        CTLineDraw(line, context)
    }
    let upright = "STIXTwoText_Medium", italic = "STIXTwoText-Italic_Medium-Italic"
    setLine([("Σ", upright), ("\u{2009}", upright), ("x", italic)], size: 10, centreY: 45.4)
    context.setStrokeColor(look.formula)
    context.setLineWidth(1.1 * unit)
    context.move(to: point(42.5, 50.2))
    context.addLine(to: point(57.5, 50.2))
    context.strokePath()
    setLine([("n", italic)], size: 10, centreY: 55.0)

    let image = context.makeImage()!
    for path in look.files {
        let output = URL(fileURLWithPath: path)
        let destination = CGImageDestinationCreateWithURL(output as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        precondition(CGImageDestinationFinalize(destination), "could not write \(path)")
        print("wrote \(output.path)")
    }
}

looks.forEach(draw)
