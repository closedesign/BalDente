import Foundation
import IOKit
import IOKit.pwr_mgt
import IOKit.ps

// Lives outside main.swift so the C callback captures nothing.
nonisolated(unsafe) var onPowerChange: (() -> Void)?
let powerCallback: IOPowerSourceCallbackType = { _ in onPowerChange?() }

/// Sleep and wake messages from the kernel. Swift does not import the kIOMessage* macros, so these are their raw values.
enum SleepMessage {
    static let canSleep: UInt32 = 0xE000_0270, willSleep: UInt32 = 0xE000_0280, poweredOn: UInt32 = 0xE000_0300
}

nonisolated(unsafe) var onSleepMessage: ((UInt32) -> Void)?
nonisolated(unsafe) var rootPort: io_connect_t = 0

/// Always answers "will sleep" and "can sleep" or the Mac waits 30 seconds before sleeping.
let sleepCallback: IOServiceInterestCallback = { _, _, type, arg in
    onSleepMessage?(type)
    if type == SleepMessage.canSleep || type == SleepMessage.willSleep { IOAllowPowerChange(rootPort, Int(bitPattern: arg)) }
}

func registerForSleep() {
    var port: IONotificationPortRef?
    var notifier: io_object_t = 0
    rootPort = IORegisterForSystemPower(nil, &port, sleepCallback, &notifier)
    guard rootPort != 0, let port else { print("sleep notifications unavailable"); return }
    CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port).takeUnretainedValue(), .defaultMode)
}
