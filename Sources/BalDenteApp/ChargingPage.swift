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
            card("Discharge", "arrow.down.to.line", .blue) {
                Text("Drain to \(Int(dischargeTarget))% with the charger plugged in.").font(.callout).foregroundStyle(.secondary)
                Slider(value: $dischargeTarget, in: 10...90, step: 5)
                Button { model.cmd("discharge \(Int(dischargeTarget))") } label: { pill("Start Discharge", "play.fill") }
                    .buttonStyle(.glass).disabled(task != nil || status == nil)
            }
            card("Calibration", "gauge.with.dots.needle.50percent", .purple) {
                Text("Drain to 15%, charge to 100%, rest an hour. Keeps the percentage accurate. Leave it plugged in; the Mac stays awake while it runs.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let at = s?.calibrateAt {
                    HStack {
                        Label("Scheduled \(at.formatted(date: .abbreviated, time: .shortened))", systemImage: "moon.stars.fill")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        Spacer()
                        Button("Cancel") { model.cmd("calibrate off") }.buttonStyle(.glass).controlSize(.small)
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
                if let sc = s?.schedule, sc.enabled {
                    Label("Repeats on days \(sc.days.map(String.init).joined(separator: ", ")) at " + String(format: "%02d:%02d", sc.hour, sc.minute),
                          systemImage: "calendar").font(.caption)
                }
                HStack {
                    Button { model.cmd("calibrate") } label: { pill("Start Now", "play.fill") }.buttonStyle(.glass).disabled(task != nil || status == nil)
                    Button { sheet = .schedule } label: { pill("Repeat…", "calendar") }.buttonStyle(.glass).disabled(status == nil)
                }
            }
            card("Low Power Mode", "leaf.fill", .green) {
                Toggle("Save energy on battery", isOn: Binding(get: { s?.lowPower ?? false },
                       set: { model.cmd("lowpower \($0 ? "on" : "off")") })).toggleStyle(.switch).disabled(status == nil)
                Text("Asks macOS to reduce power use. Applies instantly.").font(.callout).foregroundStyle(.secondary)
            }
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
    }
}
