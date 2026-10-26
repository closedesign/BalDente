import Foundation

/// Finds the newest published BalDente release. Pure parsing here; the app does the one HTTPS request.
public enum UpdateCheck {
    public static let releasesURL = URL(string: "https://api.github.com/repos/closedesign/BalDente/releases?per_page=10")!
    public static let releasesPage = URL(string: "https://github.com/closedesign/BalDente/releases/latest")!
    /// Automatic checks run at most this often.
    public static let interval: TimeInterval = 24 * 3600

    public struct Release: Equatable {
        public var version: String
        public var page: URL
        /// The BalDente.dmg attached to the release, when there is one (only accepted from this project's own releases).
        public var dmg: URL?
    }

    static let downloadPrefix = "https://github.com/closedesign/BalDente/releases/download/"

    /// Highest non-draft release in a GitHub `/releases` response (pre-releases count: BalDente ships as pre-release until 1.0).
    public static func latest(from data: Data) -> Release? {
        struct Asset: Decodable { var name: String; var browser_download_url: String }
        struct Item: Decodable { var tag_name: String; var html_url: String; var draft: Bool?; var assets: [Asset]? }
        guard let items = try? JSONDecoder().decode([Item].self, from: data) else { return nil }
        var best: Release?
        for i in items where i.draft != true {
            let v = i.tag_name.hasPrefix("v") ? String(i.tag_name.dropFirst()) : i.tag_name
            guard WhatsNew.isRelease(v), let url = URL(string: i.html_url) else { continue }
            if best == nil || WhatsNew.compare(v, best!.version) == .orderedDescending { 
                let dmg = i.assets?.first { $0.name.hasSuffix(".dmg") && $0.browser_download_url.hasPrefix(downloadPrefix) }
                    .flatMap { URL(string: $0.browser_download_url) }
                best = Release(version: v, page: url, dmg: dmg)
            }
        }
        return best
    }

    public static func isNewer(_ release: Release, than current: String) -> Bool {
        WhatsNew.isRelease(current) && WhatsNew.compare(release.version, current) == .orderedDescending
    }

    public static func due(lastCheck: Date?, now: Date = Date()) -> Bool {
        guard let last = lastCheck else { return true }
        return now.timeIntervalSince(last) >= interval || last > now
    }
}
