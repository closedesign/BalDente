import BalDenteCore
import Combine
import CoreLocation
import Foundation
import Network
import ServiceManagement
import SwiftUI
import UserNotifications

@MainActor
final class Model: NSObject, ObservableObject, CLLocationManagerDelegate, UNUserNotificationCenterDelegate {
    @Published var config = Config.load() {
        didSet {
            fixOverride(old: oldValue)
            verifyAgainst = nil     // the user edited settings; a before/after comparison would be misleading
            config.save()
            if oldValue.zones.map(\.place) != config.zones.map(\.place) { syncRegions() }
            if networkSuggestion != nil, oldValue.zones.map(\.networks) != config.zones.map(\.networks) { evaluateNetworkHint() }
            if wearSuggestion != nil { evaluateWear() }
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
    /// Where the window opens: the page it was on last time.
    @Published var page = SettingsPage(rawValue: UserDefaults.standard.string(forKey: "lastPage") ?? "") ?? .overview {
        didSet { UserDefaults.standard.set(page.rawValue, forKey: "lastPage") }
    }
    @Published var settingsFileMessage = ""
    /// Set by Overview's Ready by card so the Charging page opens the editor straight away (one click, not two).
    @Published var readyByRequested = false
    @Published var query = ""
    @Published var focus: String?
    let system = SystemMonitor()
    private(set) var statusController: StatusItemController?
    private var lastLabel: String?
    private var lastZoneID: UUID?
    private var lastHeatHold = false
    private var lastHeatSkipped = false
    /// The last 30 minutes of battery temperature, drawn on the Overview while a heat hold is on.
    @Published private(set) var tempTrend = TempTrend()
    private var lastSkipKey: String?
    private var lastAutoDischarge: Date?
    private var lastOvernightCalibration: Date? {
        get { UserDefaults.standard.object(forKey: "overnightCalibrationAttempt") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "overnightCalibrationAttempt") }
    }
    private var lastTask: TaskState?
    /// When a calibration last ran its full course (not cancelled). Nil until one finishes with this version.
    @Published private(set) var calibrationDates: [Date] = {
        let d = UserDefaults.standard
        let saved = d.array(forKey: "calibrationDates") as? [Date] ?? []
        if saved.isEmpty, let old = d.object(forKey: "lastCalibration") as? Date { return [old] }
        return saved
    }()
    var lastCalibration: Date? { calibrationDates.max() }
    private var switchNotice: Task<Void, Never>?

    // MARK: Keeping the user informed (tutorial, defaults, habits, change log)

    /// No settings, log or tutorial marker from an earlier run: this is a fresh install. Decided once, before anything is saved.
    let firstLaunch: Bool
    @Published var showTutorial = false
    /// What's New lines for this version, shown once after an update.
    @Published var whatsNew: [String]?
    /// Every limit change with its reason, newest first. Persisted; shown as "Recent changes" on Overview.
    @Published private(set) var activity = ActivityLog.load()
    /// Categories the user muted. The log still records them.
    @Published var muted: Set<NotifyCategory> = Set((UserDefaults.standard.stringArray(forKey: "mutedNotifications") ?? []).compactMap(NotifyCategory.init)) {
        didSet { UserDefaults.standard.set(muted.map(\.rawValue).sorted(), forKey: "mutedNotifications") }
    }
    @Published var holdHint: HoldHint = (UserDefaults.standard.data(forKey: "holdHint")).flatMap { try? JSONDecoder().decode(HoldHint.self, from: $0) } ?? HoldHint() {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(holdHint), forKey: "holdHint") }
    }
    /// Learn unplug times and suggest a Ready by plan. Suggestions only: nothing is applied without Accept.
    // MARK: Updates (one request a day at most, only when the user leaves it on; never installs anything)
    @Published var autoUpdateCheck = UserDefaults.standard.object(forKey: "autoUpdateCheck") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoUpdateCheck, forKey: "autoUpdateCheck"); if autoUpdateCheck { checkForUpdates(manual: false) } }
    }
    @Published private(set) var updateStatus = ""
    @Published private(set) var availableUpdate: UpdateCheck.Release?
    @Published private(set) var checkingUpdates = false

    @Published private(set) var installingUpdate = false
    /// 0...1 while the update downloads; nil otherwise.
    @Published private(set) var updateProgress: DownloadProgress?
    private var updateTask: Task<Void, Never>?
    /// What the check after the last update found, in words. Empty until an update has happened.
    @Published private(set) var settingsCheck = ""
    @Published private(set) var backups: [BackupInfo] = []
    private let backupStore = BackupStore()
    /// Settings as the previous version left them; compared once the helper answers after an update.
    private var verifyAgainst: SettingsFingerprint?
    private static let fingerprintKey = "lastSettingsFingerprint"

    /// Stops a download in progress; nothing was installed yet, so there is nothing to undo.
    func cancelUpdateDownload() { if updateProgress != nil { updateTask?.cancel() } }

    func installUpdate() {
        guard let u = availableUpdate, let dmg = u.dmg, !installingUpdate else { return }
        installingUpdate = true
        updateTask = Task {
            do { try await UpdateInstaller.install(dmg: dmg, version: u.version) { [weak self] t in Task { @MainActor in self?.updateStatus = t } }
                progress: { [weak self] f in Task { @MainActor in self?.updateProgress = f } } }
            catch {
                installingUpdate = false
                updateProgress = nil
                updateStatus = (error as? UpdateInstaller.Failure)?.message ?? "The update couldn't be installed. Download it instead."
            }
        }
    }

    /// Called when the app version changes: keep a copy of the settings and remember what they were.
    private func beginUpdateVerification() {
        if let data = try? Data(contentsOf: Config.url) { backupStore.save(data, version: UserDefaults.standard.string(forKey: "lastVersionSeen") ?? "older") }
        backups = backupStore.list()
        readMacLimit()
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.readMacLimit() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.readMacLimit() }
        }
        verifyAgainst = UserDefaults.standard.data(forKey: Self.fingerprintKey).flatMap { try? JSONDecoder().decode(SettingsFingerprint.self, from: $0) }
    }

    /// Runs on every status update; cheap (a struct compare), writes only when something changed.
    private func trackSettings() {
        guard let s = status, s.backend != "demo" else { return }
        let now = SettingsFingerprint(config: config, readyBy: s.state.chargeSchedule)
        if let before = verifyAgainst {
            verifyAgainst = nil
            let diff = before.differences(to: now)
            if diff.isEmpty { settingsCheck = "Checked after the update: your zones, limits and Ready by are unchanged." }
            else {
                settingsCheck = "After the update these differ from before: " + diff.joined(separator: ", ") + ". A backup of the earlier settings is below."
                notify("Settings changed after update", settingsCheck)
            }
        }
        if let d = try? JSONEncoder().encode(now), d != UserDefaults.standard.data(forKey: Self.fingerprintKey) {
            UserDefaults.standard.set(d, forKey: Self.fingerprintKey)
        }
    }

    func restoreBackup(_ b: BackupInfo) {
        guard let restored = backupStore.load(b) else { setupError = "That backup can't be read."; return }
        if let data = try? Data(contentsOf: Config.url) { backupStore.save(data, version: "before-restore") }
        verifyAgainst = nil
        config = restored
        backups = backupStore.list()
    }

    func checkForUpdates(manual: Bool) {
        let d = UserDefaults.standard
        guard !checkingUpdates else { return }
        if !manual { guard autoUpdateCheck, UpdateCheck.due(lastCheck: d.object(forKey: "lastUpdateCheck") as? Date) else { return } }
        let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        checkingUpdates = true
        if manual { updateStatus = "Checking…" }
        var req = URLRequest(url: UpdateCheck.releasesURL, timeoutInterval: 15)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: req) { [weak self] data, resp, _ in
            let ok = (resp as? HTTPURLResponse)?.statusCode == 200
            let latest = ok ? data.flatMap(UpdateCheck.latest(from:)) : nil
            Task { @MainActor in
                guard let self else { return }
                self.checkingUpdates = false
                guard let latest else { if manual { self.updateStatus = "Couldn't check. Try again later." }; return }
                UserDefaults.standard.set(Date(), forKey: "lastUpdateCheck")
                if UpdateCheck.isNewer(latest, than: current) {
                    self.availableUpdate = latest
                    self.updateStatus = "Version \(latest.version) is available."
                } else {
                    self.availableUpdate = nil
                    self.updateStatus = "You're up to date (\(current))."
                }
            }
        }.resume()
    }

    @Published var habitsEnabled = UserDefaults.standard.object(forKey: "habitSuggestions") as? Bool ?? true {
        didSet { UserDefaults.standard.set(habitsEnabled, forKey: "habitSuggestions"); evaluateHabits(); evaluateNetworkHint() }
    }
    @Published private(set) var habitSuggestion: HabitSuggestion?
    /// A Wi-Fi network you're on regularly that no zone knows yet. Suggest only: adding it is the user's tap.
    @Published private(set) var networkSuggestion: NetworkSuggestion?
    private var networkLog = (try? Data(contentsOf: Model.networkLogURL)).flatMap { try? JSONDecoder().decode(NetworkLog.self, from: $0) } ?? NetworkLog()
    private var habits = Model.loadHabits()
    /// Time above 80% per zone this week. Not @Published: it changes every refresh and only History reads it.
    private(set) var zoneWear = (try? Data(contentsOf: Model.zoneWearURL)).flatMap { try? JSONDecoder().decode(ZoneWear.self, from: $0) } ?? ZoneWear()
    /// A zone that keeps the battery above 80% for many hours a week. Suggest only: lowering it is the user's tap.
    @Published private(set) var wearSuggestion: WearSuggestion?
    private var lastWearSample: Date?
    /// Hours the charger was cut while plugged in this week. Not @Published, like `zoneWear`: only History reads it.
    private(set) var batteryHold = (try? Data(contentsOf: Model.batteryHoldURL)).flatMap { try? JSONDecoder().decode(BatteryHold.self, from: $0) } ?? BatteryHold()
    private var holdUnsaved: TimeInterval = 0
    private var wearUnsaved: TimeInterval = 0
    /// An unplug waiting for a fresh status: with older SMC keys a held charger also looks unplugged, so it's confirmed first.
    private var pendingUnplug: Date?
    private var habitsChecked = false

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
        let d = UserDefaults.standard
        firstLaunch = !FileManager.default.fileExists(atPath: Config.url.path)
            && ["lastLogDay", TrioPrefs.key, "tutorialSeen", "lastVersionSeen", "defaultsChoiceMade"].allSatisfy { d.object(forKey: $0) == nil }
        super.init()
        prepareFirstRun()
        location.delegate = self
        location.desiredAccuracy = kCLLocationAccuracyHundredMeters   // coarse is enough and costs less
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        // A habit suggestion can be answered from the notification itself; Accept still goes through acceptHabit().
        center.setNotificationCategories([UNNotificationCategory(identifier: Self.habitCategory, actions: [
            UNNotificationAction(identifier: Self.acceptAction, title: "Accept"),
            UNNotificationAction(identifier: Self.snoozeAction, title: "Not now"),
        ], intentIdentifiers: [])])
        center.delegate = self
        location.requestAlwaysAuthorization()
        // Network lookups happen only when the network changes (debounced), never on a timer.
        monitor.pathUpdateHandler = { [weak self] _ in Task { @MainActor in self?.scheduleNetworkRefresh() } }
        monitor.start(queue: .global(qos: .utility))
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshStatus() }
        }
        timer?.tolerance = 5      // lets macOS batch our wakeups with others
        backups = backupStore.list()
        checkForUpdates(manual: false)
        syncRegions()
        scheduleNetworkRefresh()
        refreshStatus()
        // The status item needs a running NSApplication, so it's made once launch has finished.
        DispatchQueue.main.async { [self] in statusController = StatusItemController(model: self) }
        calendar.model = self; calendar.resumeIfEnabled()
        // The battery percentage and charging state move the ring and headline; follow them between daemon polls.
        system.$power.removeDuplicates().dropFirst().sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &bag)
        // Unplug and plug events feed habit learning; they arrive from IOKit, so this costs no polling.
        system.$power.map { $0.present ? $0.plugged : true }.removeDuplicates().dropFirst()
            .sink { [weak self] p in self?.pluggedChanged(p) }.store(in: &bag)
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
            if ids != networks { networks = ids; noteNetwork() }
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

    /// Top Up from any button or menu. Using it also counts toward retiring the "why isn't it full?" hint.
    func toggleTopUp() {
        topUp.toggle()
        if topUp { holdHint.uses += 1 }
        refreshStatus()
    }

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
        t = t.sending(sailing: sailing)   // the ring, panel and helper all see the level that is really enforced
        target = t
        recordWear(t)
        recordHold()
        checkChargeKeys()
        maybeAutoDischarge(t)
        maybeOvernightCalibration()
        remindMacLimit(t)
        let sent = MacChargeLimit.sending(t, macLimit: macLimit)   // a zone macOS holds is sent as "no limit"
        let label = t.wireLabel
        let needsSend = status.map { sent != lastSent || $0.state.upper != sent.upper || $0.state.lower != sent.lower || $0.state.label != label } ?? false
        guard needsSend else { finishRefresh(); return }
        daemonQueue.async { [weak self] in
            let ok = DaemonClient.send("limit \(sent.upper) \(sent.lower) \(label)") == "ok"
            let st = ok ? DaemonClient.status() : nil
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if ok {
                        self.lastSent = sent
                        if var s = st { if s.percent < 0 { s.percent = self.system.power.percent }; self.status = s }
                    }
                    self.finishRefresh()
                }
            }
        }
    }

    private func finishRefresh() {
        refreshInFlight = false
        if let at = pendingUnplug {
            pendingUnplug = nil
            if onBattery { recordHabit(HabitEvent(date: at, kind: .unplug)) }
        }
        trackSettings()
        smartChecks()
        sideEffects()
        if !habitsChecked, status != nil { habitsChecked = true; evaluateHabits(); evaluateNetworkHint(); evaluateWear() }
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

    private func notify(_ title: String, _ body: String, category: String? = nil, info: [String: String] = [:]) {
        let c = UNMutableNotificationContent(); c.title = title; c.body = body
        if let category { c.categoryIdentifier = category }
        c.userInfo = info
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }

    static let habitCategory = "habitSuggestion", acceptAction = "accept", snoozeAction = "snooze"

    /// A button on a habit notification. Acts only if the suggestion it was about is still the current one,
    /// so a stale notification can never apply an outdated plan.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler done: @escaping () -> Void) {
        let action = response.actionIdentifier
        let sig = response.notification.request.content.userInfo["signature"] as? String
        Task { @MainActor in
            defer { done() }
            if action == UNNotificationDefaultActionIdentifier { go(.overview); WindowOpener.open("main"); return }
            if habitSuggestion == nil { evaluateHabits() }
            guard let s = habitSuggestion, sig == nil || s.signature == sig else { return }
            if action == Self.acceptAction { acceptHabit() } else if action == Self.snoozeAction { snoozeHabit() }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .list, .sound])
    }

    /// The one way a change is announced: it always goes into Recent changes, and becomes a notification unless its category is muted.
    func announce(_ e: ChangeEvent) {
        activity.add(ActivityEntry(e, at: Date()))
        activity.save()
        guard !muted.contains(e.category) else { return }
        if case .habitSuggested = e, let s = habitSuggestion {
            notify(e.title, e.body, category: Self.habitCategory, info: ["signature": s.signature])
        } else { notify(e.title, e.body) }
    }

    func clearActivity() { activity.clear(); activity.save() }

    /// Announces zone, override, heat and task changes, and appends one health row per day.
    private func sideEffects() {
        // Renaming the active zone changes its label on every keystroke; only a different zone is a switch.
        // A short delay also lets quick back-and-forth changes (Wi-Fi roaming, toggling a pin) settle into one notice.
        let renamed = target.zoneID != nil && target.zoneID == lastZoneID
        if let l = lastLabel, l != target.label, status != nil, !renamed {
            let t = target
            // Leaving a zone while on battery is a departure; habit learning uses it on days without an unplug.
            if lastZoneID != nil, t.zoneID != lastZoneID, onBattery, config.overrideZone == nil { recordHabit(HabitEvent(date: Date(), kind: .zoneExit)) }
            switchNotice?.cancel()
            switchNotice = Task {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, target.label == t.label else { return }
                announce(.limit(from: l, to: t.label, upper: t.upper, lower: t.lower, reason: t.reason))
            }
        }
        lastLabel = target.label
        lastZoneID = target.zoneID
        if let h = status?.heatHold, h != lastHeatHold {
            announce(.heat(on: h, limit: status?.state.heatLimit ?? HeatLimit.defaultLimit))
            lastHeatHold = h
        }
        // Too low to hold for heat: say once that it is charging anyway, until it cools or climbs back over the floor.
        let skipped = status?.heatSkipped == true
        if skipped, !lastHeatSkipped { announce(.heatSkipped(percent: percent, limit: status?.state.heatLimit ?? HeatLimit.defaultLimit)) }
        lastHeatSkipped = skipped
        if let c = status?.tempC { tempTrend.add(c) }
        // A zone-limited Ready by silently skips when another limit is active. Say so once per departure (checked on the 20 s refresh).
        if let st = status?.state, let skip = ReadySkip.check(st.chargeSchedule, activeLabel: target.wireLabel, percent: percent,
                                                              taskActive: st.task.active, now: Date()), skip.key != lastSkipKey {
            lastSkipKey = skip.key
            announce(.readyBySkipped(zone: skip.zone, active: target.label, percent: skip.percent, by: skip.ready))
        }
        if let now = status?.state.task {
            if let was = lastTask, was.kind != now.kind { announceTask(from: was, to: now) }
            lastTask = now
        }
        guard let i = info, status != nil else { return }
        let day = dayString(Date())
        guard UserDefaults.standard.string(forKey: "lastLogDay") != day else { return }
        UserDefaults.standard.set(day, forKey: "lastLogDay")
        checkCalibrationReminder()
        evaluateHabits()      // once a day too, so a pattern that matured overnight gets suggested without new events
        let url = Self.historyURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        checkHealthDrop(i.healthPercent)
        // Don't log a second row for a day already in the file (e.g. after the defaults key was reset).
        if let old = try? String(contentsOf: url, encoding: .utf8), old.split(whereSeparator: \.isNewline).last?.hasPrefix(day) == true { return }
        let row = "\(day),\(i.healthPercent.map(String.init) ?? ""),\(i.cycles),\(percent)\n"
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data(row.utf8)); try? h.close() }
        else { try? ("date,health_percent,cycles,battery_percent\n" + row).write(to: url, atomically: true, encoding: .utf8) }
    }

    nonisolated static var historyURL: URL { Config.url.deletingLastPathComponent().appendingPathComponent("daily-log.csv") }

    /// Deletes the daily log and the health-drop baseline; the next refresh starts a fresh log (e.g. after a battery swap).
    func resetHistory() {
        try? FileManager.default.removeItem(at: Self.historyURL)
        let d = UserDefaults.standard
        for k in ["lastLogDay", "healthBaseline", "healthBaselineDate"] { d.removeObject(forKey: k) }
        sideEffects()
    }

    // MARK: Settings file and diagnostics

    func exportSettings() {
        let p = NSSavePanel(); p.nameFieldStringValue = "BalDente-settings.json"; p.allowedContentTypes = [.json]
        guard p.runModal() == .OK, let dest = p.url else { return }
        do { try SettingsExport.encode(config, version: appVersionText).write(to: dest, options: .atomic); settingsFileMessage = "Saved to \(dest.lastPathComponent)." }
        catch { settingsFileMessage = "Couldn't save: \(error.localizedDescription)" }
    }

    /// Replaces zones, limits and appearance with a saved file's. The current settings are copied to the backups list first.
    func importSettings() {
        let p = NSOpenPanel(); p.allowedContentTypes = [.json]; p.allowsMultipleSelection = false
        guard p.runModal() == .OK, let src = p.url else { return }
        do {
            let imported = try SettingsExport.decode(Data(contentsOf: src))
            if let data = try? Data(contentsOf: Config.url) { backupStore.save(data, version: "before-import"); backups = backupStore.list() }
            config = imported
            settingsFileMessage = "Loaded \(imported.zones.count) zones from \(src.lastPathComponent)."
        } catch { settingsFileMessage = (error as? SettingsExport.Failure)?.message ?? "Couldn't read that file: \(error.localizedDescription)" }
    }

    var diagnostics: DiagnosticsInfo {
        let t = target
        return DiagnosticsInfo(
            appVersion: appVersionText, macOS: ProcessInfo.processInfo.operatingSystemVersionString,
            mac: "\(mac.productName) (\(mac.modelID), \(mac.appleSilicon ? "Apple silicon" : "Intel"))",
            helper: status != nil ? (helperOutdated ? "update available" : "running") : helperInstalled ? "not responding" : "not installed",
            backend: status?.backend, percent: status?.percent, tempC: status?.tempC,
            limit: "\(t.upper)% / \(t.lower)% (\(t.label))", zoneCount: config.zones.count, heatProtection: status?.state.heatProtection,
            recent: activity.entries.prefix(10).map { $0.title }, lastError: setupError, chargeKeys: status?.chargeKeys)
    }

    func copyDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnostics.report, forType: .string)
        settingsFileMessage = "Diagnostics copied. Paste them into your bug report."
    }

    func exportHistory() {
        guard FileManager.default.fileExists(atPath: Self.historyURL.path) else { setupError = "There's no history to export yet."; return }
        let p = NSSavePanel(); p.nameFieldStringValue = "BalDente-history.csv"; p.allowedContentTypes = [.commaSeparatedText]
        guard p.runModal() == .OK, let dest = p.url else { return }
        do { try? FileManager.default.removeItem(at: dest); try FileManager.default.copyItem(at: Self.historyURL, to: dest) }
        catch { setupError = "Couldn't export: \(error.localizedDescription)" }
    }

    /// A task the helper runs started or ended: Ready by / calendar top-ups, discharge and calibration.
    private func announceTask(from was: TaskState, to now: TaskState) {
        if was.kind == "topup" { announce(.readyByFinished(calendar: calendar.enabled, backTo: target.label)) }
        else if was.kind == "calibrate" {
            let done = CalibrationProgress.finishedCleanly(was)
            if done {
                calibrationDates = Array((calibrationDates + [Date()]).suffix(50))
                UserDefaults.standard.set(calibrationDates, forKey: "calibrationDates")
            }
            announce(.calibrationEnded(completed: done, timedOut: CalibrationProgress.timedOut(was)))
        }
        else if was.active { announce(.task(started: false, kind: was.kind, target: was.target)) }
        if now.kind == "topup" { announce(.readyByStarted(percent: now.target, by: now.restUntil?.addingTimeInterval(-30 * 60), calendar: calendar.enabled)) }
        else if now.active { announce(.task(started: true, kind: now.kind, target: now.target)) }
    }

    /// Both checks ride on the refresh that already runs, so they cost nothing extra.
    private func smartChecks() {
        calendar.tick()
        if status == nil, helperInstalled {
            // Time based, not count based: refreshes also fire on every network change, so a count would trip in seconds.
            let since = offlineSince ?? Date()
            offlineSince = since
            if Date().timeIntervalSince(since) > 120, UserDefaults.standard.object(forKey: "offlineNoticeFor") as? Date != since {
                UserDefaults.standard.set(since, forKey: "offlineNoticeFor")
                announce(.helperOffline)
            }
        } else if status != nil, let since = offlineSince {
            offlineSince = nil
            if UserDefaults.standard.object(forKey: "offlineNoticeFor") as? Date == since { announce(.helperBack) }
        }
    }

    /// Daily, from the log: suggest a calibration after 90 days without one. Suggest only; it never starts one.
    private func checkCalibrationReminder() {
        let d = UserDefaults.standard
        guard let baseline = d.object(forKey: "calibrationBaseline") as? Date else { d.set(Date(), forKey: "calibrationBaseline"); return }
        guard CalibrationReminder.due(last: lastCalibration, baseline: baseline, lastReminded: d.object(forKey: "calibrationReminded") as? Date) else { return }
        d.set(Date(), forKey: "calibrationReminded")
        announce(.calibrationDue(days: lastCalibration.map { CalibrationReminder.days(since: $0) }))
    }

    /// Monthly: tell the user if battery health fell 2 points or more. Called from the once-a-day log.
    private func checkHealthDrop(_ health: Int?) {
        guard trio.smartNotifications, let h = health else { return }
        let d = UserDefaults.standard
        guard let base = d.object(forKey: "healthBaseline") as? Int, let since = d.object(forKey: "healthBaselineDate") as? Date else {
            d.set(h, forKey: "healthBaseline"); d.set(Date(), forKey: "healthBaselineDate"); return
        }
        guard Date().timeIntervalSince(since) > 30 * 86400 || h > base else { return }   // a higher reading (recalibration) resets the baseline
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

    /// The ring's markers can be dragged when the limit comes from a zone or "Everywhere else"; Top Up and Travel Mode are fixed at 100%.
    var sailing: Bool { config.sailing ?? false }

    var ringEditable: Bool { target.zoneID != nil || target.label == "Default" }

    /// Saves limits dragged on the Overview ring into whatever set the current target. Called once when the drag ends,
    /// so the helper hears one change rather than one per pixel.
    func setTargetLimits(upper: Int, lower: Int) {
        // One assignment, so didSet saves once and the helper never sees a half-updated pair (lower above upper).
        var c = config
        if let id = target.zoneID, let i = c.zones.firstIndex(where: { $0.id == id }) {
            c.zones[i].upper = upper
            if sailing { c.zones[i].lower = lower } else { c.zones[i].lower = min(c.zones[i].lower, upper - 1) }
        } else if target.zoneID == nil, target.label == "Default" {
            c.defaultUpper = upper
            if sailing { c.defaultLower = lower } else { c.defaultLower = min(c.defaultLower, upper - 1) }
        }
        if c != config { config = c }
    }

    /// Adds a zone with a name nobody else has, and returns it so the caller can open its editor.
    @discardableResult
    func addZone() -> Zone {
        let z = Zone(name: uniqueZoneName("New Zone", existing: config.zones.map(\.name)), upper: 80, lower: 75)
        config.zones.append(z)
        return z
    }

    /// Gives a zone a usable name after editing: trimmed, not empty, not a twin of another zone, not a reserved label.
    func fixZoneName(_ id: UUID) {
        guard let i = config.zones.firstIndex(where: { $0.id == id }) else { return }
        let name = config.zones[i].name.trimmingCharacters(in: .whitespacesAndNewlines)
        let others = config.zones.filter { $0.id != id }.map(\.name)
        let fixed = uniqueZoneName(name.isEmpty ? "Zone" : name, existing: others)
        if fixed != config.zones[i].name { config.zones[i].name = fixed }
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

    // MARK: First run, What's New

    private func prepareFirstRun() {
        let d = UserDefaults.standard
        showTutorial = TutorialVersion.shouldShow(seen: d.integer(forKey: "tutorialSeen"), firstLaunch: firstLaunch)
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        if WhatsNew.shouldShow(current: version, lastSeen: d.string(forKey: "lastVersionSeen"), firstLaunch: firstLaunch),
           let url = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            whatsNew = WhatsNew.items(for: version, in: text)
        }
        if !firstLaunch, version != "dev", d.string(forKey: "lastVersionSeen") != version { beginUpdateVerification() }
        // Remember the version now unless there's a sheet to show; then it's remembered when the sheet is closed.
        if whatsNew == nil, version != "dev" { d.set(version, forKey: "lastVersionSeen") }
    }

    func finishWhatsNew() {
        whatsNew = nil
        if let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String { UserDefaults.standard.set(v, forKey: "lastVersionSeen") }
    }

    /// Which stop of the guided tour is showing, or nil when it isn't running.
    @Published private(set) var tourStep: Int?
    private var tourRestoresCompact = false

    /// Starts the spotlight tour over the real window. It needs the regular layout; compact mode comes back when it ends.
    func startTour() {
        finishTutorial()
        if appearance.compact { tourRestoresCompact = true; appearance.compact = false }
        WindowOpener.open("main")
        tourGo(0)
    }

    func tourGo(_ i: Int) {
        let steps = GuidedTour.steps(self)
        guard steps.indices.contains(i) else { endTour(); return }
        tourStep = i
        go(steps[i].page, focus: steps[i].anchor)      // opens the page and scrolls the control into view
    }

    func endTour() {
        tourStep = nil
        focus = nil
        if tourRestoresCompact { tourRestoresCompact = false; appearance.compact = true }
    }

    func finishTutorial() {
        UserDefaults.standard.set(TutorialVersion.current, forKey: "tutorialSeen")
        showTutorial = false
    }

    var defaultsChoiceMade: Bool { UserDefaults.standard.bool(forKey: "defaultsChoiceMade") }

    func choose(_ p: Defaults.Preset) {
        UserDefaults.standard.set(true, forKey: "defaultsChoiceMade")
        guard p == .everywhere80 else { return }
        config = Defaults.apply(p, to: config)
        announce(.defaultsChosen(p.title))
    }

    /// "Holding at 50% (Home zone). Need a full battery?", or nil when there's nothing to explain.
    var holdHintText: String? {
        holdHint.message(label: target.label, upper: target.upper, helperRunning: status != nil && task == nil,
                         zonesMatched: target.zoneID != nil, locationAllowed: locationAllowed, onBattery: onBattery)
    }

    /// Opens the Ready by editor from anywhere (Overview, the hint, the menu bar panel).
    func openReadyBy() {
        holdHint.uses += 1
        readyByRequested = true
        go(.charging, focus: "Ready by")
    }

    // MARK: Habits

    nonisolated static var habitsURL: URL { Config.url.deletingLastPathComponent().appendingPathComponent("habits.json") }

    private static func loadHabits() -> HabitLog {
        (try? Data(contentsOf: habitsURL)).flatMap { try? JSONDecoder().decode(HabitLog.self, from: $0) } ?? HabitLog()
    }

    private func saveHabits() {
        try? FileManager.default.createDirectory(at: Self.habitsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let d = try? JSONEncoder().encode(habits) { try? d.write(to: Self.habitsURL, options: .atomic) }
    }

    private func pluggedChanged(_ plugged: Bool) {
        guard habitsEnabled else { return }
        if plugged {
            pendingUnplug = nil
            let before = habits
            habits.plugged(at: Date())
            if habits != before { saveHabits() }
        } else {
            pendingUnplug = Date()
            refreshStatus()        // confirms it's a real unplug (not a held charger) in finishRefresh
        }
    }

    private func recordHabit(_ e: HabitEvent) {
        guard habitsEnabled else { return }
        habits.record(e)
        saveHabits()
        evaluateHabits()
    }

    /// Deletes everything learned; suggestions start over.
    func clearHabits() {
        habits = HabitLog()
        try? FileManager.default.removeItem(at: Self.habitsURL)
        networkLog = NetworkLog(); networkSuggestion = nil
        try? FileManager.default.removeItem(at: Self.networkLogURL)
        zoneWear = ZoneWear(); wearSuggestion = nil; wearUnsaved = 0
        batteryHold = BatteryHold(); holdUnsaved = 0
        try? FileManager.default.removeItem(at: Self.batteryHoldURL)
        try? FileManager.default.removeItem(at: Self.zoneWearURL)
        UserDefaults.standard.removeObject(forKey: "wearDismissed")
        for k in ["networkSnoozeUntil", "networkDismissed", "networkNotified"] { UserDefaults.standard.removeObject(forKey: k) }
        for k in ["habitSnoozeUntil", "habitDismissed", "habitNotified"] { UserDefaults.standard.removeObject(forKey: k) }
        habitSuggestion = nil
    }

    var habitSampleCount: Int { HabitPlanner.firstDepartures(habits).count }

    private func storedSuggestion(_ key: String) -> HabitSuggestion? {
        guard let d = UserDefaults.standard.dictionary(forKey: key) as? [String: Int] else { return nil }
        let r = Dictionary(uniqueKeysWithValues: d.compactMap { k, v in Int(k).map { ($0, v) } })
        return r.isEmpty ? nil : HabitSuggestion(departures: r, readyBy: r)
    }

    private func store(_ s: HabitSuggestion, _ key: String) {
        UserDefaults.standard.set(Dictionary(uniqueKeysWithValues: s.readyBy.map { (String($0.key), $0.value) }), forKey: key)
    }

    /// Recomputes the suggestion. Runs on habit events, at launch and once a day; never on a timer.
    func evaluateHabits() {
        let d = UserDefaults.standard
        guard habitsEnabled, !calendar.enabled, let cs = status?.state.chargeSchedule,
              let s = HabitPlanner.suggest(habits), !HabitPlanner.isCovered(s, by: cs),
              (d.object(forKey: "habitSnoozeUntil") as? Date).map({ $0 <= Date() }) ?? true,
              !(storedSuggestion("habitDismissed").map { s.isSimilar(to: $0) } ?? false)
        else { habitSuggestion = nil; return }
        let isNew = habitSuggestion.map { !s.isSimilar(to: $0) } ?? true
        habitSuggestion = s
        if isNew, !(storedSuggestion("habitNotified").map { s.isSimilar(to: $0) } ?? false) {
            store(s, "habitNotified")
            announce(.habitSuggested(s.question))
        }
    }

    /// Accept: sets up Ready by with the suggested times, keeping slots the user made for other days.
    func acceptHabit() {
        guard let s = habitSuggestion, let cs = status?.state.chargeSchedule else { return }
        let slots = HabitPlanner.merged(s, into: cs)
        cmd("ready zone any")
        cmd("ready travel 0")
        cmd("ready on \(ChargeSchedule.spec(slots))")
        holdHint.uses += 1
        habitSuggestion = nil
        announce(.habitAccepted("Full by \(HabitPlanner.describe(s.readyBy))."))
    }

    func snoozeHabit() {
        UserDefaults.standard.set(Date().addingTimeInterval(7 * 86400), forKey: "habitSnoozeUntil")
        habitSuggestion = nil
    }

    func dismissHabit() {
        if let s = habitSuggestion { store(s, "habitDismissed") }
        habitSuggestion = nil
    }

    // MARK: Network hints

    nonisolated static var networkLogURL: URL { Config.url.deletingLastPathComponent().appendingPathComponent("network-habits.json") }

    /// Called only when the network changes. Records a Wi-Fi name no zone knows, then re-checks the suggestion.
    private func noteNetwork() {
        guard habitsEnabled, let name = NetworkHints.wifiName(networks),
              !config.zones.contains(where: { $0.networks.contains { $0.lowercased() == name.lowercased() } }) else { return }
        let before = networkLog
        networkLog.record(name)
        if networkLog != before {
            try? FileManager.default.createDirectory(at: Self.networkLogURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let d = try? JSONEncoder().encode(networkLog) { try? d.write(to: Self.networkLogURL, options: .atomic) }
        }
        evaluateNetworkHint()
    }

    func evaluateNetworkHint() {
        let d = UserDefaults.standard
        let dismissed = Set(d.stringArray(forKey: "networkDismissed") ?? [])
        guard habitsEnabled, (d.object(forKey: "networkSnoozeUntil") as? Date).map({ $0 <= Date() }) ?? true,
              let s = NetworkHints.suggest(networkLog, config: config, dismissed: dismissed)
        else { networkSuggestion = nil; return }
        networkSuggestion = s
        var notified = Set(d.stringArray(forKey: "networkNotified") ?? [])
        if notified.insert(s.network.lowercased()).inserted {
            d.set(Array(notified), forKey: "networkNotified")
            announce(.networkSuggested(s.question()))
        }
    }

    /// Adds the suggested network to a zone (or a new zone named after it, then opens Zones to edit its limit).
    func addSuggestedNetwork(to zoneID: UUID?) {
        guard let s = networkSuggestion else { return }
        if let id = zoneID, let i = config.zones.firstIndex(where: { $0.id == id }) {
            config.zones[i].networks.append(s.network)
        } else {
            var z = addZone()
            z.name = uniqueZoneName(s.network, existing: config.zones.filter { $0.id != z.id }.map(\.name))
            z.networks = [s.network]
            if let i = config.zones.firstIndex(where: { $0.id == z.id }) { config.zones[i] = z }
            go(.zones, focus: "Zones")
        }
        networkSuggestion = nil
    }

    func snoozeNetworkHint() {
        UserDefaults.standard.set(Date().addingTimeInterval(7 * 86400), forKey: "networkSnoozeUntil")
        networkSuggestion = nil
    }

    func dismissNetworkHint() {
        guard let s = networkSuggestion else { return }
        let d = UserDefaults.standard
        d.set((d.stringArray(forKey: "networkDismissed") ?? []) + [s.network.lowercased()], forKey: "networkDismissed")
        networkSuggestion = nil
    }

    // MARK: Zone wear

    nonisolated static var zoneWearURL: URL { Config.url.deletingLastPathComponent().appendingPathComponent("zone-wear.json") }

    /// Piggybacks on the 20 s refresh; written to disk every ten minutes of counted time, not every sample.
    private func recordWear(_ t: Target) {
        let now = Date()
        defer { lastWearSample = now }
        guard let last = lastWearSample, status != nil else { return }
        let step = now.timeIntervalSince(last)
        guard zoneWear.record(zone: t.label, percent: percent, elapsed: step, at: now) else { return }
        wearUnsaved += step
        if wearUnsaved >= 600 { saveWear(); evaluateWear() }
    }

    // MARK: macOS charge limit

    private var macLimitBlocked = false
    /// What `pmset -g battlimit` reported at the last read (nil: no limit set in macOS).
    @Published private(set) var detectedMacLimit: Int?

    /// The macOS charge limit in force, detected or hand-picked.
    var macLimit: Int? { config.effectiveMacLimit(detected: detectedMacLimit) }

    /// Reads macOS's limit off the main thread. Runs on launch, when the app is activated and after wake, never on a timer.
    func readMacLimit() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset"); p.arguments = ["-g", "battlimit"]
            let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
            guard (try? p.run()) != nil else { return }
            let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
            let limit = MacChargeLimit.parse(String(decoding: data, as: UTF8.self))
            Task { @MainActor in
                guard let self, self.detectedMacLimit != limit else { return }
                self.detectedMacLimit = limit
                self.refreshStatus()
            }
        }
    }

    /// With a macOS limit in use, tell the user when a zone switch needs it raised, and when it can go back. Reminds, never changes.
    private func remindMacLimit(_ t: Target) {
        guard let m = macLimit else { macLimitBlocked = false; return }
        let blocked = MacChargeLimit.role(upper: t.upper, macLimit: m) == .blocked
        guard blocked != macLimitBlocked else { return }
        macLimitBlocked = blocked
        announce(.macLimit(blocked: blocked, zone: t.label, upper: t.upper, macLimit: m))
    }

    // MARK: Time on battery while plugged in

    nonisolated static var batteryHoldURL: URL { Config.url.deletingLastPathComponent().appendingPathComponent("battery-hold.json") }

    /// Shares the zone-wear sample clock, so both advance by the same step; saved every ten minutes of counted time.
    private func recordHold() {
        guard let last = lastWearSample, status != nil else { return }
        let step = Date().timeIntervalSince(last)
        guard batteryHold.record(held: holding && !onBattery, elapsed: step, at: Date()) else { return }
        holdUnsaved += step
        if holdUnsaved >= 600 { saveHold() }
    }

    private func saveHold() {
        holdUnsaved = 0
        try? FileManager.default.createDirectory(at: Self.batteryHoldURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let d = try? JSONEncoder().encode(batteryHold) { try? d.write(to: Self.batteryHoldURL, options: .atomic) }
    }

    /// The helper reports which charge-control keys this Mac lets it read. If a macOS update opens any, say so once per set of keys.
    private func checkChargeKeys() {
        guard let keys = status?.chargeKeys, !keys.isEmpty else { return }
        let signature = keys.sorted().joined(separator: ",")
        guard UserDefaults.standard.string(forKey: "chargeKeysSeen") != signature else { return }
        UserDefaults.standard.set(signature, forKey: "chargeKeysSeen")
        announce(.chargeKeysOpened(keys.sorted()))
    }

    private func saveWear() {
        wearUnsaved = 0
        try? FileManager.default.createDirectory(at: Self.zoneWearURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let d = try? JSONEncoder().encode(zoneWear) { try? d.write(to: Self.zoneWearURL, options: .atomic) }
    }

    func evaluateWear() {
        let dismissed = Set(UserDefaults.standard.stringArray(forKey: "wearDismissed") ?? [])
        wearSuggestion = habitsEnabled ? WearSuggestion.suggest(zoneWear, config: config, dismissed: dismissed) : nil
    }

    /// The user's tap: lower the suggested zone (or Everywhere else) to 80/75.
    func acceptWearSuggestion() {
        guard let s = wearSuggestion else { return }
        if s.zone == "Default" {
            config.defaultUpper = WearSuggestion.newUpper; config.defaultLower = min(config.defaultLower, WearSuggestion.newLower)
        } else if let i = config.zones.firstIndex(where: { $0.name == s.zone }) {
            config.zones[i].upper = WearSuggestion.newUpper; config.zones[i].lower = min(config.zones[i].lower, WearSuggestion.newLower)
        }
        wearSuggestion = nil
    }

    func dismissWearSuggestion() {
        guard let s = wearSuggestion else { return }
        let d = UserDefaults.standard
        d.set((d.stringArray(forKey: "wearDismissed") ?? []) + [s.zone], forKey: "wearDismissed")
        wearSuggestion = nil
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

    /// Where power comes from now (adapter or battery), including a Mac that is plugged in but no longer charging.
    var powerSource: PowerSourceState {
        PowerSourceState(onBattery: onBattery, charging: system.power.charging, charged: system.power.charged, held: holding,
                         percent: percent, upper: target.upper)
    }

    /// The small caption inside the battery rings; `compact` for the small rings, which have about 80 pt of room.
    func ringCaption(compact: Bool = false) -> (text: String, icon: String) {
        if !system.power.present { return ("Not charging", "battery.75percent") }
        return powerSource.caption(compact: compact)
    }

    /// What the next Ready by departure within a day will do; nil when there is nothing to say.
    var readyPreview: ReadyPreview? {
        guard let st = status?.state else { return nil }
        return ReadyPreview.make(st.chargeSchedule, activeLabel: target.wireLabel, percent: percent, plugged: !onBattery,
                                 tempC: status?.tempC ?? info?.tempC, taskActive: st.task.active, now: Date())
    }

    /// Runs a baldente:// action. Every one is logged under Top Up, Travel mode and tasks.
    func run(_ action: AutomationAction) {
        announce(.automation(action.title))
        switch action {
        case .topUp(let on): if topUp != on { toggleTopUp() }
        case .travel(let on): travelUntil = on ? Date().addingTimeInterval(86400) : nil
        case .discharge(let t): cmd("discharge \(t)")
        case .calibrate: if task?.kind != "calibrate" { cmd("calibrate") }
        case .lowPower(let on): cmd("lowpower \(on ? "on" : "off")")
        case .automatic: config.overrideZone = nil
        case .cancelTask: cmd("cancel")
        case .pinZone(let n):
            // Only an existing zone can be pinned; a link can't invent one.
            if let z = config.zones.first(where: { $0.name.caseInsensitiveCompare(n) == .orderedSame }) { config.overrideZone = z.name }
        }
    }

    /// Auto Discharge: when the limit sits below the battery with the charger in, drain to it (at most once every five minutes).
    /// "Calibrate overnight": once a month, start a calibration when the Mac is plugged in at night. One try per night, so Cancel sticks.
    private func maybeOvernightCalibration() {
        guard let st = status?.state,
              CalibrationPlan.overnightShouldStart(enabled: config.overnightCalibration == true, plugged: system.power.plugged,
                                                   taskActive: st.task.active, lastCalibrated: [lastCalibration, st.lastCalibrated].compactMap { $0 }.max(),
                                                   lastAttempt: lastOvernightCalibration) else { return }
        lastOvernightCalibration = Date()
        cmd("calibrate")
    }

    /// How long the drain step would take at the current power use, e.g. "about 4 h"; nil when it can't tell.
    var drainEstimate: String? {
        guard let i = info else { return nil }
        let w = i.flow.map { $0.toMac } ?? abs(i.watts)
        return CalibrationPlan.drainHours(percent: percent, maxMAh: i.maxMAh, volts: i.volts, watts: w).map(CalibrationPlan.durationText)
    }

    private func maybeAutoDischarge(_ t: Target) {
        guard config.autoDischarge == true, let st = status?.state,
              lastAutoDischarge.map({ Date().timeIntervalSince($0) > 300 }) ?? true,
              let goal = AutoDischarge.target(enabled: true, plugged: !onBattery, percent: percent, limitUpper: t.upper,
                                              limitEnabled: t.upper < 100, taskActive: st.task.active,
                                              overrideActive: travelUntil != nil || topUp, readyBy: st.chargeSchedule, now: Date()) else { return }
        lastAutoDischarge = Date()
        cmd("discharge \(goal)")
    }

    var headline: String {
        guard let s = status else { return "Helper offline" }
        if let t = task {
            if t.kind == "topup" { return t.phase == "hold" ? "Ready to go" : "Charging for your trip" }
            if t.kind == "discharge" { return "Discharging to \(t.target)%" }
            if t.pausedAt != nil { return "Calibration paused" }
            switch t.phase { case "discharge": return "Calibrating: draining"; case "charge": return "Calibrating: charging"; default: return "Calibrating: resting" }
        }
        if s.heatHold { return "Cooling down" }
        return powerSource.headline(upper: target.upper, percent: percent)
    }

    var subline: String {
        guard status != nil else { return "Set up the background helper to take control of charging." }
        if let t = task {
            if t.kind == "topup" { return "Ready by is active, so zone limits are paused until you leave." }
            if t.kind == "discharge" { return "Charger is off until the battery reaches \(t.target)%." }
            if t.pausedAt != nil { return "Your normal limits apply until you resume it on Charging Tools." }
            return "Full cycle: 15%, then 100%, then a one-hour rest."
        }
        if status?.heatHold == true {
            return "The charger is off until the battery cools 3 °C below \(status?.state.heatLimit ?? HeatLimit.defaultLimit) °C. Below \(HeatLimit.chargeFloor)% it charges anyway."
        }
        if onBattery { return "Plug in and BalDente charges to \(target.upper)%, then holds." }
        if holding { return "Charger paused. It comes back at \(target.lower)%." }
        if powerSource.phase == .charging { return "Charger pauses when the battery reaches \(target.upper)%." }
        return "Running from the power adapter, so the battery isn't being used. Charging resumes at \(target.lower)%."
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
