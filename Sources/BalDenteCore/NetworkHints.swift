import Foundation

/// One day the Mac was on a Wi-Fi network that no zone knows. At most one per network per day.
public struct NetworkSighting: Codable, Equatable {
    public var network: String
    public var day: String
    public var weekday: Int
    public var date: Date

    public init(network: String, date: Date, calendar cal: Calendar = .current) {
        self.network = network; self.date = date
        let c = cal.dateComponents([.year, .month, .day, .weekday], from: date)
        day = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        weekday = c.weekday ?? 1
    }
}

/// The last four weeks of unknown networks, kept on this Mac (network-habits.json).
public struct NetworkLog: Codable, Equatable {
    public var sightings: [NetworkSighting] = []
    public init(sightings: [NetworkSighting] = []) { self.sightings = sightings }

    public static let maxDays = 28
    static let maxSightings = 400

    public mutating func record(_ network: String, at date: Date = Date(), calendar cal: Calendar = .current) {
        let s = NetworkSighting(network: network, date: date, calendar: cal)
        if !sightings.contains(where: { $0.day == s.day && $0.network.lowercased() == network.lowercased() }) { sightings.append(s) }
        let cutoff = date.addingTimeInterval(-Double(Self.maxDays) * 86400)
        sightings = Array(sightings.filter { $0.date >= cutoff }.suffix(Self.maxSightings))
    }
}

/// "You're on “CafeNet” most Tuesdays. Add it to a zone?" Suggest only; adding is always the user's tap.
public struct NetworkSuggestion: Equatable {
    public var network: String
    public var days: Int
    /// Weekdays (1 = Sunday ... 7 = Saturday) it showed up on at least twice.
    public var weekdays: [Int]

    public func question(calendar cal: Calendar = .current) -> String {
        let when: String
        if weekdays.isEmpty { when = "on \(days) days lately" }
        else {
            switch HabitPlanner.dayList(weekdays, calendar: cal) {
            case "every day": when = "almost every day"
            case "weekdays": when = "most weekdays"
            case "weekends": when = "most weekends"
            case let list: when = "most \(list)"
            }
        }
        return "You're on “\(network)” \(when). Add it to a zone so its limit switches automatically?"
    }
}

public enum NetworkHints {
    /// Seen on this many different days...
    public static let minDays = 4
    /// ...spread over at least this many days, so a long weekend away doesn't count as a routine.
    public static let minSpanDays = 7

    /// The Wi-Fi name among the current identifiers: not a router address ("gw:…") and not a BSSID (a MAC address).
    public static func wifiName(_ ids: [String]) -> String? {
        ids.first { id in
            guard !id.hasPrefix("gw:") else { return false }
            let parts = id.split(separator: ":", omittingEmptySubsequences: false)
            let isMAC = parts.count == 6 && parts.allSatisfy { $0.count <= 2 && !$0.isEmpty && $0.allSatisfy(\.isHexDigit) }
            return !isMAC && !id.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    public static func suggest(_ log: NetworkLog, config: Config, dismissed: Set<String> = []) -> NetworkSuggestion? {
        let known = Set(config.zones.flatMap(\.networks).map { $0.lowercased() })
        let byNetwork = Dictionary(grouping: log.sightings) { $0.network.lowercased() }
        let candidates: [NetworkSuggestion] = byNetwork.compactMap { key, seen in
            guard !known.contains(key), !dismissed.contains(key), seen.count >= minDays,
                  let first = seen.map(\.date).min(), let last = seen.map(\.date).max(),
                  last.timeIntervalSince(first) >= Double(minSpanDays - 1) * 86400 else { return nil }
            let counts = Dictionary(grouping: seen, by: \.weekday).filter { $0.value.count >= 2 }
            return NetworkSuggestion(network: seen.last!.network, days: seen.count, weekdays: counts.keys.sorted())
        }
        return candidates.max { ($0.days, $1.network) < ($1.days, $0.network) }
    }
}
