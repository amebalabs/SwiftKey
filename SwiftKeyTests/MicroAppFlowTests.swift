import AppKit
import SwiftKeyCore
@testable import SwiftKeyRuntime
import XCTest
@testable import SwiftKey

/// The start path of a micro-app with a temporary config: folder, approvals, runner, result rules
/// and the real flow controller. The flow never puts its panel on screen, a private pasteboard
/// stands in for the clipboard, and every approval is recorded in a temporary store beforehand,
/// so no window opens and the person's screen, clipboard and files are not touched.
@MainActor
final class MicroAppFlowTests: XCTestCase {
    private var directory: URL!
    private var configURL: URL!
    private var paths: AppPaths!
    private var pasteboard: NSPasteboard!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("swiftkey-flow-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        configURL = directory.appendingPathComponent("swiftkey-test.yaml")
        paths = AppPaths(environment: [AppPaths.environmentKey: configURL.path])
        pasteboard = NSPasteboard(name: NSPasteboard.Name("com.ameba.SwiftKey.tests." + UUID().uuidString))
    }

    override func tearDown() async throws {
        pasteboard.releaseGlobally()
        try? FileManager.default.removeItem(at: directory)
    }

    private var example: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Packages/SwiftKeyCore/docs/micro-apps/examples/format-json.yaml")
    }

    private func runner(timeLimit: TimeInterval = 20, outputLimit: Int = MicroAppRunRules.outputLimit) -> MicroAppRunner {
        var runner = MicroAppRunner()
        runner.path = { "/usr/bin:/bin:/usr/sbin:/sbin" }
        runner.workingDirectory = directory.path
        runner.timeLimit = timeLimit
        runner.outputLimit = outputLimit
        return runner
    }

    private func app(_ command: String, to: [MicroApp.OutputTarget] = [.panel]) -> MicroApp {
        MicroApp(id: "test", description: "Test", input: .clipboard, command: command, output: .init(targets: to, style: .console))
    }

    /// A store over the temporary micro-apps folder with these files in it.
    private func store(_ files: [String: String]) throws -> MicroAppStore {
        let store = MicroAppStore(configURL: configURL, paths: paths)
        try FileManager.default.createDirectory(at: store.folderURL, withIntermediateDirectories: true)
        for (name, text) in files {
            try text.write(to: store.folderURL.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        return store
    }

    /// An approval store in the temporary folder with the working micro-apps of `catalog` approved.
    private func approvals(approving catalog: MicroAppCatalog) throws -> ApprovalStore {
        let store = ApprovalStore(url: paths.url(for: "approvals.json"))
        for entry in catalog.entries {
            guard let app = entry.app else { continue }
            try store.approveMicro(id: app.id, hash: entry.contentHash)
        }
        return store
    }

    private func flow(_ catalog: MicroAppCatalog, approvals: ApprovalStore) -> MicroAppFlowController {
        let gate = ApprovalGate(store: approvals)
        let flow = MicroAppFlowController(gate: gate, values: MicroAppValueStore(url: paths.url(for: "micro-values.json")),
                                          runner: runner(), pasteboard: pasteboard, presentsWindow: false, frontmost: { nil })
        gate.microApps = flow
        flow.setCatalog(catalog)
        addTeardownBlock { @MainActor in flow.close() }
        return flow
    }

    /// Waits until the flow shows a result panel.
    private func waitForResult(_ flow: MicroAppFlowController, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if case .result = flow.session.state { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("no result panel", file: file, line: line)
    }

    private static let upper = """
    format: ting.microapp/2
    description: Upper case.
    input: clipboard
    command: tr a-z A-Z
    output:
      to: [clipboard]

    """

    private static let failing = """
    format: ting.microapp/2
    description: Fails.
    input: none
    command: echo broken >&2; exit 3
    output:
      to: [panel]

    """

    /// Runs `start` to its end: an error that fits two lines is a toast and ends the flow at once;
    /// a longer one is a panel, closed here with Esc. Returns the outcome and the message shown.
    private func finish(_ flow: MicroAppFlowController,
                        _ start: @escaping @MainActor () async -> MicroAppOutcome) async -> (MicroAppOutcome, String) {
        var toasts: [String] = []
        flow.onToast = { toasts.append($0) }
        let run = Task { await start() }
        var shown = ""
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline, toasts.isEmpty {
            if case .result(let content) = flow.session.state {
                shown = content.text
                flow.handle(.escape)
                break
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        let outcome = await run.value
        return (outcome, toasts.first ?? shown)
    }

    // MARK: Files and approvals

    func testApprovalsAndValuesSitNextToTheConfigNotInTheFolderOrConfig() {
        let store = MicroAppStore(configURL: configURL, paths: paths)
        for name in ["approvals.json", "micro-values.json"] {
            let url = paths.url(for: name)
            XCTAssertEqual(url.path, configURL.path + "." + name)
            XCTAssertFalse(url.path.hasPrefix(store.folderURL.path + "/"))
            XCTAssertNotEqual(url, configURL)
        }
        let home = URL(fileURLWithPath: "/Users/someone")
        XCTAssertEqual(AppPaths(environment: [:], home: home).url(for: "approvals.json").path,
                       "/Users/someone/Library/Application Support/SwiftKey/approvals.json")
    }

    func testFormatJSONIsApprovedOnceAndAskedAgainAfterAnEdit() async throws {
        let store = try store([:])
        let fileURL = store.folderURL.appendingPathComponent("format-json.yaml")
        try FileManager.default.copyItem(at: example, to: fileURL)
        let approvalsURL = paths.url(for: "approvals.json")
        var approvals = ApprovalStore(url: approvalsURL)

        // First start: not approved; the hash is the file's own bytes.
        var catalog = store.load()
        guard case .working(let app, let entry) = catalog.resolve("format-json") else { return XCTFail("the example must load") }
        XCTAssertEqual(entry.contentHash, MicroAppApprovals.hash(try Data(contentsOf: fileURL)))
        XCTAssertFalse(approvals.isMicroApproved(id: app.id, hash: entry.contentHash))
        XCTAssertFalse(FileManager.default.fileExists(atPath: approvalsURL.path))

        // Approve and run.
        try approvals.approveMicro(id: app.id, hash: entry.contentHash)
        let result = await runner().run(app, stdin: #"{"b":1,"a":[1,2]}"#)
        let plan = MicroAppResultPlan.make(app: app, result: result)
        XCTAssertEqual(plan.clipboard, "{\n  \"a\": [\n    1,\n    2\n  ],\n  \"b\": 1\n}")
        guard case .panel(let content) = plan.show else { return XCTFail("expected the result panel") }
        XCTAssertEqual(content.notes, ["Copied"])
        XCTAssertEqual(content.style, .code)

        // Second start, also after a restart of SwiftKey: approved.
        approvals = ApprovalStore(url: approvalsURL)
        XCTAssertTrue(approvals.isMicroApproved(id: app.id, hash: entry.contentHash))

        // Any edit asks again.
        try (String(contentsOf: fileURL, encoding: .utf8) + "# edited\n").write(to: fileURL, atomically: true, encoding: .utf8)
        catalog = store.load()
        guard case .working(_, let edited) = catalog.resolve("format-json") else { return XCTFail("the edited file must load") }
        XCTAssertFalse(approvals.isMicroApproved(id: app.id, hash: edited.contentHash))

        // The approval is not in the folder and not in the config.
        let stored = try String(contentsOf: approvalsURL, encoding: .utf8)
        XCTAssertTrue(stored.contains(entry.contentHash))
        XCTAssertFalse(FileManager.default.fileExists(atPath: configURL.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.folderURL.path), ["format-json.yaml"])
    }

    func testTheApprovalWindowShowsTheWholeMicroApp() throws {
        let catalog = try store(["upper.yaml": Self.upper]).load()
        guard case .working(let app, let entry) = catalog.resolve("upper") else { return XCTFail("upper must load") }
        let pending = PendingMicroApp(app: app, hash: entry.contentHash, file: "~/micro/upper.yaml")
        XCTAssertEqual(pending.text, "tr a-z A-Z")
        XCTAssertEqual(pending.facts.first, PendingMicroApp.Fact(label: "file", value: "~/micro/upper.yaml"))
        let code = PendingCode(subject: .microApp(pending), title: app.shownName, path: "", origin: "the micro-app file x")
        XCTAssertNil(code.request)
        XCTAssertEqual(ApprovalView.windowTitle([code]), "Run Micro-app?")
        XCTAssertEqual(code.id, "micro:upper:" + entry.contentHash)
    }

    // MARK: The flow

    func testAnApprovedMicroAppRunsAndReportsSuccess() async throws {
        let catalog = try store(["upper.yaml": Self.upper]).load()
        let flow = flow(catalog, approvals: try approvals(approving: catalog))
        pasteboard.clearContents()
        pasteboard.setString("hello", forType: .string)

        let outcome = await flow.run(id: "upper")
        XCTAssertEqual(outcome, .ran(succeeded: true))
        XCTAssertEqual(pasteboard.string(forType: .string), "HELLO")
        XCTAssertFalse(flow.isOpen)
    }

    func testAFailedRunShowsItsErrorAndReportsFailureWhenClosed() async throws {
        let catalog = try store(["failing.yaml": Self.failing]).load()
        let flow = flow(catalog, approvals: try approvals(approving: catalog))
        let run = Task { await flow.run(id: "failing") }
        await waitForResult(flow)
        guard case .result(let content) = flow.session.state else { return XCTFail("expected the result panel") }
        XCTAssertTrue(content.isError)
        XCTAssertTrue(content.text.contains("broken"))
        flow.handle(.escape)
        let outcome = await run.value
        XCTAssertEqual(outcome, .ran(succeeded: false))
    }

    func testAMissingMicroAppShowsAnErrorAndNeverRuns() async throws {
        let catalog = try store([:]).load()
        let flow = flow(catalog, approvals: try approvals(approving: catalog))
        flow.folderDisplay = { "~/micro" }
        let (outcome, message) = await finish(flow) { await flow.run(id: "nothing") }
        XCTAssertTrue(message.contains("`nothing` not found in ~/micro"), message)
        XCTAssertEqual(outcome, .notRun)
    }

    func testABrokenFileShowsItsOwnErrors() async throws {
        let catalog = try store(["bad.yaml": "format: nope\n"]).load()
        let flow = flow(catalog, approvals: try approvals(approving: catalog))
        let (outcome, message) = await finish(flow) { await flow.run(file: "bad.yaml") }
        XCTAssertTrue(message.contains("bad.yaml"), message)
        XCTAssertEqual(outcome, .notRun)
    }

    func testAStartClosesTheOpenFlowWhichEndsWithItsOwnOutcome() async throws {
        let catalog = try store(["failing.yaml": Self.failing, "upper.yaml": Self.upper]).load()
        let flow = flow(catalog, approvals: try approvals(approving: catalog))
        let first = Task { await flow.run(id: "failing") }
        await waitForResult(flow)
        pasteboard.clearContents()
        pasteboard.setString("abc", forType: .string)
        let second = await flow.run(id: "upper")
        XCTAssertEqual(second, .ran(succeeded: true))
        let firstOutcome = await first.value
        XCTAssertEqual(firstOutcome, .ran(succeeded: false))
    }

    // MARK: The gate and the menu

    func testAMicroAppItemRunsThroughTheGateAndCountsOnlyWhenItRan() async throws {
        let catalog = try store(["upper.yaml": Self.upper, "failing.yaml": Self.failing]).load()
        let flow = flow(catalog, approvals: try approvals(approving: catalog))
        let gate = flow.gate

        pasteboard.clearContents()
        pasteboard.setString("x", forType: .string)
        let ran = await gate.run(MenuItem(key: "u", title: "Upper", action: "micro://upper"), path: [])
        XCTAssertTrue(ran)
        XCTAssertEqual(pasteboard.string(forType: .string), "X")

        let failing = Task { await gate.run(MenuItem(key: "f", title: "Fails", action: "micro://failing"), path: []) }
        await waitForResult(flow)
        flow.handle(.escape)
        let failingRan = await failing.value
        XCTAssertFalse(failingRan)
    }

    func testABatchRunsItsMicroAppsOneAfterAnother() async throws {
        let second = Self.upper.replacingOccurrences(of: "tr a-z A-Z", with: "tr A-Z a-z; printf !")
        let catalog = try store(["upper.yaml": Self.upper, "lower.yaml": second]).load()
        let flow = flow(catalog, approvals: try approvals(approving: catalog))
        let gate = flow.gate
        pasteboard.clearContents()
        pasteboard.setString("MiXeD", forType: .string)
        let ran = await gate.runBatch([MenuItem(key: "1", title: "Upper", action: "micro://upper"),
                                       MenuItem(key: "2", title: "Lower", action: "micro://lower")], path: [])
        XCTAssertTrue(ran)
        // The second ran on the first's result: both ran, in order.
        XCTAssertEqual(pasteboard.string(forType: .string), "mixed!")
    }

    func testMicroAppItemsHaveNoActionClosureButAnID() {
        let item = MenuItem(key: "j", title: "JSON", action: "micro://format-json")
        XCTAssertNil(item.actionClosure)
        XCTAssertEqual(item.microAppID, "format-json")
        XCTAssertNil(MenuItem(key: "j", title: "JSON", action: "micro:// ").microAppID)
        XCTAssertNil(MenuItem(key: "j", title: "JSON", action: "shell://true").microAppID)
    }

    // MARK: Results

    func testFormatJSONOnBadInputFailsInThePanel() async {
        let app = MicroAppCatalog.load([("format-json.yaml", (try? String(contentsOf: example, encoding: .utf8)) ?? "")]).apps.first
        guard let app else { return XCTFail("the example must load") }
        let result = await runner().run(app, stdin: "not json")
        let plan = MicroAppResultPlan.make(app: app, result: result)
        XCTAssertNil(plan.clipboard)
        guard case .panel(let content) = plan.show else { return XCTFail("expected the result panel") }
        XCTAssertTrue(content.isError)
        XCTAssertEqual(content.style, .console)
        XCTAssertTrue(content.notes.first?.hasPrefix("exit ") == true)
        XCTAssertFalse(content.text.isEmpty)
    }

    func testLongOutputShowsTheCutNote() async {
        let app = app("yes swiftkey | head -c 100000", to: [.panel])
        let plan = MicroAppResultPlan.make(app: app, result: await runner(outputLimit: 1000).run(app), outputLimit: 1000)
        guard case .panel(let content) = plan.show else { return XCTFail("expected the result panel") }
        XCTAssertEqual(content.notes, ["output cut at 1000 bytes"])
        XCTAssertLessThanOrEqual(content.text.utf8.count, 1000)
    }

    func testTimeoutShowsStoppedWithPartialOutput() async {
        let app = app("echo before; sleep 30", to: [.clipboard])
        let runner = runner(timeLimit: 0.5)
        let plan = MicroAppResultPlan.make(app: app, result: await runner.run(app), timeLimit: 0.5)
        XCTAssertNil(plan.clipboard)
        guard case .panel(let content) = plan.show else { return XCTFail("expected the result panel") }
        XCTAssertEqual(content.notes, ["stopped after 1 s"])
        XCTAssertEqual(content.text, "before")
        XCTAssertEqual(MicroAppResultPlan.timeoutNote(), "stopped after 60 s")
    }

    func testEscDuringTheRunStopsSilently() async {
        let app = app("sleep 30; echo late", to: [.clipboard])
        let runner = runner()
        let task = Task { await runner.run(app) }
        try? await Task.sleep(nanoseconds: 200_000_000)
        task.cancel()
        let plan = MicroAppResultPlan.make(app: app, result: await task.value)
        XCTAssertEqual(plan, MicroAppResultPlan(show: .nothing))
    }
}

/// The key-equivalent path of the flow panel: AppKit sends ⌘ shortcuts there before `sendEvent`.
@MainActor
final class MicroAppFlowPanelKeyTests: XCTestCase {
    private func keyDown(_ keyCode: UInt16, _ characters: String, flags: NSEvent.ModifierFlags = .command) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                         context: nil, characters: characters, charactersIgnoringModifiers: characters,
                         isARepeat: false, keyCode: keyCode)!
    }

    private func press(_ event: NSEvent) -> (handled: Bool, keys: [MicroAppFlowPanel.Key]) {
        let panel = MicroAppFlowPanel()
        var keys: [MicroAppFlowPanel.Key] = []
        panel.onKey = { keys.append($0) }
        let handled = panel.performKeyEquivalent(with: event)
        return (handled, keys)
    }

    func testCommandReturnConfirms() {
        let result = press(keyDown(36, "\r"))
        XCTAssertTrue(result.handled)
        XCTAssertEqual(result.keys, [.commandEnter])
    }

    func testCommandKeypadEnterConfirms() {
        let result = press(keyDown(76, "\u{3}"))
        XCTAssertTrue(result.handled)
        XCTAssertEqual(result.keys, [.commandEnter])
    }

    func testCommandQIsSwallowed() {
        let result = press(keyDown(12, "q"))
        XCTAssertTrue(result.handled)
        XCTAssertEqual(result.keys, [])
    }

    func testCommandShiftReturnIsSwallowedWithoutConfirming() {
        let result = press(keyDown(36, "\r", flags: [.command, .shift]))
        XCTAssertTrue(result.handled)
        XCTAssertEqual(result.keys, [])
    }
}

/// launcha lists micro-apps from the catalog and counts a micro-app start in its history only
/// when it ran: not when it could not start or its run failed.
@MainActor
final class LaunchaMicroAppTests: XCTestCase {
    private var directory: URL!
    private var pasteboard: NSPasteboard!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("swiftkey-launcha-micro-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        pasteboard = NSPasteboard(name: NSPasteboard.Name("com.ameba.SwiftKey.tests." + UUID().uuidString))
    }

    override func tearDown() async throws {
        pasteboard.releaseGlobally()
        try? FileManager.default.removeItem(at: directory)
    }

    private static let upper = """
    format: ting.microapp/2
    name: Upper case
    description: Upper case.
    input: clipboard
    command: tr a-z A-Z
    output:
      to: [clipboard]

    """

    private static let failing = """
    format: ting.microapp/2
    name: Always fails
    description: Fails.
    input: none
    command: exit 3
    output:
      to: [clipboard]

    """

    private static let secret = """
    format: ting.microapp/2
    description: Hidden.
    hidden: true
    input: none
    command: echo hi

    """

    private func catalog() -> MicroAppCatalog {
        MicroAppCatalog.load([("upper.yaml", Self.upper), ("failing.yaml", Self.failing), ("secret.yaml", Self.secret),
                              ("bad.yaml", "format: nope\n")])
    }

    private func model() -> LaunchaModel {
        let home = directory!
        let apps = home.appendingPathComponent("Applications")
        try? FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
        return LaunchaModel(historyStore: LaunchaHistoryStore(url: home.appendingPathComponent("history.json")),
                            consent: LaunchaConsentStore(url: home.appendingPathComponent("consent.json")), home: home) { policy in
            LaunchaModel.Services(index: LaunchaAppIndex(home: home, protectedFolders: policy, roots: [apps]),
                                  spotlight: LaunchaSpotlight(home: home, protectedFolders: policy, debounce: .zero) { _ in [] })
        }
    }

    /// A launcha controller that starts micro-apps through a real flow with every one approved.
    private func controller(_ model: LaunchaModel, catalog: MicroAppCatalog) throws -> (LaunchaController, MicroAppFlowController) {
        let approvals = ApprovalStore(url: directory.appendingPathComponent("approvals.json"))
        for entry in catalog.entries {
            if let app = entry.app { try approvals.approveMicro(id: app.id, hash: entry.contentHash) }
        }
        var runner = MicroAppRunner()
        runner.path = { "/usr/bin:/bin:/usr/sbin:/sbin" }
        runner.workingDirectory = directory.path
        let flow = MicroAppFlowController(gate: ApprovalGate(store: approvals),
                                          values: MicroAppValueStore(url: directory.appendingPathComponent("values.json")),
                                          runner: runner, pasteboard: pasteboard, presentsWindow: false, frontmost: { nil })
        flow.setCatalog(catalog)
        addTeardownBlock { @MainActor in flow.close() }
        let controller = LaunchaController(model: model)
        controller.onStartMicro = { [weak flow] start in
            guard let flow else { return .notRun }
            switch start {
            case .id(let id): return await flow.run(id: id)
            case .file(let file): return await flow.run(file: file)
            }
        }
        return (controller, flow)
    }

    /// Carries out `choice` to its end; an error panel is closed with Esc, an error toast ends at once.
    private func perform(_ choice: LaunchaChoice, on controller: LaunchaController, flow: MicroAppFlowController) async {
        var toasted = false
        flow.onToast = { _ in toasted = true }
        let task = Task { await controller.perform(choice) }
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline, !toasted {
            if case .result = flow.session.state {
                flow.handle(.escape)
                break
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        await task.value
    }

    private func count(_ model: LaunchaModel, _ id: String) async -> Int {
        await model.historyStore.load().history.recentCount(id: id, now: Date())
    }

    func testMicroAppsAreListedExceptHiddenOnesWithBrokenFilesMarked() {
        let model = model()
        model.setMicroApps(catalog().launchaCandidates(bindings: []), folder: directory)
        model.open()
        addTeardownBlock { @MainActor in model.close() }
        model.query = "upper"
        XCTAssertEqual(model.rows.first?.name, "Upper case")
        XCTAssertTrue(model.rows.first?.isMicro == true)
        XCTAssertEqual(model.rows.first?.url, directory.appendingPathComponent("upper.yaml"))
        model.query = "bad"
        XCTAssertEqual(model.rows.first?.isWorking, false)
        XCTAssertTrue(model.rows.first?.detail.hasPrefix("Not working:") == true)
        model.query = "secret"
        XCTAssertFalse(model.rows.contains { $0.isMicro })
    }

    func testChoosingAMicroAppStartsItAndRevealShowsItsFile() {
        let model = model()
        model.setMicroApps(catalog().launchaCandidates(bindings: []), folder: directory)
        model.open()
        model.query = "upper"
        XCTAssertEqual(model.activateSelection(), .startMicro(.id("upper"), candidateID: "micro:upper"))
        model.open()
        model.query = "upper"
        XCTAssertEqual(model.activateSelection(reveal: true), .reveal(directory.appendingPathComponent("upper.yaml")))
    }

    func testAStartCountsOnlyWhenTheMicroAppRan() async throws {
        let model = model()
        let catalog = catalog()
        let (controller, flow) = try controller(model, catalog: catalog)

        pasteboard.clearContents()
        pasteboard.setString("abc", forType: .string)
        await controller.perform(.startMicro(.id("upper"), candidateID: "micro:upper"))
        XCTAssertEqual(pasteboard.string(forType: .string), "ABC")
        let ran = await count(model, "micro:upper")
        XCTAssertEqual(ran, 1)

        // A failed run shows its error; the start ends when that is closed, and is not counted.
        await perform(.startMicro(.id("failing"), candidateID: "micro:failing"), on: controller, flow: flow)
        let failed = await count(model, "micro:failing")
        XCTAssertEqual(failed, 0)

        // A broken file shows its errors and is not counted either.
        await perform(.startMicro(.file("bad.yaml"), candidateID: "micro-file:bad.yaml"), on: controller, flow: flow)
        let brokenCount = await count(model, "micro-file:bad.yaml")
        XCTAssertEqual(brokenCount, 0)
    }
}
