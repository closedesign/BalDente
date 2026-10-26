import Foundation

/// Builds the What's New sheet from the bundled CHANGELOG.md.
public enum WhatsNew {
    /// The bullet lines under `## <version>` (a heading like "## 0.6 (pre-release)" matches "0.6"), up to the next heading.
    /// Continuation lines are joined onto their bullet. Nil when there's no such section or it's empty.
    public static func items(for version: String, in changelog: String) -> [String]? {
        var inside = false, out: [String] = []
        for raw in changelog.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("## ") {
                if inside { break }
                let head = line.dropFirst(3).split(separator: " ").first.map(String.init) ?? ""
                inside = head == version || head == "v" + version
                continue
            }
            guard inside, !line.isEmpty else { continue }
            if line.hasPrefix("- ") || line.hasPrefix("* ") { out.append(String(line.dropFirst(2))) }
            else if !out.isEmpty { out[out.count - 1] += " " + line }
        }
        return out.isEmpty ? nil : out
    }

    /// Whether to show the sheet for `current`. Never on a first install (the tutorial covers that) or for dev builds,
    /// and only when the version moved forward since the last one shown.
    public static func shouldShow(current: String, lastSeen: String?, firstLaunch: Bool) -> Bool {
        guard !firstLaunch, isRelease(current) else { return false }
        guard let last = lastSeen else { return true }      // upgraded from a version that didn't record this
        return compare(current, last) == .orderedDescending
    }

    static func isRelease(_ v: String) -> Bool { !v.isEmpty && v.allSatisfy { $0.isNumber || $0 == "." } }

    /// Numeric, dot-separated comparison: 0.10 is newer than 0.9.
    public static func compare(_ a: String, _ b: String) -> ComparisonResult {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l < r ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }
}
