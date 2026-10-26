import AppKit
import BalDenteCore
import CoreWLAN
import SwiftUI

enum SystemPane {
    static func open(_ id: String) {
        if let u = URL(string: "x-apple.systempreferences:\(id)") { NSWorkspace.shared.open(u) }
    }
    static let battery = "com.apple.Battery-Settings.extension"
    static let wifi = "com.apple.wifi-settings-extension"
    static let network = "com.apple.Network-Settings.extension"
    static let bluetooth = "com.apple.BluetoothSettings"
    static let sound = "com.apple.Sound-Settings.extension"
    static let keyboard = "com.apple.Keyboard-Settings.extension"
    static let location = "com.apple.preference.security?Privacy_LocationServices"
    static let loginItems = "com.apple.LoginItems-Settings.extension"
    static let menuBar = "com.apple.ControlCenter-Settings.extension"
}

/// The popover under the menu bar icon: BalDente's charging controls, then the Status Trio sections in the user's order.
struct StatusPanel: View {
    @ObservedObject var model: Model
    @ObservedObject var system: SystemMonitor

    var body: some View {
        let maxHeight = (NSScreen.main?.visibleFrame.height ?? 800) - 40
        ScrollView {
            VStack(spacing: 10) {
                ChargingHeader(model: model)
                ForEach(model.trio.visibleSections) { section in
                    switch section {
                    case .battery: BatterySection(model: model, system: system)
                    case .network: NetworkSection(model: model, system: system)
                    case .bluetooth: BluetoothSection(model: model, system: system)
                    case .volume: VolumeSection(model: model, system: system)
                    case .microphone: MicrophoneSection(system: system)
                    case .inputSource: InputSourceSection(system: system)
                    case .vpn: VPNSection(system: system)
                    }
                }
                footer
            }
            .padding(14)
        }
        .scrollIndicators(.never)
        .frame(width: 340)
        .frame(maxHeight: maxHeight)
        .fixedSize(horizontal: false, vertical: true)
        .task(id: model.panelOpen) {
            // Bluetooth batteries have no change notification; refresh them every half minute while the panel is open.
            while model.panelOpen, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                if model.panelOpen { system.refreshBluetooth() }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button { model.statusController?.openSettings() } label: { Label("Settings", systemImage: "gearshape") }
            Button { model.statusController?.openDashboard() } label: { Label("Dashboard", systemImage: "rectangle.grid.2x2") }
            Spacer()
            Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }.help("Quit BalDente")
        }
        .buttonStyle(.borderless).labelStyle(.titleAndIcon).font(.callout).foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }
}

/// BalDente's own part of the panel: charge ring, active zone, zone pins and Top Up.
struct ChargingHeader: View {
    @ObservedObject var model: Model

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                BatteryRing(percent: model.status?.percent ?? model.system.power.percent, lower: model.target.lower, upper: model.target.upper,
                            caption: model.ringCaption, tint: model.accent, size: 96)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.target.label).font(.system(size: 20, weight: .bold, design: .rounded))
                    Text(model.status == nil ? "Helper not running" : "Stop \(model.target.upper)% · resume \(model.target.lower)%")
                        .font(.callout).foregroundStyle(.secondary)
                    Text(model.headline).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 6) {
                ForEach(model.config.zones) { z in
                    Button { model.config.overrideZone = model.config.overrideZone == z.name ? nil : z.name } label: {
                        Image(systemName: Theme.icon(z)).frame(width: 26, height: 22)
                    }
                    .buttonStyle(.glass).help(z.name)
                    .tint(model.target.zoneID == z.id ? Theme.accent(z.name) : nil)
                }
                Spacer()
                Button { model.toggleTopUp() } label: {
                    Label(model.topUp ? "Cancel" : "Top Up", systemImage: "bolt.fill")
                }.buttonStyle(.glassProminent).tint(model.accent)
            }
            if let hint = model.holdHintText {
                HStack(alignment: .top, spacing: 6) {
                    Text(hint).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button { model.holdHint.dismissed = true } label: { Image(systemName: "xmark").font(.caption2) }
                        .buttonStyle(.borderless).foregroundStyle(.tertiary).help("Don't show this again")
                }
                if !model.calendar.enabled {
                    Button("Set Ready by…") { model.statusController?.openReadyBy() }.buttonStyle(.link).font(.caption)
                }
            }
        }
        .panelCard()
    }
}

