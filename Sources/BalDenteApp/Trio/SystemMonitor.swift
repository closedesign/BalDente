import AppKit
import AudioToolbox
import BalDenteCore
import Carbon
import CoreAudio
import CoreWLAN
import Darwin
import IOBluetooth
import IOKit.ps
import Network

// MARK: Snapshots

struct PowerSnap: Equatable {
    var present = false
    var percent = 0
    var plugged = false
    var charging = false
    var charged = false
    var lowPower = false
    var minutesToFull: Int?
    var minutesToEmpty: Int?
    var adapterWatts: Int?
}

enum NetKind: Equatable { case wifi(bars: Int), ethernet, hotspot, notAssociated, wifiOff, offline, noInternet }

struct NetSnap: Equatable {
    var kind = NetKind.offline
    var interface: String?
    var ssid: String?
    var bssid: String?
    var rssi = 0
    var noise = 0
    var channel: Int?
    var band: String?
    var txRate: Double?
    var security: String?
    var localIP: String?
    var router: String?
    var vpn: [String] = []

    var isProblem: Bool { [.offline, .noInternet, .wifiOff, .notAssociated].contains(kind) }
}

struct AudioDevice: Identifiable, Equatable {
    var id: AudioDeviceID
    var name: String
    var bluetooth: Bool
}

struct AudioSnap: Equatable {
    var outputs: [AudioDevice] = []
    var output: AudioDevice?
    var volume: Double?          // nil: the device has no software volume (e.g. HDMI)
    var muted = false
    var inputs: [AudioDevice] = []
    var input: AudioDevice?
    var inputVolume: Double?
    var inputMuted = false
}

struct BTDevice: Identifiable, Equatable {
    var id: String               // address
    var name: String
    var connected: Bool
    var kind: String
    var battery: Int?
    var left: Int?
    var right: Int?
    var caseLevel: Int?

    var symbol: String { SystemMonitor.bluetoothSymbol(name: name, kind: kind) }
}

struct BTSnap: Equatable {
    var powered: Bool?
    var devices: [BTDevice] = []
    var loaded = false
}

struct InputSourceItem: Identifiable, Equatable {
    var id: String
    var name: String
    var short: String
    var selected: Bool
}

// IOKit power notifications call a plain C function, so the hook lives in a global.
nonisolated(unsafe) private var powerSourcesChanged: (() -> Void)?
private let powerSourcesCallback: IOPowerSourceCallbackType = { _ in powerSourcesChanged?() }

/// Live system state for the status icon and panel. Event driven where macOS offers events,
/// with a slow poll as a fallback (signal strength has no notification).
@MainActor
final class SystemMonitor: ObservableObject {
    @Published private(set) var power = PowerSnap()
    @Published private(set) var net = NetSnap()
    @Published private(set) var audio = AudioSnap()
    @Published private(set) var bluetooth = BTSnap()
    @Published private(set) var inputSources: [InputSourceItem] = []
    @Published private(set) var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    @Published private(set) var displayAsleep = false
    /// Plays the charging animation without a charger, for trying out settings. Never saved.
    @Published var testCharging = ProcessInfo.processInfo.environment["BALDENTE_TEST_CHARGING"] != nil
    /// Bumped on plug-in (true) or each percent gained while charging (false), so the icon can play a short burst.
    @Published private(set) var chargeEvent: (date: Date, plugIn: Bool)?

    var effectivePower: PowerSnap {
        guard testCharging else { return power }
        var p = power; p.present = true; p.plugged = true; p.charging = true; p.charged = false
        return p
    }

    private let pathMonitor = NWPathMonitor()
    private var path: NWPath?
    private var poll: Timer?
    private var observers: [NSObjectProtocol] = []
    private var volumeDevice: AudioDeviceID = 0
    private var inputDevice: AudioDeviceID = 0
    private let audioListener: AudioObjectPropertyListenerBlock
    private var btTask: Task<Void, Never>?

