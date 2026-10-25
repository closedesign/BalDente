import CoreWLAN
import Foundation

/// Identifiers for the current network. SSID/BSSID need Location permission on macOS 14.4+,
/// so the gateway MAC address is included as a fallback that needs no permission.
/// Only called when the network actually changes, and always off the main thread.
enum NetworkInfo {
    static func current() async -> [String] {
        await Task.detached(priority: .utility) {
            var ids: [String] = []
            if let i = CWWiFiClient.shared().interface() {
                if let s = i.ssid() { ids.append(s) }
                if let b = i.bssid() { ids.append(b) }
            }
            if let g = gatewayMAC() { ids.append(g) }
            return ids
        }.value
    }

    static func run(_ path: String, _ args: [String]) -> String {
        let p = Process(), pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: path); p.arguments = args
        p.standardOutput = pipe; p.standardError = Pipe()
        guard (try? p.run()) != nil else { return "" }
        let d = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: d, as: UTF8.self)
    }

    /// The router on the physical link. With a VPN up, `route get default` names the tunnel's own address,
    /// which has no MAC and isn't the LAN router, so take the first default route that isn't a tunnel.
    static func gatewayIP() -> String? {
        let tunnels = ["utun", "ppp", "ipsec", "tun", "tap", "gif", "stf"]
        for line in run("/usr/sbin/netstat", ["-rn", "-f", "inet"]).split(separator: "\n") {
            let cols = line.split(separator: " ", omittingEmptySubsequences: true)
            guard cols.count >= 4, cols[0] == "default", case let netif = cols[3],
                  !tunnels.contains(where: { netif.hasPrefix($0) }),
                  cols[1].split(separator: ".").count == 4 else { continue }   // skips "link#N" gateways
            return String(cols[1])
        }
        let route = run("/sbin/route", ["-n", "get", "default"])
        guard let line = route.split(separator: "\n").first(where: { $0.contains("gateway:") }),
              let ip = line.split(separator: ":").last?.trimmingCharacters(in: .whitespaces), !ip.isEmpty
        else { return nil }
        return ip
    }

    private static func gatewayMAC() -> String? {
        guard let ip = gatewayIP() else { return nil }
        let arp = run("/usr/sbin/arp", ["-n", ip])
        guard let r = arp.range(of: " at ") else { return nil }
        let mac = arp[r.upperBound...].split(separator: " ").first.map(String.init) ?? ""
        return mac.contains(":") ? "gw:" + mac : nil
    }
}
