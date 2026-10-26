import Foundation

/// How far an update download has got, with the wording shown under the progress bar.
public struct DownloadProgress: Equatable, Sendable {
    public var written: Int64
    public var total: Int64?
    public var elapsed: TimeInterval

    public init(written: Int64, total: Int64?, elapsed: TimeInterval) {
        self.written = max(0, written); self.total = total.flatMap { $0 > 0 ? $0 : nil }; self.elapsed = max(0, elapsed)
    }

    /// 0...1, or nil when the server didn't say how big the file is.
    public var fraction: Double? { total.map { min(1, Double(written) / Double($0)) } }

    /// Average bytes per second so far (nil in the first instants, when it would be noise).
    public var bytesPerSecond: Double? { elapsed >= 0.5 && written > 0 ? Double(written) / elapsed : nil }

    public static func size(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1_000_000
        return mb >= 1 ? String(format: "%.1f MB", mb) : String(format: "%.0f KB", Double(bytes) / 1000)
    }

    /// "42% · 19.1 of 45.6 MB · 2.4 MB/s", dropping the parts that aren't known yet.
    public var label: String {
        var parts: [String] = []
        if let f = fraction { parts.append("\(Int(f * 100))%") }
        parts.append(total.map { "\(Self.size(written)) of \(Self.size($0))" } ?? Self.size(written))
        if let s = bytesPerSecond { parts.append("\(Self.size(Int64(s)))/s") }
        return parts.joined(separator: " · ")
    }
}