    init() {
        weak var weakSelf: SystemMonitor?
        audioListener = { _, _ in DispatchQueue.main.async { weakSelf?.refreshAudio() } }
        weakSelf = self

        powerSourcesChanged = { DispatchQueue.main.async { weakSelf?.refreshPower() } }
        if let src = IOPSNotificationCreateRunLoopSource(powerSourcesCallback, nil)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
        }
        pathMonitor.pathUpdateHandler = { p in DispatchQueue.main.async { weakSelf?.path = p; weakSelf?.refreshNetwork() } }
        pathMonitor.start(queue: .global(qos: .utility))

        for sel in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultInputDevice, kAudioHardwarePropertyDevices] {
            var a = AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &a, nil, audioListener)
        }

        let ws = NSWorkspace.shared.notificationCenter
        observers += [
            ws.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { weakSelf?.displayAsleep = true }
            },
            ws.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { weakSelf?.displayAsleep = false; weakSelf?.refreshAll() }
            },
            ws.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { weakSelf?.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
            },
            NotificationCenter.default.addObserver(forName: Notification.Name.NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { weakSelf?.refreshPower() }
            },
            DistributedNotificationCenter.default().addObserver(
                forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { weakSelf?.refreshInputSources() }
            },
            DistributedNotificationCenter.default().addObserver(
                forName: NSNotification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String), object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { weakSelf?.refreshInputSources() }
            },
        ]
        refreshAll()
        refreshBluetooth()
    }

    func setPollInterval(_ seconds: Int) {
        poll?.invalidate()
        poll = Timer.scheduledTimer(withTimeInterval: TimeInterval(max(2, seconds)), repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.displayAsleep else { return }
                self.refreshPower(); self.refreshNetwork()
            }
        }
        poll?.tolerance = Double(seconds) * 0.2
    }

    func refreshAll() {
        refreshPower(); refreshNetwork(); refreshAudio(); refreshInputSources()
    }

    // MARK: Battery

    func refreshPower() {
        var p = PowerSnap()
        p.lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
            for ps in list {
                guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                      d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
                let cur = d[kIOPSCurrentCapacityKey] as? Int ?? 0, mx = d[kIOPSMaxCapacityKey] as? Int ?? 100
                p.present = d[kIOPSIsPresentKey] as? Bool ?? true
                p.percent = mx > 0 ? min(100, max(0, Int((Double(cur) * 100 / Double(mx)).rounded()))) : cur
                p.plugged = d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
                p.charging = d[kIOPSIsChargingKey] as? Bool ?? false
                p.charged = d[kIOPSIsChargedKey] as? Bool ?? false
                p.minutesToFull = (d[kIOPSTimeToFullChargeKey] as? Int).flatMap { $0 > 0 ? $0 : nil }
                p.minutesToEmpty = (d[kIOPSTimeToEmptyKey] as? Int).flatMap { $0 > 0 ? $0 : nil }
            }
        }
        if p.plugged, let a = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any] {
            p.adapterWatts = a[kIOPSPowerAdapterWattsKey] as? Int
        }
        if p.plugged && !power.plugged && power.present { chargeEvent = (Date(), true) }
        else if p.charging && power.charging && p.percent > power.percent { chargeEvent = (Date(), false) }
        if p != power { power = p }
    }

    // MARK: Network

    func refreshNetwork() {
        let path = self.path
        Task.detached(priority: .utility) { [weak self] in
            let snap = Self.readNetwork(path)
            await MainActor.run { [weak self] in if let self, snap != self.net { self.net = snap } }
        }
    }

    nonisolated private static func readNetwork(_ path: NWPath?) -> NetSnap {
        var n = NetSnap()
        let wifi = CWWiFiClient.shared().interface()
        let wifiOn = wifi?.powerOn() ?? false
        if let w = wifi, wifiOn {
            n.ssid = w.ssid(); n.bssid = w.bssid()
            n.rssi = w.rssiValue(); n.noise = w.noiseMeasurement()
            n.txRate = w.transmitRate() > 0 ? w.transmitRate() : nil
            if let ch = w.wlanChannel() {
                n.channel = ch.channelNumber
                switch ch.channelBand {
                case .band2GHz: n.band = "2.4"
                case .band5GHz: n.band = "5"
                case .band6GHz: n.band = "6"
                default: break
                }
            }
            n.security = securityName(w.security())
        }
        let associated = wifiOn && (n.rssi != 0 || n.bssid != nil || n.ssid != nil)
        if let p = path, p.status == .satisfied {
            // A VPN (utun, type .other) sits first in the path and owns the default route, so judge the
            // link by the first physical interface underneath it rather than by the path as a whole.
            let physical = p.availableInterfaces.first { $0.type != .other && $0.type != .loopback }
            n.interface = physical?.name ?? p.availableInterfaces.first?.name
            switch physical?.type {
            case .wifi: n.kind = p.isExpensive ? .hotspot : .wifi(bars: max(1, TrioRules.wifiBars(rssi: n.rssi)))
            case .cellular: n.kind = .hotspot
            case .wiredEthernet: n.kind = .ethernet
            default:
                // Only tunnels are listed: fall back to Wi-Fi if it's associated, else it's some wired link.
                n.kind = associated ? .wifi(bars: max(1, TrioRules.wifiBars(rssi: n.rssi))) : .ethernet
                if associated { n.interface = wifi?.interfaceName }
            }
        } else {
            n.kind = !wifiOn && wifi != nil ? .wifiOff : associated ? .noInternet : wifiOn ? .notAssociated : .offline
        }
        let addrs = interfaceAddresses()
        n.localIP = n.interface.flatMap { addrs[$0]?.first } ?? (associated ? wifi?.interfaceName.flatMap { addrs[$0]?.first } : nil)
        n.vpn = addrs.filter { name, ips in
            ["utun", "ppp", "ipsec", "tap", "tun"].contains { name.hasPrefix($0) } && ips.contains { !$0.hasPrefix("169.254.") }
        }.keys.sorted()
        if path?.status == .satisfied { n.router = NetworkInfo.gatewayIP() }
        return n
    }

    nonisolated private static func securityName(_ s: CWSecurity) -> String? {
        switch s {
        case .none: "Open"
        case .WEP, .dynamicWEP: "WEP"
        case .wpaPersonal, .wpaPersonalMixed: "WPA Personal"
        case .wpa2Personal: "WPA2 Personal"
        case .personal: "WPA2/WPA3 Personal"
        case .wpa3Personal: "WPA3 Personal"
        case .wpa3Transition: "WPA2/WPA3 Personal"
        case .wpaEnterprise, .wpaEnterpriseMixed, .wpa2Enterprise, .enterprise, .wpa3Enterprise: "Enterprise"
        default: nil
        }
    }

    /// Up interfaces and their IPv4 addresses.
    nonisolated static func interfaceAddresses() -> [String: [String]] {
        var out: [String: [String]] = [:]
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return out }
        defer { freeifaddrs(head) }
        var p = head
        while let i = p?.pointee {
            defer { p = i.ifa_next }
            guard let sa = i.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET), i.ifa_flags & UInt32(IFF_UP) != 0,
                  i.ifa_flags & UInt32(IFF_LOOPBACK) == 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let len = host.firstIndex(of: 0) ?? host.count
            out[String(cString: i.ifa_name), default: []].append(String(decoding: host[..<len].map { UInt8(bitPattern: $0) }, as: UTF8.self))
        }
        return out
    }

    // MARK: Audio

    func refreshAudio() {
        var a = AudioSnap()
        let devices = CA.array(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices).filter { CA.alive($0) }
        func device(_ id: AudioDeviceID) -> AudioDevice { AudioDevice(id: id, name: CA.name(id), bluetooth: CA.isBluetooth(id)) }
        a.outputs = devices.filter { CA.hasStreams($0, kAudioObjectPropertyScopeOutput) }.map(device)
        a.inputs = devices.filter { CA.hasStreams($0, kAudioObjectPropertyScopeInput) }.map(device)
        let out: AudioDeviceID = CA.value(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice) ?? 0
        let inp: AudioDeviceID = CA.value(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultInputDevice) ?? 0
        if out != 0 {
            a.output = device(out)
            a.volume = CA.volume(out, kAudioObjectPropertyScopeOutput)
            a.muted = CA.muted(out, kAudioObjectPropertyScopeOutput)
        }
        if inp != 0 {
            a.input = device(inp)
            a.inputVolume = CA.volume(inp, kAudioObjectPropertyScopeInput)
            a.inputMuted = CA.muted(inp, kAudioObjectPropertyScopeInput)
        }
        watch(&volumeDevice, out, kAudioObjectPropertyScopeOutput)
        watch(&inputDevice, inp, kAudioObjectPropertyScopeInput)
        if a != audio { audio = a }
    }

    /// Follows volume and mute changes on whichever device is the current default.
    private func watch(_ current: inout AudioDeviceID, _ new: AudioDeviceID, _ scope: AudioObjectPropertyScope) {
        guard current != new else { return }
        for (id, add) in [(current, false), (new, true)] where id != 0 {
            for sel in [kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyMute] {
                for el in [kAudioObjectPropertyElementMain, 1] {
                    var addr = AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: el)
                    guard AudioObjectHasProperty(id, &addr) else { continue }
                    if add { AudioObjectAddPropertyListenerBlock(id, &addr, nil, audioListener) }
                    else { AudioObjectRemovePropertyListenerBlock(id, &addr, nil, audioListener) }
                }
            }
        }
        current = new
    }

    func setVolume(_ v: Double, input: Bool = false) {
        guard let d = input ? audio.input : audio.output else { return }
        let scope = input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput
        CA.setVolume(d.id, scope, min(1, max(0, v)))
        if !input, audio.muted, v > 0 { CA.setMuted(d.id, scope, false) }
        refreshAudio()
    }

    func toggleMute(input: Bool = false) {
        guard let d = input ? audio.input : audio.output else { return }
        CA.setMuted(d.id, input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput, !(input ? audio.inputMuted : audio.muted))
        refreshAudio()
    }

    func selectDevice(_ id: AudioDeviceID, input: Bool = false) {
        var v = id
        var a = AudioObjectPropertyAddress(mSelector: input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice,
                                           mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &v)
        if !input {   // alerts follow the output too, as they do when switching in Control Center
            a.mSelector = kAudioHardwarePropertyDefaultSystemOutputDevice
            AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &v)
        }
        refreshAudio()
    }

    // MARK: Bluetooth

    /// system_profiler is slow (about a second), so it only runs when asked and never on the main thread.
    func refreshBluetooth() {
        btTask?.cancel()
        btTask = Task.detached(priority: .utility) { [weak self] in
            let snap = Self.readBluetooth()
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in if let self, snap != self.bluetooth { self.bluetooth = snap } }
        }
    }

    nonisolated private static func readBluetooth() -> BTSnap {
        var s = BTSnap(loaded: true)
        s.powered = BluetoothPower.read()
        let json = NetworkInfo.run("/usr/sbin/system_profiler", ["SPBluetoothDataType", "-json", "-detailLevel", "basic"])
        guard let root = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any],
              let section = (root["SPBluetoothDataType"] as? [[String: Any]])?.first else { return s }
        if s.powered == nil, let c = section["controller_properties"] as? [String: Any] {
            s.powered = (c["controller_state"] as? String) == "attrib_on"
        }
        func pct(_ v: Any?) -> Int? { (v as? String).flatMap { Int($0.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)) } }
        for (key, connected) in [("device_connected", true), ("device_not_connected", false)] {
            for entry in section[key] as? [[String: Any]] ?? [] {
                for (name, v) in entry {
                    guard let p = v as? [String: Any], let addr = p["device_address"] as? String else { continue }
                    s.devices.append(BTDevice(id: addr, name: name, connected: connected, kind: p["device_minorType"] as? String ?? "",
                                              battery: pct(p["device_batteryLevelMain"]) ?? pct(p["device_batteryLevel"]),
                                              left: pct(p["device_batteryLevelLeft"]), right: pct(p["device_batteryLevelRight"]),
                                              caseLevel: pct(p["device_batteryLevelCase"])))
                }
            }
        }
        return s
    }

    func setConnected(_ device: BTDevice, _ on: Bool) {
        let addr = device.id
        Task.detached(priority: .userInitiated) { [weak self] in
            if let d = IOBluetoothDevice(addressString: addr) {
                _ = on ? d.openConnection() : d.closeConnection()
            }
            await MainActor.run { [weak self] in self?.refreshBluetooth(); self?.refreshAudio() }
        }
    }

    func setBluetoothPower(_ on: Bool) {
        BluetoothPower.set(on)
        Task { try? await Task.sleep(for: .seconds(1.5)); refreshBluetooth() }
    }

    nonisolated static func bluetoothSymbol(name: String, kind: String) -> String {
        let n = name.lowercased(), k = kind.lowercased()
        if n.contains("airpods max") { return "airpodsmax" }
        if n.contains("airpods pro") { return "airpodspro" }
        if n.contains("airpods") { return "airpods" }
        if n.contains("beats") || n.contains("headphone") || k.contains("headphone") { return "headphones" }
        if k.contains("headset") { return "headset" }
        if k.contains("speaker") || n.contains("speaker") || n.contains("homepod") { return "hifispeaker.fill" }
        if k.contains("keyboard") || n.contains("keyboard") { return "keyboard" }
        if k.contains("mouse") || n.contains("mouse") { return "magicmouse.fill" }
        if k.contains("trackpad") || n.contains("trackpad") { return "rectangle.and.hand.point.up.left.fill" }
        if k.contains("gamepad") || n.contains("controller") { return "gamecontroller.fill" }
        if n.contains("iphone") || k.contains("phone") { return "iphone" }
        return "headphones"
    }

    // MARK: Input sources

    func refreshInputSources() {
        let filter: [String: Any] = [kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String,
                                     kTISPropertyInputSourceIsSelectCapable as String: true]
        guard let list = TISCreateInputSourceList(filter as CFDictionary, false)?.takeRetainedValue() as? [TISInputSource] else { return }
        let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
        let currentID = current.flatMap { Self.tisString($0, kTISPropertyInputSourceID) }
        let items: [InputSourceItem] = list.compactMap { src in
            guard let id = Self.tisString(src, kTISPropertyInputSourceID),
                  let type = Self.tisString(src, kTISPropertyInputSourceType),
                  [kTISTypeKeyboardLayout as String, kTISTypeKeyboardInputMode as String].contains(type) else { return nil }
            let name = Self.tisString(src, kTISPropertyLocalizedName) ?? id
            var lang = "?"
            if let p = TISGetInputSourceProperty(src, kTISPropertyInputSourceLanguages),
               let langs = Unmanaged<CFArray>.fromOpaque(p).takeUnretainedValue() as? [String], let f = langs.first {
                lang = String(f.prefix(2)).uppercased()
            }
            return InputSourceItem(id: id, name: name, short: lang, selected: id == currentID)
        }
        if items != inputSources { inputSources = items }
    }

    func selectInputSource(_ id: String) {
        let filter: [String: Any] = [kTISPropertyInputSourceID as String: id]
        if let src = (TISCreateInputSourceList(filter as CFDictionary, false)?.takeRetainedValue() as? [TISInputSource])?.first {
            TISSelectInputSource(src)
        }
        refreshInputSources()
    }

    nonisolated private static func tisString(_ src: TISInputSource, _ key: CFString) -> String? {
        guard let p = TISGetInputSourceProperty(src, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue() as String
    }
}

