import BalDenteCore
import SwiftUI

// The pages that used to be sheets, a footer, or a separate Settings window.

// MARK: Zones

struct ZonesPage: View {
    @ObservedObject var model: Model
    @State private var sheet: ActiveSheet?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Label(model.networks.first ?? "No network detected", systemImage: "wifi")
                    .font(.callout).padding(.horizontal, 12).padding(.vertical, 7).glassEffect(.regular, in: .capsule)
                Text(model.config.overrideZone.map { "Pinned to \($0)" } ?? "Automatic")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                if model.config.overrideZone != nil {
                    Button { model.config.overrideZone = nil } label: { pill("Back to Automatic", "wand.and.stars") }.buttonStyle(.glass)
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210, maximum: 230), spacing: 20)], alignment: .leading, spacing: 20) {
                ForEach(model.config.zones) { z in
                    ZoneTile(zone: z, active: model.target.label == z.name,
                             pinned: model.config.overrideZone == z.name,
                             onSelect: { model.config.overrideZone = model.config.overrideZone == z.name ? nil : z.name },
                             onEdit: { sheet = .zone(z.id) })
                }
                AddTile { sheet = .zone(model.addZone().id) }
                DefaultTile(upper: model.config.defaultUpper, lower: model.config.defaultLower,
                            active: model.target.label == "Default") { sheet = .defaults }
                    .settingAnchor("Everywhere else")
            }
            .padding(.vertical, 8)
            .settingAnchor("Zones")
            Text("Tap a zone to pin it, or the sliders button to edit its limits, Wi-Fi networks and saved place. A zone whose Wi-Fi matches wins over one whose map circle you're inside; everywhere else uses the default limits.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .sheets(model, $sheet)
    }
}

// MARK: Appearance

struct AppearancePage: View {
    @ObservedObject var model: Model

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsGroup("Background") { BackgroundControls(model: model) }
            SettingsGroup("Window") {
                SettingRow("sparkles", .purple, "Animate the background",
                           "Pauses by itself when the app is in the background. Turn it off to save a little more energy.") {
                    Toggle("", isOn: Binding(get: { model.appearance.animated }, set: { model.appearance.animated = $0 }))
                        .labelsHidden().toggleStyle(.switch)
                }
                SettingRow("rectangle.compress.vertical", .indigo, "Compact mode",
                           "A dense, standard Mac layout in a smaller window. Every page stays one click away in regular mode.") {
                    Toggle("", isOn: Binding(get: { model.appearance.compact }, set: { model.appearance.compact = $0 }))
                        .labelsHidden().toggleStyle(.switch)
                }
            }
        }
    }
}

// MARK: General

struct GeneralPage: View {
    @ObservedObject var model: Model

    private var helperState: (text: String, color: Color) {
        if model.status != nil { return model.helperOutdated ? ("Update available", .orange) : ("Running", .green) }
        return model.helperInstalled ? ("Not responding", .red) : ("Not installed", .secondary)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsGroup("Startup") {
                SettingRow("power", .green, "Launch at login", "Start BalDente automatically when you log in.") {
                    Toggle("", isOn: Binding(get: { model.launchAtLogin }, set: { model.launchAtLogin = $0 })).labelsHidden().toggleStyle(.switch)
                }
                SettingRow("timer", .blue, "Status refresh interval",
                           "How often signal strength and other unannounced changes are checked. Faster uses more energy.") {
                    ValueSlider(value: Binding(get: { Double(model.trio.refreshSeconds) }, set: { model.trio.refreshSeconds = Int($0) }),
                                range: 2...30, step: 1) { "\(Int($0)) s" }
                }
            }
            SettingsGroup("Charging helper") {
                SettingRow("lock.shield.fill", .orange, "Background helper",
                           "A small root helper switches the charger. It starts at every boot and asks for your password once to install.") {
                    HStack(spacing: 8) {
                        Text(helperState.text).font(.callout.weight(.semibold)).foregroundStyle(helperState.color)
                        Button(model.status != nil ? (model.helperOutdated ? "Update" : "Reinstall") : "Install") { model.setUp() }
                            .buttonStyle(.glass).disabled(model.busy)
                        if model.helperInstalled { Button("Remove") { model.removeHelper() }.buttonStyle(.glass).disabled(model.busy) }
                    }
                }
                if let e = model.setupError { Text(e).font(.caption).foregroundStyle(.red).padding(.leading, 48) }
                Text("Details and errors are logged to /var/log/baldente.log.").font(.caption).foregroundStyle(.secondary).padding(.leading, 48)
            }
            SettingsGroup("Permissions") {
                SettingRow("location.fill", .blue, "Location access",
                           model.locationAllowed
                           ? "Allowed. BalDente can read Wi-Fi names and watch your saved places. Current network: \(model.networks.first ?? "none")."
                           : "macOS hides Wi-Fi names and blocks saved places without Location access. The router address is used meanwhile.") {
                    if model.locationAllowed { Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.callout) }
                    else { Button("Allow…") { model.requestLocation() }.buttonStyle(.glass) }
                }
            }
            SettingsGroup("Notifications") {
                SettingRow("bell.badge.fill", .red, "Smart notifications",
                           "Tells you if battery health drops 2 points in a month or the helper stops answering. Checked during refreshes that already run.") {
                    Toggle("", isOn: Binding(get: { model.trio.smartNotifications }, set: { model.trio.smartNotifications = $0 })).labelsHidden().toggleStyle(.switch)
                }
            }
            SettingsGroup("Backup") {
                SettingRow("square.and.arrow.up", .blue, "Export or import settings", "Save your zones and limits to a file, or load them on another Mac.") {
                    HStack { Button("Export…") { model.exportConfig() }.buttonStyle(.glass); Button("Import…") { model.importConfig() }.buttonStyle(.glass) }
                }
            }
            SettingsGroup("Reset") {
                SettingRow("arrow.counterclockwise", .gray, "Reset icon and panel settings", "Charging limits and zones are not affected.") {
                    Button("Reset") { model.trio = TrioPrefs() }.buttonStyle(.glass)
                }
            }
        }
    }
}

// MARK: About

struct AboutPage: View {
    var body: some View {
        SettingsGroup("About BalDente") {
            Text("BalDente \(appVersionText)").font(.headline)
            Text("A free battery charge limiter for macOS with zones, Ready by, heat protection and calibration, plus a combined menu bar icon for battery, network and volume.")
                .fixedSize(horizontal: false, vertical: true)
            Text("The combined icon's design, settings and charging animation follow Status Trio by lingyired (Apache-2.0), github.com/lingyired/status-trio. BalDente draws it with its own code.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
