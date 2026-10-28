import BalDenteCore
import SwiftUI

/// Small, shared button label. Single line and sized to its content so it never wraps or clips.
func pill(_ text: String, _ icon: String) -> some View {
    Label(text, systemImage: icon).font(.system(.subheadline, design: .rounded).weight(.semibold)).lineLimit(1).fixedSize()
        .padding(.horizontal, 8).padding(.vertical, 4)
}

enum ActiveSheet: Identifiable, Hashable {
    case zone(UUID), defaults, readyBy, schedule, appearance
    var id: String {
        switch self {
        case .zone(let u): "zone-\(u)"
        case .defaults: "defaults"
        case .readyBy: "readyBy"
        case .schedule: "schedule"
        case .appearance: "appearance"
        }
    }
}

extension View {
    /// Opens the Ready by editor when another page asked for it (calendar-driven Ready by has no manual editor).
    func opensReadyBy(_ model: Model, _ sheet: Binding<ActiveSheet?>) -> some View {
        func consume() {
            guard model.readyByRequested else { return }
            model.readyByRequested = false
            if model.status != nil, !model.calendar.enabled { sheet.wrappedValue = .readyBy }
        }
        return onAppear(perform: consume).onChange(of: model.readyByRequested) { _, _ in consume() }
    }

    /// One place that knows how to present every sheet, shared by both layouts.
    func sheets(_ model: Model, _ active: Binding<ActiveSheet?>) -> some View {
        sheet(item: active) { s in
            switch s {
            case .zone(let id): ZoneEditor(model: model, zoneID: id)
            case .defaults: DefaultLimitsSheet(model: model)
            case .readyBy: ReadyBySheet(model: model)
            case .schedule: ScheduleSheet(model: model)
            case .appearance: AppearanceSheet(model: model)
            }
        }
    }
}

struct RootView: View {
    @ObservedObject var model: Model
    @Environment(\.openWindow) private var openWindow
    private var compact: Bool { model.appearance.compact }

    var body: some View {
        Group {
            if compact { CompactView(model: model) } else { MainWindow(model: model) }
        }
        .frame(minWidth: 0, minHeight: 0)   // no minimum: the window can be made as small as wanted
        // First run gets the tour; after an update, What's New. Closing either one counts as seen.
        .sheet(isPresented: Binding(get: { model.showTutorial }, set: { if !$0, model.showTutorial { model.finishTutorial() } })) {
            TutorialSheet(model: model)
        }
        .background(Color.clear.sheet(isPresented: Binding(get: { model.whatsNew != nil && !model.showTutorial },
                                                          set: { if !$0, model.whatsNew != nil { model.finishWhatsNew() } })) {
            WhatsNewSheet(model: model, items: model.whatsNew ?? [])
        })
        .onAppear { WindowOpener.action = openWindow }
        .onOpenURL { if let a = AutomationURL.parse($0) { model.run(a) } }
        .onChange(of: compact) { _, c in
            guard let w = NSApp.windows.first(where: { $0.canBecomeMain && $0.isVisible }) else { return }
            let size = c ? NSSize(width: 520, height: 760) : NSSize(width: 1180, height: 780)
            var f = w.frame
            f.origin.y += f.height - size.height    // keep the top edge where it is
            f.size = size
            w.setFrame(f, display: true, animate: true)
        }
    }
}

struct DefaultTile: View {
    let upper: Int
    let lower: Int
    let active: Bool
    let onEdit: () -> Void
    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "globe").font(.system(size: 38, weight: .medium)).symbolRenderingMode(.hierarchical)
            Spacer()
            Text("Everywhere else").font(.system(size: 20, weight: .bold, design: .rounded))
            Text("\(upper)% / \(lower)%").font(.system(.title3, design: .rounded).weight(.light)).foregroundStyle(.secondary)
            Text(active ? "ACTIVE" : "Default limits").font(.system(size: 10, weight: .bold, design: .rounded)).tracking(1.5).foregroundStyle(.secondary)
        }
        .padding(18).frame(width: 210, height: 236, alignment: .topLeading)
        .contentShape(.rect(cornerRadius: 34))
        .glassEffect(.regular.tint(Color.primary.opacity(active ? 0.2 : 0.05)).interactive(), in: .rect(cornerRadius: 34))
        .scaleEffect(hover ? 1.06 : 1)
        .animation(.spring(duration: 0.4, bounce: 0.3), value: hover)
        .onHover { hover = $0 }
        .onTapGesture(perform: onEdit)
    }
}

// MARK: - Sheets

