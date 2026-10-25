import BalDenteCore
import Combine
import CoreLocation
import Foundation
import Network
import ServiceManagement
import SwiftUI
import UserNotifications

@MainActor
final class Model: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var config = Config.load() {
        didSet {
            fixOverride(old: oldValue)
            config.save()
            if oldValue.zones.map(\.place) != config.zones.map(\.place) { syncRegions() }
            var same = oldValue; same.appearance = config.appearance
            if same != config { refreshStatus() }     // appearance tweaks must not trigger daemon traffic
        }
    }
    @Published var status: Status?
    @Published var networks: [String] = []
    @Published var inside: Set<UUID> = []             // zones whose map circle we're currently in
    @Published var target = Target(label: "Default", upper: 80, lower: 75)
    @Published var topUp = false
    /// Travel mode: hold 100% until this moment, then return to the zone's limit. Survives a relaunch.
    @Published var travelUntil: Date? = UserDefaults.standard.object(forKey: "travelUntil") as? Date {
        didSet { UserDefaults.standard.set(travelUntil, forKey: "travelUntil"); refreshStatus() }
    }
    let calendar = CalendarReady()
    private var offlineSince: Date?
    @Published var locationAllowed = false
    @Published var captureMessage: String?
    @Published var info: BatteryInfo?
    let mac = MacProfile.current()
    @Published var helperInstalled = Installer.installed
    @Published var helperOutdated = false
    @Published var busy = false
    @Published var setupError: String?
    /// Menu bar icon and status panel settings.
    @Published var trio = TrioPrefs.load() { didSet { if trio != oldValue { trio.save() } } }
    @Published var panelOpen = false
    /// Which page of the main window is showing, what's typed in its search box, and the setting to flash after a search jump.
    @Published var page = SettingsPage.overview
    /// Set by Overview's Ready by card so the Charging page opens the editor straight away (one click, not two).
    @Published var readyByRequested = false
    @Published var query = ""
    @Published var focus: String?
    let system = SystemMonitor()
    private(set) var statusController: StatusItemController?
    private var lastLabel: String?
    private var lastZoneID: UUID?
    private var lastHeatHold = false
    private var switchNotice: Task<Void, Never>?

    private let location = CLLocationManager()
    private let monitor = NWPathMonitor()
    private var timer: Timer?
    private var networkTask: Task<Void, Never>?
    private var pendingCapture: UUID?
    private var lastSent: Target?
    /// The daemon can take up to a few seconds to answer when it's busy, so every call to it runs here, in order, never on the main thread.
    private let daemonQueue = DispatchQueue(label: "baldente.daemon-io")
    private var refreshInFlight = false
    private var refreshAgain = false

    var appearance: Appearance {
        get { config.appearance ?? Appearance() }
        set { config.appearance = newValue }
    }

    override init() {
        super.init()
        location.delegate = self
        location.desiredAccuracy = kCLLocationAccuracyHundredMeters   // coarse is enough and costs less
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        location.requestAlwaysAuthorization()
        // Network lookups happen only when the network changes (debounced), never on a timer.
        monitor.pathUpdateHandler = { [weak self] _ in Task { @MainActor in self?.scheduleNetworkRefresh() } }
        monitor.start(queue: .global(qos: .utility))
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshStatus() }
        }
        timer?.tolerance = 5      // lets macOS batch our wakeups with others
        syncRegions()
        scheduleNetworkRefresh()
        refreshStatus()
        // The status item needs a running NSApplication, so it's made once launch has finished.
        DispatchQueue.main.async { [self] in statusController = StatusItemController(model: self) }
        calendar.model = self; calendar.resumeIfEnabled()
        // The battery percentage and charging state move the ring and headline; follow them between daemon polls.
        system.$power.removeDuplicates().dropFirst().sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &bag)
    }

    private var bag: Set<AnyCancellable> = []

    func requestLocation() {
        if location.authorizationStatus == .denied || location.authorizationStatus == .restricted { SystemPane.open(SystemPane.location) }
        else { location.requestAlwaysAuthorization() }
    }

    func setLowPowerMode(_ on: Bool) {
        cmd("lowpower \(on ? "on" : "off")")
        Task { try? await Task.sleep(for: .seconds(1)); system.refreshPower() }
    }

    /// The level that fills the menu bar ring: 100%, or the active charge limit when the user asked for that.
    var ringFullLevel: Int { trio.fullFollowsLimit ? target.upper : trio.fullLevel }

    // MARK: Zone detection

    private func scheduleNetworkRefresh() {
        networkTask?.cancel()
        networkTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            let ids = await NetworkInfo.current()
            guard !Task.isCancelled else { return }
            if ids != networks { networks = ids }
            refreshStatus()
        }
    }

    /// Region monitoring is done by macOS itself: no polling and no continuous location use on our side.
    private func syncRegions() {
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }
        let wanted: [CLCircularRegion] = config.zones.compactMap { z in
            guard let p = z.place else { return nil }
            let r = CLCircularRegion(center: CLLocationCoordinate2D(latitude: p.latitude, longitude: p.longitude),
                                     radius: min(max(p.radius, 100), location.maximumRegionMonitoringDistance),
                                     identifier: z.id.uuidString)
            r.notifyOnEntry = true; r.notifyOnExit = true
            return r
        }
        let ids = Set(wanted.map(\.identifier))
        for r in location.monitoredRegions where !ids.contains(r.identifier) {
            location.stopMonitoring(for: r)
            if let u = UUID(uuidString: r.identifier) { inside.remove(u) }
        }
        for r in wanted { location.startMonitoring(for: r); location.requestState(for: r) }
    }

    func captureLocation(for id: UUID) {
        pendingCapture = id; captureMessage = "Finding your location…"
        location.requestLocation()   // one fix, then it stops
    }

    nonisolated func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        Task { @MainActor in
            locationAllowed = [.authorizedAlways, .authorized].contains(m.authorizationStatus)
            syncRegions(); scheduleNetworkRefresh()
        }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        let id = region.identifier
        Task { @MainActor in setInside(id, state == .inside) }
    }
    nonisolated func locationManager(_ m: CLLocationManager, didEnterRegion region: CLRegion) {
        let id = region.identifier
        Task { @MainActor in setInside(id, true) }
    }
    nonisolated func locationManager(_ m: CLLocationManager, didExitRegion region: CLRegion) {
        let id = region.identifier
        Task { @MainActor in setInside(id, false) }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        guard let l = locs.last else { return }
        Task { @MainActor in
            guard let id = pendingCapture, let i = config.zones.firstIndex(where: { $0.id == id }) else { return }
            pendingCapture = nil
            let radius = max(150, l.horizontalAccuracy)
            config.zones[i].place = Place(latitude: l.coordinate.latitude, longitude: l.coordinate.longitude, radius: radius)
            captureMessage = "Saved (accuracy about \(Int(l.horizontalAccuracy)) m)"
        }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            if pendingCapture != nil { pendingCapture = nil; captureMessage = "Couldn't get a location. Check Location Services in System Settings." }
        }
    }

    private func setInside(_ id: String, _ on: Bool) {
        guard let u = UUID(uuidString: id) else { return }
        if on { inside.insert(u) } else { inside.remove(u) }
        refreshStatus()
    }

    /// Keep a pinned zone pinned when it's renamed, and unpin it if it's deleted.
    private func fixOverride(old: Config) {
        guard let o = config.overrideZone else { return }
        if let renamed = config.zones.first(where: { z in old.zones.contains { $0.id == z.id && $0.name == o && $0.name != z.name } }) {
            config.overrideZone = renamed.name
        } else if !config.zones.contains(where: { $0.name == o }) {
            config.overrideZone = nil
        }
    }

    // MARK: Status and limits

    func refresh() { refreshStatus() }

    /// Reads the battery and zone locally, asks the daemon for its status off the main thread, then finishes in `apply(_:)`.
    func refreshStatus() {
        info = BatteryInfo.read()
        helperInstalled = Installer.installed
        helperOutdated = Installer.outdated
        if ProcessInfo.processInfo.environment["BALDENTE_DEMO"] != nil {
            status = Status(percent: 62, adapterOn: false, state: LimiterState(), backend: "demo", tempC: 33.4)
            target = resolveZone(config, networks: networks, inside: inside); return
        }
        // A refresh already waiting on the daemon will see our changes too; just ask it to go around once more.
        if refreshInFlight { refreshAgain = true; return }
        refreshInFlight = true
        daemonQueue.async { [weak self] in
            let st = DaemonClient.status()
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.apply(st) } }
        }
    }

    private func apply(_ fresh: Status?) {
        status = fresh
        // The daemon reports -1 when it can't read the SMC percentage; macOS's own figure is better than "-1%".
        if var s = status, s.percent < 0 { s.percent = system.power.percent; status = s }
        var t = resolveZone(config, networks: networks, inside: inside)
        if let end = travelUntil, end <= Date() { travelUntil = nil }
        if travelUntil != nil { t = Target(label: "Travel Mode", upper: 100, lower: 99) }
        else if topUp {
            if percent >= 100 { topUp = false } else { t = Target(label: "Top Up", upper: 100, lower: 99) }
        }
        target = t
        let label = t.label.replacingOccurrences(of: " ", with: "_")
        let needsSend = status.map { t != lastSent || $0.state.upper != t.upper || $0.state.lower != t.lower || $0.state.label != label } ?? false
        guard needsSend else { finishRefresh(); return }
        daemonQueue.async { [weak self] in
            let ok = DaemonClient.send("limit \(t.upper) \(t.lower) \(label)") == "ok"
            let st = ok ? DaemonClient.status() : nil
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if ok {
                        self.lastSent = t
                        if var s = st { if s.percent < 0 { s.percent = self.system.power.percent }; self.status = s }
                    }
                    self.finishRefresh()
                }
            }
        }
    }

    private func finishRefresh() {
        refreshInFlight = false
        smartChecks()
        sideEffects()
        if refreshAgain { refreshAgain = false; refreshStatus() }
    }

    /// Sends a command to the daemon, in order with every other one, then refreshes.
    func cmd(_ line: String) {
        daemonQueue.async { [weak self] in
            _ = DaemonClient.send(line)
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.refreshStatus() } }
        }
    }

    func setUp() {
        busy = true; setupError = nil
        Task {
            setupError = await Installer.install()
            // launchd can delay a restart by up to ~10s after earlier failed starts, so poll rather than check once.
            for _ in 0..<20 where setupError == nil {
                if await Task.detached(operation: { DaemonClient.status() }).value != nil { break }
                try? await Task.sleep(for: .seconds(1))
            }
            if setupError == nil, await Task.detached(operation: { DaemonClient.status() }).value == nil {
                setupError = "The helper installed but didn't start. Details: /var/log/baldente.log"
            }
            busy = false; refreshStatus()
        }
    }

    func removeHelper() {
        busy = true
        Task { setupError = await Installer.uninstall(); busy = false; refreshStatus() }
    }

    private func notify(_ title: String, _ body: String) {
        let c = UNMutableNotificationContent(); c.title = title; c.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }

    /// Fires notifications on zone and heat changes, and appends one health row per day.
    private func sideEffects() {
        // Renaming the active zone changes its label on every keystroke; only a different zone is a switch.
        // A short delay also lets quick back-and-forth changes (Wi-Fi roaming, toggling a pin) settle into one notice.
        let renamed = target.zoneID != nil && target.zoneID == lastZoneID
        if let l = lastLabel, l != target.label, status != nil, !renamed {
            let t = target
            switchNotice?.cancel()
            switchNotice = Task {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, target.label == t.label else { return }
                notify("Switched to \(t.label)", "Charging holds at \(t.upper)%, resumes at \(t.lower)%.")
            }
        }
        lastLabel = target.label
        lastZoneID = target.zoneID
        if let h = status?.heatHold, h != lastHeatHold {
            notify(h ? "Heat protection on" : "Cooled down",
                   h ? "Battery is hot, so charging is paused." : "Normal charging can continue.")
            lastHeatHold = h
        }
        guard let i = info, let s = status else { return }
        let day = dayString(Date())
        guard UserDefaults.standard.string(forKey: "lastLogDay") != day else { return }
        UserDefaults.standard.set(day, forKey: "lastLogDay")
        let url = Self.historyURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        checkHealthDrop(i.healthPercent)
        // Don't log a second row for a day already in the file (e.g. after the defaults key was reset).
        if let old = try? String(contentsOf: url, encoding: .utf8), old.split(whereSeparator: \.isNewline).last?.hasPrefix(day) == true { return }
        let row = "\(day),\(i.healthPercent.map(String.init) ?? ""),\(i.cycles),\(percent)\n"
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data(row.utf8)); try? h.close() }
        else { try? ("date,health_percent,cycles,battery_percent\n" + row).write(to: url, atomically: true, encoding: .utf8) }
    }

    static var historyURL: URL { Config.url.deletingLastPathComponent().appendingPathComponent("daily-log.csv") }

    /// Deletes the daily log and the health-drop baseline; the next refresh starts a fresh log (e.g. after a battery swap).
    func resetHistory() {
        try? FileManager.default.removeItem(at: Self.historyURL)
        let d = UserDefaults.standard
        for k in ["lastLogDay", "healthBaseline", "healthBaselineDate"] { d.removeObject(forKey: k) }
        sideEffects()
    }

    func exportHistory() {
        let p = NSSavePanel(); p.nameFieldStringValue = "BalDente-history.csv"; p.allowedContentTypes = [.commaSeparatedText]
        guard p.runModal() == .OK, let dest = p.url else { return }
        do { try? FileManager.default.removeItem(at: dest); try FileManager.default.copyItem(at: Self.historyURL, to: dest) }
        catch { setupError = "Couldn't export: \(error.localizedDescription)" }
    }

    /// Both checks ride on the refresh that already runs, so they cost nothing extra.
    private func smartChecks() {
        calendar.tick()
        guard trio.smartNotifications else { return }
        if status == nil, helperInstalled {
            // Time based, not count based: refreshes also fire on every network change, so a count would trip in seconds.
            let since = offlineSince ?? Date()
            offlineSince = since
            if Date().timeIntervalSince(since) > 120, UserDefaults.standard.object(forKey: "offlineNoticeFor") as? Date != since {
                UserDefaults.standard.set(since, forKey: "offlineNoticeFor")
                notify("BalDente's helper isn't answering", "Charging limits aren't being applied. Open BalDente > General to reinstall it.")
            }
        } else { offlineSince = nil }
    }

    /// Monthly: tell the user if battery health fell 2 points or more. Called from the once-a-day log.
    private func checkHealthDrop(_ health: Int?) {
        guard trio.smartNotifications, let h = health else { return }
        let d = UserDefaults.standard
        guard let base = d.object(forKey: "healthBaseline") as? Int, let since = d.object(forKey: "healthBaselineDate") as? Date else {
            d.set(h, forKey: "healthBaseline"); d.set(Date(), forKey: "healthBaselineDate"); return
        }
        guard Date().timeIntervalSince(since) > 30 * 86400 else { return }
        if base - h >= 2 { notify("Battery health dropped to \(h)%", "It was \(base)% a month ago. Lower limits and heat protection slow this down.") }
        d.set(h, forKey: "healthBaseline"); d.set(Date(), forKey: "healthBaselineDate")
    }

    func exportConfig() {
        let p = NSSavePanel(); p.nameFieldStringValue = "BalDente-settings.json"; p.allowedContentTypes = [.json]
        guard p.runModal() == .OK, let url = p.url else { return }
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        do { try enc.encode(config).write(to: url) } catch { setupError = "Couldn't export: \(error.localizedDescription)" }
    }

    func importConfig() {
        let p = NSOpenPanel(); p.allowedContentTypes = [.json]; p.allowsMultipleSelection = false
        guard p.runModal() == .OK, let url = p.url else { return }
        do { config = try JSONDecoder().decode(Config.self, from: Data(contentsOf: url)).sanitized() }
        catch { setupError = "That file isn't a BalDente settings export." }
    }

    /// Adds a zone with a name nobody else has, and returns it so the caller can open its editor.
    @discardableResult
    func addZone() -> Zone {
        let z = Zone(name: uniqueZoneName("New Zone", existing: config.zones.map(\.name)), upper: 80, lower: 75)
        config.zones.append(z)
        return z
    }

    /// Jumps to a page, optionally flashing one setting on it. Clears the search box so the page is visible.
    func go(_ p: SettingsPage, focus f: String? = nil) {
        query = ""
        page = p
        focus = f
        guard f != nil else { return }
        Task {
            try? await Task.sleep(for: .seconds(2.2))
            if focus == f { withAnimation(.easeOut(duration: 0.4)) { focus = nil } }
        }
    }

    func addCurrentNetwork(to id: UUID) {
        guard let i = config.zones.firstIndex(where: { $0.id == id }) else { return }
        for n in networks where !config.zones[i].networks.contains(n) { config.zones[i].networks.append(n) }
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            try? newValue ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
            objectWillChange.send()
        }
    }

    // MARK: Look and feel

    var palette: [Color] {
        let a = appearance
        switch a.mode {
        case "preset": return Theme.preset(a.preset)
        case "custom" where a.custom.count >= 3: return a.custom.prefix(3).map { Color(hex: $0) }
        default: return Theme.palette(target.label)
        }
    }
    var accent: Color { palette[0] }

    // MARK: Shared status wording

    var task: TaskState? { status?.state.task.active == true ? status?.state.task : nil }
    /// The charge level to show: the helper's reading, or macOS's own while the helper is offline (never a stuck 0%).
    var percent: Int { status?.percent ?? system.power.percent }
    /// The charger is cut off on purpose.
    var holding: Bool { status.map { !$0.adapterOn } ?? false }
    /// Whether the cable is out. With the CHIE key (this Mac's backend) macOS still reports "AC Power" while the charger is
    /// held off, so the plug state can be trusted; older keys make macOS report "Battery Power" for a held charger,
    /// so there "held" can't be told from "unplugged" and we assume held.
    var onBattery: Bool {
        guard system.power.present, !system.power.plugged else { return false }
        return !holding || status?.backend.contains("CHIE") == true
    }

    /// The small caption inside the battery rings.
    var ringCaption: (text: String, icon: String) {
        if onBattery { return ("On battery", "battery.75percent") }
        if holding { return ("Holding", "pause.fill") }
        if system.power.charging { return ("Charging", "bolt.fill") }
        if system.power.plugged { return ("Plugged in", "powerplug.fill") }
        return ("Not charging", "battery.75percent")
    }

    var headline: String {
        guard let s = status else { return "Helper offline" }
        if let t = task {
            if t.kind == "topup" { return t.phase == "hold" ? "Ready to go" : "Charging for your trip" }
            if t.kind == "discharge" { return "Discharging to \(t.target)%" }
            switch t.phase { case "discharge": return "Calibrating: draining"; case "charge": return "Calibrating: charging"; default: return "Calibrating: resting" }
        }
        if s.heatHold { return "Cooling down" }
        if onBattery { return "On battery" }
        return s.adapterOn ? "Charging to \(target.upper)%" : "Holding at \(percent)%"
    }

    var subline: String {
        guard status != nil else { return "Set up the background helper to take control of charging." }
        if let t = task {
            if t.kind == "topup" { return "Ready by is active, so zone limits are paused until you leave." }
            if t.kind == "discharge" { return "Charger is off until the battery reaches \(t.target)%." }
            return "Full cycle: 15%, then 100%, then a one-hour rest."
        }
        if status?.heatHold == true { return "Charging is paused until the battery cools down." }
        if onBattery { return "Plug in and BalDente charges to \(target.upper)%, then holds." }
        return holding ? "Charger paused. It comes back at \(target.lower)%."
                       : "Charger pauses when the battery reaches \(target.upper)%."
    }

    /// "Tue, Thu 11:00 to 100% · Wed 16:00 to 90%": days sharing a time and level are grouped.
    func readySummary(_ cs: ChargeSchedule) -> String {
        let order = [2, 3, 4, 5, 6, 7, 1]
        let names = Calendar.current.shortWeekdaySymbols
        let byKey = Dictionary(grouping: cs.slots) { String(format: "%02d:%02d to %d%%", $0.hour, $0.minute, $0.percent) }
        var text = byKey.keys.sorted().map { k in
            let days = (byKey[k] ?? []).map(\.weekday).sorted { order.firstIndex(of: $0)! < order.firstIndex(of: $1)! }
            return days.map { names[$0 - 1] }.joined(separator: ", ") + " " + k
        }.joined(separator: " · ")
        if let z = cs.onlyZone { text += " (\(z) only)" }
        return text
    }
}
