import AppKit
import SwiftKeyCore
import XCTest
@testable import SwiftKey

/// The key paths of an open menu through `KeyboardManager` and the core leader machine, with real
/// shell actions that leave files in a temporary folder.
final class KeyboardNavigationTests: XCTestCase {
    private var folder: URL!
    /// The flags of a key press with the left Option key held, device bits included, as
    /// `NSEvent.ModifierFlags.isOption` expects them.
    private let leftOption = NSEvent.ModifierFlags(rawValue: 524_576)

    override func setUpWithError() throws {
        try super.setUpWithError()
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("swiftkey-nav-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
        try super.tearDownWithError()
    }

    /// A shell action that creates `name` in the test folder. The whole command is quoted, as the
    /// README shows: SwiftKey quotes a command with spaces once more before running it.
    private func touch(_ name: String) -> String {
        "shell://'touch \(folder.appendingPathComponent(name).path)'"
    }

    private func waitForFiles(_ names: [String], file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if names.allSatisfy({ FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path) }) { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTFail("files \(names) were not made", file: file, line: line)
    }

    /// A manager whose approval store lives in the test folder with every command of `menu`
    /// approved, so no approval window opens during the tests.
    private func manager(_ menu: [MenuItem]) -> KeyboardManager {
        let url = folder.appendingPathComponent("approvals.json")
        var approvals = Approvals()
        ApprovalGate.allRequests(in: menu).forEach { approvals.approve($0) }
        XCTAssertNoThrow(try approvals.encoded().write(to: url))
        let manager = KeyboardManager(approvalGate: ApprovalGate(store: ApprovalStore(url: url)))
        manager.settingsStore.overlayStyle = .panel
        manager.menuState.rootMenu = menu
        return manager
    }

    func testStickyActionKeepsTheMenuAtItsLevel() async {
        let manager = manager([
            MenuItem(key: "g", title: "Group", submenu: [MenuItem(key: "v", title: "Volume", action: touch("v"), sticky: true)]),
        ])
        _ = await manager.handleKey(key: "g")
        let result = await manager.handleKey(key: "v")
        XCTAssertEqual(result, .actionExecuted(sticky: true))
        XCTAssertEqual(manager.menuState.breadcrumbs, ["Group"])
        waitForFiles(["v"])
    }

    func testOptionInvertsSticky() async {
        let manager = manager([
            MenuItem(key: "a", title: "A", action: touch("a")),
            MenuItem(key: "s", title: "S", action: touch("s"), sticky: true),
        ])
        var result = await manager.handleKey(key: "a", modifierFlags: leftOption)
        XCTAssertEqual(result, .actionExecuted(sticky: true))
        result = await manager.handleKey(key: "s", modifierFlags: leftOption)
        XCTAssertEqual(result, .actionExecuted(sticky: false))
        waitForFiles(["a", "s"])
    }

    func testStickyNeedsAStyleThatCanStayOpen() async {
        let manager = manager([MenuItem(key: "s", title: "S", action: touch("s"), sticky: true)])
        manager.settingsStore.overlayStyle = .hud
        defer { manager.settingsStore.overlayStyle = .panel }
        let result = await manager.handleKey(key: "s")
        XCTAssertEqual(result, .actionExecuted(sticky: false))
        waitForFiles(["s"])
    }

    func testBatchGroupRunsItsActions() async {
        let manager = manager([
            MenuItem(key: "b", title: "Batch", batch: true, submenu: [
                MenuItem(key: "1", title: "One", action: touch("one")),
                MenuItem(key: "2", title: "Two", action: touch("two")),
                MenuItem(key: "3", title: "Nested", submenu: [MenuItem(key: "x", title: "X", action: touch("nested"))]),
            ]),
        ])
        let result = await manager.handleKey(key: "b")
        XCTAssertEqual(result, .actionExecuted(sticky: false))
        XCTAssertTrue(manager.menuState.menuStack.isEmpty)
        waitForFiles(["one", "two"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("nested").path))
    }

    func testOptionOnAGroupRunsItAsABatch() async {
        let manager = manager([
            MenuItem(key: "g", title: "Group", submenu: [MenuItem(key: "1", title: "One", action: touch("one"))]),
        ])
        let result = await manager.handleKey(key: "g", modifierFlags: leftOption)
        XCTAssertEqual(result, .actionExecuted(sticky: false))
        waitForFiles(["one"])
    }

    func testDynamicItemLoadsItsMenuFromAScript() async throws {
        let script = folder.appendingPathComponent("menu.sh")
        try """
        #!/bin/bash
        echo '- key: "k"'
        echo '  title: "Loaded"'
        echo "  action: \\"\(touch("loaded"))\\""
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        let manager = manager([MenuItem(key: "p", title: "Processes", action: "dynamic://\(script.path)")])

        var result = await manager.handleKey(key: "p")
        XCTAssertEqual(result, .submenuPushed(title: "Processes"))
        XCTAssertEqual(manager.menuState.currentMenu.map(\.title), ["Loaded"])
        result = await manager.handleKey(key: "k")
        XCTAssertEqual(result, .actionExecuted(sticky: false))
        waitForFiles(["loaded"])
    }

    func testCommandUpGoesUpButNeverCloses() async {
        let manager = manager([MenuItem(key: "g", title: "Group", submenu: [MenuItem(key: "x", title: "X", action: "shell://true")])])
        var result = await manager.handleKey(key: "cmd+up")
        XCTAssertEqual(result, .up)
        _ = await manager.handleKey(key: "g")
        result = await manager.handleKey(key: "cmd+up")
        XCTAssertEqual(result, .up)
        XCTAssertTrue(manager.menuState.menuStack.isEmpty)
    }

    func testUnknownKeyIsAnErrorAndKeepsTheLevel() async {
        let manager = manager([MenuItem(key: "g", title: "Group", submenu: [MenuItem(key: "x", title: "X", action: "shell://true")])])
        _ = await manager.handleKey(key: "g")
        let result = await manager.handleKey(key: "q")
        XCTAssertEqual(result, .error(key: "q"))
        XCTAssertEqual(manager.menuState.breadcrumbs, ["Group"])
    }

    func testCaseSensitiveKeys() async {
        let manager = manager([
            MenuItem(key: "a", title: "lower", action: touch("lower")),
            MenuItem(key: "A", title: "upper", action: touch("upper")),
        ])
        let result = await manager.handleKey(key: "A")
        XCTAssertEqual(result, .actionExecuted(sticky: false))
        waitForFiles(["upper"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("lower").path))
    }

    @MainActor
    func testItemHotkeyRunsItsAction() {
        let item = MenuItem(key: "x", title: "X", action: touch("hotkey"))
        let manager = manager([MenuItem(key: "g", title: "Group", submenu: [item])])
        manager.runItemHotkey(item)
        waitForFiles(["hotkey"])
        XCTAssertTrue(manager.menuState.menuStack.isEmpty)
    }
}
