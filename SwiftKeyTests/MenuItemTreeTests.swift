import SwiftKeyCore
import XCTest
@testable import SwiftKey

final class MenuItemTreeTests: XCTestCase {
    private func tree(_ yaml: String) throws -> MenuItemTree.Result {
        MenuItemTree.build(try ConfigParser().parse(yaml))
    }

    func testBasicItemsWithAndWithoutIcons() throws {
        let result = try tree("""
        - key: "c"
          title: "Launch Calculator"
          action: "launch:///System/Applications/Calculator.app"
        - key: "n"
          icon: "note.text"
          title: "Launch Notes"
          action: "launch:///System/Applications/Notes.app"
        """)
        XCTAssertEqual(result.problems, [])
        XCTAssertEqual(result.items.map(\.key), ["c", "n"])
        XCTAssertEqual(result.items.map(\.label), ["Launch Calculator", "Launch Notes"])
        XCTAssertEqual(result.items[0].action, .app("/System/Applications/Calculator.app"))
        XCTAssertEqual(result.items[0].flags, Item.Flags())
    }

    func testNestedSubmenus() throws {
        let result = try tree("""
        - key: "d"
          icon: "folder.fill"
          title: "Development"
          submenu:
            - key: "e"
              title: "Editors"
              submenu:
                - key: "v"
                  title: "VS Code"
                  action: "launch:///Applications/Visual Studio Code.app"
            - key: "t"
              title: "Terminal"
              action: "launch:///System/Applications/Terminal.app"
        """)
        XCTAssertEqual(result.problems, [])
        let development = try XCTUnwrap(result.items.first)
        XCTAssertTrue(development.isGroup)
        XCTAssertEqual(BindingTree.item(at: ["d", "e", "v"], in: result.items)?.action,
                       .app("/Applications/Visual Studio Code.app"))
        XCTAssertEqual(BindingTree.item(at: ["d", "t"], in: result.items)?.label, "Terminal")
    }

    func testEveryActionKind() throws {
        let result = try tree("""
        - key: "a"
          title: "App"
          action: "launch://com.apple.Safari"
        - key: "o"
          title: "Web"
          action: "open://https://www.theverge.com"
        - key: "s"
          title: "Shell"
          action: "shell://say hi"
        - key: "h"
          title: "Shortcut"
          action: "shortcut://My Shortcut"
        - key: "p"
          title: "Processes"
          action: "dynamic://dynamic_menu.sh"
        - key: "j"
          title: "JSON"
          action: "micro://format-json"
        """)
        XCTAssertEqual(result.problems, [])
        XCTAssertEqual(result.items.map(\.action), [
            .app("com.apple.Safari"), .url("https://www.theverge.com"), .shell("say hi"),
            .shortcut("My Shortcut"), .dynamic("dynamic_menu.sh"), .micro("format-json"),
        ])
    }

    func testFlagsAndIds() throws {
        let menu = try ConfigParser().parse("""
        - key: "s"
          title: "Start Workflow"
          batch: true
          submenu:
            - key: "1"
              title: "Open Mail"
              action: "launch:///System/Applications/Mail.app"
        - key: "v"
          title: "Volume Up"
          action: "shell://true"
          sticky: true
          notify: true
        - key: "h"
          title: "Hidden Action"
          action: "shell://true"
          hidden: true
          hotkey: "cmd+shift+h"
        """)
        let result = MenuItemTree.build(menu)
        XCTAssertEqual(result.items.map(\.flags), [
            Item.Flags(batch: true),
            Item.Flags(sticky: true, notify: true),
            Item.Flags(hidden: true),
        ])
        XCTAssertEqual(result.items.map(\.id), menu.map(\.id.uuidString))
        XCTAssertEqual(result.items[0].children?.first?.id, menu[0].submenu?.first?.id.uuidString)
    }

    func testKeysKeepTheirCaseAndNamedKeysAreNormalized() throws {
        let result = try tree("""
        - key: "B"
          title: "Upper"
          action: "shell://true"
        - key: "b"
          title: "Lower"
          action: "shell://true"
        - key: "!"
          title: "Bang"
          action: "shell://true"
        - key: "Space"
          title: "Space"
          action: "shell://true"
        """)
        XCTAssertEqual(result.problems, [])
        XCTAssertEqual(result.items.map(\.key), ["B", "b", "!", "space"])
    }

    func testBadItemsAreLeftOutAndReported() throws {
        let result = try tree("""
        - key: "ab"
          title: "Two letters"
          action: "shell://true"
        - key: "x"
          title: "Unknown"
          action: "ftp://example.com"
        - key: "g"
          title: "Group"
          submenu:
            - key: "n"
              title: "Nothing"
        - key: "k"
          title: "Good"
          action: "shell://true"
        """)
        XCTAssertEqual(result.items.map(\.key), ["g", "k"])
        XCTAssertEqual(result.items[0].children, [])
        XCTAssertEqual(result.problems.map(\.path), [["Two letters"], ["Unknown"], ["Group", "Nothing"]])
        XCTAssertTrue(result.problems[0].message.contains("Invalid key \"ab\""))
        XCTAssertTrue(result.problems[1].message.contains("Unknown action"))
        XCTAssertEqual(result.problems[2].message, "No action or submenu.")
    }

    func testBundledDefaultConfigBuildsWithoutProblems() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "menu", withExtension: "yaml"))
        let result = try tree(String(contentsOf: url, encoding: .utf8))
        XCTAssertEqual(result.problems, [])
        XCTAssertFalse(result.items.isEmpty)
    }
}
