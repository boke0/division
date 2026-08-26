import Foundation
import Testing
@testable import DivisionKit

@Test func decodeFullConfig() throws {
    let json = """
    {
      "modifier": "ctrl+opt",
      "keys": {"focusLeft": "a", "switcher": "w"},
      "defaultLayout": "thirds",
      "defaultPane": 1
    }
    """
    let config = try AppConfigJSON.decode(from: Data(json.utf8))
    #expect(config.modifier == "ctrl+opt")
    #expect(config.keys.focusLeft == "a")
    #expect(config.keys.focusRight == "l")
    #expect(config.keys.switcher == "w")
    #expect(config.switcher == nil)
    #expect(config.defaultLayout == .thirds)
    #expect(config.defaultPane == 1)
}

@Test func decodeTopLevelSwitcher() throws {
    let json = """
    {
      "modifier": "cmd+opt",
      "switcher": "opt+tab",
      "keys": {"cycleLayout": "tab"}
    }
    """
    let config = try AppConfigJSON.decode(from: Data(json.utf8))
    #expect(config.switcher == "opt+tab")
    #expect(config.keys.cycleLayout == "tab")
    #expect(config.keys.switcher == "s")
}

@Test func decodeConfigFillsDefaults() throws {
    let config = try AppConfigJSON.decode(from: Data("{}".utf8))
    #expect(config.modifier == "cmd+opt")
    #expect(config.switcher == nil)
    #expect(config.keys.focusLeft == "h")
    #expect(config.keys.cycleLayout == "tab")
    #expect(config.defaultLayout == .half)
    #expect(config.defaultPane == 0)
}

@Test func defaultConfigSwitcherIsOptTab() {
    #expect(AppConfig.default.switcher == "opt+tab")
    #expect(AppConfig.default.keys.cycleLayout == "tab")
}

@Test func loadMissingFileReturnsDefault() {
    let url = URL(fileURLWithPath: "/tmp/division-missing-config-\(UUID().uuidString).json")
    let config = ConfigLoader.load(from: url)
    #expect(config == .default)
    #expect(config.switcher == "opt+tab")
}

@Test func loadInvalidFileReturnsDefault() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("division-invalid-\(UUID().uuidString).json")
    try Data("not json".utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    #expect(ConfigLoader.load(from: url) == .default)
}

@Test func loadValidFile() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("division-valid-\(UUID().uuidString).json")
    try Data(#"{"modifier":"ctrl+shift","defaultLayout":"oneTwo"}"#.utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    let config = ConfigLoader.load(from: url)
    #expect(config.modifier == "ctrl+shift")
    #expect(config.defaultLayout == .oneTwo)
    #expect(config.keys.switcher == "s")
}

@Test func persistAndLoadState() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("division-state-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    let state = PersistedState(layouts: ["42": .thirds, "7": .twoOne])
    try ConfigLoader.saveState(state, to: url)
    let loaded = ConfigLoader.loadState(from: url)
    #expect(loaded.layouts["42"] == .thirds)
    #expect(loaded.layouts["7"] == .twoOne)
}

@Test func loadMissingStateReturnsEmpty() {
    let url = URL(fileURLWithPath: "/tmp/division-missing-state-\(UUID().uuidString).json")
    #expect(ConfigLoader.loadState(from: url) == .empty)
}
