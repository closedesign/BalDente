import BalDenteCore
import Charts
import SwiftUI

/// Battery health and cycle count over time, from the once-a-day log. The file is read only while this page is open.
struct HistoryPage: View {
    @ObservedObject var model: Model
    @State private var points: [HistoryPoint] = []
    @State private var loaded = false
    @State private var confirmReset = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !loaded { ProgressView().controlSize(.small) } else { advisor }
            if loaded {
                if points.count < 2 {
                SettingsGroup("Battery History") {
                    Text(points.isEmpty ? "No history yet." : "One day recorded so far.")
                    Text("BalDente adds one row a day while it runs. Check back in a few days to see health and cycles trend.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            } else {
                summary
                chart("Battery health", "heart.fill", .red, \.health, unit: "%", zero: false, marks: model.calibrationDates)
                if !model.calibrationDates.isEmpty { calibrations }
                chart("Cycle count", "arrow.triangle.2.circlepath", .blue, \.cycles, unit: "", zero: false)
            }
            }
            if loaded && !points.isEmpty { manage }
            Text("Stored in ~/Library/Application Support/BalDente/daily-log.csv.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .task { await load() }
    }

    private func load() async {
        let csv = await Task.detached { try? String(contentsOf: Model.historyURL, encoding: .utf8) }.value
        points = HealthHistory.downsample(HealthHistory.parse(csv ?? ""), max: 200)
        loaded = true
    }

    private var manage: some View {
        SettingsGroup("Manage History") {
            SettingRow("square.and.arrow.up", .blue, "Export history", "Save the daily log as a CSV file.") {
                Button("Export…") { model.exportHistory() }
            }
            SettingRow("arrow.counterclockwise", .red, "Reset history", "Start a fresh log, for example after a battery replacement.") {
                Button("Reset…", role: .destructive) { confirmReset = true }
            }
        }
        .confirmationDialog("Delete all battery history?", isPresented: $confirmReset) {
            Button("Delete History", role: .destructive) { model.resetHistory(); Task { await load() } }
        } message: { Text("This can't be undone. Export first if you want a copy.") }
    }

    /// Per-Mac guidance. Cycle rating and design retention are Apple's published figures; see `BatteryAdvisor.sources`.
    private var advisor: some View {
        let tips = BatteryAdvisor.tips(profile: model.mac, cycles: model.info?.cycles ?? 0, health: model.info?.healthPercent,
                                       tempC: model.info?.tempC, upperLimit: model.target.upper,
                                       cyclesPerMonth: BatteryAdvisor.cyclesPerMonth(points))
        return VStack(alignment: .leading, spacing: 10) {
            Label("Battery Health Advisor", systemImage: "heart.text.square.fill").font(.system(size: 16, weight: .bold, design: .rounded))
            Text("\(model.mac.productName) · \(model.mac.modelID) · \(model.mac.appleSilicon ? "Apple silicon" : "Intel")")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(tips) { t in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: t.level == .warn ? "exclamationmark.triangle.fill" : t.level == .good ? "checkmark.circle.fill" : "info.circle.fill")
                        .foregroundStyle(t.level == .warn ? Color.orange : t.level == .good ? Color.green : Color.blue)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(t.title).font(.callout.weight(.semibold))
                        Text(t.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            HStack(spacing: 10) {
                ForEach(BatteryAdvisor.sources, id: \.url) { s in
                    if let u = URL(string: s.url) { Link(s.title, destination: u).font(.caption2) }
                }
            }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(.pink.opacity(0.1)), in: .rect(cornerRadius: 26))
        .settingAnchor("Battery Health Advisor")
    }

    private var summary: some View {
        let m = HealthHistory.summary(points)
        return HStack(spacing: 12) {
            tile("Health now", (model.info?.healthPercent ?? m.healthNow).map { "\($0)%" } ?? "–", "heart.fill")
            tile("Change", m.healthDelta.map { String(format: "%+d%% in %d days", $0, m.healthDays ?? 1) } ?? "–", "chart.line.downtrend.xyaxis")
            tile("To \(HealthHistory.projectionTarget)% health", m.daysToTarget.map(Self.projection) ?? "–", "calendar.badge.clock")
            tile("Cycles added", m.cyclesAdded.map { "+\($0)" } ?? "–", "arrow.triangle.2.circlepath")
        }
    }

    /// Each completed calibration with the health reading from the day before and the day after, so you can see whether it changed.
    private var calibrations: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Calibrations", systemImage: "gauge.with.dots.needle.50percent").font(.system(size: 16, weight: .bold, design: .rounded))
            ForEach(CalibrationHistory.entries(dates: model.calibrationDates, points: points).prefix(6), id: \.date) { e in
                HStack {
                    Text(e.date.formatted(date: .abbreviated, time: .omitted)).font(.callout)
                    Spacer()
                    Text(Self.healthChange(e)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            Text("Dashed lines on the health chart mark them. Health is measured by the battery itself, so a calibration mostly fixes the percentage, not the capacity.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(.purple.opacity(0.1)), in: .rect(cornerRadius: 26))
    }

    private static func healthChange(_ e: CalibrationEntry) -> String {
        switch (e.before, e.after) {
        case (let b?, let a?): return "Health \(b)% → \(a)%"
        case (let b?, nil): return "Health \(b)% before, next reading tomorrow"
        case (nil, let a?): return "Health \(a)% after"
        default: return "No health reading yet"
        }
    }

    private static func projection(_ days: Int) -> String {
        days == 0 ? "Reached" : days < 60 ? "~\(days) days" : days < 730 ? "~\(days / 30) months" : String(format: "~%.1f years", Double(days) / 365)
    }

    private func tile(_ t: String, _ v: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(t, systemImage: icon).font(.caption).foregroundStyle(.secondary)
            Text(v).font(.system(size: 20, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(14).glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    /// A flat series would otherwise get a 0 to 200 axis and look like nothing; pad the real range instead.
    private func domain(_ v: [Int]) -> ClosedRange<Int> {
        guard let lo = v.min(), let hi = v.max() else { return 0...1 }
        let pad = max(2, (hi - lo) / 5)
        return (lo - pad)...(hi + pad)
    }

    private func chart(_ title: String, _ icon: String, _ tint: Color, _ value: KeyPath<HistoryPoint, Int?>, unit: String, zero: Bool, marks: [Date] = []) -> some View {
        let data = points.compactMap { p in p[keyPath: value].map { (p.date, $0) } }
        return VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.system(size: 16, weight: .bold, design: .rounded))
            Chart(data, id: \.0) { d in
                LineMark(x: .value("Date", d.0), y: .value(title, d.1)).foregroundStyle(tint).interpolationMethod(.monotone)
                AreaMark(x: .value("Date", d.0), y: .value(title, d.1)).foregroundStyle(tint.opacity(0.15)).interpolationMethod(.monotone)
                ForEach(marks.filter { m in data.first.map { m >= $0.0 } ?? false }, id: \.self) { m in
                    RuleMark(x: .value("Calibrated", m)).foregroundStyle(.purple.opacity(0.7)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            }
            .chartYScale(domain: domain(data.map(\.1)))
            .frame(height: 170)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(tint.opacity(0.1)), in: .rect(cornerRadius: 26))
    }
}