struct DefaultLimitsSheet: View {
    @ObservedObject var model: Model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Everywhere else").font(.system(size: 28, weight: .bold, design: .rounded))
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.glassProminent)
            }
            Text("These limits apply when no zone matches your Wi-Fi or location.").foregroundStyle(.secondary)
            slider("Stop charging at", $model.config.defaultUpper, 20...100)
                .onChange(of: model.config.defaultUpper) { _, u in if model.config.defaultLower >= u { model.config.defaultLower = max(5, u - 5) } }
            if model.sailing {
                slider("Resume at", $model.config.defaultLower, 5...99)
                    .onChange(of: model.config.defaultLower) { _, l in if model.config.defaultUpper <= l { model.config.defaultUpper = l + 5 } }
            }
        }
        .padding(30).frame(width: 460).presentationBackground(.ultraThinMaterial)
    }

    private func slider(_ title: String, _ value: Binding<Int>, _ range: ClosedRange<Int>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).foregroundStyle(.secondary)
                Spacer()
                Text("\(value.wrappedValue)%").font(.system(size: 36, weight: .thin, design: .rounded)).monospacedDigit()
            }
            Slider(value: Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = Int($0) }),
                   in: Double(range.lowerBound)...Double(range.upperBound), step: 5)
        }
    }
}

/// The background picker (preview, mode, presets or custom colors), shared by the Appearance page and compact mode's sheet.
struct BackgroundControls: View {
    @ObservedObject var model: Model

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AuroraBackground(palette: model.palette, animated: false, style: model.appearance.style)
                .frame(height: 110).clipShape(.rect(cornerRadius: 22)).allowsHitTesting(false)
            Picker("Background", selection: Binding(get: { model.appearance.mode }, set: { model.appearance.mode = $0 })) {
                Text("Follow zone").tag("zone")
                Text("Preset").tag("preset")
                Text("Custom").tag("custom")
            }.pickerStyle(.segmented).labelsHidden()
            HStack {
                Text("Theme").foregroundStyle(.secondary)
                Picker("Theme", selection: Binding(get: { model.appearance.theme }, set: { model.appearance.theme = $0 })) {
                    Text("Dark").tag("dark"); Text("Light").tag("light"); Text("System").tag("system")
                }.pickerStyle(.segmented).labelsHidden()
            }
            HStack {
                Text("Style").foregroundStyle(.secondary)
                Picker("Style", selection: Binding(get: { model.appearance.style }, set: { model.appearance.style = $0 })) {
                    ForEach(Theme.styles, id: \.id) { Text($0.name).tag($0.id) }
                }.labelsHidden()
            }
            switch model.appearance.mode {
            case "preset":
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 12)], spacing: 12) {
                    ForEach(Theme.presets, id: \.name) { p in
                        let colors = p.hex.map { Color(hex: $0) }
                        let selected = model.appearance.preset == p.name
                        Button { model.appearance.preset = p.name } label: {
                            VStack(spacing: 6) {
                                Circle().fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 44, height: 44)
                                    .overlay(Circle().stroke(Color.primary.opacity(selected ? 0.9 : 0), lineWidth: 2.5).padding(-4))
                                Text(p.name).font(.caption)
                            }.frame(maxWidth: .infinity)
                        }.buttonStyle(.plain)
                    }
                }
            case "custom":
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(0..<3, id: \.self) { i in
                        ColorPicker(["Highlight", "Accent", "Deep"][i], selection: Binding(
                            get: { Color(hex: model.appearance.custom.indices.contains(i) ? model.appearance.custom[i] : "#808080") },
                            set: { c in
                                var a = model.appearance
                                while a.custom.count < 3 { a.custom.append("#808080") }
                                a.custom[i] = c.hex; model.appearance = a
                            }))
                    }
                    Text("Highlight tints buttons and the ring. Deep is the darkest area of the background.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            default:
                Text("The background changes color with the active zone: warm for Home, cool for School, and so on.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Compact mode's version of Appearance; the regular window has a full page instead.
struct AppearanceSheet: View {
    @ObservedObject var model: Model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Appearance").font(.system(size: 28, weight: .bold, design: .rounded))
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.glassProminent)
            }
            BackgroundControls(model: model)
            Toggle("Animate the background", isOn: Binding(get: { model.appearance.animated }, set: { model.appearance.animated = $0 }))
                .toggleStyle(.switch)
            Text("Animation pauses by itself when the app is in the background. Turn it off to save a little more energy.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Compact mode", isOn: Binding(get: { model.appearance.compact }, set: { model.appearance.compact = $0 }))
                .toggleStyle(.switch)
        }
        .padding(30).frame(width: 480).presentationBackground(.ultraThinMaterial)
    }
}

