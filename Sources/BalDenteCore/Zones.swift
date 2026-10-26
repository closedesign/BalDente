import Foundation

/// A circle on the map. macOS has no GPS chip, so this is Wi-Fi-based positioning: keep the radius at 100 m or more.
public struct Place: Codable, Equatable {
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
    /// SF Symbol name; nil picks one from the zone name.
    public var icon: String?
    /// Optional map circle; used when no Wi-Fi network matches.
    public var place: Place?

    public init(name: String, networks: [String] = [], upper: Int, lower: Int, icon: String? = nil, place: Place? = nil) {
        self.name = name; self.networks = networks; self.upper = upper; self.lower = lower; self.icon = icon; self.place = place
    }

    /// Labels the app uses for non-zone targets (lowercased). A zone with one of these names would be mistaken for them.
    public static let reserved: Set<String> = ["default", "top up", "travel mode", "manual"]
}

public struct Appearance: Codable, Equatable {
    public var mode = "zone"                       // zone | preset | custom
    public var preset = "Aurora"
    public var custom = ["#3A8CFF", "#1ACFD0", "#3A2FA6"]
    public var animated = true
    public var compact = false
    public init() {}
}

public struct Config: Codable, Equatable {
    public var zones: [Zone]
    public var defaultUpper = 80
    public var defaultLower = 75
    /// Name of a zone to force regardless of network, or nil for automatic.
    public var overrideZone: String?
    public var appearance: Appearance?

    public init() {
        zones = [
            Zone(name: "Home", upper: 50, lower: 45),
            Zone(name: "School", upper: 100, lower: 95),
            Zone(name: "Travel", upper: 90, lower: 85),
        ]
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
        (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(Config.self, from: $0) } ?? Config()
    }

    public func save() {
        try? FileManager.default.createDirectory(at: Config.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let d = try? JSONEncoder().encode(self) { try? d.write(to: Config.url) }
    }
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
