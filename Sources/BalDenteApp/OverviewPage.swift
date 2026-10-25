import BalDenteCore
import SwiftUI

/// The first page: ring and headline, battery facts, one-tap controls, and a pointer to every other page.
struct OverviewPage: View {
    @ObservedObject var model: Model

    private var status: Status? { model.status }
    private var task: TaskState? { model.task }
    private var s: LimiterState? { status?.state }

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            hero
            stats
            VStack(alignment: .leading, spacing: 12) {
                header("Quick controls", "The things you reach for most. Open a card for the full settings.")
                quickCards
            }
            VStack(alignment: .leading, spacing: 4) {
                header("Zones", "Your limit follows your Wi-Fi and saved places. Tap a zone to pin it.")
                zoneRow
            }
            footer
        }
    }

    private func header(_ title: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 22, weight: .bold, design: .rounded))
            Text(sub).font(.callout).foregroundStyle(.secondary)
        }
    }

    // MARK: Hero

    private var hero: some View {
        ViewThatFits(in: .horizontal) {
            heroLayout(horizontal: true)
            heroLayout(horizontal: false)
        }
    }

    private func heroLayout(horizontal: Bool) -> some View {
        let ring = BatteryRing(percent: model.percent, lower: model.target.lower, upper: model.target.upper,
                               caption: model.ringCaption, tint: model.accent, size: horizontal ? 250 : 200)
        return AnyLayout(horizontal ? AnyLayout(HStackLayout(spacing: 40)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 20))) {
            ring
            VStack(alignment: .leading, spacing: 10) {
                Label(model.target.label.uppercased(), systemImage: model.topUp ? "bolt.fill" : "location.fill")
                    .font(.system(size: 11, weight: .bold, design: .rounded)).tracking(2)
                    .padding(.horizontal, 12).padding(.vertical, 6).glassEffect(.regular, in: .capsule)
                Text(model.headline).font(.system(size: 40, weight: .bold, design: .rounded)).minimumScaleFactor(0.6).lineLimit(2)
                Text(model.subline).font(.system(.body, design: .rounded)).foregroundStyle(.secondary)
                GlassEffectContainer(spacing: 10) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) { heroButtons }
                        VStack(alignment: .leading, spacing: 10) { heroButtons }
                    }
                }.padding(.top, 6)
            }
            if horizontal { Spacer(minLength: 0) }
        }
    }

    @ViewBuilder private var heroButtons: some View {
        Button { model.topUp.toggle(); model.refresh() } label: {
            pill(model.topUp ? "Cancel Top Up" : "Top Up to 100%", "bolt.fill")
        }
        .buttonStyle(.glassProminent).tint(model.accent).settingAnchor("Top Up")
        if task != nil {
            Button { model.cmd("cancel") } label: { pill("Cancel Task", "xmark") }.buttonStyle(.glass)
        }
        Button { model.config.overrideZone = nil } label: {
            pill(model.config.overrideZone == nil ? "Automatic" : "Back to Automatic",
                 model.config.overrideZone == nil ? "checkmark.circle.fill" : "wand.and.stars")
        }
        .buttonStyle(.glass).tint(model.config.overrideZone == nil ? model.accent : nil)
        .disabled(model.config.overrideZone == nil).settingAnchor("Automatic")
    }

    // MARK: Stats

    private var stats: some View {
        let i = model.info
        return GlassEffectContainer(spacing: 12) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 12)], spacing: 12) {
                stat("Health", i?.healthPercent.map { "\($0)%" } ?? "–", "heart.fill")
                stat("Cycles", i.map { "\($0.cycles)" } ?? "–", "arrow.triangle.2.circlepath")
                stat("Temp", (status?.tempC ?? i?.tempC).map { String(format: "%.1f°", $0) } ?? "–", "thermometer.medium")
                stat("Power", i.map { String(format: "%+.1f W", $0.watts) } ?? "–", "bolt.horizontal.fill")
                stat("Capacity", i?.maxMAh.map { "\($0) mAh" } ?? "–", "battery.100percent")
            }
        }
    }

    private func stat(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon).font(.system(.caption, design: .rounded)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 21, weight: .semibold, design: .rounded)).monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    // MARK: Quick controls

    private var quickCards: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 14)], spacing: 14) {
            QuickCard("Travel mode", "airplane", .cyan,
                      model.travelUntil.map { "Holding 100% until \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "Hold 100% for 24 hours, then go back",
                      action: { model.travelUntil = model.travelUntil == nil ? Date().addingTimeInterval(86400) : nil }) {
                Toggle("", isOn: Binding(get: { model.travelUntil != nil }, set: { model.travelUntil = $0 ? Date().addingTimeInterval(86400) : nil }))
                    .labelsHidden().toggleStyle(.switch).controlSize(.small).disabled(model.status == nil)
            }
            QuickCard("Ready by", "alarm.fill", .orange, readySubtitle) { model.readyByRequested = true; model.go(.charging, focus: "Ready by") }
            QuickCard("Heat Protection", "thermometer.high", .red,
                      s?.heatProtection == false ? "Off" : "Pauses charging above \(s?.heatLimit ?? HeatLimit.defaultLimit)°C",
                      action: { model.go(.charging, focus: "Heat Protection") }) {
                Toggle("", isOn: Binding(get: { s?.heatProtection ?? true }, set: { model.cmd("heat \($0 ? "on" : "off")") }))
                    .labelsHidden().toggleStyle(.switch).controlSize(.small).disabled(status == nil)
            }
            QuickCard("Low Power Mode", "leaf.fill", .green, "Reduces power use on battery",
                      action: { model.go(.charging, focus: "Low Power Mode") }) {
                Toggle("", isOn: Binding(get: { s?.lowPower ?? false }, set: { model.cmd("lowpower \($0 ? "on" : "off")") }))
                    .labelsHidden().toggleStyle(.switch).controlSize(.small).disabled(status == nil)
            }
            QuickCard("Calibration", "gauge.with.dots.needle.50percent", .purple, calibrationSubtitle) { model.go(.charging, focus: "Calibration") }
            QuickCard("Menu bar icon", "macwindow.on.rectangle", .indigo, "Size, charging effect, what the ring shows") { model.go(.icon) }
            QuickCard("Appearance", "paintpalette.fill", .pink, "Colors, animation, compact mode") { model.go(.appearance) }
        }
    }

    private var readySubtitle: String {
        guard let cs = s?.chargeSchedule, cs.enabled else { return "Not set up. Be full before you leave." }
        return model.readySummary(cs)
    }

    private var calibrationSubtitle: String {
        if let t = task, t.kind == "calibrate" { return "Running now" }
        if let at = s?.calibrateAt { return "Scheduled \(at.formatted(date: .abbreviated, time: .shortened))" }
        if let sc = s?.schedule, sc.enabled { return "Repeats monthly on day \(sc.days.map(String.init).joined(separator: ", "))" }
        return "Not scheduled"
    }

    // MARK: Zones

    private var zoneRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 20) {
                ForEach(model.config.zones) { z in
                    ZoneTile(zone: z, active: model.target.label == z.name,
                             pinned: model.config.overrideZone == z.name,
                             onSelect: { model.config.overrideZone = model.config.overrideZone == z.name ? nil : z.name },
                             onEdit: { model.go(.zones, focus: "Zones") })
                }
                DefaultTile(upper: model.config.defaultUpper, lower: model.config.defaultLower,
                            active: model.target.label == "Default") { model.go(.zones, focus: "Everywhere else") }
            }
            .padding(.horizontal, 20).padding(.vertical, 26)
        }
        .padding(.horizontal, -20)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Label(model.networks.first ?? "No network detected", systemImage: "wifi")
                .font(.callout).padding(.horizontal, 12).padding(.vertical, 7).glassEffect(.regular, in: .capsule)
            if !model.locationAllowed {
                Text("Allow Location to read Wi-Fi names and use saved places; the router address is used meanwhile.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Open General") { model.go(.general, focus: "Location access") }.buttonStyle(.link).font(.caption)
            }
            Spacer()
        }
    }
}

