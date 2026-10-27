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
let chargeKeys = ChargeKeys.watched.filter { SMC.hasKey($0) }   // read once: only a reboot after a macOS update changes it
var batteryHot = false

/// Fixed Gregorian POSIX format, so the "already ran today" check can't drift with the system calendar or locale.
func today() -> String { dayString(Date()) }

/// Starting one, by any route, fulfils a pending one-off plan and today's repeat, so neither runs a second calibration afterwards.
func startCalibration() {
    state.task = CalibrationRun.start()
    state.calibrateAt = nil
    state.schedule.lastRun = today()
    print("calibration started")
}

var wakeAssertion: IOPMAssertionID = 0
var startingSoon = false
var readyWake: Date?
var plugged = true
var curAdapterOn = true
/// True from "will sleep" until the Mac is fully awake, with the charger cut for the Stop-charging-when-sleeping option.
var sleepHold = false
var lastLED: UInt8?
let ledAvailable = SMC.hasKey(MagSafeLED.key)

/// Keeps the Mac awake (even lid closed, on AC) while a top-up is running.
func holdAwake(_ on: Bool) {
    if on, wakeAssertion == 0 {
        IOPMAssertionCreateWithName(kIOPMAssertionTypePreventSystemSleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                    "BalDente keeping the Mac awake" as CFString, &wakeAssertion)
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

/// Runs the scheduled tasks that are due. Returns nothing: every outcome, including a skip, goes to the task history.
func runDueTasks(_ pct: Int) {
    let now = Date()
    var changed = false
    for i in state.tasks.indices {
        guard let when = state.tasks[i].due(at: now) else { continue }
        let t = state.tasks[i]
        state.tasks[i].lastRun = when
        if t.repeats == .once { state.tasks[i].enabled = false }
        let note = perform(t, pct)
        state.taskLog = Array((state.taskLog + [TaskRun(date: now, taskID: t.id, action: t.action, note: note)]).suffix(TaskRun.maxKept))
        print("scheduled task \(t.action.rawValue): \(note)")
        changed = true
    }
    if changed { saveState() }
}

func perform(_ t: ScheduledTask, _ pct: Int) -> String {
    switch t.action {
    case .lowPowerOn, .lowPowerOff:
        state.lowPower = t.action == .lowPowerOn; setLowPower(state.lowPower); return "Done"
    case .topUp:
        guard !state.task.active else { return "Skipped: another task is running" }
        guard plugged else { return "Skipped: not plugged in" }
        state.task = TaskState(); state.task.kind = "topup"; state.task.target = 100
        state.task.restUntil = Date().addingTimeInterval(12 * 3600)
        return "Started"
    case .discharge:
        guard !state.task.active else { return "Skipped: another task is running" }
        guard pct > t.percent else { return "Skipped: already at \(pct)%" }
        state.task = TaskState(); state.task.kind = "discharge"; state.task.target = t.percent
        return "Started"
    case .calibrate:
        guard !state.task.active else { return "Skipped: another task is running" }
        guard !CalibrationRun.ranRecently(state.lastCalibrated) else { return "Skipped: calibrated recently" }
        startCalibration(); return "Started"
    }
}

/// Right before the Mac sleeps: cut the charger so it cannot charge past the limit while nothing is running to stop it.
func stopChargingForSleep() {
    guard state.stopWhenSleeping, !state.task.active, plugged, let pct = batteryPercent(),
          pct > LimiterState.sleepFloor, pct < 100 else { return }
    do { try backend.setAdapter(on: false); sleepHold = true; print("sleeping at \(pct)%: charger held") }
    catch { print("sleep hold failed: \(error)") }
}

/// Drives the MagSafe LED, and only writes when the wanted value changes. Never touches the key unless the user chose a mode.
func updateLED(plugged: Bool, holding: Bool) {
    guard ledAvailable else { return }
    let v = state.led.value(plugged: plugged, holding: holding, atLimit: state.ledAtLimit, charging: state.ledCharging)
    if v == nil && lastLED == nil { return }
    let target = v ?? MagSafeLED.systemValue
    guard target != lastLED else { return }
    do { try SMC.writeByte(MagSafeLED.key, target); lastLED = target } catch { print("LED write failed: \(error)") }
}

/// Starts the scheduled calibration once per day, at or after the chosen time.
func checkSchedule(_ pct: Int) {
    checkReadyBy(pct)
    if let at = state.calibrateAt {
        if Date() > at.addingTimeInterval(3 * 3600) { state.calibrateAt = nil; saveState() }   // missed by hours: don't start at noon
        else if Date() >= at, state.task.kind == "calibrate" || CalibrationRun.ranRecently(state.lastCalibrated) {
            state.calibrateAt = nil; saveState(); print("planned calibration skipped: one is running or just ran")
        }
        else if Date() >= at, !state.task.active { startCalibration(); saveState(); return }
    }
    let s = state.schedule
    guard s.enabled, !state.task.active, s.lastRun != today(), !CalibrationRun.ranRecently(state.lastCalibrated) else { return }
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
        let r = CalibrationRun.advance(t, percent: pct)
        if r.task.phase != t.phase, r.task.active { print("calibration: \(r.task.phase) at \(pct)%") }
        t = r.task
        switch r.outcome {
        case .finished: state.lastCalibrated = Date(); print("calibration finished")
        case .timedOut: print("calibration gave up after \(Int(CalibrationRun.maxDuration / 3600)) h at \(pct)%")
        case .running: break
        }
        return r.adapterOn
    default: return nil
    }
}

func apply() {
    guard !sleepHold, let pct = batteryPercent() else { return }
    checkSchedule(pct)
    let now0 = Date()
    if let at = state.calibrateAt, at.timeIntervalSince(now0) <= 300 { startingSoon = true }
    syncWake([readyWake, state.calibrateAt].compactMap { $0 }.filter { $0 > now0 }.min())
    let adapterOn = backend.isAdapterOn()
    curAdapterOn = adapterOn
    let batt = BatteryInfo.read()
    let temp = batt?.tempC
    plugged = batt?.plugged ?? true
    runDueTasks(pct)

    // Track heat even while a task runs, so the status never reports a stale "cooling down" and the pause resumes correctly after it.
    if state.heatProtection, let t = temp {
        if t >= Double(state.heatLimit) { batteryHot = true } else if t <= Double(state.heatLimit - 3) { batteryHot = false }
    } else { batteryHot = false }
    var want: Bool
    if let task = advanceTask(pct) {
        want = task
        heatHold = false        // tasks have their own (45 °C) cutoff below; heat protection isn't what's holding the charger
    } else {
        heatHold = HeatLimit.shouldHold(hot: batteryHot, percent: pct)   // never run a low battery flat to cool it
        if heatHold { want = false }
        else if !state.enabled { want = true }
        else if pct >= state.upper {
            var load = [0.0]
            _ = getloadavg(&load, 1)
            want = LoadGuard.keepCharging(enabled: state.loadGuard, load1: load[0], cores: ProcessInfo.processInfo.activeProcessorCount,
                                          percent: pct, upper: state.upper)   // busy and only just at the limit: don't run the Mac from its battery
        }
        else if pct <= state.lower { want = true }
        else { want = adapterOn }   // inside the sailing range: leave things as they are
    }
    if state.task.kind == "topup", let t = temp, t >= Double(HeatLimit.ratedChargeMax) { want = false }   // too hot even for a top up
    holdAwake((state.task.kind == "calibrate" && state.task.pausedAt == nil) || startingSoon || (state.stayAwake && plugged && want && state.enabled && pct < state.upper))   // a topup keeps charging while asleep; calibration needs the Mac awake
    if pct <= 5 { want = true }     // never strand the battery
    updateLED(plugged: plugged, holding: !want && !heatHold)
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
                       backend: backend.name, tempC: BatteryInfo.read()?.tempC, heatHold: heatHold, ledAvailable: ledAvailable,
                       heatSkipped: state.heatProtection && batteryHot && !heatHold && !state.task.active, chargeKeys: chargeKeys)
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
        else if p.count == 2, p[1] == "pause" || p[1] == "resume" {
            guard state.task.kind == "calibrate" else { return "error: no calibration is running" }
            state.task = p[1] == "pause" ? CalibrationRun.pause(state.task) : CalibrationRun.resume(state.task)
        }
        else if state.task.kind == "calibrate" { return "error: a calibration is already running" }
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
        } else if p.count == 3, p[1] == "travel", let m = Int(p[2]) {
            state.chargeSchedule.travelMinutes = LeaveTime.clampTravel(m)
        } else { return "error: usage ready off | ready zone <name|any> | ready travel <minutes> | ready on <weekday@HH:MM[@percent],...>" }
    case "cancel":
        if state.task.kind == "calibrate" { state.calibrateAt = nil; print("calibration cancelled") }   // a leftover plan must not start another one later
        state.task = TaskState()
    case "loadguard":
        guard p.count == 2, ["on", "off"].contains(p[1]) else { return "error: usage loadguard on|off" }
        state.loadGuard = p[1] == "on"
    case "sleepstop", "stayawake":
        guard p.count == 2, ["on", "off"].contains(p[1]) else { return "error: usage \(p[0]) on|off" }
        if p[0] == "sleepstop" { state.stopWhenSleeping = p[1] == "on" } else { state.stayAwake = p[1] == "on" }
    case "led":
        guard p.count >= 2, let m = MagSafeLED(rawValue: p[1]) else { return "error: usage led system|indicate|off|custom [limitColor chargeColor]" }
        if m == .custom, p.count == 4 {
            guard let a = LEDColor(rawValue: p[2]), let c = LEDColor(rawValue: p[3]) else { return "error: colours are default|off|green|orange" }
            state.ledAtLimit = a; state.ledCharging = c
        } else if p.count != 2 { return "error: usage led custom <limitColor> <chargeColor>" }
        state.led = m
    case "task":
        guard p.count >= 2 else { return "error: usage task add|remove|enable|clear ..." }
        switch p[1] {
        case "add":
            guard let t = ScheduledTask.parse(Array(p.dropFirst(2))) else { return "error: bad task" }
            let before = state.tasks.count
            state.tasks = TaskBook.upsert(state.tasks, t, now: Date())
            if state.tasks.count == before, !state.tasks.contains(where: { $0.id == t.id }) { return "error: at most \(ScheduledTask.maxCount) tasks" }
        case "remove":
            guard p.count == 3, ScheduledTask.validID(p[2]) else { return "error: usage task remove <id>" }
            state.tasks.removeAll { $0.id == p[2] }
        case "enable":
            guard p.count == 4, ScheduledTask.validID(p[2]), ["on", "off"].contains(p[3]) else { return "error: usage task enable <id> on|off" }
            if let i = state.tasks.firstIndex(where: { $0.id == p[2] }) { state.tasks[i].enabled = p[3] == "on"; if p[3] == "on" { state.tasks[i].lastRun = Date() } }
        case "clear": state.tasks = []; state.taskLog = []
        default: return "error: usage task add|remove|enable|clear ..."
        }
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
    src.setEventHandler {
        try? backend.setAdapter(on: true)
        if lastLED != nil { try? SMC.writeByte(MagSafeLED.key, MagSafeLED.systemValue) }   // hand the LED back to macOS
        print("exit: adapter restored"); exit(0)
    }
    src.resume()
    _ = Unmanaged.passRetained(src)
}

loadState()
if state.lowPower { setLowPower(true) }
if !state.task.active { try? backend.setAdapter(on: true) }
print("baldented started, backend \(backend.name), state \(state)")

onPowerChange = { queue.async { apply() } }
onSleepMessage = { type in
    switch type {
    case SleepMessage.willSleep: queue.sync { stopChargingForSleep() }
    case SleepMessage.poweredOn: queue.async { sleepHold = false; apply() }
    default: break
    }
}
registerForSleep()
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
