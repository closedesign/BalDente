import Foundation

/// A circle on the map. macOS has no GPS chip, so this is Wi-Fi-based positioning: keep the radius at 100 m or more.
public struct Place: Codable, Equatable {
    /// Largest radius the editors offer (big enough for an airport or campus).
    public static let maxRadius: Double = 5000
    public var latitude: Double
    public var longitude: Double
    public var radius: Double
    public init(latitude: Double, longitude: Double, radius: Double) {
        self.latitude = latitude; self.longitude = longitude; self.radius = radius
    }
}

public struct Zone: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var name: String
    /// Wi-Fi SSIDs, BSSIDs or gateway MACs that put you in this zone.
    public var networks: [String]
    public var upper: Int
    public var lower: Int
    /// A copy whose resume level is the one that is enforced, for showing on tiles.
    public func showing(sailing: Bool) -> Zone {
        var z = self
        z.lower = ResumeLevel.effective(upper: upper, lower: lower, sailing: sailing)
        return z
    }
    /// SF Symbol name; nil picks one from the zone name.
    public var icon: String?
    /// Optional map circle; used when no Wi-Fi network matches.
    public var place: Place?

    public init(name: String, networks: [String] = [], upper: Int, lower: Int, icon: String? = nil, place: Place? = nil) {
        self.name = name; self.networks = networks; self.upper = upper; self.lower = lower; self.icon = icon; self.place = place
    }

    // Tolerant: a field added in a later version must never make an older saved zone unreadable.
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Zone"
        networks = try c.decodeIfPresent([String].self, forKey: .networks) ?? []
        upper = try c.decodeIfPresent(Int.self, forKey: .upper) ?? 80
        lower = try c.decodeIfPresent(Int.self, forKey: .lower) ?? 75
        icon = try c.decodeIfPresent(String.self, forKey: .icon)
        place = try c.decodeIfPresent(Place.self, forKey: .place)
    }

    /// Labels the app uses for non-zone targets (lowercased). A zone with one of these names would be mistaken for them.
    public static let reserved: Set<String> = ["default", "top up", "travel mode", "manual"]
}

public struct Appearance: Codable, Equatable {
    public var mode = "zone"                       // zone | preset | custom
    public var preset = "Aurora"
    public var theme = "dark"                      // dark | light | system
    public var style = "aurora"                    // aurora | gradient | spotlight | midnight
    public var custom = ["#3A8CFF", "#1ACFD0", "#3A2FA6"]
    public var animated = true
    public var compact = false
    public init() {}

    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        mode = try c.decodeIfPresent(String.self, forKey: .mode) ?? mode
        preset = try c.decodeIfPresent(String.self, forKey: .preset) ?? preset
        style = try c.decodeIfPresent(String.self, forKey: .style) ?? style
        theme = try c.decodeIfPresent(String.self, forKey: .theme) ?? theme
        custom = try c.decodeIfPresent([String].self, forKey: .custom) ?? custom
        animated = try c.decodeIfPresent(Bool.self, forKey: .animated) ?? animated
        compact = try c.decodeIfPresent(Bool.self, forKey: .compact) ?? compact
    }
}

public struct Config: Codable, Equatable {
    public var zones: [Zone]
    public var defaultUpper = 80
    public var defaultLower = 75
    /// Name of a zone to force regardless of network, or nil for automatic.
    public var overrideZone: String?
    public var appearance: Appearance?
    /// Start a discharge on its own when the limit drops below the battery. Optional so older config files still decode.
    public var autoDischarge: Bool?
    /// Start a calibration the next time the Mac is plugged in at night, once a month. Optional so older config files still decode.
    public var overnightCalibration: Bool?
    /// Let the battery drift down between the limit and the resume level before charging again. Off by default: the app then
    /// tells the helper to resume one point below the limit, so each charger cut is shallow. Optional so older config files still decode.
    public var sailing: Bool?
    /// The step (80, 85, 90 or 95) the user set as macOS's own charge limit, or nil if they don't use it. See `MacChargeLimit`.
    public var macLimit: Int?
    /// Follow macOS's own setting (read with `pmset -g battlimit`) instead of `macLimit`. On unless the user picked a step by hand.
    public var macLimitAuto: Bool?

    /// The macOS limit in force: the detected one when following macOS, else the hand-picked step.
    public func effectiveMacLimit(detected: Int?) -> Int? { macLimitAuto ?? (macLimit == nil) ? detected : macLimit }

    public init() {
        zones = [
            Zone(name: "Home", upper: 80, lower: 75),
            Zone(name: "School", upper: 80, lower: 75),
            Zone(name: "Travel", upper: 100, lower: 95),
        ]
    }

    // Tolerant: keep every saved value, default only what an older file lacks.
    public init(from d: Decoder) throws {
        self.init()
        let c = try d.container(keyedBy: CodingKeys.self)
        zones = try c.decodeIfPresent([Zone].self, forKey: .zones) ?? zones
        defaultUpper = try c.decodeIfPresent(Int.self, forKey: .defaultUpper) ?? defaultUpper
        defaultLower = try c.decodeIfPresent(Int.self, forKey: .defaultLower) ?? defaultLower
        overrideZone = try c.decodeIfPresent(String.self, forKey: .overrideZone)
        appearance = try c.decodeIfPresent(Appearance.self, forKey: .appearance)
        autoDischarge = try c.decodeIfPresent(Bool.self, forKey: .autoDischarge)
        overnightCalibration = try c.decodeIfPresent(Bool.self, forKey: .overnightCalibration)
        sailing = try c.decodeIfPresent(Bool.self, forKey: .sailing)
        macLimit = try c.decodeIfPresent(Int.self, forKey: .macLimit)
        macLimitAuto = try c.decodeIfPresent(Bool.self, forKey: .macLimitAuto)
    }