struct ReadyBySheet: View {
    @ObservedObject var model: Model
    @Environment(\.dismiss) private var dismiss
    private let order = [2, 3, 4, 5, 6, 7, 1]   // Monday first
    private let levels = Array(stride(from: 50, through: 100, by: 5))
    @State private var enabled = true
    @State private var on: Set<Int> = [2, 3, 4, 5, 6]
    @State private var times: [Int: Date] = [:]
    @State private var percents: [Int: Int] = [:]
    @State private var zone = ""
    @State private var travel = 0

    private func defaultTime() -> Date { Calendar.current.date(from: DateComponents(hour: 7, minute: 30)) ?? Date() }
    private func time(_ d: Int) -> Binding<Date> { Binding(get: { times[d] ?? defaultTime() }, set: { times[d] = $0 }) }
    private func percent(_ d: Int) -> Binding<Int> { Binding(get: { percents[d] ?? 100 }, set: { percents[d] = $0 }) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ready by").font(.system(size: 28, weight: .bold, design: .rounded))
            Text(travel > 0 ? "Pick the days, when you need to arrive, and how full you want the battery. Charging finishes when you leave, \(travel) minutes earlier."
                            : "Pick the days, when you leave, and how full you want the battery. Each day is independent.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Toggle("Charge automatically", isOn: $enabled).toggleStyle(.switch)
            VStack(spacing: 8) {
                ForEach(order, id: \.self) { d in
                    let isOn = on.contains(d)
                    HStack(spacing: 10) {
                        Toggle(Calendar.current.weekdaySymbols[d - 1], isOn: Binding(
                            get: { isOn }, set: { if $0 { on.insert(d) } else { on.remove(d) } }))
                            .toggleStyle(.switch)
                        Spacer()
                        // Only the time and level are disabled for an off day: disabling the whole row also froze its switch,
                        // so a day could be turned off but never back on.
                        Group {
                            DatePicker("", selection: time(d), displayedComponents: .hourAndMinute).labelsHidden()
                            Picker("", selection: percent(d)) { ForEach(levels, id: \.self) { Text("\($0)%").tag($0) } }
                                .labelsHidden().frame(width: 78)
                        }
                        .disabled(!isOn).opacity(isOn ? 1 : 0.4)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .glassEffect(.regular.tint(isOn ? .orange.opacity(0.18) : nil), in: .rect(cornerRadius: 18))
                    .opacity(1)
                }
            }
            Button("Copy the first enabled day to all enabled days") {
                if let first = order.first(where: { on.contains($0) }) {
                    for d in on { times[d] = times[first] ?? defaultTime(); percents[d] = percents[first] ?? 100 }
                }
            }.buttonStyle(.glass).controlSize(.small)
            Stepper(value: $travel, in: 0...LeaveTime.maxTravelMinutes, step: 5) {
                Text(travel == 0 ? "Travel time: none (times are when you leave)" : "Travel time: \(travel) min (times are when you arrive)")
            }
            Picker("Only when in zone", selection: $zone) {
                Text("Anywhere").tag("")
                ForEach(model.config.zones) { Text($0.name).tag($0.name) }
            }
            if !zone.isEmpty {
                Label("Won't run when you're outside \(zone), or under Travel Mode or Top Up. It only starts while \(zone) is the active zone. Choose Anywhere to run it wherever you are.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            Text("Ready by overrides your zone limits from when charging starts until 30 minutes after you leave. BalDente wakes the Mac when it needs to start, even with the lid closed. Keep the charger plugged in; a fully shut-down Mac can't be woken.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Cancel") { dismiss() }.buttonStyle(.glass)
                Spacer()
                Button("Save") { save(); dismiss() }.buttonStyle(.glassProminent)
            }
        }
        .padding(28).frame(width: 540).presentationBackground(.ultraThinMaterial)
        .onAppear(perform: load)
    }

    private func load() {
        guard let cs = model.status?.state.chargeSchedule, !cs.slots.isEmpty else { return }
        // The helper always holds a default Monday to Friday schedule, switched off. Opening this sheet means "set it up",
        // so it must start switched on; otherwise the first Save sent "ready off" and nothing was ever scheduled.
        enabled = true
        travel = cs.travelMinutes
        // Slots hold leave times; the editor shows arrival times, which are the same when there is no travel.
        let shown = cs.slots.map { ($0, LeaveTime.arrive(leaveWeekday: $0.weekday, hour: $0.hour, minute: $0.minute, travel: travel)) }
        on = Set(shown.map(\.1.weekday))
        for (s, a) in shown {
            times[a.weekday] = Calendar.current.date(from: DateComponents(hour: a.hour, minute: a.minute))
            percents[a.weekday] = min(100, max(50, Int((Double(s.percent) / 5).rounded()) * 5))
        }
        zone = cs.onlyZone ?? ""
    }

    private func save() {
        let cal = Calendar.current
        let spec = ChargeSchedule.spec(on.sorted().map { d in
            let c = cal.dateComponents([.hour, .minute], from: times[d] ?? defaultTime())
            let leave = LeaveTime.leave(arriveWeekday: d, hour: c.hour ?? 7, minute: c.minute ?? 30, travel: travel)
            return Slot(weekday: leave.weekday, hour: leave.hour, minute: leave.minute, percent: percents[d] ?? 100)
        })
        model.cmd("ready zone \(zone.isEmpty ? "any" : zone)")
        model.cmd("ready travel \(travel)")
        model.cmd(enabled && !on.isEmpty ? "ready on \(spec)" : "ready off")
        if enabled && !on.isEmpty { model.holdHint.uses += 1 }
    }
}

struct ScheduleSheet: View {
    @ObservedObject var model: Model
    @Environment(\.dismiss) private var dismiss
    @State private var enabled = true
    @State private var days = "1"
    @State private var time = Calendar.current.date(from: DateComponents(hour: 21, minute: 30)) ?? Date()

    private var validDays: [Int] {
        Array(Set(days.split(whereSeparator: { ", ".contains($0) }).compactMap { Int($0) }.filter { (1...31).contains($0) })).sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Calibration Schedule").font(.system(size: 28, weight: .bold, design: .rounded))
            Toggle("Run automatically", isOn: $enabled).toggleStyle(.switch)
            VStack(alignment: .leading, spacing: 6) {
                Text("Days of the month, comma separated").foregroundStyle(.secondary)
                TextField("6, 21", text: $days).textFieldStyle(.roundedBorder)
            }
            DatePicker("Start at", selection: $time, displayedComponents: .hourAndMinute)
            Text("The Mac must be awake and plugged in at that time. A missed run starts the next time it's awake that day.")
                .font(.caption).foregroundStyle(.secondary)
            if enabled && validDays.isEmpty {
                Text("Enter at least one day between 1 and 31.").font(.caption).foregroundStyle(.red)
            }
            HStack {
                Button("Cancel") { dismiss() }.buttonStyle(.glass)
                Spacer()
                Button("Save") {
                    let c = Calendar.current.dateComponents([.hour, .minute], from: time)
                    let d = validDays.map(String.init).joined(separator: ",")
                    model.cmd(enabled ? "schedule on \(d) \(c.hour ?? 21) \(c.minute ?? 30)" : "schedule off")
                    dismiss()
                }
                .buttonStyle(.glassProminent)
                // Text like "abc" used to be sent anyway; the helper rejected it and the sheet closed as if it had saved.
                .disabled(enabled && validDays.isEmpty)
            }
        }
        .padding(28).frame(width: 440).presentationBackground(.ultraThinMaterial)
        .onAppear {
            if let sc = model.status?.state.schedule {
                enabled = sc.enabled
                days = sc.days.map(String.init).joined(separator: ", ")
                time = Calendar.current.date(from: DateComponents(hour: sc.hour, minute: sc.minute)) ?? time
            }
        }
    }
}

struct ZoneEditor: View {
    @ObservedObject var model: Model
    let zoneID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var pickingPlace = false

