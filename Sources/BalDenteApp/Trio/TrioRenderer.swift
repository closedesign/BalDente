import AppKit
import BalDenteCore

/// Everything the icon shows, gathered in one value so previews can fake any state.
struct TrioState: Equatable {
    var power = PowerSnap()
    var net = NetSnap()
    var audio = AudioSnap()
    var inputShort: String?
    /// The level that fills the ring (100, or the active charge limit).
    var fullLevel = 100
}

/// Draws the combined icon with Core Graphics on a 120-unit, y-down canvas (see TrioGeometry).
enum TrioRenderer {
    struct Palette {
        let fg, dim, faint, green, red, yellow, blue: NSColor
        init(dark: Bool) {
            fg = dark ? .white : NSColor(white: 0, alpha: 0.85)
            dim = fg.withAlphaComponent(dark ? 0.24 : 0.2)
            faint = fg.withAlphaComponent(dark ? 0.3 : 0.26)
            green = dark ? NSColor(srgbRed: 0.2, green: 0.84, blue: 0.36, alpha: 1) : NSColor(srgbRed: 0.13, green: 0.7, blue: 0.29, alpha: 1)
            red = NSColor(srgbRed: 1, green: 0.27, blue: 0.23, alpha: 1)
            yellow = dark ? NSColor(srgbRed: 1, green: 0.8, blue: 0.04, alpha: 1) : NSColor(srgbRed: 0.85, green: 0.62, blue: 0, alpha: 1)
            blue = dark ? NSColor(srgbRed: 0.25, green: 0.6, blue: 1, alpha: 1) : NSColor(srgbRed: 0.04, green: 0.45, blue: 0.95, alpha: 1)
        }
    }

