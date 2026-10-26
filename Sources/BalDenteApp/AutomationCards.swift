import BalDenteCore
import SwiftUI

/// Sleep behaviour, the MagSafe LED and the task Schedule: the helper-side options added together.

struct SleepCard: View {
    @ObservedObject var model: Model
    private var s: LimiterState? { model.status?.state }

    var body: some View {
        CardShell("Sleep", "moon.zzz.fill", .indigo) {
            Toggle("Stop charging when sleeping", isOn: Binding(get: { s?.stopWhenSleeping ?? false },
                   set: { model.cmd("sleepstop \($0 ? "on" : "off")") })).toggleStyle(.switch).disabled(model.status == nil || model.helperOutdated)
                .settingAnchor("Stop charging when sleeping")
            Text("Cuts the charger as the Mac goes to sleep, so it can't creep past your limit overnight. The battery drifts down slowly while asleep, and it isn't done below \(LimiterState.sleepFloor)%.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Toggle("Stay awake until the limit", isOn: Binding(get: { s?.stayAwake ?? false },
                   set: { model.cmd("stayawake \($0 ? "on" : "off")") })).toggleStyle(.switch).disabled(model.status == nil || model.helperOutdated)
                .settingAnchor("Stay awake until the limit")
            Text("Keeps the Mac awake (lid closed is fine) only while it charges toward the limit, then lets it sleep. Unplugging ends it.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct LEDCard: View {
    @ObservedObject var model: Model

    var body: some View {
        CardShell("MagSafe LED", "light.beacon.max.fill", .green) {
            Picker("", selection: Binding(get: { model.status?.state.led ?? .system }, set: { model.cmd("led \($0.rawValue)") })) {
                ForEach(MagSafeLED.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().disabled(model.status == nil || model.helperOutdated)
            if model.status?.state.led == .custom, let st = model.status?.state {
                colorRow("At the limit", st.ledAtLimit) { model.cmd("led custom \($0.rawValue) \(st.ledCharging.rawValue)") }
                colorRow("While charging", st.ledCharging) { model.cmd("led custom \(st.ledAtLimit.rawValue) \($0.rawValue)") }
            }
            Text("\"Show the limit\" turns the LED green while the charger is held at your limit and orange while charging; Custom lets you pick each colour. Unplugged, macOS controls the light. Experimental: it writes a new SMC key, so if the light looks wrong, switch back to Default. BalDente also hands the LED back to macOS when it quits.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

extension LEDCard {
    fileprivate func colorRow(_ title: String, _ value: LEDColor, set: @escaping (LEDColor) -> Void) -> some View {
        HStack {
            Text(title).font(.callout)
            Spacer()
            Picker("", selection: Binding(get: { value }, set: set)) { ForEach(LEDColor.allCases) { Text($0.title).tag($0) } }
                .labelsHidden().frame(width: 120)
        }
    }
}

struct ScheduleCard: View {
    @ObservedObject var model: Model
    @State private var editing: ScheduledTask?
    @State private var showHistory = false
    private var tasks: [ScheduledTask] { model.status?.state.tasks ?? [] }

    var body: some View {
        CardShell("Schedule", "calendar.badge.clock", .teal) {
            if tasks.isEmpty {
                Text("Run Top Up, a Discharge, a Calibration or Low Power Mode on a schedule: daily, weekdays, weekly, monthly and more.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(tasks) { t in
                HStack(spacing: 8) {
                    Toggle("", isOn: Binding(get: { t.enabled }, set: { model.cmd("task enable \(t.id) \($0 ? "on" : "off")") }))
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(t.summary).font(.callout.weight(.semibold)).lineLimit(2)
                        if let n = t.nextRun(after: Date()) {
                            Text("Next: \(n.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 4)
                    Button { editing = t } label: { Image(systemName: "pencil") }.buttonStyle(.glass).buttonBorderShape(.circle)
                    Button { model.cmd("task remove \(t.id)") } label: { Image(systemName: "trash") }.buttonStyle(.glass).buttonBorderShape(.circle)
                }
            }
            HStack {
                Button { editing = Self.template() } label: { pill("Add Task", "plus") }
                    .buttonStyle(.glass).disabled(model.status == nil || model.helperOutdated || tasks.count >= ScheduledTask.maxCount)
                if let log = model.status?.state.taskLog, !log.isEmpty {
                    Button { showHistory.toggle() } label: { pill("History", "clock.arrow.circlepath") }.buttonStyle(.glass)
                }
            }
            if showHistory, let log = model.status?.state.taskLog {
                ForEach(log.suffix(6).reversed()) { r in
                    Text("\(r.date.formatted(date: .abbreviated, time: .shortened)): \(r.action.title), \(r.note)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("The helper checks every 20 seconds, but a sleeping Mac can't run tasks. \"Catch up\" runs a missed one when the Mac wakes within a day. A limit isn't a task: zones set the limit.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .sheet(item: $editing) { t in TaskEditor(model: model, task: t) }
    }

    /// A monthly calibration at 09:00, the example most people want first.
    private static func template() -> ScheduledTask {
        ScheduledTask(action: .calibrate, repeats: .monthly, hour: 9, minute: 0, anchor: Date())
    }
}

struct TaskEditor: View {
    @ObservedObject var model: Model
    @State var task: ScheduledTask
    @Environment(\.dismiss) private var dismiss

    private var time: Binding<Date> {
        Binding(get: { Calendar.current.date(from: DateComponents(hour: task.hour, minute: task.minute)) ?? Date() },
                set: { let c = Calendar.current.dateComponents([.hour, .minute], from: $0); task.hour = c.hour ?? 9; task.minute = c.minute ?? 0 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Scheduled task").font(.system(size: 24, weight: .bold, design: .rounded))
            Picker("Action", selection: $task.action) { ForEach(ScheduledTask.Action.allCases, id: \.self) { Text($0.title).tag($0) } }
            if task.action == .discharge {
                Stepper("Discharge to \(task.percent)%", value: $task.percent, in: AutoDischarge.minimumTarget...90, step: 5)
            }
            Picker("Repeat", selection: $task.repeats) { ForEach(ScheduledTask.Repeat.allCases, id: \.self) { Text($0.title).tag($0) } }
            DatePicker("Starting", selection: $task.anchor, displayedComponents: .date)
            DatePicker("At", selection: time, displayedComponents: .hourAndMinute)
            Toggle("Catch up if the Mac was asleep", isOn: $task.catchUp).toggleStyle(.switch)
            if let n = task.nextRun(after: Date()) {
                Text("Next run: \(n.formatted(date: .complete, time: .shortened))").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("Cancel") { dismiss() }.buttonStyle(.glass)
                Spacer()
                Button("Save") { model.cmd(task.wire); dismiss() }.buttonStyle(.glassProminent)
            }
        }
        .padding(28).frame(width: 440).presentationBackground(.ultraThinMaterial)
    }
}

/// The same glass card the Charging page uses, shared so the new cards match.
struct CardShell<C: View>: View {
    let title: String, icon: String, tint: Color
    @ViewBuilder var content: C
    init(_ title: String, _ icon: String, _ tint: Color, @ViewBuilder content: () -> C) {
        self.title = title; self.icon = icon; self.tint = tint; self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon).font(.system(size: 16, weight: .bold, design: .rounded))
            content
            Spacer(minLength: 0)
        }
        .padding(18).frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .glassEffect(.regular.tint(tint.opacity(0.14)), in: .rect(cornerRadius: 26))
        .settingAnchor(title)
    }
}