    private var index: Int? { model.config.zones.firstIndex { $0.id == zoneID } }

    var body: some View {
        if let i = index {
            // Looked up by id on every access: after "Delete zone" a stale index would point past the end of the array.
            let fallback = model.config.zones[i]
            let z = Binding(get: { model.config.zones.first { $0.id == zoneID } ?? fallback },
                            set: { v in if let j = model.config.zones.firstIndex(where: { $0.id == zoneID }) { model.config.zones[j] = v } })
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        TextField("Zone name", text: z.name)
                            .textFieldStyle(.plain).font(.system(size: 34, weight: .bold, design: .rounded))
                        Spacer()
                        Button("Done") { dismiss() }.buttonStyle(.glassProminent)
                    }
                    if model.config.zones.contains(where: { $0.id != zoneID && $0.name.lowercased() == z.wrappedValue.name.lowercased() })
                        || Zone.reserved.contains(z.wrappedValue.name.lowercased().trimmingCharacters(in: .whitespaces)) {
                        // Zones are pinned by name, so a twin can never be pinned on its own and both light up as active.
                        Label("This name is taken. A number is added when you close this, unless you pick another.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        GlassEffectContainer(spacing: 8) {
                            HStack(spacing: 8) {
                                ForEach(Theme.iconChoices, id: \.self) { name in
                                    Button { z.wrappedValue.icon = name } label: {
                                        Image(systemName: name).font(.title3).frame(width: 28, height: 28)
                                    }
                                    .buttonStyle(.glass).buttonBorderShape(.circle).help("Use the \(name) icon")
                                    .tint(Theme.icon(z.wrappedValue) == name ? Theme.accent(z.wrappedValue.name) : nil)
                                }
                            }.padding(4)
                        }
                    }
                    limit("Stop charging at", value: z.upper, range: 20...100)
                        .onChange(of: z.wrappedValue.upper) { _, u in if z.wrappedValue.lower >= u { z.wrappedValue.lower = max(5, u - 5) } }
                    if model.sailing {
                        limit("Resume at (sailing floor)", value: z.lower, range: 5...99)
                            .onChange(of: z.wrappedValue.lower) { _, l in if z.wrappedValue.upper <= l { z.wrappedValue.upper = l + 5 } }
                        Text("Between the two numbers the battery sails: no charging, no extra wear.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    wifiSection(z)
                    locationSection(z)
                    Button("Delete zone", role: .destructive) {
                        model.config.zones.removeAll { $0.id == zoneID }; dismiss()
                    }.buttonStyle(.glass)
                }
                .padding(30)
            }
            .frame(width: 540, height: 680)
            .presentationBackground(.ultraThinMaterial)
            // Zones are pinned by name: an empty, duplicate or reserved name ("Default", "Top Up") is fixed when the editor closes.
            .onDisappear { model.fixZoneName(zoneID) }
        }
    }

