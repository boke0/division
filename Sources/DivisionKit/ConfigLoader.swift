import Foundation

public enum ConfigLoader {
    public static var defaultConfigDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/division")
    }

    public static var defaultConfigURL: URL {
        defaultConfigDirectory.appendingPathComponent("config.json")
    }

    public static var defaultStateURL: URL {
        defaultConfigDirectory.appendingPathComponent("state.json")
    }

    /// Loads config from `url`. Missing or invalid files fall back to `AppConfig.default`.
    public static func load(from url: URL = defaultConfigURL) -> AppConfig {
        guard let data = try? Data(contentsOf: url) else {
            return .default
        }
        return (try? AppConfigJSON.decode(from: data)) ?? .default
    }

    public static func loadState(from url: URL = defaultStateURL) -> PersistedState {
        guard let data = try? Data(contentsOf: url) else {
            return .empty
        }
        return (try? JSONDecoder().decode(PersistedState.self, from: data)) ?? .empty
    }

    public static func saveState(_ state: PersistedState, to url: URL = defaultStateURL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: url, options: .atomic)
    }
}

public struct PersistedState: Codable, Equatable, Sendable {
    /// Space identifier (stringified) to layout mapping.
    public var layouts: [String: Layout]

    public static let empty = PersistedState(layouts: [:])

    public init(layouts: [String: Layout] = [:]) {
        self.layouts = layouts
    }
}
