import AppKit
import CryptoKit
import Foundation

/// Installs baldented as a LaunchDaemon so charging control survives reboots without anyone typing sudo.
/// One system password prompt, then it starts at every boot.
enum Installer {
    static let helper = "/Library/PrivilegedHelperTools/org.baldente.daemon"
    static let plist = "/Library/LaunchDaemons/org.baldente.daemon.plist"

    static var installed: Bool { FileManager.default.fileExists(atPath: plist) }

    static let versionFile = "/Library/Application Support/BalDente/helper.version"

    /// The installed copy is re-signed, so its bytes never match the bundle. We compare a hash recorded at install time instead.
    /// Hashed once; the app bundle can't change while it's running.
    static let bundled: String? = bundledHash()

    static func bundledHash() -> String? {
        guard let src = Bundle.main.url(forResource: "baldented", withExtension: nil),
              let data = try? Data(contentsOf: src) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static var outdated: Bool {
        guard installed, let want = bundled else { return false }
        let have = (try? String(contentsOfFile: versionFile, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
        return have != want
    }

    static func install() async -> String? {
        guard let src = Bundle.main.url(forResource: "baldented", withExtension: nil) else {
            return "The app bundle has no helper inside. Rebuild with make_app.sh."
        }
        let script = """
        #!/bin/bash
        set -e
        mkdir -p /Library/PrivilegedHelperTools
        launchctl bootout system/org.baldente.daemon 2>/dev/null || true
        rm -f \(helper)
        cp '\(src.path)' \(helper)
        chown root:wheel \(helper)
        chmod 755 \(helper)
        codesign --force --sign - \(helper)
        cat > \(plist) <<'PL'
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>Label</key><string>org.baldente.daemon</string>
        <key>ProgramArguments</key><array><string>\(helper)</string></array>
        <key>RunAtLoad</key><true/>
        <key>KeepAlive</key><true/>
        <key>StandardOutPath</key><string>/var/log/baldente.log</string>
        <key>StandardErrorPath</key><string>/var/log/baldente.log</string>
        </dict></plist>
        PL
        chown root:wheel \(plist)
        chmod 644 \(plist)
        mkdir -p '/Library/Application Support/BalDente'
        echo '\(bundledHash() ?? "")' > '\(versionFile)'
        chmod 644 '\(versionFile)'
        launchctl bootstrap system \(plist)
        """
        return await runAsAdmin(script)
    }

    static func uninstall() async -> String? {
        // bootout sends SIGTERM, and the daemon turns the charger back on before exiting.
        await runAsAdmin("""
        #!/bin/bash
        launchctl bootout system/org.baldente.daemon 2>/dev/null || true
        rm -f \(plist) \(helper) /var/run/baldente.sock
        """)
    }

    private static func runAsAdmin(_ script: String) async -> String? {
        await Task.detached {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("baldente-\(UUID().uuidString).sh")
            do { try script.write(to: url, atomically: true, encoding: .utf8) } catch { return error.localizedDescription }
            defer { try? FileManager.default.removeItem(at: url) }
            var err: NSDictionary?
            NSAppleScript(source: "do shell script \"/bin/bash '\(url.path)'\" with administrator privileges")?
                .executeAndReturnError(&err)
            return (err?[NSAppleScript.errorMessage] as? String)
        }.value
    }
}
