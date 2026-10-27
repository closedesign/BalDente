import AppKit
import BalDenteCore
import Carbon
import SwiftUI

/// The menu bar icon and status panel pages of the main window: a live preview on top, then grouped rows.
struct TrioPageView: View {
    @ObservedObject var model: Model
    @ObservedObject var system: SystemMonitor
    let page: SettingsPage
    @State private var previewDark = true

    private var p: Binding<TrioPrefs> { $model.trio }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            IconPreviewCard(model: model, system: system, dark: $previewDark).tourAnchor("Menu bar preview")
            Text("Live preview. Changes below show up here and in your menu bar immediately.").font(.callout).foregroundStyle(.secondary)
            MasonryLayout { content }
        }
    }

    @ViewBuilder private var content: some View {
        switch page {
        case .icon: appIconPage
        case .battery: batteryPage
        case .network: networkPage
        case .bluetooth: bluetoothPage
        case .audio: audioPage
        case .panel: panelPage
        default: EmptyView()
        }
    }

    // MARK: Pages

    @ViewBuilder private var appIconPage: some View {
        SettingsGroup("Status Icon") {
            SettingRow("macwindow", .indigo, "Show BalDente in", "Choose where the live status icon stays available.") {
                Picker("", selection: p.placement) {
                    Text("Menu Bar").tag(TrioPrefs.Placement.menuBar)
                    Text("Dock").tag(TrioPrefs.Placement.dock)
                    Text("Both").tag(TrioPrefs.Placement.both)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 230)
            }
            if model.trio.placement == .menuBar {
                Text("The Dock icon disappears after you close BalDente's windows.").font(.caption).foregroundStyle(.secondary)
            }
            SettingRow("arrow.up.left.and.arrow.down.right", .blue, "Icon size", "Menu bar render size, 16–36 pt. The Dock icon keeps its size.") {
                ValueSlider(value: p.iconSize, range: 16...36, step: 1) { "\(Int($0)) pt" }
            }
            SettingRow("circle.circle", .purple, "Ring stroke width", "Line thickness of the ring in the menu bar and Dock icons.") {
                Picker("", selection: p.stroke) {
                    Text("Light").tag(TrioPrefs.Stroke.light)
                    Text("Regular").tag(TrioPrefs.Stroke.regular)
                    Text("Bold").tag(TrioPrefs.Stroke.bold)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 230)
            }
        }
        SettingsGroup("Dock Icon") {
            SettingRow("dock.rectangle", .gray, "Dock icon background", "Applies to the live icon shown in the Dock. Follow System uses the system appearance.") {
                Picker("", selection: p.dockBackground) {
                    Text("Follow System").tag(TrioPrefs.DockBackground.system)
                    Text("Light").tag(TrioPrefs.DockBackground.light)
                    Text("Dark").tag(TrioPrefs.DockBackground.dark)
                }.labelsHidden().frame(width: 150)
            }
        }
        SettingsGroup("State combinations") {
            Text("A quick look at common battery, network and volume combinations.").font(.callout).foregroundStyle(.secondary)
            StateGallery(prefs: model.trio, dark: previewDark)
        }
        SettingsGroup("Can't find the menu bar icon?") {
            Text("When the menu bar is crowded, the notch can hide icons. Hold ⌘ and drag the icon to the right, or hide system items you don't need, like Wi-Fi, Battery or Sound, since BalDente shows them.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button("Open Menu Bar Settings") { SystemPane.open(SystemPane.menuBar) }
        }
    }

    @ViewBuilder private var batteryPage: some View {
        SettingsGroup("Battery Display") {
            SettingRow("percent", .green, "Show battery percentage", nil) { Toggle("", isOn: p.showPercentage).labelsHidden().toggleStyle(.switch) }
            SettingRow("bolt.fill", .green, "Show a bolt while charging",
                       "When enabled, the percentage becomes a bolt while charging. When plugged in but holding, the percentage shows.") {
                Toggle("", isOn: p.showChargingIndicator).labelsHidden().toggleStyle(.switch)
            }
            SettingRow("wifi", .blue, "Show battery percentage in the connection position",
                       "Replaces the Wi-Fi or connection symbol. Independent of the top battery indicator.") {
                Toggle("", isOn: p.percentInMiddle).labelsHidden().toggleStyle(.switch)
            }
        }
        SettingsGroup("Charging Effect") {
            SettingRow("sparkles", .yellow, "Menu bar charging effect",
                       "Animate the charging highlight in the menu bar. Stops when Reduce Motion is on.") {
                Toggle("", isOn: p.menuBarChargingEffect).labelsHidden().toggleStyle(.switch)
            }
            SettingRow("dock.arrow.up.rectangle", .yellow, "Dock charging effect",
                       "Animate the charging highlight in the Dock icon. Both stop when Reduce Motion is on.") {
                Toggle("", isOn: p.dockChargingEffect).labelsHidden().toggleStyle(.switch)
            }
            SettingRow("heart.fill", .red, "Charging bolt pulse",
                       "Turn off to keep the bolt at its usual size and color; the charging arc effect continues.") {
                Toggle("", isOn: p.boltPulse).labelsHidden().toggleStyle(.switch)
            }
            SettingRow("play.circle.fill", .orange, "Test charging animation", "Plays the animation without a charger. Turns off when BalDente quits.") {
                Toggle("", isOn: $system.testCharging).labelsHidden().toggleStyle(.switch)
            }
            if system.reduceMotion {
                Text("Reduce Motion is on in Accessibility settings, so the effect stays still.").font(.caption).foregroundStyle(.orange)
            }
            SettingRow("waveform.path", .teal, "Wave speed",
                       "How fast the charging animation runs: the glow, the heartbeat and the wave. 1× is the default; lower is slower.") {
                ValueSlider(value: p.chargeWaveSpeed, range: 0.2...6, step: 0.1) { String(format: "%.1f×", $0) }
            }
        }
        SettingsGroup("Text Beside the Icon") {
            SettingRow("percent", .green, "Show percentage next to the icon while charging",
                       "Adds the battery level as text beside the icon while the ring shows the bolt.") {
                Toggle("", isOn: p.showPercentWhileCharging).labelsHidden().toggleStyle(.switch)
            }
            SettingRow("clock", .mint, "Show time remaining", "Minutes to full or to empty as text next to the menu bar icon.") {
                Toggle("", isOn: p.showTimeRemaining).labelsHidden().toggleStyle(.switch)
            }
            SettingRow("textformat.size", .blue, "Percentage/bolt size", "The percentage and bolt share this size.") {
                ValueSlider(value: p.symbolScale, range: 0.8...1.4, step: 0.05) { "\(Int(($0 * 100).rounded()))%" }
            }
        }
        SettingsGroup("Ring Colors") {
            SettingRow("paintpalette.fill", .orange, "Color the arc by battery state",
                       "Low battery is red, Low Power Mode is yellow, and charging or connected power is green.") {
                Toggle("", isOn: p.statusColors).labelsHidden().toggleStyle(.switch)
            }
            SettingRow("exclamationmark.triangle.fill", .red, "Low battery threshold",
                       "Battery levels below this threshold are treated as low and shown in red.") {
                ValueSlider(value: Binding(get: { Double(model.trio.lowThreshold) }, set: { model.trio.lowThreshold = Int($0) }),
                            range: 5...50, step: 1) { "\(Int($0))%" }
            }
            SettingRow("circle.dotted.circle", .green, "Full ring level",
                       "The ring counts as full at this level. Useful because BalDente holds the battery below 100%.") {
                if model.trio.fullFollowsLimit {
                    HStack {
                        Text("Charge limit · \(model.target.upper)%").monospacedDigit().foregroundStyle(.secondary)
                        Button("Use a fixed level") { model.trio.fullFollowsLimit = false }.buttonStyle(.link)
                    }
                } else {
                    ValueSlider(value: Binding(get: { Double(model.trio.fullLevel) }, set: { model.trio.fullLevel = Int($0) }),
                                range: 50...100, step: 1) { "\(Int($0))%" }
                }
            }
            if !model.trio.fullFollowsLimit {
                Button("Use the charge limit (\(model.target.upper)% in \(model.target.label))") { model.trio.fullFollowsLimit = true }
                    .buttonStyle(.link).padding(.leading, 48)
            }
        }
    }

    @ViewBuilder private var networkPage: some View {
        SettingsGroup("Status Icon") {
            SettingRow("circle.grid.2x1.fill", .blue, "Middle slot", "Choose what the icon's middle slot shows. Automatic keeps the usual network and Bluetooth behavior.") {
                Picker("", selection: p.middleSlot) {
                    Text("Automatic").tag(TrioPrefs.MiddleSlot.automatic)
                    Text("Current Input Source").tag(TrioPrefs.MiddleSlot.inputSource)
                }.labelsHidden().frame(width: 180)
            }
            if model.trio.middleSlot == .inputSource {
                SettingRow("exclamationmark.icloud", .orange, "Show network problems instead",
                           "When the Mac is offline, the middle slot shows the network state instead of the input source.") {
                    Toggle("", isOn: p.networkProblemsOverInput).labelsHidden().toggleStyle(.switch)
                }
            }
            SettingRow("arrow.up.left.and.arrow.down.right", .blue, "Wi-Fi icon size", "Scales the network icon inside the ring from 100% to 180%.") {
                ValueSlider(value: p.wifiScale, range: 1...1.8, step: 0.05) { "\(Int(($0 * 100).rounded()))%" }
            }
        }
        SettingsGroup("Connection Icon Style") {
            Text("When on, that connection uses the standard Wi-Fi signal icon instead of its own mark.").font(.callout).foregroundStyle(.secondary)
            SettingRow("cable.connector", .gray, "Use Wi-Fi icon for Ethernet", nil) { Toggle("", isOn: p.wifiIconForEthernet).labelsHidden().toggleStyle(.switch) }
            SettingRow("personalhotspot", .green, "Use Wi-Fi icon for Personal Hotspot", nil) { Toggle("", isOn: p.wifiIconForHotspot).labelsHidden().toggleStyle(.switch) }
        }
        SettingsGroup("Panel") {
            SettingRow("number.square", .indigo, "Show local IP address", "Shows this Mac's private LAN address on the network row.") {
                Toggle("", isOn: p.showLocalIP).labelsHidden().toggleStyle(.switch)
            }
        }
    }

    @ViewBuilder private var bluetoothPage: some View {
        SettingsGroup("Bluetooth Audio") {
            SettingRow("headphones", .blue, "Replace the network icon with a Bluetooth device icon",
                       "While audio plays through Bluetooth, the Wi-Fi icon becomes the device's icon in blue.") {
                Toggle("", isOn: p.bluetoothReplacesNetwork).labelsHidden().toggleStyle(.switch)
            }
            SettingRow("exclamationmark.triangle", .orange, "Let network errors take priority",
                       "Connection errors and offline states keep the network icon instead of the Bluetooth icon.") {
                Toggle("", isOn: p.networkErrorsFirst).labelsHidden().toggleStyle(.switch)
            }
            SettingRow("airpods", .blue, "Bluetooth audio icon", "Automatic follows the current Bluetooth audio device.") {
                Picker("", selection: p.bluetoothGlyph) {
                    Text("Automatic").tag(TrioPrefs.BluetoothGlyph.automatic)
                    Text("Earbuds").tag(TrioPrefs.BluetoothGlyph.earbuds)
                    Text("Headphones").tag(TrioPrefs.BluetoothGlyph.headphones)
                    Text("Over-Ear Headphones").tag(TrioPrefs.BluetoothGlyph.overEar)
                    Text("Headset").tag(TrioPrefs.BluetoothGlyph.headset)
                    Text("Speaker").tag(TrioPrefs.BluetoothGlyph.speaker)
                }.labelsHidden().frame(width: 180)
            }
            SettingRow("arrow.up.left.and.arrow.down.right", .blue, "Bluetooth icon size", "Scales the Bluetooth icon inside the ring from 100% to 180%.") {
                ValueSlider(value: p.bluetoothScale, range: 1...1.8, step: 0.05) { "\(Int(($0 * 100).rounded()))%" }
            }
            SettingRow("speaker.wave.2.fill", .blue, "Use blue for Bluetooth volume",
                       "The volume dots or arc turn blue while audio plays through Bluetooth.") {
                Toggle("", isOn: p.bluetoothBlueVolume).labelsHidden().toggleStyle(.switch)
            }
        }
        SettingsGroup("Status Panel List") {
            SettingRow("battery.75percent", .green, "Show Bluetooth battery levels", "Shows battery levels for connected devices that report them.") {
                Toggle("", isOn: p.bluetoothBattery).labelsHidden().toggleStyle(.switch)
            }
            SettingRow("power", .gray, "Show Bluetooth power control", "Adds a Bluetooth on/off switch to the status panel.") {
                Toggle("", isOn: p.bluetoothPowerButton).labelsHidden().toggleStyle(.switch).disabled(!BluetoothPower.available)
            }
            SettingRow("list.number", .gray, "Maximum visible Bluetooth devices", "How many devices appear before Show all.") {
                Stepper("\(model.trio.bluetoothVisible)", value: p.bluetoothVisible, in: 1...12).monospacedDigit()
            }
        }
    }

    @ViewBuilder private var audioPage: some View {
        SettingsGroup("Volume Indicator Style") {
            SettingRow("circle.grid.3x3.fill", .teal, "Display style", "Show volume as four dots or a continuous bottom arc.") {
                Picker("", selection: p.volumeStyle) {
                    Text("Dots").tag(TrioPrefs.VolumeStyle.dots)
                    Text("Arc").tag(TrioPrefs.VolumeStyle.arc)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 160)
            }
        }
        SettingsGroup("Display Rules") {
            SettingRow("list.number", .gray, "Maximum visible output devices", "How many output devices appear before Show all.") {
                Stepper("\(model.trio.outputsVisible)", value: p.outputsVisible, in: 1...12).monospacedDigit()
            }
            Text("The active output device is highlighted with the accent color.").font(.caption).foregroundStyle(.secondary)
        }
        SettingsGroup("Panel Scrolling") {
            SettingRow("scroll", .teal, "Adjust volume by scrolling", "Scroll over the volume slider in the status panel to change the volume.") {
                Toggle("", isOn: p.scrollAdjustsVolume).labelsHidden().toggleStyle(.switch)
            }
            SettingRow("arrow.up.arrow.down", .teal, "Natural scrolling", "When on, scrolling up always turns the volume up. When off, it follows the system scroll direction.") {
                Toggle("", isOn: p.naturalScroll).labelsHidden().toggleStyle(.switch).disabled(!model.trio.scrollAdjustsVolume)
            }
        }
    }

    @ViewBuilder private var panelPage: some View {
        SettingsGroup("Displayed Items") {
            Text("Choose which items appear in the status panel and drag to change their order. BalDente's charging controls always stay on top.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            List {
                ForEach(model.trio.sections) { s in
                    HStack {
                        Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
                        Image(systemName: s.icon).frame(width: 22)
                        Text(s.title)
                        Spacer()
                        Toggle("", isOn: Binding(get: { !model.trio.hiddenSections.contains(s) },
                                                 set: { if $0 { model.trio.hiddenSections.remove(s) } else { model.trio.hiddenSections.insert(s) } }))
                            .labelsHidden().toggleStyle(.switch).controlSize(.small)
                    }
                }
                .onMove { model.trio.sections.move(fromOffsets: $0, toOffset: $1) }
            }
            .frame(height: CGFloat(model.trio.sections.count) * 34 + 12)
            .scrollDisabled(true)
            .clipShape(.rect(cornerRadius: 8))
        }
        SettingsGroup("Open status panel") {
            SettingRow("command", .gray, "Global shortcut", "Opens the same status panel from any app.") {
                ShortcutRecorder(hotKey: p.hotKey)
            }
        }
    }
}

