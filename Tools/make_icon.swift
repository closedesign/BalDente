// Draws the BalDente app icon (flat squircle, spectrum ring, limit marker) to a 1024px PNG.
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let S: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// Squircle tile, 824pt inside the 1024 canvas (standard macOS icon grid).
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let path = CGPath(roundedRect: tile, cornerWidth: 184, cornerHeight: 184, transform: nil)
ctx.saveGState()
ctx.addPath(path); ctx.clip()
let space = CGColorSpaceCreateDeviceRGB()
let bg = CGGradient(colorsSpace: space, colors: [
    CGColor(red: 0.07, green: 0.06, blue: 0.16, alpha: 1), CGColor(red: 0.02, green: 0.03, blue: 0.08, alpha: 1)] as CFArray,
    locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 100, y: 924), end: CGPoint(x: 924, y: 100), options: [])

// Soft color glow behind the ring: flat blobs, no blur-heavy effects.
func blob(_ c: CGPoint, _ r: CGFloat, _ col: CGColor) {
    let g = CGGradient(colorsSpace: space, colors: [col, col.copy(alpha: 0)!] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: r, options: [])
}
blob(CGPoint(x: 330, y: 760), 420, CGColor(red: 1.0, green: 0.35, blue: 0.55, alpha: 0.28))
blob(CGPoint(x: 720, y: 280), 460, CGColor(red: 0.15, green: 0.75, blue: 0.95, alpha: 0.30))

// Spectrum ring: 270 degrees, drawn as short colored segments to fake a conic gradient.
let center = CGPoint(x: S / 2, y: S / 2), radius: CGFloat = 235, width: CGFloat = 96
let stops: [(CGFloat, CGFloat, CGFloat)] = [(1.0, 0.55, 0.25), (1.0, 0.30, 0.55), (0.65, 0.35, 1.0), (0.20, 0.55, 1.0), (0.10, 0.85, 0.85)]
func color(_ t: CGFloat) -> CGColor {
    let x = t * CGFloat(stops.count - 1), i = min(Int(x), stops.count - 2), f = x - CGFloat(i)
    let a = stops[i], b = stops[i + 1]
    return CGColor(red: a.0 + (b.0 - a.0) * f, green: a.1 + (b.1 - a.1) * f, blue: a.2 + (b.2 - a.2) * f, alpha: 1)
}
let start: CGFloat = 225 * .pi / 180            // lower-left
let sweep: CGFloat = 270 * .pi / 180
let n = 270
ctx.setLineWidth(width)
ctx.setLineCap(.butt)
for k in 0..<n {
    let a0 = start - sweep * CGFloat(k) / CGFloat(n), a1 = start - sweep * CGFloat(k + 1) / CGFloat(n) - 0.004
    ctx.setStrokeColor(color(CGFloat(k) / CGFloat(n - 1)))
    ctx.addArc(center: center, radius: radius, startAngle: a0, endAngle: a1, clockwise: true)
    ctx.strokePath()
}
// Round caps
for (ang, t) in [(start, CGFloat(0)), (start - sweep, CGFloat(1))] {
    let p = CGPoint(x: center.x + radius * cos(ang), y: center.y + radius * sin(ang))
    ctx.setFillColor(color(t)); ctx.fillEllipse(in: CGRect(x: p.x - width / 2, y: p.y - width / 2, width: width, height: width))
}

// Limit marker: a white capsule crossing the ring at ~80%.
let ma = start - sweep * 0.8
ctx.saveGState()
ctx.translateBy(x: center.x + radius * cos(ma), y: center.y + radius * sin(ma))
ctx.rotate(by: ma + .pi / 2)
ctx.setFillColor(CGColor(gray: 1, alpha: 1))
ctx.addPath(CGPath(roundedRect: CGRect(x: -20, y: -78, width: 40, height: 156), cornerWidth: 20, cornerHeight: 20, transform: nil))
ctx.fillPath()
ctx.restoreGState()

// Center bolt, flat white.
let bolt = CGMutablePath()
let pts: [(CGFloat, CGFloat)] = [(548, 640), (418, 478), (500, 478), (468, 384), (606, 548), (522, 548)]
bolt.move(to: CGPoint(x: pts[0].0, y: pts[0].1))
for p in pts.dropFirst() { bolt.addLine(to: CGPoint(x: p.0, y: p.1)) }
bolt.closeSubpath()
ctx.setFillColor(CGColor(gray: 1, alpha: 0.95))
ctx.setLineJoin(.round); ctx.setLineWidth(22); ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.95))
ctx.addPath(bolt); ctx.drawPath(using: .fillStroke)
ctx.restoreGState()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