// MARK: Shared pieces

extension View {
    func panelCard() -> some View {
        padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 14))
    }
}

struct SectionHeader<Trailing: View>: View {
    let icon: String
    let title: String
    var subtitle: String?
    var tint: Color = .accentColor
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 28, height: 28).background(tint.gradient, in: .circle)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(.body, design: .rounded).weight(.semibold))
                if let s = subtitle { Text(s).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 4)
            trailing
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(icon: String, title: String, subtitle: String? = nil, tint: Color = .accentColor) {
        self.init(icon: icon, title: title, subtitle: subtitle, tint: tint) { EmptyView() }
    }
}

struct DetailRows: View {
    let rows: [(String, String)]
    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            ForEach(rows.indices, id: \.self) { i in
                GridRow {
                    Text(rows[i].0).foregroundStyle(.secondary)
                    Text(rows[i].1).monospacedDigit().textSelection(.enabled).frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .font(.caption)
    }
}

struct MoreButton: View {
    @Binding var expanded: Bool
    var more = "Show Details", less = "Hide Details"
    var body: some View {
        Button(expanded ? less : more) { withAnimation(.snappy) { expanded.toggle() } }
            .buttonStyle(.borderless).font(.caption)
    }
}

private func minutes(_ m: Int) -> String {
    m >= 60 ? (m % 60 == 0 ? "\(m / 60) h" : "\(m / 60) h \(m % 60) min") : "\(m) min"
}

// MARK: Battery

struct BatterySection: View {
    @ObservedObject var model: Model
    @ObservedObject var system: SystemMonitor
    @State private var details = false

    private var stateLine: String {
        let p = system.power
        guard p.present else { return "No battery" }
        if p.charging { return p.minutesToFull.map { "Charging · about \(minutes($0)) to full" } ?? "Charging · calculating time to full" }
        if p.plugged { return p.charged ? "Fully charged" : model.holding ? "Connected · held by BalDente" : "Connected to power" }
        let left = p.minutesToEmpty.map { " · \(minutes($0)) left" } ?? ""
        return (p.lowPower ? "Low Power Mode" : "On battery") + left
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(icon: system.power.charging ? "battery.100percent.bolt" : "battery.75percent",
                          title: "Battery · \(system.power.percent)%", subtitle: stateLine,
                          tint: system.power.plugged ? .green : system.power.lowPower ? .yellow : system.power.percent < model.trio.lowThreshold ? .red : .gray) {
                MoreButton(expanded: $details, more: "Details", less: "Less")
            }
            if details {
                let i = model.info
                DetailRows(rows: [
                    ("Health", i?.healthPercent.map { "\($0)%" } ?? "–"),
                    ("Cycle count", i.map { "\($0.cycles)" } ?? "–"),
                    ("Temperature", (model.status?.tempC ?? i?.tempC).map { String(format: "%.1f °C", $0) } ?? "–"),
                    ("Battery voltage", i.map { String(format: "%.2f V", $0.volts) } ?? "–"),
                    (system.power.plugged ? "Charging (estimate)" : "Battery discharge (estimate)", i.map { String(format: "%.1f W", abs($0.watts)) } ?? "–"),
                    ("Adapter rating", system.power.adapterWatts.map { "\($0) W" } ?? "–"),
                ])
                Toggle("Low Power Mode", isOn: Binding(get: { system.power.lowPower }, set: { model.setLowPowerMode($0) }))
                    .toggleStyle(.switch).controlSize(.small).font(.callout)
                    .disabled(model.status == nil)
                    .help(model.status == nil ? "Install BalDente's helper to switch Low Power Mode from here." : "Reduces energy use to extend battery life.")
                Button("Open Battery Settings") { SystemPane.open(SystemPane.battery) }.buttonStyle(.borderless).font(.caption)
            }
        }
        .panelCard()
    }
}

// MARK: Network

struct NetworkSection: View {
    @ObservedObject var model: Model
    @ObservedObject var system: SystemMonitor
    @State private var details = false

