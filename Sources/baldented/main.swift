import BalDenteCore
import Darwin
import Foundation
import IOKit.ps
import IOKit.pwr_mgt

// Root daemon: applies the current limits. Everything is serialized on one queue.
setvbuf(stdout, nil, _IOLBF, 0)
guard getuid() == 0 else { print("baldented must run as root"); exit(1) }
do { try SMC.open() } catch { print("cannot open SMC: \(error)"); exit(1) }
guard let backend = AdapterBackend() else { print("no supported charge-control key found"); exit(1) }

let queue = DispatchQueue(label: "baldented")
var state = LimiterState()

func loadState() {
    if let d = try? Data(contentsOf: URL(fileURLWithPath: statePath)),
       let s = try? JSONDecoder().decode(LimiterState.self, from: d) { state = s }
}

func saveState() {
    try? FileManager.default.createDirectory(atPath: stateDir, withIntermediateDirectories: true)
    if let d = try? JSONEncoder().encode(state) { try? d.write(to: URL(fileURLWithPath: statePath)) }
}

var heatHold = false
var batteryHot = false

/// Fixed Gregorian POSIX format, so the "already ran today" check can't drift with the system calendar or locale.
func today() -> String { dayString(Date()) }

func startCalibration() {
    state.task = TaskState(); state.task.kind = "calibrate"; state.task.phase = "discharge"
    print("calibration started")
}

var wakeAssertion: IOPMAssertionID = 0
var startingSoon = false
var readyWake: Date?
var plugged = true
var curAdapterOn = true

/// Keeps the Mac awake (even lid closed, on AC) while a top-up is running.
func holdAwake(_ on: Bool) {
    if on, wakeAssertion == 0 {
        IOPMAssertionCreateWithName(kIOPMAssertionTypePreventSystemSleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                    "BalDente scheduled top up" as CFString, &wakeAssertion)
    } else if !on, wakeAssertion != 0 {
        IOPMAssertionRelease(wakeAssertion); wakeAssertion = 0
    }
}

func pmset(_ args: [String]) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset"); p.arguments = args
    try? p.run(); p.waitUntilExit()
}

let wakeFormat: DateFormatter = {
    let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "MM/dd/yyyy HH:mm:ss"; return f
}()

/// Starts a top-up when it's time to reach 100% by the departure time, and keeps a wake scheduled for it.
func checkReadyBy(_ pct: Int) {
    startingSoon = false; readyWake = nil
    let cs = state.chargeSchedule
    let now = Date()
    guard let next = cs.nextSlot(after: now) else { return }
    let ready = next.ready, slot = next.slot
    // Zone-limited schedules only run while that zone is active (the app sends zone names with spaces as underscores).
    if let z = cs.onlyZone, Target.wire(z) != state.label { return }
    let startAt = ready.addingTimeInterval(-ChargeSchedule.leadMinutes(percent: pct, target: slot.percent) * 60)
    if now >= startAt, !state.task.active {
        state.task = TaskState(); state.task.kind = "topup"; state.task.target = slot.percent
        state.task.restUntil = ready.addingTimeInterval(30 * 60)
        state.chargeSchedule.ran = Array((state.chargeSchedule.ran + [ChargeSchedule.key(ready)]).suffix(30))
        saveState()
        print("scheduled top up started at \(pct)%, ready by \(ready)")
    } else {
        readyWake = startAt
        // A scheduled wake can land seconds early; stay awake until the start time so the top up actually begins.
        startingSoon = startAt.timeIntervalSince(now) <= 300
    }
}

/// Wake the Mac when the top-up should start. Once the charger is switched on it keeps charging even if the Mac sleeps again.
func syncWake(_ at: Date?) {
    let current = state.chargeSchedule.wakeAt.flatMap { wakeFormat.date(from: $0) }
    if let a = at, a > Date() {
        if let c = current, abs(c.timeIntervalSince(a)) < 300 { return }
        if let c = current { pmset(["schedule", "cancel", "wakeorpoweron", wakeFormat.string(from: c)]) }
        pmset(["schedule", "wakeorpoweron", wakeFormat.string(from: a)])
        state.chargeSchedule.wakeAt = wakeFormat.string(from: a); saveState()
    } else if let c = current {
        pmset(["schedule", "cancel", "wakeorpoweron", wakeFormat.string(from: c)])
        state.chargeSchedule.wakeAt = nil; saveState()
    }
}

