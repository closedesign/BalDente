import Darwin
import Foundation

/// Talks to baldented over its Unix socket.
public enum DaemonClient {
    public static func send(_ cmd: String) -> String? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: socketPath.utf8CString.map { UInt8(bitPattern: $0) }) }
        let r = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard r == 0 else { return nil }
        _ = cmd.withCString { write(fd, $0, strlen($0)) }
        var tv = timeval(tv_sec: 3, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        // The daemon closes after replying, so read to EOF; one read() can return a partial reply.
        var out = Data(), buf = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = read(fd, &buf, buf.count)
            if n <= 0 { break }
            out.append(contentsOf: buf[0..<n])
        }
        return out.isEmpty ? nil : String(decoding: out, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func status() -> Status? {
        send("status").flatMap { try? JSONDecoder().decode(Status.self, from: Data($0.utf8)) }
    }
}
