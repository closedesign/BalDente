import IOKit.ps

// Lives outside main.swift so the C callback captures nothing.
nonisolated(unsafe) var onPowerChange: (() -> Void)?
let powerCallback: IOPowerSourceCallbackType = { _ in onPowerChange?() }
