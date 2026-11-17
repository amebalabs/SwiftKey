import SwiftKeyCore
import XCTest
@testable import SwiftKey

/// How launcha reaches the menu: a chosen menu item runs through `KeyboardManager` like its keys,
/// with real shell actions that leave files in a temporary folder.
final class LaunchaWiringTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("swiftkey-launcha-run-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
        try super.tearDownWithError()
    }

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

    /// A manager whose approval store lives in the test folder with every command approved, so no
    /// approval window opens during the tests.
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

    private let menu: (LaunchaWiringTests) -> [MenuItem] = { test in
        [
            MenuItem(key: "d", title: "Developer", submenu: [
                MenuItem(key: "g", title: "Git", submenu: [MenuItem(key: "s", title: "Status", action: test.touch("status"))]),
                MenuItem(key: ".", title: "Dot", action: test.touch("dot")),
            ]),
            MenuItem(key: "b", title: "Batch", batch: true, submenu: [
                MenuItem(key: "1", title: "One", action: test.touch("one")),
                MenuItem(key: "2", title: "Two", action: test.touch("two")),
            ]),
            MenuItem(key: "v", title: "Volume", action: test.touch("volume"), sticky: true),
        ]
    }

    @MainActor
    func testAnActionRunsAndCountsByItsPath() async {
        let manager = manager(menu(self))
        var launches: [String] = []
        manager.onLaunch = { launches.append($0) }
        let result = await manager.runFromLauncha(path: ["d", "g", "s"])
        XCTAssertEqual(result, .actionExecuted(sticky: false))
        waitForFiles(["status"])
        XCTAssertEqual(launches, ["menu:d g s"])
    }

    @MainActor
    func testAGroupOpensTheMenuThere() async {
        let manager = manager(menu(self))
        let result = await manager.runFromLauncha(path: ["d", "g"])
        XCTAssertEqual(result, .submenuPushed(title: "Git"))
        XCTAssertEqual(manager.menuState.keyPath, ["d", "g"])
        XCTAssertEqual(manager.menuState.breadcrumbs, ["Developer", "Git"])
    }

    @MainActor
    func testABatchGroupRunsItsActions() async {
        let manager = manager(menu(self))
        var launches: [String] = []
        manager.onLaunch = { launches.append($0) }
        let result = await manager.runFromLauncha(path: ["b"])
        XCTAssertEqual(result, .actionExecuted(sticky: false))
        waitForFiles(["one", "two"])
        XCTAssertEqual(launches, ["menu:b"])
    }

    @MainActor
    func testAStickyActionKeepsItsLevel() async {
        let manager = manager(menu(self))
        let result = await manager.runFromLauncha(path: ["v"])
        XCTAssertEqual(result, .actionExecuted(sticky: true))
        waitForFiles(["volume"])
    }

    /// Keys such as "." repeat the last action when typed in the menu; from launcha they are the
    /// item's own key.
    @MainActor
    func testKeysWithAMeaningInTheMenuStillNameTheirItem() async {
        let manager = manager(menu(self))
        let result = await manager.runFromLauncha(path: ["d", "."])
        XCTAssertEqual(result, .actionExecuted(sticky: false))
        waitForFiles(["dot"])
    }

    @MainActor
    func testAPathThatIsGoneIsAnErrorAndLeavesTheMenuAtTheTop() async {
        let manager = manager(menu(self))
        let result = await manager.runFromLauncha(path: ["x", "y"])
        XCTAssertEqual(result, .error(key: "x"))
        XCTAssertTrue(manager.menuState.keyPath.isEmpty)
    }

    func testKeyPressesInTheMenuCountToo() async {
        let manager = manager(menu(self))
        var launches: [String] = []
        manager.onLaunch = { launches.append($0) }
        _ = await manager.handleKey(key: "d")
        _ = await manager.handleKey(key: "g")
        _ = await manager.handleKey(key: "s")
        waitForFiles(["status"])
        XCTAssertEqual(launches, ["menu:d g s"], "Opening groups is navigation, not a launch")
    }

    func testEveryKeyInTheMenuIsReported() async {
        let manager = manager(menu(self))
        var keys = 0
        manager.onKeyInput = { keys += 1 }
        _ = await manager.handleKey(key: "d")
        _ = await manager.handleKey(key: "q")
        XCTAssertEqual(keys, 2)
    }

    /// The link posts to the handler's own center: the panel of the app hosting the tests stays closed.
    func testTheLaunchaLinkAsksToOpenLauncha() async {
        let center = NotificationCenter()
        let opened = expectation(forNotification: .openLauncha, object: nil, notificationCenter: center)
        await DeepLinkHandler(notificationCenter: center).handle(url: URL(string: "swiftkey://launcha")!)
        await fulfillment(of: [opened], timeout: 2)
    }

    func testDoubleTapIsOffInHoldModeAndWithoutAMainKey() {
        let settings = SettingsStore()
        let saved = (settings.mainHotkey, settings.triggerKeyHoldMode, settings.launchaDoubleTap, settings.launchaDoubleTapWindow)
        defer {
            settings.mainHotkey = saved.0
            settings.triggerKeyHoldMode = saved.1
            settings.launchaDoubleTap = saved.2
            settings.launchaDoubleTapWindow = saved.3
        }
        settings.mainHotkey = "ctrl+option+shift+cmd+f15"
        settings.triggerKeyHoldMode = false
        settings.launchaDoubleTap = true
        XCTAssertTrue(settings.launchaSettings.doubleTap)
        settings.triggerKeyHoldMode = true
        XCTAssertFalse(settings.launchaSettings.doubleTap, "Hold mode keeps the key down: no double tap")
        settings.triggerKeyHoldMode = false
        settings.mainHotkey = ""
        XCTAssertFalse(settings.launchaSettings.doubleTap, "No main key, nothing to press twice")
        settings.launchaDoubleTapWindow = 5
        XCTAssertEqual(settings.launchaSettings.doubleTapWindow, LaunchaSettings.doubleTapWindowRange.upperBound)
    }
}
