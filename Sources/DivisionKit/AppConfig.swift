import Foundation

public struct KeyBindings: Codable, Equatable, Sendable {
    public var focusLeft: String
    public var focusDown: String
    public var focusUp: String
    public var focusRight: String
    public var switcher: String
    public var cycleLayout: String

    public static let `default` = KeyBindings(
        focusLeft: "h",
        focusDown: "j",
        focusUp: "k",
        focusRight: "l",
        switcher: "s",
        cycleLayout: "tab"
    )

    public init(
        focusLeft: String = KeyBindings.default.focusLeft,
        focusDown: String = KeyBindings.default.focusDown,
        focusUp: String = KeyBindings.default.focusUp,
        focusRight: String = KeyBindings.default.focusRight,
        switcher: String = KeyBindings.default.switcher,
        cycleLayout: String = KeyBindings.default.cycleLayout
    ) {
        self.focusLeft = focusLeft
        self.focusDown = focusDown
        self.focusUp = focusUp
        self.focusRight = focusRight
        self.switcher = switcher
        self.cycleLayout = cycleLayout
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        focusLeft = try container.decodeIfPresent(String.self, forKey: .focusLeft) ?? Self.default.focusLeft
        focusDown = try container.decodeIfPresent(String.self, forKey: .focusDown) ?? Self.default.focusDown
        focusUp = try container.decodeIfPresent(String.self, forKey: .focusUp) ?? Self.default.focusUp
        focusRight = try container.decodeIfPresent(String.self, forKey: .focusRight) ?? Self.default.focusRight
        switcher = try container.decodeIfPresent(String.self, forKey: .switcher) ?? Self.default.switcher
        cycleLayout = try container.decodeIfPresent(String.self, forKey: .cycleLayout) ?? Self.default.cycleLayout
    }

    public func key(for direction: Direction) -> String {
        switch direction {
        case .left: focusLeft
        case .down: focusDown
        case .up: focusUp
        case .right: focusRight
        }
    }
}

public struct AppConfig: Codable, Equatable, Sendable {
    public var modifier: String
    /// Full hotkey for the switcher (for example `"opt+tab"`). `nil` means fall back to
    /// `modifier` + `keys.switcher` for older configs that only set `keys.switcher`.
    public var switcher: String?
    public var keys: KeyBindings
    public var defaultLayout: Layout
    public var defaultPane: Int

    public static let `default` = AppConfig(
        modifier: "cmd+opt",
        switcher: "opt+tab",
        keys: .default,
        defaultLayout: .half,
        defaultPane: 0
    )

    public init(
        modifier: String = AppConfig.default.modifier,
        switcher: String? = AppConfig.default.switcher,
        keys: KeyBindings = AppConfig.default.keys,
        defaultLayout: Layout = AppConfig.default.defaultLayout,
        defaultPane: Int = AppConfig.default.defaultPane
    ) {
        self.modifier = modifier
        self.switcher = switcher
        self.keys = keys
        self.defaultLayout = defaultLayout
        self.defaultPane = defaultPane
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        modifier = try container.decodeIfPresent(String.self, forKey: .modifier) ?? Self.default.modifier
        switcher = try container.decodeIfPresent(String.self, forKey: .switcher)
        keys = try container.decodeIfPresent(KeyBindings.self, forKey: .keys) ?? Self.default.keys
        defaultLayout = try container.decodeIfPresent(Layout.self, forKey: .defaultLayout)
            ?? Self.default.defaultLayout
        defaultPane = try container.decodeIfPresent(Int.self, forKey: .defaultPane)
            ?? Self.default.defaultPane
    }
}

public enum AppConfigJSON {
    public static func decode(from data: Data) throws -> AppConfig {
        try JSONDecoder().decode(AppConfig.self, from: data)
    }

    public static func encode(_ config: AppConfig) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(config)
    }
}