    /// Makes imported or hand-edited limits something the helper accepts (it rejects upper outside 5...100 or lower >= upper),
    /// and gives duplicate zone names a numeric suffix because zones are pinned by name.
    public func sanitized() -> Config {
        var c = self
        func clamp(_ u: Int, _ l: Int) -> (Int, Int) { let up = min(100, max(5, u)); return (up, min(max(1, l), up - 1)) }
        (c.defaultUpper, c.defaultLower) = clamp(c.defaultUpper, c.defaultLower)
        var seen = Set<String>()
        for i in c.zones.indices {
            (c.zones[i].upper, c.zones[i].lower) = clamp(c.zones[i].upper, c.zones[i].lower)
            let trimmed = c.zones[i].name.trimmingCharacters(in: .whitespacesAndNewlines)
            let base = trimmed.isEmpty ? "Zone" : trimmed
            var name = base, n = 2
            while seen.contains(name.lowercased()) || Zone.reserved.contains(name.lowercased()) { name = "\(base) \(n)"; n += 1 }
            seen.insert(name.lowercased()); c.zones[i].name = name
        }
        if let o = c.overrideZone, !c.zones.contains(where: { $0.name == o }) { c.overrideZone = nil }
        return c
    }

    public static var url: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("BalDente/config.json")
    }

    public static func load() -> Config {
        guard let data = try? Data(contentsOf: url) else { return Config() }
        if let c = try? JSONDecoder().decode(Config.self, from: data) { return c }
        // Unreadable: keep a copy so the next save can't destroy the only record of the user's settings.
        let backup = url.deletingLastPathComponent().appendingPathComponent("config.unreadable.json")
        if !FileManager.default.fileExists(atPath: backup.path) { try? data.write(to: backup) }
        return Config()
    }

    public func save() {
        try? FileManager.default.createDirectory(at: Config.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let d = try? JSONEncoder().encode(self) { try? d.write(to: Config.url) }
    }
}

/// The resume level the helper really enforces: the saved one with sailing on, one point under the limit with it off.
public enum ResumeLevel {
    public static func effective(upper: Int, lower: Int, sailing: Bool) -> Int { sailing ? lower : max(1, upper - 1) }
}

public struct Target: Equatable {
    public var label: String
    public var upper: Int
    public var lower: Int
    /// The zone this came from, so renaming a zone isn't mistaken for switching zones. Nil for Default and Top Up.
    public var zoneID: UUID?
    /// Why this target won, in words ("Wi-Fi HomeNet", "pinned"). Not part of equality: it never changes what the helper enforces.
    public var reason: String?
    public init(label: String, upper: Int, lower: Int, zoneID: UUID? = nil, reason: String? = nil) {
        self.label = label; self.upper = upper; self.lower = lower; self.zoneID = zoneID; self.reason = reason
    }
    init(_ z: Zone, reason: String) { self.init(label: z.name, upper: z.upper, lower: z.lower, zoneID: z.id, reason: reason) }

    /// What the helper should enforce. With sailing off the resume level sits one point under the limit, so the adapter is only
    /// cut for a point or so at a time (every cut runs the Mac from its battery). The zone keeps its own saved resume level.
    public func sending(sailing: Bool) -> Target {
        guard !sailing else { return self }
        var t = self
        t.lower = ResumeLevel.effective(upper: upper, lower: lower, sailing: false)
        return t
    }

    public static func == (a: Target, b: Target) -> Bool {
        a.label == b.label && a.upper == b.upper && a.lower == b.lower && a.zoneID == b.zoneID
    }

    /// The label as sent to the helper: one token (the protocol splits on spaces), no control characters, never empty,
    /// at most 64 characters. The helper applies the same function, so the label it reports always equals what was sent.
    public var wireLabel: String { Target.wire(label) }

    public static func wire(_ s: String) -> String {
        let cleaned = String(String.UnicodeScalarView(s.unicodeScalars.map {
            CharacterSet.whitespacesAndNewlines.contains($0) ? "_" : $0
        }.filter { !CharacterSet.controlCharacters.contains($0) }))
        let t = String(cleaned.prefix(64))
        return t.isEmpty ? "zone" : t
    }
}

/// Override wins, then a zone whose Wi-Fi matches, then a zone whose map circle we're inside, then the default.
public func resolveZone(_ config: Config, networks: [String], inside: Set<UUID> = []) -> Target {
    if let name = config.overrideZone, let z = config.zones.first(where: { $0.name == name }) {
        return Target(z, reason: "you pinned it")
    }
    let current = Set(networks.map { $0.lowercased() })
    for z in config.zones {
        if let n = z.networks.first(where: { current.contains($0.lowercased()) }) { return Target(z, reason: "connected to \(n)") }
    }
    if let z = config.zones.first(where: { inside.contains($0.id) }) {
        return Target(z, reason: "you're at its saved place")
    }
    return Target(label: "Default", upper: config.defaultUpper, lower: config.defaultLower,
                  reason: config.zones.contains { !$0.networks.isEmpty || $0.place != nil } ? "no zone's Wi-Fi or place matches" : "no zone has a Wi-Fi network or place yet")
}
