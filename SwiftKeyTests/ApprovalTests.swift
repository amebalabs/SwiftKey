import SwiftKeyCore
import XCTest
@testable import SwiftKey

/// The approval store, what the gate asks about, deep links and editor approvals. No test here
/// opens the approval window: every path that reaches the gate has its code approved first.
final class ApprovalTests: XCTestCase {
    private var folder: URL!
    private var storeURL: URL { folder.appendingPathComponent("approvals.json") }

    override func setUpWithError() throws {
        try super.setUpWithError()
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("swiftkey-approvals-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
        try super.tearDownWithError()
    }

    private let list = CodeRequest(kind: .shell, content: "ls ~")

    // MARK: - Store

    func testMissingFileApprovesNothing() {
        let store = ApprovalStore(url: storeURL)
        XCTAssertEqual(store.pending([list]), [list])
        XCTAssertFalse(FileManager.default.fileExists(atPath: storeURL.path))
    }

    func testApprovalIsSavedAndReadBack() throws {
        try ApprovalStore(url: storeURL).approve([list])
        XCTAssertTrue(ApprovalStore(url: storeURL).pending([list]).isEmpty)
        let text = try String(contentsOf: storeURL, encoding: .utf8)
        XCTAssertTrue(text.contains(list.hash))
        XCTAssertFalse(text.contains("ls ~"))
    }

    func testUnreadableFileApprovesNothing() throws {
        try Data("{ not json".utf8).write(to: storeURL)
        XCTAssertEqual(ApprovalStore(url: storeURL).pending([list]), [list])
    }

    func testDefaultStoreFollowsTheConfigOverride() {
        let paths = AppPaths(environment: ["SWIFTKEY_CONFIG": "/tmp/x/config.yaml"])
        XCTAssertEqual(paths.url(for: "approvals.json").path, "/tmp/x/config.yaml.approvals.json")
    }

    // MARK: - What needs approval

    func testRequestsOfItems() {
        let items = [
            MenuItem(key: "a", title: "List", action: "shell://ls ~"),
            MenuItem(key: "b", title: "Safari", action: "launch://com.apple.Safari"),
            MenuItem(key: "c", title: "Site", action: "open://https://example.com"),
            MenuItem(key: "d", title: "Focus", action: "shortcut://Focus"),
            MenuItem(key: "e", title: "Menu", action: "dynamic://~/menu.sh"),
            MenuItem(key: "f", title: "Group", submenu: [MenuItem(key: "x", title: "X", action: "shell://date")]),
        ]
        XCTAssertEqual(ApprovalGate.requests(for: items).map(\.request),
                       [list, CodeRequest(kind: .dynamic, content: "~/menu.sh")])
        XCTAssertEqual(ApprovalGate.allRequests(in: items).count, 3)
    }

    func testBatchGroupAsksForItsChildren() {
        let batch = MenuItem(key: "b", title: "Batch", batch: true, submenu: [
            MenuItem(key: "1", title: "One", action: "shell://date"),
            MenuItem(key: "2", title: "Two", action: "launch://com.apple.Safari"),
        ])
        XCTAssertEqual(ApprovalGate.requests(for: [batch]).map(\.request), [CodeRequest(kind: .shell, content: "date")])
    }

    func testItemsMadeByADynamicScriptNeedNoApproval() {
        let made = MenuItem(key: "a", title: "Kill", action: "shell://kill 1", submenu: nil).markedGenerated()
        XCTAssertTrue(made.isGenerated)
        XCTAssertTrue(ApprovalGate.requests(for: [made]).isEmpty)
        let group = MenuItem(key: "g", title: "G", submenu: [MenuItem(key: "a", title: "A", action: "shell://x")]).markedGenerated()
        XCTAssertEqual(group.submenu?.first?.isGenerated, true)
    }

    /// The config's coding keys never include the mark, so a config file cannot set it.
    func testGeneratedMarkIsNeverEncodedOrDecoded() throws {
        let item = MenuItem(key: "a", title: "A", action: "shell://x").markedGenerated()
        let encoded = String(decoding: try JSONEncoder().encode([item]), as: UTF8.self)
        XCTAssertFalse(encoded.contains("isGenerated"))
        let text = #"[{"key": "a", "title": "A", "action": "shell://x", "isGenerated": true}]"#
        let decoded = try JSONDecoder().decode([MenuItem].self, from: Data(text.utf8))
        XCTAssertEqual(decoded.first?.isGenerated, false)
    }

    func testPendingCodeNamesTheOrigin() throws {
        let store = ApprovalStore(url: storeURL)
        let gate = ApprovalGate(store: store)
        let items = [MenuItem(key: "a", title: "List", action: "shell://ls ~"),
                     MenuItem(key: "b", title: "Date", action: "shell://date")]
        try gate.recordSnippet(named: "Dev tools", items: [items[0]])

        let pending = gate.pendingCode(for: items, path: ["Tools", "Shell"])
        XCTAssertEqual(pending.map(\.title), ["List", "Date"])
        XCTAssertEqual(pending.map(\.origin), ["snippet “Dev tools”", ApprovalGate.outsideOrigin])
        XCTAssertEqual(pending.first?.path, "Tools › Shell")

        try store.approve([list])
        XCTAssertEqual(gate.pendingCode(for: items, path: []).map(\.title), ["Date"])
    }

    @MainActor
    func testApprovedCodeIsAuthorizedWithoutAsking() async throws {
        let store = ApprovalStore(url: storeURL)
        try store.approve([list])
        let gate = ApprovalGate(store: store)
        let authorized = await gate.authorize([MenuItem(key: "a", title: "List", action: "shell://ls ~")], path: [])
        XCTAssertTrue(authorized)
        let noCode = await gate.authorize([MenuItem(key: "s", title: "Safari", action: "launch://com.apple.Safari")], path: [])
        XCTAssertTrue(noCode)
    }

    // MARK: - Dynamic menus

    func testDynamicMenuDoesNotRunWithoutAGate() async throws {
        let marker = folder.appendingPathComponent("ran")
        let item = MenuItem(key: "p", title: "P", action: "dynamic://'touch \(marker.path)'")
        let menu = await DynamicMenuLoader().loadDynamicMenu(for: item)
        XCTAssertNil(menu)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }

    func testApprovedDynamicMenuItemsAreMarkedGenerated() async throws {
        let script = folder.appendingPathComponent("menu.sh")
        try "#!/bin/sh\nprintf -- '- key: k\\n  title: Kill\\n  action: shell://true\\n'\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        let item = MenuItem(key: "p", title: "P", action: "dynamic://\(script.path)")
        let store = ApprovalStore(url: storeURL)
        try store.approve(ApprovalGate.allRequests(in: [item]))

        let menu = await DynamicMenuLoader(approvalGate: ApprovalGate(store: store)).loadDynamicMenu(for: item)
        XCTAssertEqual(menu?.map(\.title), ["Kill"])
        XCTAssertEqual(menu?.first?.isGenerated, true)
    }

    // MARK: - Deep links

    private let menu = [
        MenuItem(key: "d", title: "Developer", submenu: [
            MenuItem(key: "g", title: "Git Pull", action: "shell://git pull"),
            MenuItem(key: "m", title: "Menu", action: "dynamic://~/menu.sh"),
            MenuItem(key: "j", title: "JSON", action: "micro://format-json"),
            MenuItem(key: "s", title: "Safari", action: "launch://com.apple.Safari"),
            MenuItem(key: "w", title: "Web", action: "open://https://example.com"),
            MenuItem(key: "f", title: "Focus", action: "shortcut://Focus"),
        ]),
        MenuItem(key: "t", title: "Top", action: "shell://date"),
    ]

    func testDeepLinkToCodeOnlyNavigates() {
        for (key, title) in [("g", "Git Pull"), ("m", "Menu"), ("j", "JSON")] {
            guard case let .navigate(groups, hint) = DeepLinkHandler.resolve(["d", key], in: menu) else {
                return XCTFail("\(title) should navigate")
            }
            XCTAssertEqual(groups.map(\.title), ["Developer"])
            XCTAssertEqual(hint, "Press \(key) to run \(title)")
        }
        guard case let .navigate(groups, hint) = DeepLinkHandler.resolve(["t"], in: menu) else {
            return XCTFail("top-level code should navigate")
        }
        XCTAssertTrue(groups.isEmpty)
        XCTAssertEqual(hint, "Press t to run Top")
    }

    func testDeepLinkRunsLaunchOpenAndShortcut() {
        for key in ["s", "w", "f"] {
            guard case let .run(item, path) = DeepLinkHandler.resolve(["d", key], in: menu) else {
                return XCTFail("\(key) should run")
            }
            XCTAssertEqual(item.key, key)
            XCTAssertEqual(path, ["Developer"])
        }
    }

    func testDeepLinkToAGroupOpensIt() {
        XCTAssertEqual(DeepLinkHandler.resolve(["d"], in: menu), .navigate(groups: [menu[0]], hint: nil))
    }

    /// A link to a group whose only item is `dynamic://` opens the menu without running the
    /// command: the menu is told not to load the dynamic menu on its own.
    @MainActor
    func testDeepLinkNeverLoadsADynamicMenuByItself() async {
        let center = NotificationCenter()
        let handler = DeepLinkHandler(notificationCenter: center)
        handler.menuState.rootMenu = [
            MenuItem(key: "g", title: "Generated", submenu: [MenuItem(key: "p", title: "Processes", action: "dynamic://ps")]),
        ]
        var loads: [Bool] = []
        let token = center.addObserver(forName: .presentOverlay, object: nil, queue: nil) { note in
            loads.append(note.userInfo?[PresentOverlayKey.loadsDynamicMenu] as? Bool ?? true)
        }
        defer { center.removeObserver(token) }
        await handler.handle(url: URL(string: "swiftkey://open?path=g")!)
        await handler.handle(url: URL(string: "swiftkey://open?path=g,p")!)
        XCTAssertEqual(loads, [false, false])
        XCTAssertTrue(handler.menuState.hasSingleDynamicMenuItem, "the lone dynamic item is shown, not run")
    }

    func testDeepLinkToAMissingKeyFindsNothing() {
        XCTAssertEqual(DeepLinkHandler.resolve(["x"], in: menu), .notFound)
        XCTAssertEqual(DeepLinkHandler.resolve(["d", "x"], in: menu), .notFound)
    }

    // MARK: - Editor

    func testOnlyCommandsTypedInTheEditorAreApprovedOnSave() throws {
        let store = ApprovalStore(url: storeURL)
        let model = ConfigEditorViewModel(configManager: ConfigManager.create(), approvalGate: ApprovalGate(store: store))
        let outside = MenuItem(key: "o", title: "Outside", action: "shell://echo outside")
        var typed = MenuItem(key: "t", title: "Typed", action: "launch://com.apple.Safari")
        model.menuItems = [outside, typed]

        typed.action = "shell://echo typed"
        model.updateMenuItem(typed)
        var renamed = outside
        renamed.title = "Renamed"
        model.updateMenuItem(renamed)
        model.approveTypedCommands()

        XCTAssertTrue(store.pending([CodeRequest(kind: .shell, content: "echo typed")]).isEmpty)
        XCTAssertFalse(store.pending([CodeRequest(kind: .shell, content: "echo outside")]).isEmpty)
        XCTAssertTrue(model.typedCommands.isEmpty)
    }

    func testTypedCommandRemovedBeforeSaveIsNotApproved() throws {
        let store = ApprovalStore(url: storeURL)
        let model = ConfigEditorViewModel(configManager: ConfigManager.create(), approvalGate: ApprovalGate(store: store))
        var item = MenuItem(key: "t", title: "Typed", action: "launch://com.apple.Safari")
        model.menuItems = [item]
        item.action = "shell://echo draft"
        model.updateMenuItem(item)
        item.action = "shell://echo final"
        model.updateMenuItem(item)
        model.approveTypedCommands()

        XCTAssertFalse(store.pending([CodeRequest(kind: .shell, content: "echo draft")]).isEmpty)
        XCTAssertTrue(store.pending([CodeRequest(kind: .shell, content: "echo final")]).isEmpty)
    }
}
