import Foundation

/// Settings saved to a file so they can move to another Mac. Zones carry Wi-Fi names and saved places, so the file is personal.
public enum SettingsExport {
    public static let format = "BalDenteSettings"

    struct Envelope: Codable { var format: String; var version: String; var config: Config }
    public struct Failure: LocalizedError {
        public let message: String
        public var errorDescription: String? { message }
    }

    public static func encode(_ config: Config, version: String) throws -> Data {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try e.encode(Envelope(format: format, version: version, config: config))
    }

    /// Accepts an export file or a bare config.json, and returns settings the helper will accept. The override pin is not carried over.
    public static func decode(_ data: Data) throws -> Config {
        let d = JSONDecoder()
        var config: Config
        if let env = try? d.decode(Envelope.self, from: data), env.format == format { config = env.config }
        else if let bare = try? d.decode(Config.self, from: data), (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["zones"] != nil { config = bare }
        else { throw Failure(message: "That file isn't a BalDente settings export.") }
        config.overrideZone = nil
        return config.sanitized()
    }
}
