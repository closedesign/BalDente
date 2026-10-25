import AppKit
import BalDenteCore
import Carbon
import Combine
import SwiftUI

/// Remembers SwiftUI's window opener so AppKit code (the status item, its menu, the hotkey) can open scenes.
@MainActor
enum WindowOpener {
    static var action: OpenWindowAction?

    static func open(_ id: String) {
        NSApp.setActivationPolicy(.regular)   // windows need a Dock icon and the app menu while they're up
        if let a = action { a(id: id) }
        else { NSApp.windows.first { $0.identifier?.rawValue.hasPrefix(id) == true }?.makeKeyAndOrderFront(nil) }
        NSApp.activate(ignoringOtherApps: true)
    }
}

// Carbon hotkey events call a plain C function, so the hook lives in a global.
nonisolated(unsafe) private var hotKeyPressed: (() -> Void)?

/// Owns the menu bar icon, the status panel popover and the live Dock tile.
@MainActor
final class StatusItemController: NSObject {
    private let model: Model
    private let system: SystemMonitor
    private var item: NSStatusItem?
    private let popover = NSPopover()
    private var timer: Timer?
    private var animationStart = Date()
    private var bag: Set<AnyCancellable> = []
    private var renderQueued = false
    private var dockView: NSImageView?
    private var hotKey: EventHotKeyRef?
    private var registeredKey: HotKey?
    private var lastDockFrame = Date.distantPast

