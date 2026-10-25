import Foundation

/// How we stop the battery from charging. Chosen at runtime from the SMC keys the firmware exposes.
public protocol ChargeBackend {
    var name: String { get }
    func setAdapter(on: Bool) throws
    func isAdapterOn() -> Bool
}

/// Cuts adapter power (CHIE on Tahoe/macOS 27 firmware, CH0I/CH0J on older ones).
/// While off, the Mac runs from the battery; the limiter turns it back on at the lower threshold.
public struct AdapterBackend: ChargeBackend {
    let key: String
    let offValue: UInt8
    public var name: String { "adapter(\(key))" }

    public init?() {
        if SMC.hasKey("CHIE") { key = "CHIE"; offValue = 0x08 }
        else if SMC.hasKey("CH0J") { key = "CH0J"; offValue = 0x01 }
        else if SMC.hasKey("CH0I") { key = "CH0I"; offValue = 0x01 }
        else { return nil }
    }

    public func setAdapter(on: Bool) throws { try SMC.writeByte(key, on ? 0x00 : offValue) }
    public func isAdapterOn() -> Bool { SMC.readByte(key) == 0x00 }
}

public func batteryPercent() -> Int? {
    SMC.readByte("BUIC").map { Int($0) }
}
