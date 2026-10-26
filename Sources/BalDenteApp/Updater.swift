import AppKit
import BalDenteCore

/// Downloads a release DMG, checks it is really BalDente, and swaps it in after the app quits. Never runs unless the user clicks Install.
enum UpdateInstaller {
    struct Failure: LocalizedError { let message: String; var errorDescription: String? { message } }

    @discardableResult
    private static func run(_ tool: String, _ args: [String]) async throws -> String {
        try await Task.detached {
            let p = Process(), out = Pipe()
            p.executableURL = URL(fileURLWithPath: tool); p.arguments = args; p.standardOutput = out; p.standardError = out
            try p.run(); p.waitUntilExit()
            let text = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            guard p.terminationStatus == 0 else { throw Failure(message: "\((tool as NSString).lastPathComponent) failed: \(text.prefix(120))") }
            return text
        }.value
    }

    /// Where the running app lives, if it can be replaced there.
    static func installTarget() throws -> URL {
        let url = Bundle.main.bundleURL
        guard url.pathExtension == "app", FileManager.default.isWritableFile(atPath: url.deletingLastPathComponent().path) else {
            throw Failure(message: "BalDente can't replace itself where it is. Download the update instead.")
        }
        return url
    }

    static func install(dmg: URL, version: String, status: @escaping (String) -> Void) async throws {
        let target = try installTarget()
        status("Downloading \(version)…")
        let (tmp, resp) = try await URLSession.shared.download(from: dmg)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw Failure(message: "The download failed.") }
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("baldente-update-\(UUID().uuidString)")
        let mount = work.appendingPathComponent("mnt")
        try fm.createDirectory(at: mount, withIntermediateDirectories: true)
        let image = work.appendingPathComponent("BalDente.dmg")
        try fm.moveItem(at: tmp, to: image)

        status("Checking the download…")
        try await run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noverify", "-mountpoint", mount.path, image.path])
        var mounted = true
        func detach() async { if mounted { mounted = false; _ = try? await run("/usr/bin/hdiutil", ["detach", "-force", mount.path]) } }
        do {
            let src = mount.appendingPathComponent("BalDente.app")
            let info = NSDictionary(contentsOf: src.appendingPathComponent("Contents/Info.plist"))
            guard info?["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier,
                  info?["CFBundleShortVersionString"] as? String == version else {
                throw Failure(message: "The download isn't BalDente \(version).")
            }
            let staged = work.appendingPathComponent("BalDente.app")
            try await run("/usr/bin/ditto", [src.path, staged.path])
            await detach()
            try await run("/usr/bin/xattr", ["-cr", staged.path])
            try await run("/usr/bin/codesign", ["--verify", "--deep", "--strict", staged.path])

            // The swap happens after this process exits. Settings live in Application Support and UserDefaults, so they are untouched.
            let script = """
            while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.3; done
            rm -rf "\(target.path)" && mv "\(staged.path)" "\(target.path)" && open "\(target.path)"
            rm -rf "\(work.path)"
            """
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/sh"); p.arguments = ["-c", script]
            try p.run()
            status("Restarting…")
            await MainActor.run { NSApp.terminate(nil) }
        } catch {
            await detach()
            try? fm.removeItem(at: work)
            throw error
        }
    }
}