// MARK: Building blocks

struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            VStack(alignment: .leading, spacing: 4) { content }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
        }
        .settingAnchor(title)
    }
}

struct SettingRow<Control: View>: View {
    let icon: String
    let tint: Color
    let title: String
    let detail: String?
    @ViewBuilder var control: Control

    init(_ icon: String, _ tint: Color, _ title: String, _ detail: String?, @ViewBuilder control: () -> Control) {
        self.icon = icon; self.tint = tint; self.title = title; self.detail = detail; self.control = control()
    }

    var body: some View {
        // Wide windows keep the control on the right; narrow ones drop it under the text instead of squeezing the words.
        RowControlLayout {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 34, height: 34).background(tint.gradient, in: .rect(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body)
                    if let d = detail { Text(d).font(.callout).foregroundStyle(.secondary) }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            control
        }
        .padding(.vertical, 6)
        .settingAnchor(title)
    }
}

/// Two children: the label block and its control. Side by side when the label keeps at least `minLead` points, otherwise stacked.
struct RowControlLayout: Layout {
    var minLead: CGFloat = 230
    var gap: CGFloat = 12
    var indent: CGFloat = 48
    /// Center the control when stacked (the banner's button), instead of indenting it under the label.
    var centerStacked = false

    private func stacked(_ width: CGFloat, _ control: CGSize) -> Bool { RowLayoutRule.stacked(width: width, controlWidth: control.width, minLead: minLead, gap: gap) }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        let c = subviews[1].sizeThatFits(.unspecified)
        let w = proposal.width ?? (minLead + gap + c.width)
        if stacked(w, c) {
            let lead = subviews[0].sizeThatFits(ProposedViewSize(width: w, height: nil))
            let cw = min(c.width, w - indent)
            let ch = subviews[1].sizeThatFits(ProposedViewSize(width: cw, height: nil)).height
            return CGSize(width: w, height: lead.height + 8 + ch)
        }
        let lead = subviews[0].sizeThatFits(ProposedViewSize(width: w - c.width - gap, height: nil))
        return CGSize(width: w, height: max(lead.height, c.height))
    }

    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let c = subviews[1].sizeThatFits(.unspecified)
        if stacked(b.width, c) {
            let lead = subviews[0].sizeThatFits(ProposedViewSize(width: b.width, height: nil))
            subviews[0].place(at: b.origin, anchor: .topLeading, proposal: ProposedViewSize(width: b.width, height: lead.height))
            let cw = min(c.width, b.width - indent)
            let ch = subviews[1].sizeThatFits(ProposedViewSize(width: cw, height: nil)).height
            subviews[1].place(at: CGPoint(x: centerStacked ? b.midX - cw / 2 : b.minX + indent, y: b.minY + lead.height + 8), anchor: .topLeading,
                              proposal: ProposedViewSize(width: cw, height: ch))
        } else {
            let lw = b.width - c.width - gap
            let lead = subviews[0].sizeThatFits(ProposedViewSize(width: lw, height: nil))
            subviews[0].place(at: CGPoint(x: b.minX, y: b.midY), anchor: .leading, proposal: ProposedViewSize(width: lw, height: lead.height))
            subviews[1].place(at: CGPoint(x: b.maxX, y: b.midY), anchor: .trailing, proposal: ProposedViewSize(width: c.width, height: c.height))
        }
    }
}