    private func wifiSection(_ z: Binding<Zone>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Wi-Fi networks", systemImage: "wifi").font(.system(.headline, design: .rounded))
            ForEach(z.wrappedValue.networks, id: \.self) { n in
                HStack {
                    Text(n).lineLimit(1)
                    Spacer()
                    Button { z.wrappedValue.networks.removeAll { $0 == n } } label: { Image(systemName: "xmark") }
                        .buttonStyle(.glass).buttonBorderShape(.circle).controlSize(.small).help("Remove this network from the zone")
                }
            }
            if z.wrappedValue.networks.isEmpty { Text("None yet").foregroundStyle(.secondary) }
            Button("Add current network") { model.addCurrentNetwork(to: zoneID) }.buttonStyle(.glass)
        }
    }

    private func locationSection(_ z: Binding<Zone>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Saved place", systemImage: "location.fill").font(.system(.headline, design: .rounded))
            if let p = z.wrappedValue.place {
                Text(model.inside.contains(zoneID) ? "You're inside this area now." : "Saved. You're outside this area.")
                    .foregroundStyle(.secondary)
                HStack {
                    Text("Radius \(Int(p.radius)) m").monospacedDigit()
                    Slider(value: Binding(get: { z.wrappedValue.place?.radius ?? 150 }, set: { z.wrappedValue.place?.radius = $0 }),
                           in: 100...Place.maxRadius, step: 100)
                }
                HStack {
                    Button("Update to here") { model.captureLocation(for: zoneID) }.buttonStyle(.glass)
                    Button("Choose on map…") { pickingPlace = true }.buttonStyle(.glass)
                    Button("Remove") { z.wrappedValue.place = nil }.buttonStyle(.glass)
                }
            } else {
                HStack {
                    Button("Use my current location") { model.captureLocation(for: zoneID) }.buttonStyle(.glass)
                    Button("Choose on map…") { pickingPlace = true }.buttonStyle(.glass)
                }
            }
            if let m = model.captureMessage { Text(m).font(.caption).foregroundStyle(.secondary) }
            Text("Used when no saved Wi-Fi matches. Macs have no GPS chip, so this uses Wi-Fi positioning, good to about 100 m. macOS watches the area itself, so it costs almost no battery.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .sheet(isPresented: $pickingPlace) {
            PlacePicker(initial: z.wrappedValue.place) { z.wrappedValue.place = $0; model.captureMessage = nil }
        }
    }

    private func limit(_ title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.system(.subheadline, design: .rounded)).foregroundStyle(.secondary)
                Spacer()
                Text("\(value.wrappedValue)%").font(.system(size: 36, weight: .thin, design: .rounded)).monospacedDigit()
            }
            Slider(value: Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = Int($0) }),
                   in: Double(range.lowerBound)...Double(range.upperBound), step: 5)
        }
    }
}
