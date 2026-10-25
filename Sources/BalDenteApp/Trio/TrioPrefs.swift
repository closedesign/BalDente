import Foundation

/// Everything the combined menu bar icon and status panel can be tuned with.
/// Stored in UserDefaults; keys missing from older saves fall back to these defaults.
struct TrioPrefs: Codable, Equatable {
    enum Placement: String, Codable, CaseIterable { case menuBar, dock, both }
    enum Stroke: String, Codable, CaseIterable { case light, regular, bold }
    enum VolumeStyle: String, Codable, CaseIterable { case dots, arc }
    enum MiddleSlot: String, Codable, CaseIterable { case automatic, inputSource }
    enum DockBackground: String, Codable, CaseIterable { case system, light, dark }
    enum BluetoothGlyph: String, Codable, CaseIterable {
        case automatic, earbuds, headphones, overEar, headset, speaker
        var symbol: String? {
            switch self {
            case .automatic: nil
            case .earbuds: "airpods"
            case .headphones: "headphones"
            case .overEar: "airpodsmax"
            case .headset: "headset"
            case .speaker: "hifispeaker.fill"
            }
        }
    }
    enum Section: String, Codable, CaseIterable, Identifiable {
        case battery, network, bluetooth, volume, microphone, inputSource, vpn
        var id: String { rawValue }
        var title: String {
            switch self {
            case .battery: "Battery"
            case .network: "Network"
            case .bluetooth: "Bluetooth"
            case .volume: "Volume"
            case .microphone: "Microphone"
            case .inputSource: "Input Source"
            case .vpn: "VPN"
            }
        }
        var icon: String {
            switch self {
            case .battery: "battery.75percent"
            case .network: "wifi"
            case .bluetooth: "dot.radiowaves.left.and.right"
            case .volume: "speaker.wave.2.fill"
            case .microphone: "mic.fill"
            case .inputSource: "keyboard"
            case .vpn: "lock.shield"
            }
        }
    }

    // App icon
    var placement = Placement.menuBar
    var iconSize = 22.0                      // 16...36 pt
    var stroke = Stroke.regular
    var dockBackground = DockBackground.system

    // Battery
    var showPercentage = true
    var showChargingIndicator = true
    var percentageWhenConnected = false
    var symbolScale = 1.0                    // 0.8...1.4, shared by the number and the bolt
    var statusColors = true
    var lowThreshold = 20
    var fullLevel = 100
    var fullFollowsLimit = false             // use BalDente's active charge limit as "full"
    var menuBarChargingEffect = true
    var dockChargingEffect = true
    var boltPulse = true
    var percentInMiddle = false
    var showTimeRemaining = true             // minutes to full / empty as text beside the icon
    var showPercentWhileCharging = true      // "58%" as text beside the icon while the bolt or plug is in the ring
    var chargeWaveSpeed = 1.0                // 0.25...3, multiplier for the wave rippling along the ring

    // Network
    var middleSlot = MiddleSlot.automatic
    var networkProblemsOverInput = true
    var wifiIconForEthernet = false
    var wifiIconForHotspot = false
    var showLocalIP = true
    var wifiScale = 1.0                      // 1.0...1.8

    // Bluetooth
    var bluetoothReplacesNetwork = false
    var networkErrorsFirst = true
    var bluetoothGlyph = BluetoothGlyph.automatic
    var bluetoothScale = 1.2                 // 1.0...1.8
    var bluetoothBlueVolume = true
    var bluetoothBattery = true
    var bluetoothPowerButton = true
    var bluetoothVisible = 4

    // Audio
    var volumeStyle = VolumeStyle.dots
    var outputsVisible = 4

    // Status panel
    var sections: [Section] = Section.allCases
    var hiddenSections: Set<Section> = [.microphone, .inputSource, .vpn]
    var scrollAdjustsVolume = true
    var naturalScroll = true

    // General
    var refreshSeconds = 5
    var hotKey: HotKey?
    var smartNotifications = true            // battery-health drops and a helper that stopped answering

    var visibleSections: [Section] { sections.filter { !hiddenSections.contains($0) } }

    static let key = "trioPrefs"

    static func load() -> TrioPrefs {
        // Overlay what was saved on top of the defaults, so new settings get their default instead of failing to decode.
        let ud = UserDefaults.standard
        // Version 2 turned "Show time remaining" on by default; the old default (off) was never a choice, so move it once.
        let migrate = ud.integer(forKey: "trioPrefsVersion") < 2
        ud.set(2, forKey: "trioPrefsVersion")
        guard let saved = ud.data(forKey: key),
              let over = (try? JSONSerialization.jsonObject(with: saved)) as? [String: Any],
              let defaults = try? JSONEncoder().encode(TrioPrefs()),
              var base = (try? JSONSerialization.jsonObject(with: defaults)) as? [String: Any]
        else { return TrioPrefs() }
        base.merge(over) { _, new in new }
        if migrate { base["showTimeRemaining"] = true }
        guard let merged = try? JSONSerialization.data(withJSONObject: base),
              var p = try? JSONDecoder().decode(TrioPrefs.self, from: merged) else { return TrioPrefs() }
        // A section added in a newer version shows up at the end of a saved order.
        p.sections += Section.allCases.filter { !p.sections.contains($0) }
        return p
    }

    func save() {
        if let d = try? JSONEncoder().encode(self) { UserDefaults.standard.set(d, forKey: Self.key) }
    }
}

/// A global shortcut: a virtual key code plus Carbon modifier flags.
struct HotKey: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var display: String
}
