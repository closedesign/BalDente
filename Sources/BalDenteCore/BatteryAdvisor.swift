import Foundation
import IOKit

/// Which Mac this is, read from the IORegistry (no process spawn, no root).
public struct MacProfile: Equatable {
    public var productName: String      // e.g. "MacBook Pro"
    public var modelID: String          // e.g. "Mac16,1"
    public var appleSilicon: Bool

    public init(productName: String, modelID: String, appleSilicon: Bool) {
        self.productName = productName; self.modelID = modelID; self.appleSilicon = appleSilicon
    }

    public static func current() -> MacProfile {
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        defer { if svc != 0 { IOObjectRelease(svc) } }
        func str(_ key: String) -> String? {
            guard svc != 0, let d = IORegistryEntryCreateCFProperty(svc, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else { return nil }
            if let data = d as? Data { return String(decoding: data.prefix { $0 != 0 }, as: UTF8.self) }
            return d as? String
        }
        var arm: Int32 = 0; var size = MemoryLayout<Int32>.size
        sysctlbyname("hw.optional.arm64", &arm, &size, nil, 0)
        return MacProfile(productName: str("product-name") ?? "Mac", modelID: str("model") ?? "Unknown", appleSilicon: arm == 1)
    }

    public var isNotebook: Bool { productName.contains("MacBook") }

    /// Apple's published maximum cycle count. Apple lists 1000 for every notebook that runs current macOS; only
    /// pre-2010 machines (300 or 500) differ and none of them can run this app.
    public var ratedCycles: Int { 1000 }
}

public struct AdvisorTip: Equatable, Identifiable {
    public enum Level { case good, info, warn }
    public var id: String
    public var level: Level
    public var title: String
    public var detail: String
}

public enum BatteryAdvisor {
    /// Apple: "designed to retain up to 80% of its original charge capacity at its maximum cycle count".
    public static let designRetention = 80

    public static let sources: [(title: String, url: String)] = [
        ("Apple: Determine battery cycle count for Mac notebooks", "https://support.apple.com/en-us/102888"),
        ("Apple: Maximizing battery lifespan", "https://www.apple.com/batteries/maximizing-performance/"),
    ]

    /// Months until the rated cycle count at the observed pace, or nil without a usable pace.
    public static func monthsToRating(cycles: Int, rated: Int, cyclesPerMonth: Double?) -> Double? {
        guard let r = cyclesPerMonth, r > 0.05 else { return nil }
        return Double(max(0, rated - cycles)) / r
    }

    /// Cycles per 30 days from the first and last logged cycle counts.
    public static func cyclesPerMonth(_ points: [HistoryPoint]) -> Double? {
        let c = points.compactMap { p in p.cycles.map { (p.date, $0) } }
        guard let a = c.first, let b = c.last else { return nil }
        let days = b.0.timeIntervalSince(a.0) / 86400
        guard days >= 7, b.1 >= a.1 else { return nil }
        return Double(b.1 - a.1) / days * 30
    }

    public static func tips(profile: MacProfile, cycles: Int, health: Int?, tempC: Double?, upperLimit: Int, cyclesPerMonth: Double?) -> [AdvisorTip] {
        var out: [AdvisorTip] = []
        let rated = profile.ratedCycles
        let used = min(100, cycles * 100 / rated)
        var budget = "\(cycles) of \(rated) rated cycles used (\(used)%)."
        if let m = monthsToRating(cycles: cycles, rated: rated, cyclesPerMonth: cyclesPerMonth) {
            budget += m > 120 ? " At your pace that is more than ten years away." : String(format: " At your pace you reach it in about %.0f months.", m)
        }
        out.append(AdvisorTip(id: "cycles", level: used >= 90 ? .warn : .info, title: "Cycle budget",
                              detail: budget + " Apple designs this \(profile.productName) to keep \(designRetention)% capacity at \(rated) cycles."))
        if let h = health {
            if h < designRetention {
                out.append(AdvisorTip(id: "health", level: .warn, title: "Below Apple's design point",
                                      detail: "Health is \(h)%, under the \(designRetention)% Apple targets at the rated cycle count. If the battery is service-eligible, Apple Support can check it."))
            } else if cycles < rated / 2 && h < 85 {
                out.append(AdvisorTip(id: "wear", level: .warn, title: "Wearing faster than designed",
                                      detail: "\(h)% health after only \(cycles) cycles. Heat is the usual cause; keep it cool and avoid sitting at 100% while hot."))
            } else {
                out.append(AdvisorTip(id: "health", level: .good, title: "Health on track", detail: "\(h)% after \(cycles) cycles is within Apple's design curve."))
            }
        }
        if upperLimit >= 95 {
            out.append(AdvisorTip(id: "limit", level: .info, title: "Limit is near full",
                                  detail: "Holding at \(upperLimit)% for long stretches stresses lithium-ion cells. For desk use, a zone that stops at 80% keeps most of the benefit; use 100% only when you need the runtime."))
        }
        if let t = tempC, t >= 35 {
            out.append(AdvisorTip(id: "heat", level: .warn, title: "Battery is warm",
                                  detail: String(format: "%.0f°C now. Apple rates Macs for 10–35°C ambient; keep Heat Protection on and avoid charging in direct sun or on soft surfaces.", t)))
        }
        out.append(AdvisorTip(id: "storage", level: .info, title: "Long-term storage",
                              detail: "Apple advises about 50% charge, powered off, somewhere cool and dry below 32°C, and a recharge to 50% every six months."))
        return out
    }
}