    init(model: Model) {
        self.model = model
        self.system = model.system
        super.init()
        popover.behavior = .transient
        popover.animates = true
        let host = NSHostingController(rootView: StatusPanel(model: model, system: system))
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        popover.delegate = self

        model.objectWillChange.sink { [weak self] in self?.queueRender() }.store(in: &bag)
        system.objectWillChange.sink { [weak self] in self?.queueRender() }.store(in: &bag)
        NotificationCenter.default.addObserver(self, selector: #selector(windowClosed(_:)), name: NSWindow.willCloseNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(windowBecameKey(_:)), name: NSWindow.didBecomeKeyNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(themeChanged),
                                                            name: NSNotification.Name("AppleInterfaceThemeChangedNotification"), object: nil)

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in hotKeyPressed?(); return noErr }, 1, &spec, nil, nil)
        hotKeyPressed = { DispatchQueue.main.async { [weak self] in self?.togglePanel() } }
        apply()
        // Nothing publishes between launch and the first poll, so draw now; otherwise the icon stays blank
        // (and a charge already in progress doesn't animate) until something changes.
        queueRender()
    }

    // MARK: Placement, hotkey and refresh rate follow the preferences

    private var lastPrefs: TrioPrefs?

    private func apply() {
        let p = model.trio
        defer { lastPrefs = p }
        if lastPrefs?.placement != p.placement || lastPrefs == nil {
            let wantsItem = p.placement != .dock, wantsDock = p.placement != .menuBar
            if wantsItem, item == nil { makeItem() }
            if !wantsItem, let i = item { NSStatusBar.system.removeStatusItem(i); item = nil; popover.close() }
            if wantsDock {
                NSApp.setActivationPolicy(.regular)
                let v = NSImageView(); dockView = v; NSApp.dockTile.contentView = v
            } else {
                dockView = nil; NSApp.dockTile.contentView = nil; NSApp.dockTile.display()
                if !hasOpenWindow { NSApp.setActivationPolicy(.accessory) }
            }
        }
        if lastPrefs?.refreshSeconds != p.refreshSeconds { system.setPollInterval(p.refreshSeconds) }
        if registeredKey != p.hotKey { registerHotKey(p.hotKey) }
    }

    private func makeItem() {
        let i = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        i.autosaveName = "BalDenteTrio"
        i.button?.target = self
        i.button?.action = #selector(clicked(_:))
        i.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        i.button?.imagePosition = .imageOnly
        item = i
    }

    private func registerHotKey(_ k: HotKey?) {
        if let h = hotKey { UnregisterEventHotKey(h); hotKey = nil }
        registeredKey = k
        guard let k else { return }
        RegisterEventHotKey(k.keyCode, k.modifiers, EventHotKeyID(signature: OSType(0x42444E54), id: 1),
                            GetApplicationEventTarget(), 0, &hotKey)
    }

    private var hasOpenWindow: Bool {
        NSApp.windows.contains { $0.isVisible && $0.styleMask.contains(.titled) && !($0 is NSPanel) }
    }

    /// Without a Dock placement, the Dock icon only shows while a window is open (like Status Trio's settings).
    @objc private func windowClosed(_ n: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, self.model.trio.placement == .menuBar, !self.hasOpenWindow else { return }
            NSApp.setActivationPolicy(.accessory)
        }
    }

    /// Any real window (the dashboard at launch, Settings) brings back the Dock icon and the app menu.
    @objc private func windowBecameKey(_ n: Notification) {
        guard let w = n.object as? NSWindow, w.styleMask.contains(.titled), !(w is NSPanel),
              NSApp.activationPolicy() != .regular else { return }
        NSApp.setActivationPolicy(.regular)
    }

    @objc private func themeChanged() { DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.render() } }

    // MARK: Rendering

    var state: TrioState {
        var s = TrioState(power: system.effectivePower, net: system.net, audio: system.audio,
                          inputShort: system.inputSources.first { $0.selected }?.short)
        s.fullLevel = model.ringFullLevel
        return s
    }

    private func queueRender() {
        guard !renderQueued else { return }
        renderQueued = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.renderQueued = false
            self.apply()
            self.render()
            self.updateAnimation()
        }
    }

    private var waveClock = WaveClock()

    private var chargingAnimates: Bool {
        let p = system.effectivePower
        return p.charging && !p.charged && !system.reduceMotion && !system.displayAsleep
    }
    private var menuAnimates: Bool { item != nil && model.trio.menuBarChargingEffect && chargingAnimates }
    private var dockAnimates: Bool { dockView != nil && model.trio.dockChargingEffect && chargingAnimates }

    private func updateAnimation() {
        let want = menuAnimates || dockAnimates
        if want, timer == nil {
            animationStart = Date()
            let t = Timer(timeInterval: 1 / ChargingFrame.fps, repeats: true) { _ in
                MainActor.assumeIsolated { [weak self] in self?.render() }
            }
            t.tolerance = 0.01
            RunLoop.main.add(t, forMode: .common)   // keep animating while menus track the mouse
            timer = t
        } else if !want, let t = timer {
            t.invalidate(); timer = nil
            render()
        }
    }

    /// Steady 1.8 s cycles, with one short burst right after plugging in or gaining a percent.
    func currentFrame(gap: CGFloat, boltInGap: Bool, progress: Double) -> ChargingFrame? {
        let now = Date()
        var t = now.timeIntervalSince(animationStart), cycle = ChargingFrame.steadyCycle
        if let e = system.chargeEvent, e.date > animationStart.addingTimeInterval(-1) {
            let burst = e.plugIn ? ChargingFrame.plugInBurst : ChargingFrame.levelUpBurst
            let dt = now.timeIntervalSince(e.date)
            if dt < burst { t = dt; cycle = burst } else { t = dt - burst }
        }
        guard var f = ChargingFrame.at(progress: progress, t: t, cycle: cycle, gap: gap, boltInGap: boltInGap) else { return nil }
        // The wave runs on its own clock so its speed is independent of the comet and the plug-in burst.
        f.wavePhase = waveClock.advance(now: now, speed: model.trio.chargeWaveSpeed, cycle: ChargingFrame.steadyCycle)
        return f
    }

    private func frame(for s: TrioState) -> ChargingFrame? {
        let p = model.trio
        let top = TrioRules.topIndicator(charging: s.power.charging, plugged: s.power.plugged, showPercentage: p.showPercentage,
                                         showChargingIndicator: p.showChargingIndicator, percentageWhenConnected: p.percentageWhenConnected)
        let gap: CGFloat = top == .bolt ? TrioGeometry.boltGap * p.symbolScale : top == .number ? TrioGeometry.numberGap * p.symbolScale : 0
        return currentFrame(gap: gap, boltInGap: top == .bolt, progress: TrioRules.ringProgress(percent: s.power.percent, full: s.fullLevel))
    }

    private func render() {
        let s = state, p = model.trio
        let f = timer != nil ? frame(for: s) : nil
        if let b = item?.button {
            let size = CGFloat(min(36, max(16, p.iconSize)))
            b.image = TrioRenderer.image(s, p, size: size, frame: menuAnimates ? f : nil)
            let text = menuText(s)
            if b.title != text {     // render runs at 20 fps while animating; only touch the button when the text changes
                b.title = text
                b.imagePosition = text.isEmpty ? .imageOnly : .imageLeft
            }
            b.setAccessibilityLabel(accessibilityText(s))
            b.toolTip = accessibilityText(s)
        }
        // The Dock redraws a full tile, so it runs at half the menu bar's frame rate.
        if let v = dockView, !dockAnimates || Date().timeIntervalSince(lastDockFrame) > 0.09 {
            lastDockFrame = Date()
            v.image = TrioRenderer.dockImage(s, p, frame: dockAnimates ? f : nil)
            NSApp.dockTile.display()
        }
    }

    private func menuText(_ s: TrioState) -> String {
        let p = s.power, prefs = model.trio
        let top = TrioRules.topIndicator(charging: p.charging, plugged: p.plugged, showPercentage: prefs.showPercentage,
                                         showChargingIndicator: prefs.showChargingIndicator, percentageWhenConnected: prefs.percentageWhenConnected)
        return TrioRules.sideText(present: p.present, percent: p.percent, plugged: p.plugged, charging: p.charging,
                                  minutesToFull: p.minutesToFull, minutesToEmpty: p.minutesToEmpty, top: top,
                                  showPercentWhileCharging: prefs.showPercentWhileCharging, showPercentage: prefs.showPercentage,
                                  percentInMiddle: prefs.percentInMiddle, showTime: prefs.showTimeRemaining)
    }

    private func accessibilityText(_ s: TrioState) -> String {
        let battery = s.power.present ? "Battery \(s.power.percent)%\(s.power.charging ? ", charging" : s.power.plugged ? ", on power" : "")" : "No battery"
        let net: String = switch s.net.kind {
        case .wifi(let b): "Wi-Fi \(s.net.ssid ?? ""), \(b) bars"
        case .ethernet: "Ethernet"
        case .hotspot: "Personal Hotspot"
        case .noInternet: "No internet"
        case .notAssociated: "Wi-Fi not connected"
        case .wifiOff: "Wi-Fi off"
        case .offline: "Offline"
        }
        let vol = s.audio.muted ? "Muted" : s.audio.volume.map { "Volume \(Int(($0 * 100).rounded()))%" } ?? "Volume unavailable"
        return "\(battery), \(net), \(vol)"
    }

    // MARK: Clicks

    @objc private func clicked(_ sender: NSStatusBarButton) {
        let e = NSApp.currentEvent
        if e?.type == .rightMouseUp || e?.modifierFlags.contains(.control) == true { showMenu() } else { togglePanel() }
    }

    func togglePanel() {
        if popover.isShown { popover.performClose(nil); return }
        guard let b = item?.button else { WindowOpener.open("main"); return }
        system.refreshAll(); system.refreshBluetooth()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func showMenu() {
        let m = NSMenu()
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        let title = NSMenuItem(title: "BalDente \(v)", action: nil, keyEquivalent: ""); title.isEnabled = false
        m.addItem(title)
        m.addItem(.separator())
        m.addItem(withTitle: "Open Dashboard", action: #selector(openDashboard), keyEquivalent: "d").target = self
        m.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        m.addItem(.separator())
        m.addItem(withTitle: "Quit BalDente", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item?.menu = m
        item?.button?.performClick(nil)
        item?.menu = nil
    }

    @objc func openDashboard() { popover.close(); model.go(.overview); WindowOpener.open("main") }
    @objc func openSettings() { popover.close(); model.go(.icon); WindowOpener.open("main") }
}

extension StatusItemController: NSPopoverDelegate {
    func popoverDidShow(_ notification: Notification) { model.panelOpen = true }
    func popoverDidClose(_ notification: Notification) { model.panelOpen = false }
}
