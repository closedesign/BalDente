import BalDenteCore
import SwiftUI

enum Theme {
    /// Three hues per zone; the aurora background and glass tints are built from these.
    static func palette(_ label: String) -> [Color] {
        switch label {
        case "Home": [Color(red: 1.0, green: 0.55, blue: 0.25), Color(red: 1.0, green: 0.30, blue: 0.55), Color(red: 0.45, green: 0.10, blue: 0.30)]
        case "School": [Color(red: 0.20, green: 0.55, blue: 1.0), Color(red: 0.10, green: 0.80, blue: 0.80), Color(red: 0.22, green: 0.18, blue: 0.65)]
        case "Travel": [Color(red: 0.65, green: 0.35, blue: 1.0), Color(red: 0.95, green: 0.30, blue: 0.80), Color(red: 0.25, green: 0.25, blue: 0.80)]
        case "Top Up": [Color(red: 0.30, green: 0.90, blue: 0.50), Color(red: 0.20, green: 0.80, blue: 0.70), Color(red: 0.08, green: 0.40, blue: 0.50)]
        default: [Color(red: 0.35, green: 0.55, blue: 0.85), Color(red: 0.25, green: 0.70, blue: 0.60), Color(red: 0.10, green: 0.15, blue: 0.35)]
        }
    }

    static func accent(_ label: String) -> Color { palette(label)[0] }

    static func icon(_ zone: Zone) -> String {
        if let i = zone.icon { return i }
        let n = zone.name.lowercased()
        if n.contains("home") { return "house.fill" }
        if n.contains("school") || n.contains("uni") || n.contains("campus") { return "graduationcap.fill" }
        if n.contains("work") || n.contains("office") { return "briefcase.fill" }
        if n.contains("travel") { return "airplane" }
        return "mappin.circle.fill"
    }

    static let iconChoices = ["house.fill", "graduationcap.fill", "briefcase.fill", "airplane", "cup.and.saucer.fill",
                              "building.2.fill", "tram.fill", "moon.stars.fill", "mappin.circle.fill"]
}

extension Theme {
    static let presets: [(name: String, hex: [String])] = [
        ("Aurora", ["#3A8CFF", "#1ACFD0", "#3A2FA6"]),
        ("Sunset", ["#FF8C40", "#FF4D8C", "#731A4D"]),
        ("Ocean", ["#1E90FF", "#00C2A8", "#0B2A5B"]),
        ("Forest", ["#3DDC84", "#1FA37A", "#0B3B2E"]),
        ("Violet", ["#A65BFF", "#F24DCC", "#3F3FCC"]),
        ("Ember", ["#FF5A36", "#FFB020", "#5B1A12"]),
        ("Rose", ["#FF7AA8", "#FFB3C7", "#6B2B49"]),
        ("Graphite", ["#7A8394", "#4B5563", "#161A22"]),
    ]

    static func preset(_ name: String) -> [Color] {
        (presets.first { $0.name == name } ?? presets[0]).hex.map { Color(hex: $0) }
    }
}

extension Color {
    init(hex: String) {
        var h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if h.count != 6 { h = "808080" }
        let v = UInt64(h, radix: 16) ?? 0x808080
        self.init(red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255, blue: Double(v & 0xff) / 255)
    }

    var hex: String {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .gray
        return String(format: "#%02X%02X%02X", Int(round(c.redComponent * 255)), Int(round(c.greenComponent * 255)), Int(round(c.blueComponent * 255)))
    }
}

/// Slowly drifting mesh gradient. It only animates while the app is active and animation is on,
/// at a modest frame rate, so it costs next to nothing when you're not looking at it.
struct AuroraBackground: View {
    let palette: [Color]
    var animated = true

