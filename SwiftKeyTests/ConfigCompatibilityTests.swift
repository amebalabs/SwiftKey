import SwiftKeyCore
import XCTest
@testable import SwiftKey

/// Configs that loaded before named keys and Carbon hotkeys still load: every single character is
/// a key, and a key or hotkey SwiftKey cannot use leaves out only that item or hotkey.
final class ConfigCompatibilityTests: XCTestCase {
    private func load(_ yaml: String) async throws -> [MenuItem] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("swiftkey-compat-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("config.yaml")
        try yaml.write(to: url, atomically: true, encoding: .utf8)
        let result = await ConfigManager(configURL: url).loadConfig()
        guard case .success(let items) = result else {
            XCTFail("the config did not load: \(result)")
            return []
        }
        return items
    }

    /// Every key and hotkey form the single-character validator and the `cmd/ctrl/alt/shift`
    /// hotkey check accepted.
    func testEveryFormTheOldValidatorAcceptedLoads() async throws {
        let items = try await load("""
        - key: "a"
          title: "Lower"
          action: "open://https://example.com"
        - key: "B"
          title: "Upper"
          action: "open://https://example.com"
        - key: "!"
          title: "Punctuation"
          action: "open://https://example.com"
        - key: " "
          title: "Space character"
          action: "open://https://example.com"
        - key: "§"
          title: "Section sign"
          action: "open://https://example.com"
        - key: "é"
          title: "Accented"
          action: "open://https://example.com"
        - key: "1"
          title: "Hotkeys"
          submenu:
            - key: "q"
              title: "Plain"
              action: "open://https://example.com"
              hotkey: "cmd+shift+q"
            - key: "w"
              title: "Enter"
              action: "open://https://example.com"
              hotkey: "cmd+enter"
            - key: "e"
              title: "Escape"
              action: "open://https://example.com"
              hotkey: "cmd+esc"
            - key: "r"
              title: "Backspace"
              action: "open://https://example.com"
              hotkey: "ctrl+backspace"
            - key: "t"
              title: "Unknown key name"
              action: "open://https://example.com"
              hotkey: "alt+frobnicate"
        """)
        XCTAssertEqual(items.map(\.title), ["Lower", "Upper", "Punctuation", "Space character", "Section sign", "Accented", "Hotkeys"])
        let tree = MenuItemTree.build(items).items
        XCTAssertEqual(tree.map(\.key), ["a", "B", "!", "space", "§", "é", "1"])

        let hotkeys = items.last?.submenu?.map(\.hotkey)
        XCTAssertEqual(hotkeys, ["cmd+shift+q", "cmd+enter", "cmd+esc", "ctrl+backspace", nil],
                       "a hotkey SwiftKey cannot use is ignored, the item stays")
    }

    func testAnItemWithAnUnusableKeyIsLeftOutAndTheRestLoads() async throws {
        let items = try await load("""
        - key: "ab"
          title: "Two letters"
          action: "open://https://example.com"
        - key: "g"
          title: "Group"
          submenu:
            - key: "f99"
              title: "No such key"
              action: "open://https://example.com"
            - key: "k"
              title: "Kept"
              action: "open://https://example.com"
        """)
        XCTAssertEqual(items.map(\.title), ["Group"])
        XCTAssertEqual(items.first?.submenu?.map(\.title), ["Kept"])
    }
}
