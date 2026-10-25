import BalDenteCore
import SwiftUI

@main
struct BalDenteApp: App {
    @StateObject private var model = Model()

    var body: some Scene {
        Window("BalDente", id: "main") {
            RootView(model: model)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 780)
        .commands { ChargingCommands(model: model) }

        // The menu bar icon itself is an AppKit status item (see StatusItemController), so it can animate frame by frame.
    }
}

struct ChargingCommands: Commands {
    @ObservedObject var model: Model

    var body: some Commands {
        CommandGroup(replacing: .newItem) {}
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { model.go(.icon); WindowOpener.open("main") }.keyboardShortcut(",")
        }
        CommandGroup(after: .toolbar) {
            Button(model.appearance.compact ? "Switch to Regular Mode" : "Switch to Compact Mode") {
                model.appearance.compact.toggle()
            }.keyboardShortcut("c", modifiers: [.command, .shift])
            Button("Find Setting…") { model.appearance.compact = false; model.go(.overview); WindowOpener.open("main") }
                .keyboardShortcut("f", modifiers: [.command, .shift])
        }
        CommandMenu("Charging") {
            Button(model.topUp ? "Cancel Top Up" : "Top Up to 100%") { model.topUp.toggle(); model.refresh() }
                .keyboardShortcut("t")
            Button("Start Calibration") { model.cmd("calibrate") }.keyboardShortcut("k")
            Button("Cancel Running Task") { model.cmd("cancel") }.keyboardShortcut(".")
            Divider()
            Button("Automatic Zone") { model.config.overrideZone = nil }.keyboardShortcut("0")
            // Only single digits make a key equivalent; Character("10") would crash.
            ForEach(Array(model.config.zones.enumerated()), id: \.element.id) { i, z in
                if i < 9 {
                    Button("Pin \(z.name)") { model.config.overrideZone = z.name }
                        .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")))
                } else {
                    Button("Pin \(z.name)") { model.config.overrideZone = z.name }
                }
            }
            Divider()
            Button("Install or Repair Helper…") { model.setUp() }
        }
    }
}
