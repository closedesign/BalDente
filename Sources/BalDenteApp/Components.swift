import BalDenteCore
import SwiftUI

struct BatteryRing: View {
    let percent: Int
    let lower: Int
    let upper: Int
    let caption: (text: String, icon: String)
    let tint: Color
    var size: CGFloat = 340
    /// Whether the faded resume marker and band are drawn (and draggable). Off when Sailing is off: resume then sits one point under the limit.
    var showsResume = true
    /// When set, the limit and resume markers can be dragged; called once with (upper, lower) when the drag ends.
    var onLimitsChange: ((Int, Int) -> Void)? = nil

    @State private var drag: (handle: RingDrag.Handle, upper: Int, lower: Int)?
    @State private var ignoringDrag = false
    @State private var pressStart: Int?        // percent under the press, until the drag has picked a marker
    @State private var hovered: RingDrag.Handle?

    private var lw: CGFloat { size * 0.075 }
    private var shownUpper: Int { drag?.upper ?? upper }
    private var shownLower: Int { drag?.lower ?? lower }

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.13), style: StrokeStyle(lineWidth: lw, lineCap: .round)).padding(lw / 2)
            // The band the battery sails in: between resume and the limit the charger stays off.
            if showsResume {
                Circle().trim(from: CGFloat(shownLower) / 100, to: CGFloat(shownUpper) / 100)
                    .stroke(tint.opacity(drag != nil ? 0.28 : 0.14), style: StrokeStyle(lineWidth: lw, lineCap: .butt))
                    .rotationEffect(.degrees(-90)).padding(lw / 2)
            }
            Circle().trim(from: 0, to: CGFloat(max(percent, 1)) / 100)
                .stroke(AngularGradient(colors: [tint.opacity(0.5), tint, tint.opacity(0.85)], center: .center,
                                        startAngle: .degrees(0), endAngle: .degrees(Double(max(percent, 1)) * 3.6)),
                        style: StrokeStyle(lineWidth: lw, lineCap: .round))
                .rotationEffect(.degrees(-90)).padding(lw / 2)
                .shadow(color: tint.opacity(0.7), radius: size * 0.07)
            if showsResume { marker(.lower, shownLower, opacity: 0.4) }
            marker(.upper, shownUpper, opacity: 0.95)
            VStack(spacing: size * 0.01) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(drag.map { $0.handle == .upper ? $0.upper : $0.lower } ?? percent)")
                        .font(.system(size: size * 0.34, weight: .thin, design: .rounded)).monospacedDigit()
                        .contentTransition(.numericText())
                    Text("%").font(.system(size: size * 0.11, weight: .light, design: .rounded)).foregroundStyle(.secondary)
                }
                Label(drag.map { $0.handle == .upper ? "Stop charging at" : "Resume at" } ?? caption.text,
                      systemImage: drag.map { $0.handle == .upper ? "bolt.slash.fill" : "bolt.fill" } ?? caption.icon)
                    // The small panel ring (96 pt) made this 4.8 pt, unreadable; never go below 10 pt there (11.5 pt on big rings) and use the short caption so it fits inside the ring.
                    .font(.system(size: max(size * 0.05, size < 140 ? 10 : 11.5), weight: .semibold, design: .rounded)).imageScale(size < 140 ? .medium : .large)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .foregroundStyle(.secondary).labelStyle(.titleAndIcon)
            }
        }
        .frame(width: size, height: size)
        .contentShape(.circle)
        .gesture(dragGesture, isEnabled: onLimitsChange != nil)
        .animation(.smooth(duration: 0.9), value: percent)
        .accessibilityElement(children: .combine)
        .accessibilityValue(showsResume ? "Charge \(percent)%, limit \(upper)%, resumes at \(lower)%" : "Charge \(percent)%, limit \(upper)%")
        .accessibilityAdjustableAction { dir in
            guard let onLimitsChange else { return }
            let m = RingDrag.move(.upper, to: upper + (dir == .increment ? 5 : -5), upper: upper, lower: lower, gap: RingDrag.step)
            onLimitsChange(m.upper, m.lower)
        }
    }

    private func marker(_ h: RingDrag.Handle, _ value: Int, opacity: Double) -> some View {
        let editable = onLimitsChange != nil
        let active = drag?.handle == h || (drag == nil && hovered == h)
        return Capsule().fill(Color.primary.opacity(active ? 1 : opacity))
            .frame(width: size * (active ? 0.026 : editable ? 0.018 : 0.014), height: lw * (active ? 1.9 : 1.5))
            .shadow(color: .black.opacity(active ? 0.35 : 0), radius: 3)
            .frame(width: lw * 1.6, height: lw * 2.2)       // a bigger target than the drawn marker
            .contentShape(.rect)
            .onHover { inside in if editable { hovered = inside ? h : (hovered == h ? nil : hovered) } }
            .pointerStyle(editable ? (drag != nil ? .grabActive : .grabIdle) : nil)
            .help(editable ? (h == .upper ? "Drag to change where charging stops" : "Drag to change where charging resumes") : "")
            .offset(y: -(size - lw) / 2)
            .rotationEffect(.degrees(Double(value) * 3.6))
            .animation(.spring(duration: 0.25), value: active)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                guard !ignoringDrag else { return }
                let c = size / 2
                let dx = v.location.x - c, dy = v.location.y - c
                if drag == nil {
                    if pressStart == nil {
                        // Only a press on the ring's band near a marker grabs it; elsewhere the ring is just a picture.
                        let r = hypot(v.startLocation.x - c, v.startLocation.y - c)
                        let p = RingDrag.percent(dx: v.startLocation.x - c, dy: v.startLocation.y - c, previous: 50)  // 50: no wrap clamp
                        let near = showsResume ? min(RingDrag.distance(p, upper), RingDrag.distance(p, lower)) : RingDrag.distance(p, upper)
                        guard abs(r - (size - lw) / 2) < lw * 1.2, near <= 6 else { ignoringDrag = true; return }
                        pressStart = p
                    }
                    guard let s = pressStart else { return }
                    let now = RingDrag.percent(dx: dx, dy: dy, previous: s)
                    guard let h = showsResume ? RingDrag.handle(start: s, now: now, upper: upper, lower: lower) : .upper else { return }
                    drag = (h, upper, lower)
                }
                guard let d = drag else { return }
                let p = RingDrag.snap(RingDrag.percent(dx: dx, dy: dy, previous: d.handle == .upper ? d.upper : d.lower))
                let m = RingDrag.move(d.handle, to: p, upper: d.upper, lower: d.lower, gap: RingDrag.step)
                if m.upper != d.upper || m.lower != d.lower {
                    drag = (d.handle, m.upper, m.lower)
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                }
            }
            .onEnded { _ in
                if let d = drag { onLimitsChange?(d.upper, d.lower) }
                drag = nil; ignoringDrag = false; pressStart = nil
            }
    }
}

