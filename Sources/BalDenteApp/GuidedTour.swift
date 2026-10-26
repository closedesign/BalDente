import BalDenteCore
import SwiftUI

/// One stop of the guided tour: the page to open, the control to spotlight (a `settingAnchor`/`tourAnchor` id), and what to say.
struct TourStep {
    let page: SettingsPage
    let anchor: String?
    let icon: String
    let tint: Color
    let title: String
    let text: String
}

/// The tour walks the real window: it opens each page, scrolls to the control, dims everything else and points at it.
/// The spotlighted control stays clickable, so people can try it right there.
enum GuidedTour {
    @MainActor static func steps(_ model: Model) -> [TourStep] {
        [
            TourStep(page: .overview, anchor: "Charge ring", icon: "battery.75percent", tint: .green, title: "Your battery at a glance",
                     text: "The ring is your charge. The bright tick is where charging stops, the faint one where it starts again. In between, the battery rests and the Mac runs from the adapter."),
            TourStep(page: .overview, anchor: "Top Up", icon: "bolt.fill", tint: .yellow, title: "Need 100% right now?",
                     text: "Top Up charges to full once, then your normal limit comes back. You never have to change a zone just to leave with a full battery."),
            TourStep(page: .overview, anchor: "Zone tiles", icon: "location.fill", tint: .orange, title: "Zones switch limits for you",
                     text: "Each zone has its own limit. The active one is marked; tap a zone to pin it, or leave it on Automatic."),
            TourStep(page: .zones, anchor: "Zones", icon: "wifi", tint: .orange, title: "Add your home Wi-Fi",
                     text: model.locationAllowed
                        ? "Open a zone with its sliders button and add your current network or a saved place. Home's limit applies once BalDente recognises home."
                        : "Open a zone with its sliders button and add a network or saved place. Allow Location in General first: macOS hides Wi-Fi names without it."),
            TourStep(page: .charging, anchor: "Ready by", icon: "alarm.fill", tint: .orange, title: "Be full before you leave",
                     text: "Pick the days, the time you leave and how full you want to be. BalDente also learns when you usually unplug and can suggest this for you."),
            TourStep(page: .charging, anchor: "Calendar Ready by", icon: "calendar.badge.clock", tint: .teal, title: "Or follow your calendar",
                     text: "Turn this on to be full a set time before your next timed event. Only the start time is read."),
            TourStep(page: .charging, anchor: "Heat Protection", icon: "thermometer.high", tint: .red, title: "Heat Protection",
                     text: "Heat ages a battery even faster than a high charge. Charging pauses above \(model.status?.state.heatLimit ?? HeatLimit.defaultLimit) °C and resumes 3 degrees cooler."),
            TourStep(page: .icon, anchor: "Menu bar preview", icon: "macwindow.on.rectangle", tint: .indigo, title: "The menu bar icon",
                     text: "This is your menu bar icon. It animates only while macOS says the battery is charging; sitting still at your limit is the limit working. Click it in the menu bar for zones and Top Up."),
            TourStep(page: .overview, anchor: "Recent changes", icon: "list.bullet.rectangle", tint: .mint, title: "Nothing happens behind your back",
                     text: "Every time the limit changes you get a notification with the reason, and it's listed here."),
            TourStep(page: .general, anchor: "Notifications", icon: "bell.badge.fill", tint: .red, title: "You decide what's noisy",
                     text: "Mute any kind of notification here. Replay this tour any time from Help → BalDente Tutorial."),
        ]
    }
}

/// Bounds of every anchor on screen, so the tour can find the control it points at.
struct TourAnchorKey: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// Lets the guided tour spotlight this view. `settingAnchor` already includes it.
    func tourAnchor(_ id: String) -> some View {
        // Transform, not set: a plain anchorPreference on a group would hide the anchors of the rows inside it.
        transformAnchorPreference(key: TourAnchorKey.self, value: .bounds) { $0[id] = $1 }
    }
}

/// The dimmed layer with a hole around the current control, plus the callout bubble.
struct TourOverlay: View {
    @ObservedObject var model: Model
    let anchors: [String: Anchor<CGRect>]

