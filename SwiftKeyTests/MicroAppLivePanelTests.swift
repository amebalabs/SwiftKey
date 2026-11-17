@testable import SwiftKeyRuntime
import AppKit
import XCTest
import SwiftKeyCore
@testable import SwiftKey

/// The working panel of a steps micro-app: it names the running step and shows the output of the
/// last step while it comes. The real panel is built but never shown, with a private pasteboard.
@MainActor
final class MicroAppLivePanelTests: XCTestCase {
    func testWorkingPanelShowsTheStepAndTheLiveOutput() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("swiftkey-live-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let text = """
        format: ting.microapp/2
        name: Live
        description: Prints slowly.
        input: none
        steps:
          - text: start
          - command: cat; echo; echo one; sleep 1; echo two
        output:
          to: [panel, clipboard]
          as: code

        """
        let catalog = MicroAppCatalog.load([("live.yaml", text)])
        let entry = try XCTUnwrap(catalog.entries.first)
        XCTAssertEqual(entry.issues, [])
        let approvals = ApprovalStore(url: directory.appendingPathComponent("approvals.json"))
        try approvals.approveMicro(id: "live", hash: entry.contentHash)

        var runner = MicroAppRunner()
        runner.path = { "/usr/bin:/bin:/usr/sbin:/sbin" }
        runner.environment = [:]
        runner.workingDirectory = directory.path
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.ameba.SwiftKey.tests." + UUID().uuidString))
        addTeardownBlock { @MainActor in pasteboard.releaseGlobally() }
        let flow = MicroAppFlowController(gate: ApprovalGate(store: approvals),
                                          values: MicroAppValueStore(url: directory.appendingPathComponent("values.json")),
                                          runner: runner, pasteboard: pasteboard, presentsWindow: false, frontmost: { nil })
        addTeardownBlock { @MainActor in flow.close() }
        flow.setCatalog(catalog)
        let run = Task { await flow.run(id: "live") }

        // While the last step sleeps, the panel shows its first line and the step label.
        var live: MicroAppRunProgress?
        let end = Date().addingTimeInterval(5)
        while Date() < end {
            if let progress = flow.session.progress, progress.liveOutput?.contains("one") == true { live = progress; break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let progress = try XCTUnwrap(live, "no live output")
        XCTAssertEqual(progress.label, "Step 2 of 2 · command")
        XCTAssertFalse(progress.liveOutput?.contains("two") == true)
        guard case .working = flow.session.state else { return XCTFail("expected the working panel") }
        let panel = try XCTUnwrap(flow.flowPanel)
        panel.contentView?.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds: 50_000_000)
        panel.contentView?.layoutSubtreeIfNeeded()
        var shown: [String] = []
        func walk(_ view: NSView) {
            if let textView = view as? NSTextView, !textView.isEditable { shown.append(textView.string) }
            view.subviews.forEach(walk)
        }
        if let content = panel.contentView { walk(content) }
        XCTAssertTrue(shown.contains { $0.contains("start\none") }, "\(shown)")

        // Then the result replaces it; the clipboard gets the whole output.
        while case .working = flow.session.state, Date() < end.addingTimeInterval(5) {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        guard case .result(let content) = flow.session.state else { return XCTFail("expected the result panel") }
        XCTAssertEqual(content.text, "start\none\ntwo")
        XCTAssertNil(flow.session.progress)
        XCTAssertEqual(pasteboard.string(forType: .string), "start\none\ntwo")
        flow.handle(.escape)
        let outcome = await run.value
        XCTAssertEqual(outcome, .ran(succeeded: true))
    }
}