struct ValueSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let label: (Double) -> String

    var body: some View {
        HStack {
            Slider(value: $value, in: range, step: step).frame(width: 170)
            Text(label(value)).monospacedDigit().foregroundStyle(.secondary).frame(width: 52, alignment: .trailing)
        }
    }
}

/// The fake menu bar at the top of Settings, showing the real icon (animated while charging).
struct IconPreviewCard: View {
    /// "Sun Oct 25 16:46", the way the menu bar clock reads (day names follow the system language, 12 or 24 hour follows the system).
    private static func clock(_ d: Date) -> String {
        let day = DateFormatter(); day.dateFormat = "EEE MMM d"
        let time = DateFormatter(); time.timeStyle = .short; time.dateStyle = .none
        return day.string(from: d) + "  " + time.string(from: d)
    }

    @ObservedObject var model: Model
    @ObservedObject var system: SystemMonitor
    @Binding var dark: Bool
    /// The preview animates only while its window is up front; a hidden or background window must not keep redrawing SwiftUI.
    @Environment(\.scenePhase) private var phase

    var body: some View {
        let s = model.statusController?.state ?? TrioState(power: system.effectivePower, net: system.net, audio: system.audio)
        let p = model.trio
        let animate = p.menuBarChargingEffect && s.power.charging && !s.power.charged && !system.reduceMotion && phase == .active
        let top = TrioRules.topIndicator(charging: s.power.charging, plugged: s.power.plugged, showPercentage: p.showPercentage,
                                         showChargingIndicator: p.showChargingIndicator, percentageWhenConnected: p.percentageWhenConnected)
        let side = TrioRules.sideText(present: s.power.present, percent: s.power.percent, plugged: s.power.plugged, charging: s.power.charging,
                                      minutesToFull: s.power.minutesToFull, minutesToEmpty: s.power.minutesToEmpty, top: top,
                                      showPercentWhileCharging: p.showPercentWhileCharging, showPercentage: p.showPercentage,
                                      percentInMiddle: p.percentInMiddle, showTime: p.showTimeRemaining)
        let iconSize = CGFloat(min(36, max(16, p.iconSize)))
        VStack(alignment: .trailing, spacing: 6) {
            // A faithful strip of the macOS menu bar: app menu on the left, status items and the clock on the right.
            HStack(spacing: 0) {
                // In a narrow window the menus drop out and only the app name stays, as in a crowded real menu bar.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 18) {
                        Image(systemName: "apple.logo").font(.system(size: 15))
                        Text("BalDente").fontWeight(.bold)
                        ForEach(["Edit", "View", "Charging", "Window", "Help"], id: \.self) { Text($0) }
                    }
                    HStack(spacing: 18) {
                        Image(systemName: "apple.logo").font(.system(size: 15))
                        Text("BalDente").fontWeight(.bold)
                    }
                }
                .font(.system(size: 13)).lineLimit(1).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 16)
                HStack(spacing: 14) {
                    HStack(spacing: 4) {
                        let still = TrioRenderer.image(s, p, size: iconSize, frame: nil, forceDark: dark)
                        LiveIconView(still: still, animate: animate) { [weak controller = model.statusController] in
                            let f = controller?.currentFrame(
                                gap: s.power.charging && p.showChargingIndicator ? TrioGeometry.boltGap * p.symbolScale : TrioGeometry.numberGap,
                                boltInGap: s.power.charging && p.showChargingIndicator,
                                progress: TrioRules.ringProgress(percent: s.power.percent, full: s.fullLevel))
                            return f.map { TrioRenderer.image(s, p, size: iconSize, frame: $0, forceDark: dark) }
                        }
                        .frame(width: still.size.width, height: still.size.height)
                        if !side.isEmpty { Text(side.trimmingCharacters(in: .whitespaces)).font(.system(size: 13)).monospacedDigit().lineLimit(1) }
                    }
                    Image(systemName: "switch.2").font(.system(size: 13))
                    Text(Self.clock(Date.now)).font(.system(size: 13)).monospacedDigit().lineLimit(1).fixedSize()
                }
            }
            .foregroundStyle(dark ? Color.white : Color.black)
            .padding(.horizontal, 14).frame(height: max(30, iconSize + 8))
            .background(dark ? Color.black.opacity(0.72) : Color.white.opacity(0.72), in: .rect(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(dark ? 0.10 : 0.35)))
            Button { dark.toggle() } label: { Label(dark ? "Dark menu bar" : "Light menu bar", systemImage: dark ? "moon.fill" : "sun.max.fill").font(.caption) }
                .buttonStyle(.borderless).foregroundStyle(.secondary).help("Toggle menu bar dark/light preview")
        }
    }
}

