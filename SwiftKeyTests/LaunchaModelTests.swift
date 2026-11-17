import SwiftKeyCore
import XCTest
@testable import SwiftKey

/// Thread-safe record of file searches.
private final class Calls: @unchecked Sendable {
    private let lock = NSLock()
    private var queries: [String] = []
    func add(_ query: String) { lock.withLock { queries.append(query) } }
    var all: [String] { lock.withLock { queries } }
}

@MainActor
final class LaunchaModelTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("swiftkey-launcha-model-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        root = try XCTUnwrap(LaunchaPathPolicy.realURL(url))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func app(_ name: String, id: String, in folder: URL) throws -> URL {
        let url = folder.appendingPathComponent(name + ".app")
        let contents = url.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info = ["CFBundleName": name, "CFBundleIdentifier": id, "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        return url
    }

    private struct Fixture {
        var model: LaunchaModel
        var calls: Calls
        var history: URL
        var consent: URL
    }

    private var policies: [ProtectedFolderPolicy] = []

    /// A model over real folders under `root`: apps in `Applications` (and `Desktop` with consent),
    /// and a real file-name search of `Projects` in place of the Spotlight index, which does not
    /// cover temporary folders.
    private func makeModel(searchDelay: Duration = .zero) throws -> Fixture {
        let apps = root.appendingPathComponent("Applications")
        let projects = root.appendingPathComponent("Projects")
        for folder in [apps, projects] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let calls = Calls()
        let home = root!
        let historyURL = root.appendingPathComponent("history.json")
        let consentURL = root.appendingPathComponent("consent.json")
        let model = LaunchaModel(historyStore: LaunchaHistoryStore(url: historyURL),
                                 consent: LaunchaConsentStore(url: consentURL), home: home) { [weak self] policy in
            self?.policies.append(policy)
            let desktop = home.appendingPathComponent("Desktop")
            return LaunchaModel.Services(
                index: LaunchaAppIndex(home: home, protectedFolders: policy, roots: [apps, desktop]),
                spotlight: LaunchaSpotlight(home: home, protectedFolders: policy, debounce: .zero) { query in
                    calls.add(query)
                    if searchDelay > .zero { try? await Task.sleep(for: searchDelay) }
                    let names = try FileManager.default.contentsOfDirectory(atPath: projects.path).sorted()
                    return names.filter { $0.localizedCaseInsensitiveContains(query) }.map { projects.appendingPathComponent($0) }
                })
        }
        return Fixture(model: model, calls: calls, history: historyURL, consent: consentURL)
    }

    private func wait(_ message: String = "condition", timeout: Duration = .seconds(3),
                      until condition: () -> Bool) async throws {
        let clock = ContinuousClock()
        let end = clock.now + timeout
        while !condition() {
            guard clock.now < end else { return XCTFail("Timed out waiting for \(message)") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func testEmptyQueryRanksAppsAndSpotlightOnlyWithoutMatches() async throws {
        let apps = root.appendingPathComponent("Applications")
        try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
        let alpha = try app("Alpha", id: "com.ameba.test.Alpha", in: apps)
        _ = try app("Beta", id: "com.ameba.test.beta", in: apps)
        let fixture = try makeModel()
        let note = root.appendingPathComponent("Projects/zeta-note.txt")
        try Data().write(to: note)
        let model = fixture.model

        // History decides the order: Beta was launched, so it comes first.
        await model.record(.opened, id: "app:com.ameba.test.beta")
        model.open()
        try await wait("index") { model.hasIndex && model.rows.count == 2 }
        XCTAssertEqual(model.rows.map(\.name), ["Beta", "Alpha"])
        XCTAssertEqual(model.rows.last?.url.path, alpha.path)
        XCTAssertTrue(fixture.calls.all.isEmpty)

        model.query = "alp"
        XCTAssertEqual(model.rows.map(\.name), ["Alpha"])
        XCTAssertTrue(fixture.calls.all.isEmpty, "Spotlight must not run while an app matches")

        model.query = "zeta"
        XCTAssertTrue(model.rows.isEmpty)
        try await wait("files") { model.rows.first?.kind == .file }
        XCTAssertEqual(fixture.calls.all, ["zeta"])
        XCTAssertEqual(model.rows.map(\.url.path), [note.path])
        XCTAssertEqual(model.rows.first?.detail, "~/Projects")
        XCTAssertTrue(model.showsConsentNotice, "Protected folders were skipped; the search is not complete")

        // An app match cancels the file search and hides its results.
        model.query = "be"
        XCTAssertEqual(model.rows.map(\.name), ["Beta"])
        XCTAssertEqual(model.spotlight.status, .idle)
        model.close()
    }

    func testIncompleteAndFailedStatesAreShown() async throws {
        let fixture = try makeModel()
        let model = fixture.model
        model.open()
        try await wait("index") { model.hasIndex }
        XCTAssertEqual(model.statusMessage, .info("No menu items or apps found."))
        model.query = "nothing"
        try await wait("empty search") { model.spotlight.status == .empty }
        XCTAssertEqual(model.statusMessage, .info("Nothing matches “nothing”."))
        XCTAssertEqual(Set(model.spotlight.issues.map(\.kind)), [.needsConsent])
        XCTAssertTrue(model.showsConsentNotice)
        XCTAssertNil(model.incompleteMessage)
        model.close()
    }

    func testClosedSessionIgnoresLateResults() async throws {
        let fixture = try makeModel(searchDelay: .milliseconds(150))
        try Data().write(to: root.appendingPathComponent("Projects/late.txt"))
        let model = fixture.model
        model.open()
        try await wait("index") { model.hasIndex }
        model.query = "late"
        XCTAssertEqual(model.spotlight.status, .searching)
        model.close()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(model.rows.isEmpty)
        XCTAssertEqual(model.query, "")
        XCTAssertEqual(model.spotlight.status, .idle)

        // A new session starts clean, with no results of the old query.
        model.open()
        XCTAssertTrue(model.rows.isEmpty)
        XCTAssertEqual(model.query, "")
        model.close()
    }

    func testChoicesForAppsAndCountingOnlySuccessfulLaunches() async throws {
        let apps = root.appendingPathComponent("Applications")
        try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
        let tool = try app("Tool", id: "com.ameba.test.Tool", in: apps)
        let fixture = try makeModel()
        let model = fixture.model
        var closeRequests = 0
        model.onRequestClose = { closeRequests += 1 }

        model.open()
        try await wait("index") { model.rows.count == 1 }
        guard case let .openApp(url, name, candidateID)? = model.activateSelection() else { return XCTFail("Expected an app") }
        XCTAssertEqual(url.path, tool.path)
        XCTAssertEqual(name, "Tool")
        // Same identity as the menu would use for the app: app: + lower-case bundle ID.
        XCTAssertEqual(candidateID, "app:com.ameba.test.tool")
        XCTAssertFalse(model.isOpen)
        XCTAssertEqual(closeRequests, 1)

        await model.record(.opened, id: "app:com.ameba.test.tool")
        await model.record(.failed, id: "app:com.ameba.test.tool")
        await model.record(.revealed, id: "app:com.ameba.test.tool")
        await model.record(.activated, id: "app:com.ameba.test.tool")
        let saved = try LaunchHistory.decode(Data(contentsOf: fixture.history))
        XCTAssertEqual(saved.entries["app:com.ameba.test.tool"]?.events.count, 2, "Failed opens and reveals are not counted")

        model.open()
        try await wait("index") { model.rows.count == 1 }
        guard case let .reveal(revealed)? = model.activateSelection(reveal: true) else { return XCTFail("Expected a reveal") }
        XCTAssertEqual(revealed.path, tool.path)
        XCTAssertNil(model.activateSelection(), "Nothing happens while closed")
    }

    func testSelectionMovesWithinBounds() async throws {
        let apps = root.appendingPathComponent("Applications")
        try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
        for name in ["A1", "A2", "A3"] { _ = try app(name, id: "com.ameba.test." + name, in: apps) }
        let model = try makeModel().model
        model.open()
        try await wait("index") { model.rows.count == 3 }
        model.moveSelection(by: -1)
        XCTAssertEqual(model.selection, 0)
        model.moveSelection(by: 8)
        XCTAssertEqual(model.selection, 2)
        model.query = "a2"
        XCTAssertEqual(model.selection, 0, "A new query selects the first result")
        model.close()
    }

    func testConsentRecreatesServicesAndPersistsSeparately() async throws {
        let desktop = root.appendingPathComponent("Desktop")
        try FileManager.default.createDirectory(at: desktop, withIntermediateDirectories: true)
        _ = try app("DeskTool", id: "com.ameba.test.desk", in: desktop)
        policies = []
        let fixture = try makeModel()
        let model = fixture.model
        model.open()
        try await wait("index") { model.hasIndex }
        XCTAssertTrue(model.rows.isEmpty, "Desktop needs consent first")
        XCTAssertEqual(model.indexIssues.map(\.kind), [.needsConsent])

        model.isExplainingConsent = true
        model.allowProtectedFolders()
        XCTAssertFalse(model.isExplainingConsent)
        XCTAssertEqual(model.protectedFolders, .allowed)
        XCTAssertEqual(policies, [.needsConsent, .allowed])
        try await wait("desktop app") { model.rows.map(\.name) == ["DeskTool"] }
        XCTAssertFalse(model.showsConsentNotice)

        // A fresh store reads the saved choice.
        XCTAssertEqual(LaunchaConsentStore(url: fixture.consent).policy, .allowed)

        model.revokeProtectedFolders()
        XCTAssertTrue(model.rows.isEmpty, "Apps from folders no longer allowed are dropped at once")
        XCTAssertEqual(LaunchaConsentStore(url: fixture.consent).policy, .needsConsent)
        model.close()
    }

    func testConsentStoreIsolationAndFailClosed() throws {
        let config = root.appendingPathComponent("swiftkey-test.yaml")
        let isolated = AppPaths(environment: ["SWIFTKEY_CONFIG": config.path], home: root)
        XCTAssertEqual(isolated.url(for: "launcha-consent.json").path, config.path + ".launcha-consent.json")
        XCTAssertNotEqual(isolated.url(for: "launcha-consent.json"), isolated.url(for: "launcha-history.json"))
        XCTAssertEqual(AppPaths(environment: [:], home: root).url(for: "launcha-consent.json").path,
                       root.appendingPathComponent("Library/Application Support/SwiftKey/launcha-consent.json").path)
        // The running tests use the scheme's override, never the real choice.
        XCTAssertEqual(LaunchaConsentStore().url, AppPaths.current.url(for: "launcha-consent.json"))

        let fresh = LaunchaConsentStore(url: root.appendingPathComponent("missing.json"))
        XCTAssertEqual(fresh.policy, .needsConsent)
        XCTAssertNil(fresh.error)

        let broken = root.appendingPathComponent("broken.json")
        try Data("{\"protectedFolders\": tru".utf8).write(to: broken)
        let store = LaunchaConsentStore(url: broken)
        XCTAssertEqual(store.policy, .needsConsent)
        XCTAssertNotNil(store.error)

        let blocked = root.appendingPathComponent("blocked")
        try Data().write(to: blocked)
        let unwritable = LaunchaConsentStore(url: blocked.appendingPathComponent("consent.json"))
        XCTAssertFalse(unwritable.set(.allowed))
        XCTAssertEqual(unwritable.policy, .needsConsent, "The choice changes only when it was saved")
    }

    func testMenuItemsAreListedAndRunByTheirPath() async throws {
        let apps = root.appendingPathComponent("Applications")
        try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
        _ = try app("Safari", id: "com.apple.Safari", in: apps)
        let fixture = try makeModel()
        try Data().write(to: root.appendingPathComponent("Projects/git-notes.txt"))
        let model = fixture.model
        let config = root.appendingPathComponent("config.yaml")
        let menu: [MenuItem] = [
            MenuItem(key: "d", title: "Developer", submenu: [
                MenuItem(key: "g", title: "Git", submenu: [
                    MenuItem(key: "s", title: "Git Status", action: "shell://git status"),
                ]),
            ]),
            MenuItem(key: "h", title: "Hidden Tool", action: "shell://true", hidden: true),
        ]
        model.setMenu(LaunchaMenuCandidate.from(MenuItemTree.build(menu).items), configFile: config)
        model.open()
        try await wait("index") { model.hasIndex }
        XCTAssertEqual(Set(model.rows.map(\.name)), ["Developer", "Git", "Git Status", "Safari"])

        model.query = "git status"
        XCTAssertEqual(model.rows.map(\.name), ["Git Status"])
        XCTAssertEqual(model.rows.first?.detail, "Developer › Git")
        XCTAssertTrue(fixture.calls.all.isEmpty, "A menu match keeps the file search off")
        XCTAssertEqual(model.activateSelection(), .runMenu(path: ["d", "g", "s"], candidateID: "menu:d g s"))

        // ⌘↩ on a menu item shows its config file.
        model.open()
        model.query = "git status"
        XCTAssertEqual(model.activateSelection(reveal: true), .reveal(config))

        // A group opens the menu there.
        model.open()
        model.query = "developer"
        guard case .menu(_, let path, let kind, _) = model.rows.first?.kind else { return XCTFail("Expected a menu row") }
        XCTAssertEqual(path, ["d"])
        XCTAssertEqual(kind, .group)

        // History counts menu items by their path, like apps.
        await model.record(.opened, id: "menu:d g s")
        model.close()
        model.open()
        try await wait("ranked") { model.rows.first?.name == "Git Status" }
        model.close()
    }

    func testACalculationComesFirstAndReturnCopiesIt() async throws {
        let apps = root.appendingPathComponent("Applications")
        try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
        _ = try app("Calc 2", id: "com.ameba.test.calc2", in: apps)
        let fixture = try makeModel()
        try Data().write(to: root.appendingPathComponent("Projects/2+2 notes.txt"))
        let model = fixture.model
        var closed = 0
        model.onRequestClose = { closed += 1 }
        model.open()
        try await wait("index") { model.hasIndex }

        // Nothing else matches: the value first, the files after it.
        model.query = "2+2"
        XCTAssertEqual(model.rows.first?.kind, .calculation(value: "4"))
        XCTAssertEqual(model.rows.first?.name, "4")
        try await wait("files") { model.rows.count == 2 }
        XCTAssertEqual(model.rows.map(\.kind), [.calculation(value: "4"), .file])
        XCTAssertEqual(model.selection, 0)

        // An app whose name matches the digits comes after the value.
        model.query = "2 * 3"
        XCTAssertEqual(model.rows.first?.kind, .calculation(value: "6"))
        model.query = "calc 2"
        XCTAssertEqual(model.rows.map(\.name), ["Calc 2"], "no operator: no value")

        // Plain text and lone numbers are not calculations.
        model.query = "42"
        XCTAssertFalse(model.rows.contains(where: \.isCalculation))

        // Return copies the value and closes.
        model.query = "1,5 × 4"
        XCTAssertEqual(model.activateSelection(), .copy("6"))
        XCTAssertEqual(closed, 1)

        // Command-Return copies too: a value has nothing to reveal.
        model.open()
        model.query = "10/4"
        XCTAssertEqual(model.activateSelection(reveal: true), .copy("2.5"))

        // Turned off in Settings: no value, at once.
        model.open()
        model.query = "2+2"
        XCTAssertTrue(model.rows.first?.isCalculation == true)
        model.calculator = false
        XCTAssertFalse(model.rows.contains(where: \.isCalculation))
        model.close()
    }
}
