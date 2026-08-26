import Foundation
import Testing
@testable import DivisionKit

@Test func resolveDefaultBindings() throws {
    let bindings = try BindingResolver.resolve(.default)
    #expect(bindings.count == HotkeyAction.allCases.count)

    let focusLeft = try #require(bindings[.focusLeft])
    #expect(focusLeft.modifiers == [.command, .option])
    #expect(focusLeft.key.name == "h")

    let moveLeft = try #require(bindings[.moveLeft])
    #expect(moveLeft.modifiers == [.command, .option, .shift])
    #expect(moveLeft.key.name == "h")

    let switcher = try #require(bindings[.switcher])
    #expect(switcher.modifiers == .option)
    #expect(!switcher.modifiers.contains(.command))
    #expect(switcher.key.name == "tab")
    #expect(switcher.carbonKeyCode == 0x30)
    #expect(switcher.carbonModifiers == 1 << 11)

    let cycle = try #require(bindings[.cycleLayout])
    #expect(cycle.modifiers == [.command, .option])
    #expect(cycle.key.name == "tab")
    #expect(cycle.carbonKeyCode == 0x30)
    #expect(cycle.carbonModifiers == (1 << 8) | (1 << 11))
}

private let commandEventFlag = Hotkey.Modifier.commandEventFlag
private let shiftEventFlag = Hotkey.Modifier.shiftEventFlag
private let optionEventFlag = Hotkey.Modifier.optionEventFlag
private let controlEventFlag = Hotkey.Modifier.controlEventFlag
private let capsLockEventFlag: UInt64 = 0x0001_0000

@Test func matcherMatchesDefaultSwitcherAndTab() throws {
    let bindings = try BindingResolver.resolve(.default)
    let cmdOpt = commandEventFlag | optionEventFlag
    let cmdOptShift = cmdOpt | shiftEventFlag
    let optionOnly = optionEventFlag
    let carbonCmdOpt = UInt64((1 << 8) | (1 << 11))

    #expect(
        HotkeyMatcher.matchingAction(keyCode: 0x04, eventFlags: cmdOpt, bindings: bindings) == .focusLeft
    )
    #expect(
        HotkeyMatcher.matchingAction(keyCode: 0x04, eventFlags: cmdOptShift, bindings: bindings) == .moveLeft
    )
    #expect(
        HotkeyMatcher.matchingAction(keyCode: 0x30, eventFlags: optionOnly, bindings: bindings) == .switcher
    )
    #expect(
        HotkeyMatcher.matchingAction(keyCode: 0x30, eventFlags: cmdOpt, bindings: bindings) == .cycleLayout
    )
    #expect(
        HotkeyMatcher.matchingAction(keyCode: 0x01, eventFlags: cmdOpt, bindings: bindings) == nil
    )
    #expect(
        HotkeyMatcher.matchingAction(keyCode: 0x2E, eventFlags: cmdOpt, bindings: bindings) == nil
    )
    #expect(
        HotkeyMatcher.matchingAction(keyCode: 0x04, eventFlags: carbonCmdOpt, bindings: bindings) == nil
    )
}

@Test func matcherDistinguishesShiftAndIgnoresCapsLock() throws {
    let bindings = try BindingResolver.resolve(.default)
    let cmdOpt = commandEventFlag | optionEventFlag
    let cmdOptShift = cmdOpt | shiftEventFlag

    #expect(
        HotkeyMatcher.matchingAction(keyCode: 0x04, eventFlags: cmdOpt, bindings: bindings) == .focusLeft
    )
    #expect(
        HotkeyMatcher.matchingAction(keyCode: 0x04, eventFlags: cmdOptShift, bindings: bindings) == .moveLeft
    )
    #expect(
        HotkeyMatcher.matchingAction(
            keyCode: 0x30,
            eventFlags: cmdOpt | capsLockEventFlag,
            bindings: bindings
        ) == .cycleLayout
    )
    #expect(
        HotkeyMatcher.matchingAction(keyCode: 0x30, eventFlags: commandEventFlag, bindings: bindings) == nil
    )
    #expect(
        HotkeyMatcher.matchingAction(keyCode: 0x30, eventFlags: cmdOpt | shiftEventFlag, bindings: bindings)
            == nil
    )
    #expect(
        HotkeyMatcher.matchingAction(keyCode: 0x30, eventFlags: optionEventFlag | commandEventFlag, bindings: bindings)
            == .cycleLayout
    )
    #expect(
        HotkeyMatcher.matchingAction(keyCode: 0x01, eventFlags: controlEventFlag | optionEventFlag, bindings: bindings)
            == nil
    )
}

@Test func hotkeyMatchesTabKeyCode() throws {
    let cycle = try #require(try BindingResolver.resolve(.default)[.cycleLayout])
    #expect(cycle.matches(keyCode: 0x30, eventFlags: commandEventFlag | optionEventFlag))
    #expect(!cycle.matches(keyCode: 0x30, eventFlags: optionEventFlag))
    #expect(!cycle.matches(keyCode: 0x01, eventFlags: commandEventFlag | optionEventFlag))

    let switcher = try #require(try BindingResolver.resolve(.default)[.switcher])
    #expect(switcher.matches(keyCode: 0x30, eventFlags: optionEventFlag))
    #expect(!switcher.matches(keyCode: 0x30, eventFlags: commandEventFlag | optionEventFlag))
}

@Test func resolveCustomModifierAndKeys() throws {
    let config = AppConfig(
        modifier: "ctrl",
        switcher: "opt+tab",
        keys: KeyBindings(focusLeft: "a", switcher: "w", cycleLayout: "tab")
    )
    let bindings = try BindingResolver.resolve(config)
    #expect(bindings[.focusLeft]?.modifiers == .control)
    #expect(bindings[.focusLeft]?.key.name == "a")
    #expect(bindings[.moveLeft]?.modifiers == [.control, .shift])
    #expect(bindings[.switcher]?.modifiers == .option)
    #expect(bindings[.switcher]?.key.name == "tab")
    #expect(bindings[.cycleLayout]?.modifiers == .control)
    #expect(bindings[.cycleLayout]?.key.name == "tab")
}

@Test func resolveSwitcherFallsBackToModifierPlusKey() throws {
    let config = AppConfig(
        modifier: "ctrl",
        switcher: nil,
        keys: KeyBindings(focusLeft: "a", switcher: "w", cycleLayout: "tab")
    )
    let bindings = try BindingResolver.resolve(config)
    let switcher = try #require(bindings[.switcher])
    #expect(switcher.modifiers == .control)
    #expect(switcher.key.name == "w")
    #expect(switcher.carbonKeyCode == 0x0D)
}

@Test func resolveDecodedLegacySwitcherKey() throws {
    let json = """
    {
      "modifier": "cmd+opt",
      "keys": {"switcher": "s", "cycleLayout": "tab"}
    }
    """
    let config = try AppConfigJSON.decode(from: Data(json.utf8))
    #expect(config.switcher == nil)
    let bindings = try BindingResolver.resolve(config)
    let switcher = try #require(bindings[.switcher])
    #expect(switcher.modifiers == [.command, .option])
    #expect(switcher.key.name == "s")
    let cycle = try #require(bindings[.cycleLayout])
    #expect(cycle.modifiers == [.command, .option])
    #expect(cycle.key.name == "tab")
}
