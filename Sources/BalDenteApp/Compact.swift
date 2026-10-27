import BalDenteCore
import SwiftUI

/// The same features as the regular dashboard in a dense, standard-looking Mac layout.
struct CompactView: View {
    @ObservedObject var model: Model
    @State private var sheet: ActiveSheet?
    @State private var dischargeTarget = 30.0
    @State private var calTime = Calendar.current.date(from: DateComponents(hour: 3, minute: 0)) ?? Date()

    private var s: LimiterState? { model.status?.state }

    var body: some View {
        Form {
            if model.status == nil || model.helperOutdated {
                Section {
                    HStack {
                        Label(model.status != nil ? "Helper update available" : model.helperInstalled ? "Helper isn't responding" : "Helper not installed",
                              systemImage: "lock.shield.fill")
                        Spacer()
                        Button(model.status != nil ? "Update" : "Install") { model.setUp() }.disabled(model.busy)
                    }
                    if let e = model.setupError { Text(e).font(.caption).foregroundStyle(.red) }
                }
            }
            Section {
                HStack(spacing: 14) {
                    BatteryRing(percent: model.percent, lower: model.target.lower, upper: model.target.upper,
                                caption: model.ringCaption(compact: true), tint: model.accent, size: 92)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.headline).font(.title3.weight(.semibold))
                        Text(model.subline).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                HStack {
                    Button(model.topUp ? "Cancel Top Up" : "Top Up to 100%") { model.toggleTopUp() }
                        .buttonStyle(.borderedProminent)
                    if model.task != nil { Button("Cancel Task") { model.cmd("cancel") } }
                }
            }
            if let hint = model.holdHintText {
                Section {
                    HStack(alignment: .top) {
                        Label(hint, systemImage: "info.circle").font(.callout)
                        Spacer()
                        Button { model.holdHint.dismissed = true } label: { Image(systemName: "xmark") }
                            .buttonStyle(.borderless).help("Don't show this again")
                    }
                    HStack {
                        Button("Top Up Now") { model.toggleTopUp() }
                        Button("Set Ready by…") { model.openReadyBy() }.disabled(model.calendar.enabled)
                    }
                }
            }
            if let sug = model.habitSuggestion {
                Section("Suggestion") {
                    Text(sug.question)
                    Text("Nothing changes unless you accept. It sets up Ready by.").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Accept") { model.acceptHabit() }.buttonStyle(.borderedProminent)
                        Button("Not Now") { model.snoozeHabit() }
                        Button("Don't Suggest Again") { model.dismissHabit() }
                    }
                }
            }
            if let ns = model.networkSuggestion { NetworkSuggestionView(model: model, suggestion: ns, compact: true) }
            Section("Zones") {
                Picker("Mode", selection: Binding(get: { model.config.overrideZone ?? "" },
                                                  set: { model.config.overrideZone = $0.isEmpty ? nil : $0 })) {
                    Text("Automatic").tag("")
                    ForEach(model.config.zones) { Text("Pin \($0.name)").tag($0.name) }
                }
                ForEach(model.config.zones) { z in
                    HStack {
                        Image(systemName: Theme.icon(z)).frame(width: 22)
                        Text(z.name)
                        if z.place != nil { Image(systemName: "location.fill").font(.caption2).foregroundStyle(.secondary) }
                        Spacer()
                        Text("\(z.upper)% / \(z.lower)%").foregroundStyle(.secondary).monospacedDigit()
                        if model.target.zoneID == z.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(model.accent) }
                        Button { sheet = .zone(z.id) } label: { Image(systemName: "slider.horizontal.3") }.buttonStyle(.borderless)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { model.config.overrideZone = model.config.overrideZone == z.name ? nil : z.name }
                }
                HStack {
                    Button("Add Zone") { sheet = .zone(model.addZone().id) }
                    Button("Everywhere else…") { sheet = .defaults }
                }
            }
            Section("Ready by") {
                if let cs = s?.chargeSchedule, cs.enabled {
                    Text(model.readySummary(cs)).font(.callout)
                    if let next = cs.nextSlot(after: Date()) {
                        let pct = model.percent
                        let start = next.ready.addingTimeInterval(-ChargeSchedule.leadMinutes(percent: pct, target: next.slot.percent) * 60)
                        Text("Next: starts about \(start.formatted(date: .omitted, time: .shortened)) to reach \(next.slot.percent)% by \(next.ready.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Text("Not set").foregroundStyle(.secondary)
                }
                Button(s?.chargeSchedule.enabled == true ? "Edit…" : "Set Up…") { sheet = .readyBy }
            }
            Section("Protection") {
                Toggle("Heat protection", isOn: Binding(get: { s?.heatProtection ?? true }, set: { model.cmd("heat \($0 ? "on" : "off")") }))
                HeatLimitField(value: s?.heatLimit ?? HeatLimit.defaultLimit, enabled: s?.heatProtection != false) {
                    model.cmd("heat \(s?.heatProtection ?? true ? "on" : "off") \($0)")
                }
                Toggle("Low Power Mode on battery", isOn: Binding(get: { s?.lowPower ?? false }, set: { model.cmd("lowpower \($0 ? "on" : "off")") }))
            }
            Section("Discharge and calibration") {
                HStack {
                    Stepper("Discharge to \(Int(dischargeTarget))%", value: $dischargeTarget, in: 10...90, step: 5)
                    Button("Start") { model.cmd("discharge \(Int(dischargeTarget))") }.disabled(model.task != nil)
                }
                if let at = s?.calibrateAt {
                    HStack {
                        Label("Calibration \(at.formatted(date: .abbreviated, time: .shortened))", systemImage: "moon.stars.fill")
                        Spacer()
                        Button("Cancel") { model.cmd("calibrate off") }
                    }
                } else {
                    HStack {
                        DatePicker("Calibrate at", selection: $calTime, displayedComponents: .hourAndMinute)
                        Button("Schedule") {
                            let c = Calendar.current.dateComponents([.hour, .minute], from: calTime)
                            model.cmd("calibrate at \(String(format: "%02d:%02d", c.hour ?? 3, c.minute ?? 0))")
                        }.disabled(model.task != nil)
                    }
                }
                HStack {
                    Button("Calibrate Now") { model.cmd("calibrate") }.disabled(model.task != nil)
                    Button("Repeat…") { sheet = .schedule }
                }
            }
            Section {
                if model.activity.entries.isEmpty {
                    Text("Nothing yet. Every limit change shows up here with its reason.").font(.callout).foregroundStyle(.secondary)
                }
                ForEach(model.activity.entries.prefix(5)) { e in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.title).font(.callout.weight(.semibold))
                        Text("\(e.date.formatted(date: .abbreviated, time: .shortened)) · \(e.detail)").font(.caption).foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            } header: {
                HStack {
                    Text("Recent changes")
                    Spacer()
                    if !model.activity.entries.isEmpty { Button("Clear") { model.clearActivity() }.buttonStyle(.borderless).font(.caption) }
                }
            }
            Section("Battery") {
                LabeledContent("Health", value: model.info?.healthPercent.map { "\($0)%" } ?? "–")
                LabeledContent("Cycles", value: model.info.map { "\($0.cycles)" } ?? "–")
                LabeledContent("Temperature", value: (model.status?.tempC ?? model.info?.tempC).map { String(format: "%.1f °C", $0) } ?? "–")
                LabeledContent("Power", value: model.info.map { String(format: "%+.1f W", $0.watts) } ?? "–")
            }
            Section("Support BalDente") {
                Text("Free forever. Chip in if it helps.").font(.callout).foregroundStyle(.secondary)
                DonateButtons()
            }
            Section("Menu bar icon") {
                Text("Icon size, charging animation, network, Bluetooth, audio and status panel options live in the regular window.")
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    Button("Menu Bar Icon…") { model.go(.icon); model.appearance.compact = false }
                    Button("Battery Display…") { model.go(.battery); model.appearance.compact = false }
                }
            }
            Section {
                Toggle("Launch at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.launchAtLogin = $0 }))
                HStack {
                    Button("Appearance…") { sheet = .appearance }
                    Button("All Settings & Search") { model.go(.overview); model.appearance.compact = false }
                        .help("Switch to the regular window, where every setting has a page and a search box.")
                    Spacer()
                    if model.helperInstalled { Button("Remove Helper") { model.removeHelper() }.disabled(model.busy) }
                }
            }
        }
        .formStyle(.grouped)
        .tint(model.accent)
        .safeAreaInset(edge: .top, spacing: 0) { Color.clear.frame(height: 18) }   // room for the window buttons
        .sheets(model, $sheet)
        .opensReadyBy(model, $sheet)
    }
}