// MARK: CoreAudio helpers

enum CA {
    static func addr(_ sel: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                     _ el: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: el)
    }

    static func value<T>(_ id: AudioObjectID, _ sel: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                         _ el: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> T? {
        var a = addr(sel, scope, el)
        guard AudioObjectHasProperty(id, &a) else { return nil }
        var size = UInt32(MemoryLayout<T>.size)
        let p = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<T>.alignment)
        defer { p.deallocate() }
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, p) == noErr else { return nil }
        return p.load(as: T.self)
    }

    static func array(_ id: AudioObjectID, _ sel: AudioObjectPropertySelector) -> [AudioObjectID] {
        var a = addr(sel), size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &a, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    static func name(_ id: AudioObjectID) -> String {
        var a = addr(kAudioObjectPropertyName)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, &name) == noErr, let n = name else { return "Unknown device" }
        return n.takeRetainedValue() as String
    }

    static func alive(_ id: AudioObjectID) -> Bool {
        let hidden: UInt32 = value(id, kAudioDevicePropertyIsHidden) ?? 0
        let alive: UInt32 = value(id, kAudioDevicePropertyDeviceIsAlive) ?? 1
        return hidden == 0 && alive != 0
    }

    static func hasStreams(_ id: AudioObjectID, _ scope: AudioObjectPropertyScope) -> Bool {
        var a = addr(kAudioDevicePropertyStreams, scope), size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &a, 0, nil, &size) == noErr && size > 0
    }

    static func isBluetooth(_ id: AudioObjectID) -> Bool {
        let t: UInt32 = value(id, kAudioDevicePropertyTransportType) ?? 0
        return t == kAudioDeviceTransportTypeBluetooth || t == kAudioDeviceTransportTypeBluetoothLE
    }

    static func volume(_ id: AudioObjectID, _ scope: AudioObjectPropertyScope) -> Double? {
        if let v: Float32 = value(id, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope) { return Double(v) }
        if let v: Float32 = value(id, kAudioDevicePropertyVolumeScalar, scope) { return Double(v) }
        if let v: Float32 = value(id, kAudioDevicePropertyVolumeScalar, scope, 1) { return Double(v) }
        return nil
    }

    static func muted(_ id: AudioObjectID, _ scope: AudioObjectPropertyScope) -> Bool {
        let m: UInt32 = value(id, kAudioDevicePropertyMute, scope) ?? 0
        return m != 0
    }

    @discardableResult
    static func set<T>(_ id: AudioObjectID, _ sel: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope,
                       _ el: AudioObjectPropertyElement = kAudioObjectPropertyElementMain, _ v: T) -> Bool {
        var a = addr(sel, scope, el)
        var settable: DarwinBoolean = false
        guard AudioObjectHasProperty(id, &a), AudioObjectIsPropertySettable(id, &a, &settable) == noErr, settable.boolValue else { return false }
        var value = v
        let size = UInt32(MemoryLayout<T>.size)
        return withUnsafePointer(to: &value) { AudioObjectSetPropertyData(id, &a, 0, nil, size, $0) } == noErr
    }

    static func setVolume(_ id: AudioObjectID, _ scope: AudioObjectPropertyScope, _ v: Double) {
        if set(id, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope, kAudioObjectPropertyElementMain, Float32(v)) { return }
        if set(id, kAudioDevicePropertyVolumeScalar, scope, kAudioObjectPropertyElementMain, Float32(v)) { return }
        for ch: UInt32 in [1, 2] { set(id, kAudioDevicePropertyVolumeScalar, scope, ch, Float32(v)) }
    }

    static func setMuted(_ id: AudioObjectID, _ scope: AudioObjectPropertyScope, _ on: Bool) {
        set(id, kAudioDevicePropertyMute, scope, kAudioObjectPropertyElementMain, UInt32(on ? 1 : 0))
    }
}

/// Bluetooth radio power through IOBluetooth's preference calls (not in the public headers, so looked up at runtime).
enum BluetoothPower {
    private typealias GetFn = @convention(c) () -> Int32
    private typealias SetFn = @convention(c) (Int32) -> Void
    nonisolated(unsafe) private static let lib = dlopen("/System/Library/Frameworks/IOBluetooth.framework/IOBluetooth", RTLD_LAZY)

    static var available: Bool { dlsym(lib, "IOBluetoothPreferenceSetControllerPowerState") != nil }

    static func read() -> Bool? {
        guard let s = dlsym(lib, "IOBluetoothPreferenceGetControllerPowerState") else { return nil }
        return unsafeBitCast(s, to: GetFn.self)() == 1
    }

    static func set(_ on: Bool) {
        guard let s = dlsym(lib, "IOBluetoothPreferenceSetControllerPowerState") else { return }
        unsafeBitCast(s, to: SetFn.self)(on ? 1 : 0)
    }
}
