import Foundation
import Testing
@testable import DivisionKit

@Test func parseDefaultModifier() throws {
    let modifiers = try HotkeyParser.parseModifiers("cmd+opt")
    #expect(modifiers == [.command, .option])
    #expect(modifiers.carbonFlags == (1 << 8) | (1 << 11))
}

@Test func parseHotkeyIsCaseInsensitive() throws {
    let hotkey = try HotkeyParser.parse("CMD+SHIFT+A")
    #expect(hotkey.modifiers == [.command, .shift])
    #expect(hotkey.key.name == "a")
    #expect(hotkey.carbonKeyCode == 0x00)
}

@Test func parseHotkeyAliases() throws {
    let command = try HotkeyParser.parse("command+space")
    #expect(command.modifiers == .command)
    #expect(command.carbonKeyCode == 0x31)

    let option = try HotkeyParser.parse("alt+1")
    #expect(option.modifiers == .option)

    let control = try HotkeyParser.parse("ctrl+escape")
    #expect(control.modifiers == .control)
}

@Test func parseModifierOnlyRejectsKeylessEmpty() {
    #expect(throws: HotkeyParseError.empty) {
        try HotkeyParser.parseModifiers("")
    }
}

@Test func parseKeyHJKL() throws {
    let h = try HotkeyParser.parseKey("h")
    #expect(h.carbonKeyCode == 0x04)
    let j = try HotkeyParser.parseKey("j")
    #expect(j.carbonKeyCode == 0x26)
    let k = try HotkeyParser.parseKey("k")
    #expect(k.carbonKeyCode == 0x28)
    let l = try HotkeyParser.parseKey("l")
    #expect(l.carbonKeyCode == 0x25)
}

@Test func parseKeyTab() throws {
    let tab = try HotkeyParser.parseKey("tab")
    #expect(tab.name == "tab")
    #expect(tab.carbonKeyCode == 0x30)
}

@Test func parseOptTab() throws {
    let hotkey = try HotkeyParser.parse("opt+tab")
    #expect(hotkey.modifiers == .option)
    #expect(!hotkey.modifiers.contains(.command))
    #expect(hotkey.key.name == "tab")
    #expect(hotkey.carbonKeyCode == 0x30)
    #expect(hotkey.carbonModifiers == 1 << 11)
}

@Test func parseUnknownToken() {
    #expect(throws: HotkeyParseError.unknownToken("foo")) {
        try HotkeyParser.parse("cmd+foo")
    }
}

@Test func modifierEventFlagsAreCGEventBitsNotCarbon() {
    let cmdOpt = Hotkey.Modifier([.command, .option])
    #expect(cmdOpt.carbonFlags == (1 << 8) | (1 << 11))
    #expect(cmdOpt.eventFlags == Hotkey.Modifier.commandEventFlag | Hotkey.Modifier.optionEventFlag)
    #expect(cmdOpt.eventFlags == 0x0010_0000 | 0x0008_0000)
    #expect(Hotkey.Modifier.fromEventFlags(cmdOpt.eventFlags) == cmdOpt)
    #expect(Hotkey.Modifier.fromEventFlags(UInt64(cmdOpt.carbonFlags)).isEmpty)
}

@Test func matchesUsesCGEventFlagsForCmdOptH() throws {
    let hotkey = try HotkeyParser.parse("cmd+opt+h")
    let cg = Hotkey.Modifier([.command, .option]).eventFlags
    let carbon = UInt64(hotkey.carbonModifiers)
    #expect(hotkey.carbonKeyCode == 0x04)
    #expect(hotkey.matches(keyCode: 0x04, eventFlags: cg))
    #expect(!hotkey.matches(keyCode: 0x04, eventFlags: carbon))
}
