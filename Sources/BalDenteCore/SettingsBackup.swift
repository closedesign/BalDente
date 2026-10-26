import Foundation

/// What matters about the user's settings, small enough to compare before and after an update.
public struct SettingsFingerprint: Codable, Equatable {
    public struct ZoneInfo: Codable, Equatable { var name: String; var networks: [String]; var upper: Int; var lower: Int; var hasPlace: Bool }
    public var zones: [ZoneInfo]
    public var defaultUpper: Int
    public var defaultLower: Int
    /// Nil while the helper isn't answering, so a missing helper is never reported as lost settings.
    public var readyBy: ChargeSchedule?

    public init(config: Config, readyBy: ChargeSchedule?) {
        zones = config.zones.map { ZoneInfo(name: $0.name, networks: $0.networks, upper: $0.upper, lower: $0.lower, hasPlace: $0.place != nil) }
        defaultUpper = config.defaultUpper; defaultLower = config.defaultLower
        self.readyBy = readyBy.map { var r = $0; r.ran = []; r.wakeAt = nil; return r }   // bookkeeping changes on its own
    }

    /// Plain-words differences between what was saved before an update and what is there now. Empty means nothing changed.
    public func differences(to now: SettingsFingerprint) -> [String] {
        var out: [String] = []
        if zones != now.zones {
            if zones.count != now.zones.count { out.append("zones: \(zones.count) before, \(now.zones.count) now") }
            else { out.append("a zone's name, Wi-Fi, place or limits") }
        }
        if (defaultUpper, defaultLower) != (now.defaultUpper, now.defaultLower) { out.append("the \"Everywhere else\" limits") }
        if let a = readyBy, let b = now.readyBy, a != b { out.append("Ready by") }
        return out
    }
}

public struct BackupInfo: Equatable, Identifiable {
    public var url: URL
    public var version: String
    public var date: Date
    public var id: String { url.lastPathComponent }
}

/// Copies of config.json taken whenever the app version changes (and before a restore), so an update or a bad edit can be undone.
public struct BackupStore {
    public var directory: URL
    public var keep = 5
    public init(directory: URL = Config.url.deletingLastPathComponent().appendingPathComponent("Backups")) { self.directory = directory }

    private static func stamp(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyyMMdd-HHmmss"; return f.string(from: d)
    }

    /// Writes `data` as a new backup tagged with the version it came from. Returns nil if there was nothing to save.
    @discardableResult
    public func save(_ data: Data, version: String, date: Date = Date()) -> BackupInfo? {
        guard !data.isEmpty else { return nil }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("config-\(version)-\(Self.stamp(date)).json")
        guard (try? data.write(to: url)) != nil else { return nil }
        prune()
        return BackupInfo(url: url, version: version, date: date)
    }

    /// Newest first.
    public func list() -> [BackupInfo] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files.compactMap { u -> BackupInfo? in
            let n = u.deletingPathExtension().lastPathComponent
            guard n.hasPrefix("config-") else { return nil }
            let parts = n.dropFirst(7).split(separator: "-", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            let date = (try? u.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return BackupInfo(url: u, version: parts[0], date: date)
        }.sorted { $0.date > $1.date || ($0.date == $1.date && $0.id > $1.id) }
    }

    func prune() { for b in list().dropFirst(keep) { try? FileManager.default.removeItem(at: b.url) } }

    /// The settings in a backup, or nil if the file can't be read.
    public func load(_ b: BackupInfo) -> Config? {
        (try? Data(contentsOf: b.url)).flatMap { try? JSONDecoder().decode(Config.self, from: $0) }?.sanitized()
    }
}