/// The preview's icon, drawn into a layer outside SwiftUI. Swapping a SwiftUI `Image` 12 times a second made SwiftUI lay out
/// the whole settings page (every card in the masonry) on each frame, about 40% of a core while charging. A fixed size and
/// layer contents mean a new frame never touches layout. The timer only runs while the view is in a window and `animate` is on.
struct LiveIconView: NSViewRepresentable {
    let still: NSImage
    let animate: Bool
    let frame: () -> NSImage?

    func makeNSView(context: Context) -> LiveIconNSView { LiveIconNSView() }
    func updateNSView(_ v: LiveIconNSView, context: Context) { v.update(still: still, animate: animate, frame: frame) }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: LiveIconNSView, context: Context) -> CGSize? { still.size }
}

final class LiveIconNSView: NSView {
    private var still: NSImage?
    private var draw: (() -> NSImage?)?
    private var wantsAnimation = false
    private var timer: Timer?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.contentsGravity = .resizeAspect
    }
    required init?(coder: NSCoder) { nil }

    func update(still: NSImage, animate: Bool, frame: @escaping () -> NSImage?) {
        self.still = still; draw = frame; wantsAnimation = animate
        syncTimer()
        if timer == nil { show(still) }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        syncTimer()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        layer?.contentsScale = window?.backingScaleFactor ?? 2
    }

    private func syncTimer() {
        let want = wantsAnimation && window != nil
        if want, timer == nil {
            let t = Timer(timeInterval: 1 / 12, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
            t.tolerance = 0.02
            RunLoop.main.add(t, forMode: .common)
            timer = t
        } else if !want, let t = timer {
            t.invalidate(); timer = nil
            show(still)
        }
    }

    private func tick() { show(draw?() ?? still) }

    private func show(_ image: NSImage?) {
        CATransaction.begin(); CATransaction.setDisableActions(true)   // no implicit cross-fade between frames
        layer?.contentsScale = window?.backingScaleFactor ?? 2
        layer?.contents = image
        CATransaction.commit()
    }
}