/// A tappable summary of one setting, with an optional control (like a switch) that doesn't trigger the tap.
struct QuickCard<Trailing: View>: View {
    let title: String
    let icon: String
    let tint: Color
    let subtitle: String
    let action: () -> Void
    @ViewBuilder var trailing: Trailing
    @State private var hover = false

    init(_ title: String, _ icon: String, _ tint: Color, _ subtitle: String, action: @escaping () -> Void,
         @ViewBuilder trailing: () -> Trailing) {
        self.title = title; self.icon = icon; self.tint = tint; self.subtitle = subtitle; self.action = action; self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: action) {
                HStack(spacing: 12) {
                    Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 36, height: 36).background(tint.gradient, in: .rect(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.system(.body, design: .rounded).weight(.semibold)).lineLimit(1)
                        Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            trailing
            if Trailing.self == EmptyView.self {
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
        .padding(14).frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
        .glassEffect(.regular.tint(tint.opacity(hover ? 0.22 : 0.12)), in: .rect(cornerRadius: 22))
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: hover)
    }
}

extension QuickCard where Trailing == EmptyView {
    init(_ title: String, _ icon: String, _ tint: Color, _ subtitle: String, action: @escaping () -> Void) {
        self.init(title, icon, tint, subtitle, action: action) { EmptyView() }
    }
}
