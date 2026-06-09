import AppKit

// Renders the Finder background for the install DMG: a dark canvas with a title,
// an arrow pointing from the app to the Applications folder, and a hint. The app
// and Applications icons are positioned on top by Finder (see build-dmg.sh).
//
// Coordinates are y-up (AppKit default), so values are measured from the bottom.
// The Finder icon row sits at y≈195 from the bottom (205 from the top of a
// 660×400 window), and the arrow is drawn to line up with it.

let w = 660, h = 400
let outPath = CommandLine.arguments.dropFirst().first ?? "/tmp/dmg-bg.png"

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!

NSGraphicsContext.saveGraphicsState()
let gctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = gctx
let cg = gctx.cgContext

// Background gradient.
let grad = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [NSColor(white: 0.12, alpha: 1).cgColor, NSColor(white: 0.035, alpha: 1).cgColor] as CFArray,
    locations: [0, 1]
)!
cg.drawLinearGradient(grad, start: CGPoint(x: 0, y: CGFloat(h)), end: .zero, options: [])

func drawText(_ s: String, font: NSFont, color: NSColor, centerX: CGFloat, baselineY: CGFloat) {
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let str = NSAttributedString(string: s, attributes: attrs)
    let size = str.size()
    str.draw(at: NSPoint(x: centerX - size.width / 2, y: baselineY))
}

// Title + hint.
drawText("Install Rimote", font: .systemFont(ofSize: 30, weight: .semibold),
         color: NSColor(white: 1, alpha: 0.96), centerX: 330, baselineY: 318)
drawText("Drag the app onto the Applications folder.",
         font: .systemFont(ofSize: 14, weight: .regular),
         color: NSColor(white: 1, alpha: 0.5), centerX: 330, baselineY: 56)

// Arrow lined up with the icon row (y ≈ 195 from bottom), between the two icons.
let arrowColor = NSColor(white: 1, alpha: 0.4)
arrowColor.setStroke()
let shaft = NSBezierPath()
shaft.lineWidth = 4
shaft.lineCapStyle = .round
shaft.move(to: NSPoint(x: 258, y: 195))
shaft.line(to: NSPoint(x: 402, y: 195))
shaft.stroke()
let head = NSBezierPath()
head.lineWidth = 4
head.lineCapStyle = .round
head.lineJoinStyle = .round
head.move(to: NSPoint(x: 384, y: 211))
head.line(to: NSPoint(x: 404, y: 195))
head.line(to: NSPoint(x: 384, y: 179))
head.stroke()

NSGraphicsContext.restoreGraphicsState()

let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