/// Sample icons for the states people most often ask about.
struct StateGallery: View {
    let prefs: TrioPrefs
    let dark: Bool

    private var samples: [(String, TrioState)] {
        func s(_ pct: Int, plugged: Bool = false, charging: Bool = false, lpm: Bool = false, net: NetKind = .wifi(bars: 3),
               vol: Double = 0.5, muted: Bool = false, bt: Bool = false) -> TrioState {
            var t = TrioState()
            t.power = PowerSnap(present: true, percent: pct, plugged: plugged, charging: charging, charged: plugged && !charging, lowPower: lpm)
            t.net.kind = net; t.net.rssi = -50
            t.audio.volume = vol; t.audio.muted = muted
            t.audio.output = AudioDevice(id: 1, name: bt ? "AirPods Pro" : "MacBook Speakers", bluetooth: bt)
            return t
        }
        return [
            ("Charging + Wi-Fi", s(71, plugged: true, charging: true)),
            ("Charged + Ethernet", s(100, plugged: true, net: .ethernet)),
            ("Low battery + Wi-Fi", s(12)),
            ("Hotspot + Low Power", s(48, lpm: true, net: .hotspot)),
            ("Weak Wi-Fi + 25% volume", s(64, net: .wifi(bars: 1), vol: 0.25)),
            ("No Internet + Muted", s(83, net: .noInternet, muted: true)),
            ("Wi-Fi off", s(55, net: .wifiOff)),
            ("Bluetooth audio", s(90, vol: 0.75, bt: true)),
        ]
    }