/// Starts the scheduled calibration once per day, at or after the chosen time.
func checkSchedule(_ pct: Int) {
    checkReadyBy(pct)
    if let at = state.calibrateAt {
        if Date() > at.addingTimeInterval(3 * 3600) { state.calibrateAt = nil; saveState() }   // missed by hours: don't start at noon
        else if Date() >= at, !state.task.active { state.calibrateAt = nil; startCalibration(); saveState(); return }
    }
    let s = state.schedule
    guard s.enabled, !state.task.active, s.lastRun != today() else { return }
    let c = Calendar.current, now = Date()
    let dim = c.range(of: .day, in: .month, for: now)?.count ?? 31
    guard scheduleDayMatches(days: s.days, today: c.component(.day, from: now), daysInMonth: dim) else { return }
    let mins = c.component(.hour, from: now) * 60 + c.component(.minute, from: now)
    if mins >= s.hour * 60 + s.minute {
        state.schedule.lastRun = today()
        startCalibration(); saveState()
    }
}

/// Moves a running task forward; returns the adapter state the task wants, or nil to use the normal limiter.
func advanceTask(_ pct: Int) -> Bool? {
    var t = state.task
    defer { if t != state.task { state.task = t; saveState() } }
    switch t.kind {
    case "discharge":
        if pct <= t.target { t = TaskState(); return nil }
        return false
    case "topup":
        // Stay topped up until you leave: zone limits are suspended for the whole window, not just until 100%.
        if let until = t.restUntil, Date() >= until { t = TaskState(); print("top up window ended"); return nil }
        if pct >= t.target { t.phase = "hold" }
        if t.phase == "hold" && !plugged && curAdapterOn { t = TaskState(); print("unplugged, top up done"); return nil }
        if t.target >= 100 { return true }
        if pct >= t.target { return false }        // hold a level below 100 by letting it drift...
        if pct <= t.target - 2 { return true }     // ...and topping it back up
        return curAdapterOn
    case "calibrate":
        switch t.phase {
        case "discharge":
            if pct <= 15 { t.phase = "charge"; return true }
            return false
        case "charge":
            if pct >= 100 { t.phase = "rest"; t.restUntil = Date().addingTimeInterval(3600) }
            return true
        default:
            if let until = t.restUntil, Date() >= until { t = TaskState(); print("calibration finished"); return nil }
            return true
        }
    default: return nil
    }
}

func apply() {
    guard let pct = batteryPercent() else { return }
    checkSchedule(pct)
    let now0 = Date()
    if let at = state.calibrateAt, at.timeIntervalSince(now0) <= 300 { startingSoon = true }
    syncWake([readyWake, state.calibrateAt].compactMap { $0 }.filter { $0 > now0 }.min())
    let adapterOn = backend.isAdapterOn()
    curAdapterOn = adapterOn
    let batt = BatteryInfo.read()
    let temp = batt?.tempC
    plugged = batt?.plugged ?? true

    // Track heat even while a task runs, so the status never reports a stale "cooling down" and the pause resumes correctly after it.
    if state.heatProtection, let t = temp {
        if t >= Double(state.heatLimit) { batteryHot = true } else if t <= Double(state.heatLimit - 3) { batteryHot = false }
    } else { batteryHot = false }
    var want: Bool
    if let task = advanceTask(pct) {
        want = task
        heatHold = false        // tasks have their own (45 °C) cutoff below; heat protection isn't what's holding the charger
    } else {
        heatHold = batteryHot
        if heatHold { want = false }
        else if !state.enabled { want = true }
        else if pct >= state.upper { want = false }
        else if pct <= state.lower { want = true }
        else { want = adapterOn }   // inside the sailing range: leave things as they are
    }
    if state.task.kind == "topup", let t = temp, t >= 45 { want = false }   // too hot even for a top up
    holdAwake(state.task.kind == "calibrate" || startingSoon)   // a topup keeps charging while asleep; calibration needs the Mac awake
    if pct <= 5 { want = true }     // never strand the battery
    if want != adapterOn {
        do { try backend.setAdapter(on: want) } catch { print("adapter write failed: \(error)"); return }
        print("\(pct)% temp \(temp.map { String(format: "%.1f", $0) } ?? "?")C: adapter \(want ? "on" : "off")")
    }
}