/// Big tvOS-style card: lifts and glows on hover, tint deepens when active.
struct ZoneTile: View {
    let zone: Zone
    let active: Bool
    let pinned: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Image(systemName: Theme.icon(zone)).font(.system(size: 38, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                Spacer()
                if active {
                    Text(pinned ? "PINNED" : "ACTIVE").font(.system(size: 11, weight: .bold, design: .rounded)).tracking(1.5)
                        .padding(.horizontal, 10).padding(.vertical, 5).glassEffect(.regular, in: .capsule)
                }
            }
            Spacer()
            Text(zone.name).font(.system(size: 24, weight: .bold, design: .rounded))
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(zone.upper)").font(.system(size: 52, weight: .thin, design: .rounded)).monospacedDigit()
                Text("%").font(.system(size: 20, weight: .light, design: .rounded)).foregroundStyle(.secondary)
            }
            HStack {
                Text("resume at \(zone.lower)%").font(.system(.callout, design: .rounded)).foregroundStyle(.secondary)
                Spacer()
                Button(action: onEdit) { Image(systemName: "slider.horizontal.3") }
                    .buttonStyle(.glass).buttonBorderShape(.circle).help("Edit \(zone.name) limits")
            }
        }
        .padding(18)
        .frame(width: 210, height: 236, alignment: .topLeading)
        .contentShape(.rect(cornerRadius: 34))
        .glassEffect(.regular.tint(Theme.accent(zone.name).opacity(active ? 0.5 : 0.14)).interactive(), in: .rect(cornerRadius: 34))
        .shadow(color: Theme.accent(zone.name).opacity(hover || active ? 0.45 : 0), radius: hover ? 34 : 20, y: 14)
        .scaleEffect(hover ? 1.06 : 1)
        .animation(.spring(duration: 0.4, bounce: 0.3), value: hover)
        .animation(.smooth, value: active)
        .onHover { hover = $0 }
        .onTapGesture(perform: onSelect)
    }
}

struct AddTile: View {
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "plus").font(.system(size: 40, weight: .light))
            Text("New Zone").font(.system(.headline, design: .rounded))
        }
        .foregroundStyle(.secondary)
        .frame(width: 210, height: 236)
        .contentShape(.rect(cornerRadius: 34))
        .glassEffect(.clear.interactive(), in: .rect(cornerRadius: 34))
        .scaleEffect(hover ? 1.06 : 1)
        .animation(.spring(duration: 0.4, bounce: 0.3), value: hover)
        .onHover { hover = $0 }
        .onTapGesture(perform: action)
    }
}
