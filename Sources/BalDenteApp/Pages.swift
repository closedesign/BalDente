import BalDenteCore
import SwiftUI

/// Everything in the main window's sidebar, grouped the way people look for things.
enum SettingsPage: String, CaseIterable, Identifiable {
    case overview = "Overview", zones = "Zones", charging = "Charging Tools", history = "Battery History"
    case icon = "Menu Bar Icon", battery = "Battery Display", network = "Network", bluetooth = "Bluetooth", audio = "Audio", panel = "Status Panel"
    case appearance = "Appearance", general = "General", about = "About"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .overview: "gauge.with.dots.needle.67percent"
        case .zones: "location.fill"
        case .charging: "bolt.batteryblock.fill"
        case .history: "chart.xyaxis.line"
        case .icon: "macwindow.on.rectangle"
        case .battery: "battery.100percent"
        case .network: "wifi"
        case .bluetooth: "dot.radiowaves.left.and.right"
        case .audio: "hifispeaker.fill"
        case .panel: "list.bullet.rectangle.fill"
        case .appearance: "paintpalette.fill"
        case .general: "gearshape.fill"
        case .about: "info"
        }
    }

    var tint: Color {
        switch self {
        case .overview: .green
        case .zones: .orange
        case .charging: .yellow
        case .history: .mint
        case .icon: .indigo
        case .battery: .green
        case .network, .bluetooth: .blue
        case .audio: .teal
        case .panel: .pink
        case .appearance: .purple
        case .general: .gray
        case .about: .orange
        }
    }

    var subtitle: String {
        switch self {
        case .overview: "Where your battery stands and what BalDente is doing about it."
        case .zones: "Charge limits that follow your Wi-Fi and saved places."
        case .charging: "Ready by, heat protection, discharge, calibration and Low Power Mode."
        case .history: "Battery health and cycle count over time."
        case .icon: "Where the live status icon lives and how big it is."
        case .battery: "How the battery ring, number and charging effect look."
        case .network: "What the icon's middle slot shows."
        case .bluetooth: "Bluetooth audio in the icon and the status panel."
        case .audio: "Volume display and scrolling."
        case .panel: "What the menu bar popover shows, and its shortcut."
        case .appearance: "Colors, background animation and window layout."
        case .general: "Startup, the background helper, permissions and resets."
        case .about: "Version and credits."
        }
    }

    /// The sidebar sections.
    static let groups: [(title: String?, pages: [SettingsPage])] = [
        (nil, [.overview, .zones, .charging, .history]),
        ("Menu Bar & Panel", [.icon, .battery, .network, .bluetooth, .audio, .panel]),
        ("App", [.appearance, .general, .about]),
    ]

    /// Pages drawn by `TrioPageView`, which show the live menu bar preview on top.
    var isMenuBarPage: Bool { [.icon, .battery, .network, .bluetooth, .audio, .panel].contains(self) }
}