    var body: some View {
        var p = prefs
        p.bluetoothReplacesNetwork = true
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
            ForEach(samples, id: \.0) { name, state in
                VStack(spacing: 6) {
                    Image(nsImage: TrioRenderer.image(state, p, size: 40, frame: nil, forceDark: dark))
                    Text(name).font(.caption2).multilineTextAlignment(.center).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 78)
                .background(dark ? Color(white: 0.17) : Color(white: 0.93), in: .rect(cornerRadius: 10))
            }
        }
    }
}

/// Records a global shortcut: press Record, then the key combination. Esc cancels.
struct ShortcutRecorder: View {
    @Binding var hotKey: HotKey?
    @State private var recording = false
    @State private var monitor: Any?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack {
                Text(recording ? "Type shortcut…" : hotKey?.display ?? "Not set")
                    .monospaced().padding(.horizontal, 10).padding(.vertical, 4)
                    .background(.quaternary, in: .rect(cornerRadius: 6))
                Button(recording ? "Cancel" : "Record") { recording ? stop() : start() }
                if hotKey != nil, !recording { Button("Clear") { hotKey = nil } }
            }
            if let e = error { Text(e).font(.caption).foregroundStyle(.red) }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        error = nil; recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            if e.keyCode == UInt16(kVK_Escape) { stop(); return nil }
            let f = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard !f.intersection([.command, .control, .option]).isEmpty else {
                error = "Use a key with Command, Control or Option."; return nil
            }
            var mods: UInt32 = 0, text = ""
            if f.contains(.control) { mods |= UInt32(controlKey); text += "⌃" }
            if f.contains(.option) { mods |= UInt32(optionKey); text += "⌥" }
            if f.contains(.shift) { mods |= UInt32(shiftKey); text += "⇧" }
            if f.contains(.command) { mods |= UInt32(cmdKey); text += "⌘" }
            text += (e.charactersIgnoringModifiers ?? "?").uppercased()
            hotKey = HotKey(keyCode: UInt32(e.keyCode), modifiers: mods, display: text)
            stop()
            return nil
        }
    }

    private func stop() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil; recording = false
    }
}