func setLowPower(_ on: Bool) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
    p.arguments = ["-a", "lowpowermode", on ? "1" : "0"]
    try? p.run()
}

func handle(_ line: String) -> String {
    let p = line.split(separator: " ").map(String.init)
    switch p.first {
    case "status":
        let s = Status(percent: batteryPercent() ?? -1, adapterOn: backend.isAdapterOn(), state: state,
                       backend: backend.name, tempC: BatteryInfo.read()?.tempC, heatHold: heatHold)
        return String(decoding: (try? JSONEncoder().encode(s)) ?? Data(), as: UTF8.self)
    case "limit":
        guard p.count >= 3, let u = Int(p[1]), let l = Int(p[2]), (5...100).contains(u), (1..<u).contains(l)
        else { return "error: usage limit <upper 5-100> <lower below upper> [label]" }
        state.enabled = u < 100; state.upper = u; state.lower = l
        state.label = p.count > 3 ? Target.wire(p[3]) : "manual"
    case "disable": state.enabled = false
    case "enable": state.enabled = true
    case "heat":
        guard p.count >= 2, ["on", "off"].contains(p[1]) else { return "error: usage heat on|off [celsius \(HeatLimit.range.lowerBound)-\(HeatLimit.range.upperBound)]" }
        if p.count > 2 { guard let c = Int(p[2]), HeatLimit.range.contains(c) else { return "error: celsius must be \(HeatLimit.range.lowerBound)-\(HeatLimit.range.upperBound)" }; state.heatLimit = c }
        state.heatProtection = p[1] == "on"
    case "lowpower":
        guard p.count == 2, ["on", "off"].contains(p[1]) else { return "error: usage lowpower on|off" }
        state.lowPower = p[1] == "on"; setLowPower(state.lowPower)
    case "discharge":
        guard p.count == 2, let t = Int(p[1]), (5...99).contains(t) else { return "error: usage discharge <5-99>" }
        state.task = TaskState(); state.task.kind = "discharge"; state.task.target = t
    case "calibrate":
        if p.count == 3, p[1] == "at" {
            let t = p[2].split(separator: ":")
            guard t.count == 2, let h = Int(t[0]), let m = Int(t[1]), (0..<24).contains(h), (0..<60).contains(m),
                  let when = nextOccurrence(hour: h, minute: m, after: Date()) else { return "error: usage calibrate at HH:MM" }
            state.calibrateAt = when
        } else if p.count == 2, p[1] == "off" { state.calibrateAt = nil }
        else { startCalibration() }
    case "ready":
        if p.count == 2, p[1] == "off" {
            state.chargeSchedule.enabled = false
            if state.task.kind == "topup" { state.task = TaskState() }   // turning Ready by off also ends a top-up it started
        }
        else if p.count >= 3, p[1] == "zone" {
            let name = String(p[2...].joined(separator: " ").prefix(64))
            state.chargeSchedule.onlyZone = name == "any" ? nil : name
        } else if p.count == 3, p[1] == "on" {
            // spec: weekday@HH:MM[@percent][,...] with 1 = Sunday ... 7 = Saturday
            let slots: [Slot] = p[2].split(separator: ",").compactMap { part in
                let a = part.split(separator: "@"); guard a.count == 2 || a.count == 3, let wd = Int(a[0]), (1...7).contains(wd) else { return nil }
                let t = a[1].split(separator: ":"); guard t.count == 2, let h = Int(t[0]), let m = Int(t[1]),
                                                        (0..<24).contains(h), (0..<60).contains(m) else { return nil }
                let pc = a.count == 3 ? Int(a[2]) ?? 100 : 100
                guard (20...100).contains(pc) else { return nil }
                return Slot(weekday: wd, hour: h, minute: m, percent: pc)
            }
            guard !slots.isEmpty else { return "error: no valid slots" }
            state.chargeSchedule.enabled = true; state.chargeSchedule.slots = slots; state.chargeSchedule.ran = []
        } else { return "error: usage ready off | ready zone <name|any> | ready on <weekday@HH:MM[@percent],...>" }
    case "cancel": state.task = TaskState()
    case "schedule":
        if p.count == 2, p[1] == "off" { state.schedule.enabled = false }
        else if p.count == 5, p[1] == "on", let h = Int(p[3]), let m = Int(p[4]), (0..<24).contains(h), (0..<60).contains(m) {
            let days = p[2].split(separator: ",").compactMap { Int($0) }.filter { (1...31).contains($0) }
            guard !days.isEmpty else { return "error: no valid days" }
            state.schedule.enabled = true; state.schedule.days = days; state.schedule.hour = h; state.schedule.minute = m
        } else { return "error: usage schedule off | schedule on <d1,d2,..> <hour> <minute>" }
    default: return "error: unknown command"
    }
    saveState(); apply()
    return "ok"
}