    var body: some View {
        // The drift runs as Core Animation layers (GPU, outside SwiftUI). Animating the mesh from a TimelineView re-evaluated the
        // whole window, glass cards included, on every frame and cost 25 to 50 percent of a core.
        ZStack {
            MeshGradient(width: 3, height: 3, points: points(0), colors: colors)
            DriftingGlow(colors: [palette[0], palette[1], palette[2]].map { NSColor($0) },
                         animated: animated && !ProcessInfo.processInfo.isLowPowerModeEnabled)
                .opacity(0.55)
        }
        .overlay(Color.black.opacity(0.22))
        .ignoresSafeArea()
    }

    private var colors: [Color] {
        let d = Color(red: 0.03, green: 0.03, blue: 0.08)
        return [d, palette[2], d, palette[0], palette[1], palette[2], d, palette[0], d]
    }

    private func points(_ t: Double) -> [SIMD2<Float>] {
        func w(_ i: Double) -> Float { Float(sin(t + i) * 0.09) }
        return [
            SIMD2(0, 0), SIMD2(0.5, 0), SIMD2(1, 0),
            SIMD2(0, 0.5 + w(1)), SIMD2(0.5 + w(2), 0.5 + w(3)), SIMD2(1, 0.5 + w(4)),
            SIMD2(0, 1), SIMD2(0.5 + w(5), 1), SIMD2(1, 1),
        ]
    }
}


/// Three soft color blobs that drift slowly. Pure Core Animation: once started, the render server moves them with no app CPU.
private struct DriftingGlow: NSViewRepresentable {
    let colors: [NSColor]
    let animated: Bool

    func makeNSView(context: Context) -> GlowView { let v = GlowView(); v.update(colors: colors, animated: animated); return v }
    func updateNSView(_ v: GlowView, context: Context) { v.update(colors: colors, animated: animated) }

    final class GlowView: NSView {
        private var blobs: [CAGradientLayer] = []
        private var colors: [NSColor] = []
        private var animated = true
        // Where each blob starts and drifts to, as fractions of the view.
        private let routes: [(CGPoint, CGPoint, Double)] = [
            (CGPoint(x: 0.22, y: 0.30), CGPoint(x: 0.42, y: 0.55), 24),
            (CGPoint(x: 0.78, y: 0.25), CGPoint(x: 0.58, y: 0.45), 31),
            (CGPoint(x: 0.55, y: 0.85), CGPoint(x: 0.30, y: 0.62), 27),
        ]

        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func update(colors: [NSColor], animated: Bool) {
            let changed = colors != self.colors || animated != self.animated
            self.colors = colors; self.animated = animated
            if changed { rebuild() }
        }

        private var builtFor = CGSize.zero
        override func layout() {
            super.layout()
            if bounds.size != builtFor { rebuild() }     // only on a real resize, so the drift isn't restarted by every layout pass
        }

        private func rebuild() {
            wantsLayer = true
            layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
            blobs = []
            guard bounds.width > 1, bounds.height > 1 else { return }
            builtFor = bounds.size
            let d = max(bounds.width, bounds.height) * 0.85
            for (i, r) in routes.enumerated() where i < colors.count {
                let g = CAGradientLayer()
                g.type = .radial
                g.colors = [colors[i].withAlphaComponent(0.9).cgColor, colors[i].withAlphaComponent(0).cgColor]
                g.startPoint = CGPoint(x: 0.5, y: 0.5); g.endPoint = CGPoint(x: 1, y: 1)
                g.bounds = CGRect(x: 0, y: 0, width: d, height: d)
                g.position = CGPoint(x: bounds.width * r.0.x, y: bounds.height * r.0.y)
                if animated {
                    let a = CABasicAnimation(keyPath: "position")
                    a.fromValue = CGPoint(x: bounds.width * r.0.x, y: bounds.height * r.0.y)
                    a.toValue = CGPoint(x: bounds.width * r.1.x, y: bounds.height * r.1.y)
                    a.duration = r.2; a.autoreverses = true; a.repeatCount = .infinity
                    a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    g.add(a, forKey: "drift")
                }
                layer?.addSublayer(g); blobs.append(g)
            }
        }
    }
}
