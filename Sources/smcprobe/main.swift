import CSMC
import Foundation

// Read-only probe: lists which battery/charge SMC keys exist on this Mac.
let keys = ["CH0B", "CH0C", "CHTE", "CH0I", "CHWA", "CH0J", "bfF0", "bfD0", "bfE0",
            "CHIE", "BUIC", "AC-W", "ACLC", "PPBR", "PDTR"]
guard smc_open() == 0 else { print("cannot open AppleSMC"); exit(1) }
for k in keys {
    var v = SMCValue()
    let r = smc_read(k, &v)
    if r == 0 {
        let type = withUnsafeBytes(of: v.type) { String(decoding: $0.prefix(4), as: UTF8.self) }
        let hex = withUnsafeBytes(of: v.bytes) { Array($0.prefix(Int(v.size))).map { String(format: "%02x", $0) }.joined() }
        print("\(k): type=\(type) size=\(v.size) value=0x\(hex)")
    } else {
        print("\(k): not readable (code 0x\(String(r, radix: 16)))")
    }
}