    private var n: NetSnap { system.net }

    private var title: String {
        switch n.kind {
        case .ethernet: "Ethernet"
        case .hotspot: n.ssid ?? "Personal Hotspot"
        case .wifi, .noInternet: n.ssid ?? "Wi-Fi"
        default: "Wi-Fi"
        }
    }

    private var subtitle: String {
        switch n.kind {
        case .wifi:
            let band = n.band.map { "\($0) GHz · " } ?? ""
            return band + "\(n.rssi) dBm" + (model.trio.showLocalIP ? n.localIP.map { " · \($0)" } ?? "" : "")
        case .ethernet: return "Connected" + (model.trio.showLocalIP ? n.localIP.map { " · \($0)" } ?? "" : "")
        case .hotspot: return "Using an iPhone hotspot"
        case .noInternet: return "Network reachability check failed"
        case .notAssociated: return "Wi-Fi is on but not associated"
        case .wifiOff: return "Wi-Fi is off"
        case .offline: return "Not connected"
        }
    }

    private var wifiOn: Bool { n.kind != .wifiOff }

    /// Associated with Wi-Fi but macOS hides the name: Location permission is missing.
    private var needsLocation: Bool {
        guard n.ssid == nil else { return false }
        if case .wifi = n.kind { return true }
        return n.kind == .noInternet
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(icon: n.kind == .ethernet ? "network" : n.kind == .wifiOff ? "wifi.slash" : n.kind == .noInternet ? "wifi.exclamationmark" : "wifi",
                          title: title, subtitle: subtitle, tint: n.isProblem ? .orange : .blue) {
                if n.kind != .ethernet {
                    Toggle("", isOn: Binding(get: { wifiOn }, set: { on in
                        try? CWWiFiClientShared.setPower(on); Task { try? await Task.sleep(for: .seconds(1)); system.refreshNetwork() }
                    })).toggleStyle(.switch).labelsHidden().controlSize(.mini).help(wifiOn ? "Turn Wi-Fi off" : "Turn Wi-Fi on")
                }
            }
            if needsLocation {
                Button("Allow location to show Wi-Fi name") { model.requestLocation() }.buttonStyle(.borderless).font(.caption)
            }
            MoreButton(expanded: $details, more: "More Details", less: "Less Details")
            if details {
                DetailRows(rows: detailRows)
                Button(n.kind == .ethernet ? "Open Network Settings" : "Open Wi-Fi Settings") {
                    SystemPane.open(n.kind == .ethernet ? SystemPane.network : SystemPane.wifi)
                }
                .buttonStyle(.borderless).font(.caption)
            }
        }
        .panelCard()
    }

    private var detailRows: [(String, String)] {
        var rows: [(String, String)] = []
        if let s = n.ssid { rows.append(("SSID", s)) }
        if let b = n.bssid { rows.append(("BSSID", b)) }
        if let c = n.channel { rows.append(("Channel", "\(c)" + (n.band.map { " (\($0) GHz)" } ?? ""))) }
        if n.rssi != 0 {
            rows.append(("RSSI", "\(n.rssi) dBm")); rows.append(("Noise", "\(n.noise) dBm"))
            rows.append(("Signal-to-noise", "\(n.rssi - n.noise) dB"))
        }
        if let t = n.txRate { rows.append(("Link Tx Rate", "\(Int(t)) Mbps")) }
        if let s = n.security { rows.append(("Security", s)) }
        if let i = n.interface { rows.append(("Interface", i)) }
        if let ip = n.localIP { rows.append(("IPv4", ip)) }
        if let r = n.router { rows.append(("Router", r)) }
        return rows
    }
}

enum CWWiFiClientShared {
    static func setPower(_ on: Bool) throws { try CWWiFiClient.shared().interface()?.setPower(on) }
}

// MARK: Bluetooth

struct BluetoothSection: View {
    @ObservedObject var model: Model
    @ObservedObject var system: SystemMonitor
    @State private var expanded = false
    @State private var busy: Set<String> = []