    var body: some View {
        if let i = model.tourStep {
            let steps = GuidedTour.steps(model)
            let step = steps[min(i, steps.count - 1)]
            GeometryReader { proxy in
                let size = proxy.size
                let hole = step.anchor.flatMap { anchors[$0] }.map { proxy[$0].insetBy(dx: -10, dy: -10) }
                    .flatMap { $0.intersects(CGRect(origin: .zero, size: size)) ? $0 : nil }
                // With nothing to point at, the hole shrinks to the centre, so moving between steps animates smoothly.
                let cut = hole ?? CGRect(x: size.width / 2, y: size.height / 2, width: 0, height: 0)
                ZStack(alignment: .topLeading) {
                    let shape = Spotlight(hole: cut)
                    // Clicks on the dim area are swallowed; the hole lets them through to the control.
                    shape.fill(Color.black.opacity(0.58), style: FillStyle(eoFill: true))
                        .contentShape(shape, eoFill: true)
                        .onTapGesture {}
                    RoundedRectangle(cornerRadius: 24).strokeBorder(step.tint, lineWidth: 2.5)
                        .shadow(color: step.tint.opacity(0.8), radius: 14)
                        .frame(width: cut.width, height: cut.height).offset(x: cut.minX, y: cut.minY)
                        .opacity(hole == nil ? 0 : 1)
                        .allowsHitTesting(false)
                    callout(step, index: i, count: steps.count)
                        .frame(width: 380)
                        .position(Self.calloutCenter(hole: hole, size: size))
                }
                .animation(.smooth(duration: 0.45), value: cut)
            }
            .ignoresSafeArea()
            .transition(.opacity)
        }
    }

    /// Below the control when there's room, otherwise above it; centred when there's nothing to point at.
    static func calloutCenter(hole: CGRect?, size: CGSize) -> CGPoint {
        let h: CGFloat = 220, w: CGFloat = 380, m: CGFloat = 20
        guard let r = hole else { return CGPoint(x: size.width / 2, y: size.height / 2) }
        let x = min(max(r.midX, w / 2 + m), size.width - w / 2 - m)
        if r.maxY + m + h <= size.height { return CGPoint(x: x, y: r.maxY + m + h / 2) }
        if r.minY - m - h >= 0 { return CGPoint(x: x, y: r.minY - m - h / 2) }
        // A tall control: sit beside it if there's room, else over its lower part.
        if size.width - r.maxX >= w + 2 * m { return CGPoint(x: r.maxX + m + w / 2, y: min(max(r.midY, h / 2 + m), size.height - h / 2 - m)) }
        return CGPoint(x: x, y: size.height - h / 2 - m)
    }

    private func callout(_ step: TourStep, index i: Int, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: step.icon).font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 40, height: 40).background(step.tint.gradient, in: .rect(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 2) {
                    Text("STEP \(i + 1) OF \(count)").font(.system(size: 10, weight: .bold, design: .rounded)).tracking(1.2).foregroundStyle(.secondary)
                    Text(step.title).font(.system(size: 19, weight: .bold, design: .rounded))
                }
            }
            Text(step.text).font(.callout).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("End tour") { model.endTour() }.buttonStyle(.plain).foregroundStyle(.secondary).keyboardShortcut(.cancelAction)
                Spacer()
                if i > 0 { Button("Back") { model.tourGo(i - 1) }.buttonStyle(.glass) }
                Button { i == count - 1 ? model.endTour() : model.tourGo(i + 1) } label: {
                    Text(i == count - 1 ? "Done" : "Next").fontWeight(.semibold).padding(.horizontal, 6)
                }
                .buttonStyle(.glassProminent).tint(step.tint).keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .background(.regularMaterial, in: .rect(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.4), radius: 24, y: 10)
    }
}

/// The whole window with a rounded hole cut out (filled even-odd). Animatable, so the hole glides with the highlight ring.
private struct Spotlight: Shape {
    var hole: CGRect

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(AnimatablePair(hole.minX, hole.minY), AnimatablePair(hole.width, hole.height)) }
        set { hole = CGRect(x: newValue.first.first, y: newValue.first.second, width: newValue.second.first, height: newValue.second.second) }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path(rect)
        if hole.width > 0, hole.height > 0 {
            p.addRoundedRect(in: hole, cornerSize: CGSize(width: min(24, hole.width / 2), height: min(24, hole.height / 2)))
        }
        return p
    }
}