/// Every setting you can search for. Titles must match the on-screen row or card titles, because a search jump
/// scrolls to and flashes the view whose title (or `anchor`) matches.
enum SettingsIndex {
    static let all: [SettingsItem] = {
        func i(_ t: String, _ d: String = "", _ k: [String] = [], _ p: SettingsPage, anchor: String? = nil) -> SettingsItem {
            SettingsItem(t, d, keywords: k, page: p.rawValue, anchor: anchor)
        }
        return [
            // Overview
            i("Drag the charge ring", "Drag the markers on the Overview ring to set where charging stops and resumes for the active zone.", ["limit", "resume", "buffer", "hysteresis", "drag", "ring"], .overview, anchor: "Charge ring"),
            i("Top Up to 100%", "Charge fully now, for a trip, then go back to your zone's limit.", ["charge fully", "full charge", "travel", "boost"], .overview, anchor: "Top Up"),
            i("Automatic zone", "Let Wi-Fi and location choose the limit instead of pinning one.", ["pin", "override", "manual"], .overview, anchor: "Automatic"),
            i("Travel mode", "Hold 100% for 24 hours, then return to your zone's limit.", ["trip", "flight", "airplane", "full charge"], .overview, anchor: "Travel mode"),
            i("Recent changes", "Every limit change with when and why. Clear it any time.", ["activity", "log", "history", "what changed", "why", "events"], .overview),
            // Zones
            i("Zones", "Add, rename and edit zones with their own charge limits.", ["add zone", "new zone", "home", "school", "work", "travel", "delete zone", "icon"], .zones),
            i("Everywhere else", "Default limits when no zone matches.", ["default limits", "fallback", "stop charging at", "resume at", "sailing"], .zones),
            i("Wi-Fi networks", "Networks that put you in a zone. Open a zone to edit them.", ["ssid", "router", "bssid", "add current network"], .zones, anchor: "Zones"),
            i("Saved place", "Switch zones by location with a map circle. Open a zone to set it.", ["location", "radius", "gps", "geofence", "map"], .zones, anchor: "Zones"),
            // Charging tools
            i("Ready by", "Reach a chosen charge before you leave each day.", ["schedule", "departure", "leave", "alarm", "weekday", "wake"], .charging),
            i("Heat Protection", "Pause charging when the battery gets hot.", ["temperature", "thermal", "hot", "cool", "celsius"], .charging),
            i("Heat limit", "The temperature at which charging pauses.", ["celsius", "degrees", "threshold"], .charging, anchor: "Heat Protection"),
            i("Discharge", "Drain to a level with the charger plugged in.", ["drain", "lower", "run down"], .charging),
            i("Calibration", "Drain to 15%, charge to 100%, rest an hour.", ["calibrate", "accuracy", "percentage wrong", "cycle"], .charging),
            i("Calibration schedule", "Repeat calibration on chosen days of the month.", ["repeat", "monthly", "calibrate at"], .charging, anchor: "Calibration"),
            i("Low Power Mode", "Ask macOS to reduce power use.", ["energy", "save power", "efficiency"], .charging),
            i("Calendar Ready by", "Be full a set time before your next calendar event.", ["calendar", "event", "meeting", "schedule", "automatic", "leave"], .charging),
            i("Battery Health Advisor", "Cycle budget and care tips for your Mac model, from Apple's published figures.", ["health", "lifespan", "cycles", "tips", "storage", "heat", "model", "macbook"], .history),
            i("Export history", "Save the daily battery log as a CSV file.", ["csv", "download", "save", "backup"], .history),
            i("Reset history", "Delete the log and start fresh, for example after a battery replacement.", ["clear", "delete", "new battery", "baseline"], .history),
            i("Battery History", "Health and cycle count over time.", ["graph", "chart", "health trend", "cycles", "log", "degradation"], .history),
            // Menu bar icon
            i("Show BalDente in", "Menu bar, Dock or both.", ["placement", "dock icon", "menu bar icon", "hide"], .icon),
            i("Icon size", "Menu bar render size, 16 to 36 pt.", ["bigger", "smaller", "scale"], .icon),
            i("Ring stroke width", "Line thickness of the ring.", ["thickness", "bold", "light", "thin"], .icon),
            i("Dock icon background", "Light, dark or follow the system.", ["dock tile", "appearance"], .icon),
            i("State combinations", "A gallery of common icon states.", ["gallery", "samples", "examples"], .icon),
            i("Can't find the menu bar icon?", "The notch can hide icons in a crowded menu bar.", ["notch", "hidden", "missing", "crowded"], .icon),
            // Battery
            i("Show battery percentage", "The number in the ring's top gap.", ["number", "digits"], .battery),
            i("Show a bolt while charging", "A bolt replaces the number while charging.", ["bolt", "plug", "lightning"], .battery),
            i("Menu bar charging effect", "Animate the charging highlight in the menu bar.", ["animation", "animate", "comet", "glow", "moving", "reduce motion"], .battery),
            i("Dock charging effect", "Animate the charging highlight in the Dock icon.", ["animation", "animate"], .battery),
            i("Charging bolt pulse", "The bolt swells and glows as the comet passes.", ["animation", "bolt"], .battery),
            i("Test charging animation", "Plays the animation without a charger.", ["preview", "demo", "try"], .battery),
            i("Wave speed", "How fast the charging animation runs. Lower is slower.", ["animation", "speed", "faster", "slower", "wave"], .battery),
            i("Show percentage next to the icon while charging", "Battery level as text beside the icon while charging or plugged in.", ["percent", "percentage", "text", "charging"], .battery),
            i("Show time remaining", "Minutes to full or empty beside the icon.", ["time", "minutes", "hours", "text", "estimate"], .battery),
            i("Percentage/bolt size", "The number and bolt share this size.", ["font", "scale"], .battery),
            i("Show battery percentage in the connection position", "Number in the middle instead of Wi-Fi.", ["middle", "center"], .battery),
            i("Color the arc by battery state", "Red when low, yellow in Low Power Mode, green on power.", ["colour", "green", "red", "yellow", "status colors"], .battery),
            i("Low battery threshold", "Below this level the ring turns red.", ["low", "red", "warning"], .battery),
            i("Full ring level", "Which level counts as a full ring.", ["limit", "80%", "100%", "follow limit"], .battery),
            // Network
            i("Middle slot", "What the middle of the icon shows.", ["input source", "keyboard", "language"], .network),
            i("Show network problems instead", "Offline states beat the input source.", ["offline", "error"], .network),
            i("Wi-Fi icon size", "Scale the network icon inside the ring.", ["bigger", "scale"], .network),
            i("Use Wi-Fi icon for Ethernet", "Show Wi-Fi bars for a wired connection.", ["cable", "wired", "lan"], .network),
            i("Use Wi-Fi icon for Personal Hotspot", "Show Wi-Fi bars on a phone hotspot.", ["tethering", "iphone", "cellular"], .network),
            i("Show local IP address", "Your private LAN address in the panel.", ["ip", "address", "lan", "privacy"], .network),
            // Bluetooth
            i("Replace the network icon with a Bluetooth device icon", "Headphones show in the middle while audio plays.", ["airpods", "headphones", "earbuds"], .bluetooth),
            i("Let network errors take priority", "Offline beats the Bluetooth icon.", ["offline", "error"], .bluetooth),
            i("Bluetooth audio icon", "Pick earbuds, headphones, headset or speaker.", ["airpods", "glyph", "symbol"], .bluetooth),
            i("Bluetooth icon size", "Scale the Bluetooth icon.", ["bigger", "scale"], .bluetooth),
            i("Use blue for Bluetooth volume", "Volume dots turn blue on Bluetooth audio.", ["color", "colour"], .bluetooth),
            i("Show Bluetooth battery levels", "Battery of connected devices in the panel.", ["airpods", "case", "left", "right"], .bluetooth),
            i("Show Bluetooth power control", "A Bluetooth on/off switch in the panel.", ["toggle", "radio"], .bluetooth),
            i("Maximum visible Bluetooth devices", "How many show before Show all.", ["list", "count"], .bluetooth),
            // Audio
            i("Display style", "Volume as four dots or a continuous arc.", ["volume", "dots", "arc", "indicator"], .audio),
            i("Maximum visible output devices", "How many show before Show all.", ["speakers", "list", "count"], .audio),
            i("Adjust volume by scrolling", "Scroll over the panel's volume slider.", ["scroll wheel", "trackpad"], .audio),
            i("Natural scrolling", "Scrolling up always raises volume.", ["direction", "inverted"], .audio),
            // Status panel
            i("Displayed Items", "Choose and reorder the panel's sections.", ["sections", "order", "drag", "microphone", "input source", "vpn", "hide"], .panel),
            i("Global shortcut", "Open the status panel from any app.", ["hotkey", "keyboard", "key combination"], .panel),
            // Appearance
            i("Background", "Follow the active zone, pick a preset or choose your own colors.", ["theme", "colors", "aurora", "preset", "custom", "gradient"], .appearance),
            i("Animate the background", "Drifting background animation.", ["motion", "energy", "performance"], .appearance),
            i("Compact mode", "A dense, standard Mac layout in a small window.", ["layout", "small window", "dense", "regular mode"], .appearance),
            // General
            i("Launch at login", "Start BalDente when you log in.", ["startup", "boot", "login items", "autostart"], .general),
            i("Status refresh interval", "How often signal strength is checked.", ["poll", "energy", "battery drain", "seconds"], .general),
            i("Background helper", "The root helper that switches charging. Install, update or remove it.", ["daemon", "install", "uninstall", "update", "reinstall", "permission", "password"], .general),
            i("Location access", "Needed to read Wi-Fi names and use saved places.", ["permission", "privacy", "wifi name", "ssid"], .general),
            i("Smart notifications", "Battery health drops.", ["alerts", "health", "warning"], .general),
            i("Change notifications", "Notify on zone switches, Ready by, heat, habits, Top Up and helper problems. Mute any kind.", ["alerts", "mute", "silence", "zone switch", "notify", "banner"], .general),
            i("Suggest a charge plan from my routine", "Learn when you usually unplug and suggest a Ready by plan.", ["habit", "routine", "learn", "suggestion", "unplug", "privacy"], .general),
            i("Clear learned habits", "Delete the recorded unplug times and often-used Wi-Fi names.", ["habit", "privacy", "delete", "reset", "routine", "wifi"], .general),
            i("Show tutorial again", "Replay the short tour.", ["tour", "help", "intro", "onboarding", "guide", "welcome", "defaults"], .general),
            i("Export or import settings", "Back up zones and limits to a file.", ["backup", "restore", "json", "transfer"], .general),
            i("Reset icon and panel settings", "Charging limits and zones are not affected.", ["defaults", "restore"], .general),
            i("Support BalDente", "Donate on Ko-fi or Buy Me a Coffee. BalDente stays free.", ["donate", "coffee", "ko-fi", "tip", "sponsor", "support", "money"], .about),
            i("About BalDente", "Version, credits and licenses.", ["version", "credits", "license", "status trio"], .about),
        ]
    }()