func serve() {
    unlink(socketPath)
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: socketPath.utf8CString.map { UInt8(bitPattern: $0) }) }
    // Create the socket owner-only, so there's no window before chown/chmod where anyone else could connect.
    let oldMask = umask(0o177)
    let ok = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
    umask(oldMask)
    guard ok == 0, listen(fd, 8) == 0 else { print("socket setup failed"); exit(1) }
    chown(socketPath, 0, 80)       // root:admin, so only administrators (and root) can change charging
    chmod(socketPath, 0o660)
    while true {
        let c = accept(fd, nil, nil)
        guard c >= 0 else { usleep(100_000); continue }    // e.g. out of descriptors: back off instead of spinning a core
        var tv = timeval(tv_sec: 2, tv_usec: 0)   // a silent client must not freeze the daemon
        setsockopt(c, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var buf = [UInt8](repeating: 0, count: 512)
        let n = read(c, &buf, buf.count)
        if n > 0 {
            // One command per connection: only the first line counts, so stray bytes can't smuggle a second one in.
            let text = String(decoding: buf[0..<n], as: UTF8.self)
            let line = String(text.split(whereSeparator: \.isNewline).first ?? "").trimmingCharacters(in: .whitespaces)
            let reply = queue.sync { handle(line) } + "\n"
            _ = reply.withCString { write(c, $0, strlen($0)) }
        }
        close(c)
    }
}

// A client that gives up before the reply would otherwise kill us with SIGPIPE on write, skipping the cleanup below.
signal(SIGPIPE, SIG_IGN)
// Never leave the Mac with its charger cut off if we exit.
for sig in [SIGTERM, SIGINT] {
    signal(sig, SIG_IGN)
    let src = DispatchSource.makeSignalSource(signal: sig, queue: queue)
    src.setEventHandler { try? backend.setAdapter(on: true); print("exit: adapter restored"); exit(0) }
    src.resume()
    _ = Unmanaged.passRetained(src)
}

loadState()
if state.lowPower { setLowPower(true) }
if !state.task.active { try? backend.setAdapter(on: true) }
print("baldented started, backend \(backend.name), state \(state)")

onPowerChange = { queue.async { apply() } }
// Re-check on power events, with a timer as backup.
let ctx = Unmanaged.passRetained(NSObject()).toOpaque()
if let rl = IOPSNotificationCreateRunLoopSource(powerCallback, ctx)?.takeRetainedValue() {
    CFRunLoopAddSource(CFRunLoopGetMain(), rl, .defaultMode)
}
let timer = DispatchSource.makeTimerSource(queue: queue)
timer.schedule(deadline: .now(), repeating: 20)
timer.setEventHandler { apply() }
timer.resume()
Thread.detachNewThread { serve() }
CFRunLoopRun()
