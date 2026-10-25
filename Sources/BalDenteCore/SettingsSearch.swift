import Foundation

/// One searchable setting: what it's called, what it does, and extra words people might type for it.
public struct SettingsItem: Equatable, Identifiable {
    public var id: String { page + "/" + title }
    public var title: String
    public var detail: String
    public var keywords: [String]
    /// The name of the page it lives on; also searchable, so typing "battery" lists everything under Battery.
    public var page: String
    /// What to scroll to and flash on that page. Defaults to the title; set it when the setting lives inside a bigger card or sheet.
    public var anchor: String

    public init(_ title: String, _ detail: String = "", keywords: [String] = [], page: String, anchor: String? = nil) {
        self.title = title; self.detail = detail; self.keywords = keywords; self.page = page; self.anchor = anchor ?? title
    }
}

public enum SettingsSearch {
    /// Case and accent blind, so "Wi-Fi", "wifi" and "WI-FI" all line up.
    static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "-", with: "")
    }

    /// Items matching every word of `query`, best first. Title matches beat keyword matches beat description matches;
    /// ties keep their original (page) order. An empty query matches nothing.
    public static func rank(_ items: [SettingsItem], query: String) -> [SettingsItem] {
        let words = fold(query).split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !words.isEmpty else { return [] }
        var scored: [(item: SettingsItem, score: Int, order: Int)] = []
        for (order, item) in items.enumerated() {
            let title = fold(item.title), detail = fold(item.detail), page = fold(item.page)
            let keywords = item.keywords.map(fold)
            var total = 0
            var matchedAll = true
            for w in words {
                let s: Int
                if title.hasPrefix(w) || title.split(separator: " ").contains(where: { $0.hasPrefix(w) }) { s = 100 }
                else if title.contains(w) { s = 70 }
                else if keywords.contains(where: { $0.contains(w) }) { s = 50 }
                else if page.contains(w) { s = 30 }
                else if detail.contains(w) { s = 20 }
                else { matchedAll = false; break }
                total += s
            }
            if matchedAll { scored.append((item, total, order)) }
        }
        return scored.sorted { $0.score != $1.score ? $0.score > $1.score : $0.order < $1.order }.map(\.item)
    }
}

/// A zone name that doesn't collide with any in `existing` ("New Zone", "New Zone 2", ...). Zones are pinned by name,
/// so two with the same name would both light up and the second could never be pinned.
public func uniqueZoneName(_ base: String, existing: [String]) -> String {
    let taken = Set(existing.map { $0.lowercased() })
    if !taken.contains(base.lowercased()) { return base }
    var n = 2
    while taken.contains("\(base) \(n)".lowercased()) { n += 1 }
    return "\(base) \(n)"
}