    static func page(for item: SettingsItem) -> SettingsPage { SettingsPage(rawValue: item.page) ?? .overview }
}

// MARK: Flashing a setting after a search jump

private struct FocusedSettingKey: EnvironmentKey { static let defaultValue: String? = nil }

extension EnvironmentValues {
    /// The anchor of the setting a search just jumped to, so it can flash.
    var focusedSetting: String? {
        get { self[FocusedSettingKey.self] }
        set { self[FocusedSettingKey.self] = newValue }
    }
}

private struct SettingAnchor: ViewModifier {
    let id: String
    @Environment(\.focusedSetting) private var focused

    func body(content: Content) -> some View {
        content
            .id(id)
            .tourAnchor(id)
            // An outline and glow drawn on top, so it still shows over glass cards (a background would be hidden by them).
            .overlay {
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color.accentColor.opacity(0.10))
                    .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Color.accentColor, lineWidth: 3))
                    .shadow(color: Color.accentColor.opacity(0.55), radius: 12)
                    .padding(-5).opacity(focused == id ? 1 : 0).allowsHitTesting(false)
            }
            .animation(.easeInOut(duration: 0.35), value: focused)
    }
}

extension View {
    /// Marks a row or card as something search can jump to.
    func settingAnchor(_ id: String) -> some View { modifier(SettingAnchor(id: id)) }
}
