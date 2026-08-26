import Foundation

public enum HotkeyAction: UInt32, CaseIterable, Sendable, Equatable {
    case focusLeft = 1
    case focusDown = 2
    case focusUp = 3
    case focusRight = 4
    case moveLeft = 5
    case moveDown = 6
    case moveUp = 7
    case moveRight = 8
    case switcher = 9
    case cycleLayout = 10

    public var direction: Direction? {
        switch self {
        case .focusLeft, .moveLeft: return .left
        case .focusDown, .moveDown: return .down
        case .focusUp, .moveUp: return .up
        case .focusRight, .moveRight: return .right
        default: return nil
        }
    }

    public var isMove: Bool {
        switch self {
        case .moveLeft, .moveDown, .moveUp, .moveRight:
            return true
        default:
            return false
        }
    }

    public var isFocus: Bool {
        switch self {
        case .focusLeft, .focusDown, .focusUp, .focusRight:
            return true
        default:
            return false
        }
    }
}

public enum BindingResolver {
    public static func resolve(_ config: AppConfig) throws -> [HotkeyAction: Hotkey] {
        let modifier = try HotkeyParser.parseModifiers(config.modifier)
        var moveModifier = modifier
        moveModifier.insert(.shift)

        func hotkey(_ name: String, modifiers: Hotkey.Modifier) throws -> Hotkey {
            Hotkey(modifiers: modifiers, key: try HotkeyParser.parseKey(name))
        }

        let switcher: Hotkey
        if let spec = config.switcher {
            switcher = try HotkeyParser.parse(spec)
        } else {
            switcher = try hotkey(config.keys.switcher, modifiers: modifier)
        }

        return [
            .focusLeft: try hotkey(config.keys.focusLeft, modifiers: modifier),
            .focusDown: try hotkey(config.keys.focusDown, modifiers: modifier),
            .focusUp: try hotkey(config.keys.focusUp, modifiers: modifier),
            .focusRight: try hotkey(config.keys.focusRight, modifiers: modifier),
            .moveLeft: try hotkey(config.keys.focusLeft, modifiers: moveModifier),
            .moveDown: try hotkey(config.keys.focusDown, modifiers: moveModifier),
            .moveUp: try hotkey(config.keys.focusUp, modifiers: moveModifier),
            .moveRight: try hotkey(config.keys.focusRight, modifiers: moveModifier),
            .switcher: switcher,
            .cycleLayout: try hotkey(config.keys.cycleLayout, modifiers: modifier),
        ]
    }
}

public enum HotkeyMatcher {
    public static func matchingAction(
        keyCode: UInt32,
        eventFlags: UInt64,
        bindings: [HotkeyAction: Hotkey]
    ) -> HotkeyAction? {
        bindings.first { _, hotkey in
            hotkey.matches(keyCode: keyCode, eventFlags: eventFlags)
        }?.key
    }
}
