import CSMC
import Foundation

public enum SMCError: Error { case open(Int32), read(String, Int32), write(String, Int32) }

public enum SMC {
    public static func open() throws {
        let r = smc_open()
        if r != 0 { throw SMCError.open(r) }
    }

    public static func readByte(_ key: String) -> UInt8? {
        var v = SMCValue()
        guard smc_read(key, &v) == 0, v.size >= 1 else { return nil }
        return withUnsafeBytes(of: v.bytes) { $0[0] }
    }

    public static func hasKey(_ key: String) -> Bool { readByte(key) != nil }

    public static func writeByte(_ key: String, _ value: UInt8) throws {
        var b = value
        let r = smc_write(key, &b, 1)
        if r != 0 { throw SMCError.write(key, r) }
    }
}

extension SMC {
    /// SMC floats are little-endian IEEE 754.
    public static func readFloat(_ key: String) -> Double? {
        var v = SMCValue()
        guard smc_read(key, &v) == 0, v.size == 4 else { return nil }
        let bits = withUnsafeBytes(of: v.bytes) { UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self)) }
        return Double(Float(bitPattern: bits))
    }
}