    /// An image that redraws itself for whatever appearance it lands in (dark or light menu bar).
    static func image(_ s: TrioState, _ p: TrioPrefs, size: CGFloat, frame: ChargingFrame?, forceDark: Bool? = nil) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let dark = forceDark ?? (NSAppearance.currentDrawing().bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
            ctx.saveGState()
            ctx.scaleBy(x: rect.width / TrioGeometry.side, y: rect.height / TrioGeometry.side)
            draw(ctx, s, p, Palette(dark: dark), frame: frame)
            ctx.restoreGState()
            return true
        }
        img.isTemplate = false
        return img
    }

    /// The Dock version: the same icon on a rounded tile.
    static func dockImage(_ s: TrioState, _ p: TrioPrefs, frame: ChargingFrame?) -> NSImage {
        let side: CGFloat = 512
        let systemDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let dark = p.dockBackground == .system ? systemDark : p.dockBackground == .dark
        return NSImage(size: NSSize(width: side, height: side), flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let tile = rect.insetBy(dx: side * 0.1, dy: side * 0.1)
            let path = CGPath(roundedRect: tile, cornerWidth: tile.width * 0.225, cornerHeight: tile.width * 0.225, transform: nil)
            ctx.addPath(path)
            ctx.setFillColor(dark ? CGColor(srgbRed: 0.11, green: 0.11, blue: 0.13, alpha: 1) : CGColor(srgbRed: 0.96, green: 0.96, blue: 0.97, alpha: 1))
            ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 14, color: CGColor(gray: 0, alpha: 0.3))
            ctx.fillPath()
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
            let inner = tile.insetBy(dx: tile.width * 0.14, dy: tile.width * 0.14)
            ctx.translateBy(x: inner.minX, y: inner.minY)
            ctx.scaleBy(x: inner.width / TrioGeometry.side, y: inner.height / TrioGeometry.side)
            draw(ctx, s, p, Palette(dark: dark), frame: frame)
            return true
        }
    }

    static func ringWidth(_ p: TrioPrefs) -> CGFloat {
        switch p.stroke { case .light: 6.5; case .regular: 8; case .bold: 10 }
    }

    // MARK: Drawing

    static func draw(_ ctx: CGContext, _ s: TrioState, _ p: TrioPrefs, _ c: Palette, frame: ChargingFrame?) {
        ctx.setLineCap(.round); ctx.setLineJoin(.round)
        drawBattery(ctx, s, p, c, frame: frame)
        drawMiddle(ctx, s, p, c)
        drawVolume(ctx, s, p, c)
    }

    static func ringColor(_ s: TrioState, _ p: TrioPrefs, _ c: Palette) -> NSColor {
        guard p.statusColors else { return c.fg }
        if s.power.plugged || s.power.charging { return c.green }
        if s.power.lowPower { return c.yellow }
        if s.power.percent < p.lowThreshold { return c.red }
        return c.fg
    }

    private static func roundedFont(_ size: CGFloat, _ weight: NSFont.Weight = .bold) -> NSFont {
        let f = NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
        return NSFont(descriptor: f.fontDescriptor.withDesign(.rounded) ?? f.fontDescriptor, size: size) ?? f
    }

    private static func text(_ string: String, size: CGFloat, color: NSColor) -> NSAttributedString {
        NSAttributedString(string: string, attributes: [.font: roundedFont(size), .foregroundColor: color, .kern: -size * 0.04])
    }

    private static func drawBattery(_ ctx: CGContext, _ s: TrioState, _ p: TrioPrefs, _ c: Palette, frame: ChargingFrame?) {
        let pw = s.power
        let lw = ringWidth(p)
        let top = pw.present ? TrioRules.topIndicator(charging: pw.charging, plugged: pw.plugged, showPercentage: p.showPercentage,
                                                       showChargingIndicator: p.showChargingIndicator,
                                                       percentageWhenConnected: p.percentageWhenConnected) : .none
        let fs = 32 * p.symbolScale
        let number = text(pw.present ? "\(pw.percent)" : "–", size: fs, color: c.fg)
        let gap: CGFloat = switch top {
        case .none: 0
        case .number: max(44, number.size().width + 10)
        case .bolt, .plug: TrioGeometry.boltGap * p.symbolScale
        }
        let progress = pw.present ? TrioRules.ringProgress(percent: pw.percent, full: s.fullLevel) : 0
        let fill = ringColor(s, p, c)

        ctx.setLineWidth(lw)
        ctx.addPath(TrioGeometry.arc(from: 0, to: 1, gap: gap)); ctx.setStrokeColor(c.dim.cgColor); ctx.strokePath()
        if progress > 0 {
            ctx.addPath(TrioGeometry.arc(from: 0, to: max(progress, 0.012), gap: gap)); ctx.setStrokeColor(fill.cgColor); ctx.strokePath()
        }

        let hi = highlight(for: fill)
        if let f = frame { drawEffect(ctx, f, gap: gap, lw: lw, color: hi, progress: progress) }

        let boltScale = p.boltPulse ? (frame?.boltScale ?? 1) : 1
        let boltColor = p.boltPulse ? blend(c.fg, hi, frame?.boltTint ?? 0) : c.fg
        switch top {
        case .none: break
        case .number:
            // Status Trio's baseline: y 17 at 20 units, y 24 at 32 units, so the digits sit in the gap at the top of the ring.
            drawText(ctx, number, centerX: TrioGeometry.centerX, baseline: 17 + (fs - 20) * 7 / 12)
        case .bolt:
            ctx.saveGState()
            let center = CGPoint(x: TrioGeometry.centerX, y: 11.8)
            ctx.translateBy(x: center.x, y: center.y)
            ctx.scaleBy(x: p.symbolScale * boltScale, y: p.symbolScale * boltScale)
            ctx.translateBy(x: -center.x, y: -center.y)
            ctx.addPath(boltPath()); ctx.setFillColor(boltColor.cgColor); ctx.setStrokeColor(boltColor.cgColor)
            ctx.setLineWidth(1.4); ctx.drawPath(using: .fillStroke)
            ctx.restoreGState()
        case .plug:
            let h = 21 * p.symbolScale
            symbol("powerplug.portrait.fill", fallback: "powerplug.fill", color: c.fg, height: h)?
                .draw(centeredAt: CGPoint(x: TrioGeometry.centerX, y: 11.8))
        }
    }

    /// Draws a line of text centered on x with its baseline exactly at `baseline`, in the y-down canvas.
    private static func drawText(_ ctx: CGContext, _ s: NSAttributedString, centerX: CGFloat, baseline: CGFloat) {
        let line = CTLineCreateWithAttributedString(s)
        let width = CTLineGetTypographicBounds(line, nil, nil, nil)
        ctx.saveGState()
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)   // the canvas is flipped; keep glyphs upright
        ctx.textPosition = CGPoint(x: centerX - CGFloat(width) / 2, y: baseline)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    /// The charging bolt in the top gap, centered on (59.5, 11.8).
    private static func boltPath() -> CGPath {
        let b = CGMutablePath()
        b.addLines(between: [CGPoint(x: 63.4, y: 2.4), CGPoint(x: 51.8, y: 13.6), CGPoint(x: 58.1, y: 13.6),
                             CGPoint(x: 55.6, y: 21.4), CGPoint(x: 67.2, y: 9.8), CGPoint(x: 60.9, y: 9.8)])
        b.closeSubpath()
        return b
    }

    private static func drawEffect(_ ctx: CGContext, _ f: ChargingFrame, gap: CGFloat, lw: CGFloat, color: NSColor, progress: Double) {
        if progress > 0.03 {
            // A wave rippling along the filled arc: the ring swells and brightens as each crest passes.
            let n = 30
            ctx.setLineCap(.butt)
            for i in 0..<n {
                let a = progress * Double(i) / Double(n), b = progress * Double(i + 1) / Double(n)
                let w = 0.5 + 0.5 * sin(2 * .pi * (2.2 * (a + b) / 2 - f.wavePhase))
                ctx.addPath(TrioGeometry.arc(from: a, to: b + 0.002, gap: gap))
                ctx.setStrokeColor(color.withAlphaComponent(0.55 * w).cgColor)
                ctx.setLineWidth(lw * (1 + 0.28 * w)); ctx.strokePath()
            }
            ctx.setLineWidth(lw); ctx.setLineCap(.round)
        }
        if let tail = f.tail {
            // A fading comet tail: thin slices, transparent at the back and bright at the head.
            let n = 14
            ctx.setLineCap(.butt)
            for i in 0..<n {
                let a = tail.lowerBound + (tail.upperBound - tail.lowerBound) * Double(i) / Double(n)
                let b = tail.lowerBound + (tail.upperBound - tail.lowerBound) * Double(i + 1) / Double(n)
                ctx.addPath(TrioGeometry.arc(from: a, to: b + 0.002, gap: gap))
                ctx.setStrokeColor(color.withAlphaComponent(pow(Double(i + 1) / Double(n), 1.6)).cgColor)
                ctx.setLineWidth(lw); ctx.strokePath()
            }
            ctx.setLineCap(.round)
        }
        guard f.headVisible else { return }
        let pt = TrioGeometry.point(at: f.head)
        if f.beadAlpha > 0 {
            // A glowing head so the motion reads even at 16 to 22 pt in the menu bar.
            let r = lw * 0.78
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: lw * 1.4, color: color.withAlphaComponent(0.9 * f.beadAlpha).cgColor)
            ctx.setFillColor(color.withAlphaComponent(f.beadAlpha).cgColor)
            ctx.fillEllipse(in: CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2))
            ctx.restoreGState()
        }
        if f.heartbeatAlpha > 0 {
            let r = lw * 0.95 * f.heartbeatScale
            ctx.setFillColor(color.withAlphaComponent(min(1, f.heartbeatAlpha) * 0.85).cgColor)
            ctx.fillEllipse(in: CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2))
        }
    }

    // MARK: Middle slot

    enum Middle: Equatable { case network(NetKind), bluetooth(String), percent, input(String) }

    static func middle(_ s: TrioState, _ p: TrioPrefs) -> Middle {
        if p.percentInMiddle, s.power.present { return .percent }
        let problem = s.net.isProblem && s.net.kind != .notAssociated
        if p.middleSlot == .inputSource, let i = s.inputShort, !(p.networkProblemsOverInput && problem) { return .input(i) }
        if p.bluetoothReplacesNetwork, let out = s.audio.output, out.bluetooth, !(p.networkErrorsFirst && s.net.isProblem) {
            return .bluetooth(p.bluetoothGlyph.symbol ?? SystemMonitor.bluetoothSymbol(name: out.name, kind: ""))
        }
        var k = s.net.kind
        if k == .ethernet && p.wifiIconForEthernet { k = .wifi(bars: 3) }
        if k == .hotspot && p.wifiIconForHotspot { k = .wifi(bars: max(1, TrioRules.wifiBars(rssi: s.net.rssi))) }
        return .network(k)
    }

    private static func drawMiddle(_ ctx: CGContext, _ s: TrioState, _ p: TrioPrefs, _ c: Palette) {
        let center = CGPoint(x: TrioGeometry.centerX, y: 64)
        switch middle(s, p) {
        case .percent:
            drawText(ctx, text("\(s.power.percent)", size: 30, color: c.fg), centerX: center.x, baseline: center.y + 11)
        case .input(let label):
            let size: CGFloat = label.count > 2 ? 22 : 30
            drawText(ctx, text(label, size: size, color: c.fg), centerX: center.x, baseline: center.y + size * 0.36)
        case .bluetooth(let name):
            symbol(name, fallback: "headphones", color: c.blue, height: 34 * p.bluetoothScale)?.draw(centeredAt: center)
        case .network(let kind):
            ctx.saveGState()
            ctx.translateBy(x: center.x, y: center.y); ctx.scaleBy(x: p.wifiScale, y: p.wifiScale); ctx.translateBy(x: -center.x, y: -center.y)
            drawNetwork(ctx, kind, c)
            ctx.restoreGState()
        }
    }

    private static func drawNetwork(_ ctx: CGContext, _ kind: NetKind, _ c: Palette) {
        let cx = TrioGeometry.centerX
        func arc(_ cy: CGFloat, _ r: CGFloat) -> CGPath {
            let a = CGMutablePath()
            a.addArc(center: CGPoint(x: cx, y: cy), radius: r, startAngle: 227.4 * .pi / 180, endAngle: 312.6 * .pi / 180, clockwise: false)
            return a
        }
        func wifi(bars: Int, dimAll: Bool) {
            ctx.setLineWidth(7)
            for (i, path) in [arc(78.6, 18.5), arc(78.3, 31)].enumerated() {
                ctx.addPath(path); ctx.setStrokeColor((!dimAll && bars >= i + 2 ? c.fg : c.faint).cgColor); ctx.strokePath()
            }
            ctx.setFillColor((dimAll ? c.faint : c.fg).cgColor)
            ctx.fillEllipse(in: CGRect(x: cx - 6.2, y: 69.4, width: 12.4, height: 11.6))
        }
        switch kind {
        case .wifi(let bars): wifi(bars: bars, dimAll: false)
        case .notAssociated: wifi(bars: 0, dimAll: true)
        case .wifiOff, .offline:
            wifi(bars: 0, dimAll: true)
            ctx.setLineWidth(6); ctx.setStrokeColor(c.fg.cgColor)
            ctx.move(to: CGPoint(x: 40, y: 45)); ctx.addLine(to: CGPoint(x: 80, y: 80)); ctx.strokePath()
        case .noInternet:
            wifi(bars: 0, dimAll: true)
            ctx.setLineWidth(6.5); ctx.setStrokeColor(c.fg.cgColor)
            ctx.move(to: CGPoint(x: cx, y: 46)); ctx.addLine(to: CGPoint(x: cx, y: 63)); ctx.strokePath()
            ctx.setFillColor(c.fg.cgColor); ctx.fillEllipse(in: CGRect(x: cx - 4, y: 70, width: 8, height: 8))
        case .ethernet:
            ctx.setLineWidth(4.9); ctx.setStrokeColor(c.fg.cgColor)
            ctx.addLines(between: [CGPoint(x: 41, y: 53), CGPoint(x: 31.5, y: 65.5), CGPoint(x: 41, y: 78)])
            ctx.addLines(between: [CGPoint(x: 78, y: 53), CGPoint(x: 87.5, y: 65.5), CGPoint(x: 78, y: 78)])
            ctx.strokePath()
            ctx.setFillColor(c.fg.cgColor)
            for x in [48.0, cx, 71.0] { ctx.fillEllipse(in: CGRect(x: x - 2.6, y: 62.9, width: 5.2, height: 5.2)) }
        case .hotspot:
            symbol("personalhotspot", fallback: "link", color: c.fg, height: 30)?.draw(centeredAt: CGPoint(x: cx, y: 64))
        }
    }

    // MARK: Volume

    private static func drawVolume(_ ctx: CGContext, _ s: TrioState, _ p: TrioPrefs, _ c: Palette) {
        let bt = s.audio.output?.bluetooth == true && p.bluetoothBlueVolume
        let on = bt ? c.blue : c.fg
        let v = s.audio.volume ?? 0
        switch p.volumeStyle {
        case .dots:
            let lit = TrioRules.volumeDots(volume: v, muted: s.audio.muted)
            let r = TrioGeometry.volumeDotRadius
            for (i, pt) in TrioGeometry.volumeDots.enumerated() {
                ctx.setFillColor((i < lit ? on : c.faint).cgColor)
                ctx.fillEllipse(in: CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2))
            }
        case .arc:
            let lw = ringWidth(p)
            func arc(_ f: Double) -> CGPath {
                let a = CGMutablePath(), sweep = TrioGeometry.volumeArcStart - TrioGeometry.volumeArcEnd
                a.addArc(center: TrioGeometry.ringCenter, radius: TrioGeometry.ringRadius, startAngle: TrioGeometry.volumeArcStart,
                         endAngle: TrioGeometry.volumeArcStart - sweep * CGFloat(f), clockwise: true)
                return a
            }
            ctx.setLineWidth(lw)
            ctx.addPath(arc(1)); ctx.setStrokeColor(c.dim.cgColor); ctx.strokePath()
            if !s.audio.muted, v > 0 { ctx.addPath(arc(max(0.04, v))); ctx.setStrokeColor(on.cgColor); ctx.strokePath() }
        }
    }

    // MARK: Helpers

    private static func symbol(_ name: String, fallback: String, color: NSColor, height: CGFloat) -> NSImage? {
        let cfg = NSImage.SymbolConfiguration(pointSize: height, weight: .semibold).applying(.init(paletteColors: [color]))
        guard let img = (NSImage(systemSymbolName: name, accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: fallback, accessibilityDescription: nil))?.withSymbolConfiguration(cfg) else { return nil }
        // Normalise to the requested height whatever the glyph's aspect ratio.
        let s = img.size
        img.size = NSSize(width: s.width * height / max(1, s.height), height: height)
        return img
    }

    /// A lighter (or darker) shade of the fill with enough contrast to read as a moving highlight.
    static func highlight(for fill: NSColor) -> NSColor {
        let rgb = fill.usingColorSpace(.sRGB) ?? fill
        let lum = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
        return lum > 0.72 ? blend(rgb, NSColor(srgbRed: 0.35, green: 0.35, blue: 0.4, alpha: 1), 0.6)
                          : blend(rgb, .white, 0.8)
    }

    static func blend(_ a: NSColor, _ b: NSColor, _ t: Double) -> NSColor {
        guard t > 0, let x = a.usingColorSpace(.sRGB), let y = b.usingColorSpace(.sRGB) else { return a }
        let k = CGFloat(min(1, t))
        return NSColor(srgbRed: x.redComponent + (y.redComponent - x.redComponent) * k,
                       green: x.greenComponent + (y.greenComponent - x.greenComponent) * k,
                       blue: x.blueComponent + (y.blueComponent - x.blueComponent) * k,
                       alpha: x.alphaComponent + (y.alphaComponent - x.alphaComponent) * k)
    }
}

private extension NSImage {
    func draw(centeredAt c: CGPoint) {
        draw(in: CGRect(x: c.x - size.width / 2, y: c.y - size.height / 2, width: size.width, height: size.height),
             from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
}