    var body: some View {
        let bt = system.bluetooth
        let devices = bt.devices.sorted { $0.connected && !$1.connected }
        let limit = max(1, model.trio.bluetoothVisible)
        let shown = expanded ? devices : Array(devices.prefix(limit))
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(icon: "dot.radiowaves.left.and.right", title: "Bluetooth",
                          subtitle: !bt.loaded ? "Reading devices…" : bt.powered == false ? "Bluetooth is off" :
                            "\(devices.filter(\.connected).count) connected", tint: bt.powered == false ? .gray : .blue) {
                if model.trio.bluetoothPowerButton, BluetoothPower.available, let on = bt.powered {
                    Toggle("", isOn: Binding(get: { on }, set: { system.setBluetoothPower($0) }))
                        .toggleStyle(.switch).labelsHidden().controlSize(.mini).help(on ? "Turn Bluetooth off" : "Turn Bluetooth on")
                }
            }
            if bt.powered != false {
                ForEach(shown) { d in row(d) }
                if devices.count > limit {
                    Button(expanded ? "Collapse" : "Show all \(devices.count)") { withAnimation(.snappy) { expanded.toggle() } }
                        .buttonStyle(.borderless).font(.caption)
                }
                if bt.loaded && devices.isEmpty { Text("No paired devices found.").font(.caption).foregroundStyle(.secondary) }
            }
            Button("Open Bluetooth Settings") { SystemPane.open(SystemPane.bluetooth) }.buttonStyle(.borderless).font(.caption)
        }
        .panelCard()
    }

    private func row(_ d: BTDevice) -> some View {
        HStack(spacing: 8) {
            Image(systemName: d.symbol).frame(width: 22).foregroundStyle(d.connected ? Color.blue : .secondary)
            VStack(alignment: .leading, spacing: 0) {
                Text(d.name).lineLimit(1)
                if model.trio.bluetoothBattery, d.connected, let b = batteryText(d) {
                    Text(b).font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            Spacer()
            if busy.contains(d.id) { ProgressView().controlSize(.small) }
            else {
                Button(d.connected ? "Disconnect" : "Connect") {
                    busy.insert(d.id); system.setConnected(d, !d.connected)
                    Task { try? await Task.sleep(for: .seconds(4)); busy.remove(d.id) }
                }
                .buttonStyle(.borderless).font(.caption)
            }
        }
        .font(.callout)
    }

    private func batteryText(_ d: BTDevice) -> String? {
        var parts: [String] = []
        if let l = d.left { parts.append("L \(l)%") }
        if let r = d.right { parts.append("R \(r)%") }
        if let c = d.caseLevel { parts.append("Case \(c)%") }
        if parts.isEmpty, let b = d.battery { parts.append("\(b)%") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

// MARK: Volume

struct VolumeSection: View {
    @ObservedObject var model: Model
    @ObservedObject var system: SystemMonitor
    @State private var expanded = false

    var body: some View {
        let a = system.audio
        let limit = max(1, model.trio.outputsVisible)
        let shown = expanded ? a.outputs : Array(a.outputs.prefix(limit))
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(icon: a.muted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                          title: a.volume.map { "Volume · \(Int(($0 * 100).rounded()))%" } ?? "Volume · —",
                          subtitle: a.output?.name, tint: a.output?.bluetooth == true ? .blue : .pink) {
                Button { system.toggleMute() } label: { Image(systemName: a.muted ? "speaker.slash" : "speaker") }
                    .buttonStyle(.borderless).help(a.muted ? "Unmute" : "Mute")
            }
            if let v = a.volume {
                Slider(value: Binding(get: { a.muted ? 0 : v }, set: { system.setVolume($0) }), in: 0...1)
                    .controlSize(.small)
                    .background(ScrollCatcher(enabled: model.trio.scrollAdjustsVolume, natural: model.trio.naturalScroll) { d in
                        system.setVolume((system.audio.volume ?? 0) + d)
                    })
            }
            ForEach(shown) { d in
                Button { system.selectDevice(d.id) } label: {
                    HStack {
                        Image(systemName: d.bluetooth ? "headphones" : "speaker.wave.2").frame(width: 20)
                        Text(d.name).lineLimit(1)
                        Spacer()
                        if d.id == a.output?.id { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).font(.callout)
                .foregroundStyle(d.id == a.output?.id ? Color.accentColor : .primary)
            }
            if a.outputs.count > limit {
                Button(expanded ? "Collapse" : "Show all \(a.outputs.count)") { withAnimation(.snappy) { expanded.toggle() } }
                    .buttonStyle(.borderless).font(.caption)
            }
            Button("Open Sound Settings") { SystemPane.open(SystemPane.sound) }.buttonStyle(.borderless).font(.caption)
        }
        .panelCard()
    }
}

/// Turns scroll-wheel and trackpad scrolling over a control into small steps.
struct ScrollCatcher: NSViewRepresentable {
    var enabled: Bool
    var natural: Bool
    var onStep: (Double) -> Void

    final class V: NSView {
        var enabled = true, natural = true
        var onStep: (Double) -> Void = { _ in }
        override func scrollWheel(with e: NSEvent) {
            guard enabled else { return super.scrollWheel(with: e) }
            let dy = Double(e.scrollingDeltaY) * (e.hasPreciseScrollingDeltas ? 0.004 : 0.02)
            // "Natural" means the physical gesture decides: fingers or wheel moving up turn it up, whatever the system setting.
            // Otherwise follow the system's scroll direction as delivered.
            let step = natural && e.isDirectionInvertedFromDevice ? -dy : dy
            if step != 0 { onStep(step) }
        }
    }

    func makeNSView(context: Context) -> V { V() }
    func updateNSView(_ v: V, context: Context) { v.enabled = enabled; v.natural = natural; v.onStep = onStep }
}

// MARK: Microphone

struct MicrophoneSection: View {
    @ObservedObject var system: SystemMonitor

    var body: some View {
        let a = system.audio
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(icon: a.inputMuted ? "mic.slash.fill" : "mic.fill", title: "Microphone",
                          subtitle: a.input?.name ?? "No default input device", tint: .orange) {
                Button { system.toggleMute(input: true) } label: { Image(systemName: a.inputMuted ? "mic.slash" : "mic") }
                    .buttonStyle(.borderless).help(a.inputMuted ? "Unmute" : "Mute").disabled(a.input == nil)
            }
            if let v = a.inputVolume {
                Slider(value: Binding(get: { v }, set: { system.setVolume($0, input: true) }), in: 0...1) {
                    Text("Input volume")
                }.controlSize(.small).labelsHidden()
            }
            if a.inputs.count > 1 {
                Picker("Input", selection: Binding(get: { a.input?.id ?? 0 }, set: { system.selectDevice($0, input: true) })) {
                    ForEach(a.inputs) { Text($0.name).tag($0.id) }
                }
                .pickerStyle(.menu).controlSize(.small).labelsHidden()
            }
        }
        .panelCard()
    }
}

// MARK: Input source

struct InputSourceSection: View {
    @ObservedObject var system: SystemMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(icon: "keyboard", title: "Input Source", subtitle: system.inputSources.first { $0.selected }?.name, tint: .indigo)
            ForEach(system.inputSources) { s in
                Button { system.selectInputSource(s.id) } label: {
                    HStack {
                        Text(s.short).font(.caption.weight(.bold)).frame(width: 26, height: 18)
                            .background(.quaternary, in: .rect(cornerRadius: 4))
                        Text(s.name).lineLimit(1)
                        Spacer()
                        if s.selected { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).font(.callout)
            }
            if system.inputSources.isEmpty {
                Button("Open Keyboard Settings") { SystemPane.open(SystemPane.keyboard) }.buttonStyle(.borderless).font(.caption)
            }
        }
        .panelCard()
    }
}

// MARK: VPN

struct VPNSection: View {
    @ObservedObject var system: SystemMonitor

    var body: some View {
        let on = !system.net.vpn.isEmpty
        SectionHeader(icon: on ? "lock.shield.fill" : "lock.shield", title: "VPN",
                      subtitle: on ? "Connected · \(system.net.vpn.joined(separator: ", "))" : "Not connected", tint: on ? .green : .gray) {
            Button("Settings") { SystemPane.open(SystemPane.network) }.buttonStyle(.borderless).font(.caption)
        }
        .panelCard()
    }
}
