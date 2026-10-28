import BalDenteCore
import SwiftUI

/// Every charging tool as a card: Ready by, heat protection, discharge, calibration and Low Power Mode.
struct ChargingPage: View {
    @ObservedObject var model: Model
    @State private var sheet: ActiveSheet?
    @State private var dischargeTarget = 30.0
    @State private var calTime = Calendar.current.date(from: DateComponents(hour: 3, minute: 0)) ?? Date()

    private var status: Status? { model.status }
    private var task: TaskState? { model.task }

    var body: some View {
        let s = status?.state
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16)], spacing: 16) {
            card("Ready by", "alarm.fill", .orange) {
                if let cs = s?.chargeSchedule, cs.enabled {
                    Text(model.readySummary(cs)).font(.callout.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                    if let next = cs.nextSlot(after: Date()) {
                        let start = next.ready.addingTimeInterval(-ChargeSchedule.leadMinutes(percent: model.percent, target: next.slot.percent) * 60)
                        Text("Next: charging starts about \(start.formatted(date: .omitted, time: .shortened)) to reach \(next.slot.percent)% by \(next.ready.formatted(date: .abbreviated, time: .shortened)).")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text("Reach a chosen charge before you leave, then go back to your zone's limit.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Button { sheet = .readyBy } label: { pill(s?.chargeSchedule.enabled == true ? "Edit" : "Set Up", "calendar.badge.clock") }
                    .buttonStyle(.glass).disabled(status == nil || model.calendar.enabled)
            }
            CalendarCard(model: model, cal: model.calendar)
            card("Heat Protection", "thermometer.high", .red) {
                Toggle("Pause charging when hot", isOn: Binding(get: { s?.heatProtection ?? true },
                       set: { model.cmd("heat \($0 ? "on" : "off")") })).toggleStyle(.switch).disabled(status == nil)
                HeatLimitControl(value: s?.heatLimit ?? HeatLimit.defaultLimit, enabled: s?.heatProtection != false && status != nil) {
                    model.cmd("heat \(s?.heatProtection ?? true ? "on" : "off") \($0)")
                }
            }
            card("macOS Charge Limit", "bolt.horizontal.fill", .green) {
                if let p = model.macLimitPrompt {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(p.message, systemImage: "exclamationmark.triangle.fill").font(.callout.weight(.semibold)).foregroundStyle(.orange)
                        Text(MacLimitPrompt.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Button { model.openBatterySettings() } label: { pill(MacLimitPrompt.buttonTitle, "gearshape") }
                            .buttonStyle(.glass).help("Open System Settings > Battery to set macOS's charge limit to \(p.needed)%")
                    }.settingAnchor("Open Battery Settings")
                }
                Picker("macOS charge limit", selection: Binding(
                    get: { model.config.macLimitAuto ?? (model.config.macLimit == nil) ? -1 : (model.config.macLimit ?? 0) },
                    set: { v in
                        model.config.macLimitAuto = v == -1
                        if v != -1 { model.config.macLimit = v == 0 ? nil : v }
                    })) {
                    Text("Automatic (follow macOS)").tag(-1)
                    Text("Not using").tag(0)
                    ForEach(MacChargeLimit.steps, id: \.self) { Text("\($0)%").tag($0) }
                }.settingAnchor("macOS charge limit")
                Text(model.macLimit.map {
                    "macOS is set to hold \($0)%\(model.config.effectiveMacLimit(detected: nil) == nil ? " (read from System Settings > Battery)" : ""). A zone set to \($0)% is left to macOS, which stops charging there and runs the Mac from the charger. BalDente only reminds you to change the macOS setting when a zone needs more than \($0)%."
                } ?? "No macOS charge limit is set, so BalDente holds every zone itself by cutting the charger. It follows System Settings > Battery automatically: set 80, 85, 90 or 95% there and zones at that level are left to macOS, which runs the Mac from the charger instead of the battery.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            card("Sailing", "sailboat", .teal) {
                Toggle("Sailing", isOn: Binding(get: { model.sailing }, set: { model.config.sailing = $0 }))
                    .toggleStyle(.switch).settingAnchor("Sailing")
                Text(model.sailing
                     ? "Charging resumes at each zone's own resume level, so the battery drifts down between the two numbers. This Mac can only pause charging by cutting the charger, so that drift runs it from the battery."
                     : "Off: charging resumes one point under the limit, so the charger is only cut for a moment at a time.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Toggle("Keep charging while busy", isOn: Binding(get: { s?.loadGuard ?? true },
                       set: { model.cmd("loadguard \($0 ? "on" : "off")") })).toggleStyle(.switch)
                    .disabled(status == nil || model.helperOutdated).settingAnchor("Keep charging while busy")
                Text("When the Mac is busy and the battery has only just reached its limit, the charger stays on for up to \(LoadGuard.maxOvershoot) more points, so a build or export doesn't run on the battery. Needs the latest helper.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            card("Discharge", "arrow.down.to.line", .blue) {
                Text("Drain to \(Int(dischargeTarget))% with the charger plugged in.").font(.callout).foregroundStyle(.secondary)
                Slider(value: $dischargeTarget, in: 10...90, step: 5)
                Button { model.cmd("discharge \(Int(dischargeTarget))") } label: { pill("Start Discharge", "play.fill") }
                    .buttonStyle(.glass).disabled(task != nil || status == nil)
                Toggle("Discharge automatically", isOn: Binding(get: { model.config.autoDischarge ?? false },
                       set: { model.config.autoDischarge = $0 })).toggleStyle(.switch).settingAnchor("Automatic Discharge")
                Text("When your limit drops below the battery, drain to it on its own. Skips Top Up, Travel mode and a Ready by within \(Int(AutoDischarge.readyByQuietHours)) hours.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            card("Calibration", "gauge.with.dots.needle.50percent", .purple) {
                Text("Drain to 15%, charge to 100%, rest an hour. Keeps the percentage accurate. Leave it plugged in; the Mac stays awake while it runs.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let t = task, let progress = CalibrationProgress.text(t, percent: model.percent) {
                    Label(progress, systemImage: "gauge.with.dots.needle.50percent")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold)).foregroundStyle(.purple)
                    if t.phase == "discharge", t.pausedAt == nil, let est = model.drainEstimate {
                        Text("Draining to 15% takes \(est) at the current power use.").font(.caption).foregroundStyle(.secondary)
                    }
                    if let e = CalibrationProgress.elapsedText(t) {
                        Text(e).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    if t.phase != "discharge", model.onBattery {
                        Label("Unplugged: plug the charger back in to continue.", systemImage: "bolt.slash.fill")
                            .font(.caption.weight(.semibold)).foregroundStyle(.orange)
                    }
                } else if let at = s?.calibrateAt {
                    HStack {
                        Label("Scheduled \(at.formatted(date: .abbreviated, time: .shortened))", systemImage: "moon.stars.fill")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        Spacer()
                    }
                } else {
                    VStack(spacing: 10) {
                        HStack(spacing: 10) {
                            Image(systemName: "moon.stars.fill").foregroundStyle(.purple)
                            DatePicker("", selection: $calTime, displayedComponents: .hourAndMinute).labelsHidden()
                            Spacer(minLength: 8)
                            Text(nextCalibrationText).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Color.purple.opacity(0.12), in: .rect(cornerRadius: 14))
                        Button {
                            let c = Calendar.current.dateComponents([.hour, .minute], from: calTime)
                            model.cmd("calibrate at \(String(format: "%02d:%02d", c.hour ?? 3, c.minute ?? 0))")
                        } label: { pill("Calibrate at this time", "moon.stars.fill").frame(maxWidth: .infinity) }
                            .buttonStyle(.glassProminent).tint(.purple).controlSize(.large)
                            .disabled(task != nil || status == nil)
                    }
                }
                if task == nil, let est = model.drainEstimate, model.percent > CalibrationProgress.drainTarget {
                    Label("Draining from \(model.percent)% would take \(est) at the current power use.", systemImage: "hourglass")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Calibrate overnight", isOn: Binding(get: { model.config.overnightCalibration ?? false },
                       set: { model.config.overnightCalibration = $0 })).toggleStyle(.switch).settingAnchor("Calibrate overnight")
                Text("Once a month, starts when you plug in between 10 PM and 5 AM. Cancelling it skips that night.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if task == nil, let last = CalibrationProgress.lastText(model.lastCalibration) {
                    Label(last, systemImage: "checkmark.circle").font(.caption).foregroundStyle(.secondary)
                }
                if let sc = s?.schedule, sc.enabled {
                    Label("Repeats on days \(sc.days.map(String.init).joined(separator: ", ")) at " + String(format: "%02d:%02d", sc.hour, sc.minute),
                          systemImage: "calendar").font(.caption)
                }
                HStack {
                    if task?.kind == "calibrate" {
                        Button { model.cmd("cancel") } label: { pill("Cancel", "xmark") }.buttonStyle(.glass)
                        if task?.pausedAt != nil {
                            Button { model.cmd("calibrate resume") } label: { pill("Resume", "play.fill") }.buttonStyle(.glass)
                        } else {
                            Button { model.cmd("calibrate pause") } label: { pill("Pause", "pause.fill") }.buttonStyle(.glass)
                        }
                    } else if s?.calibrateAt != nil {
                        Button { model.cmd("calibrate off") } label: { pill("Cancel", "xmark") }.buttonStyle(.glass)
                    } else {
                        Button { model.cmd("calibrate") } label: { pill("Start Now", "play.fill") }.buttonStyle(.glass).disabled(task != nil || status == nil)
                    }
                    Button { sheet = .schedule } label: { pill("Repeat…", "calendar") }.buttonStyle(.glass).disabled(status == nil)
                }
            }
            card("Low Power Mode", "leaf.fill", .green) {
                Toggle("Save energy on battery", isOn: Binding(get: { s?.lowPower ?? false },
                       set: { model.cmd("lowpower \($0 ? "on" : "off")") })).toggleStyle(.switch).disabled(status == nil)
                Text("Asks macOS to reduce power use. Applies instantly.").font(.callout).foregroundStyle(.secondary)
            }
            SleepCard(model: model).modifier(HelperLock(model: model))
            ScheduleCard(model: model).modifier(HelperLock(model: model))
            if model.status?.ledAvailable == true { LEDCard(model: model).modifier(HelperLock(model: model)) }
        }
        .sheets(model, $sheet)
        .opensReadyBy(model, $sheet)
    }

    /// "Tonight", "Today" or "Tomorrow": the next time the chosen clock reading occurs.
    private var nextCalibrationText: String {
        let cal = Calendar.current
        let c = cal.dateComponents([.hour, .minute], from: calTime)
        guard let next = cal.nextDate(after: Date(), matching: c, matchingPolicy: .nextTime) else { return "" }
        let hour = c.hour ?? 3
        if cal.isDateInToday(next) { return hour >= 18 || hour < 5 ? "Tonight" : "Today" }
        return cal.isDateInTomorrow(next) && hour < 5 ? "Tonight" : "Tomorrow"
    }

    private func card<C: View>(_ title: String, _ icon: String, _ tint: Color, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon).font(.system(size: 16, weight: .bold, design: .rounded))
            content()
            Spacer(minLength: 0)
        }
        .padding(18).frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .glassEffect(.regular.tint(tint.opacity(0.14)), in: .rect(cornerRadius: 26))
        .settingAnchor(title)
        .modifier(HelperLock(model: model))
    }
}
