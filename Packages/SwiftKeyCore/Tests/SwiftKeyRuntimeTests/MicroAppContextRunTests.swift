import Foundation
import XCTest
import SwiftKeyCore
@testable import SwiftKeyRuntime

/// The context of a start reaches templates, code and libraries through the real runner; the
/// values go in as the app's reader or `swiftkey-micro --context` hand them over. Without a
/// keyboard the runner refuses to send keys or text.
final class MicroAppContextRunTests: XCTestCase {
    private let header = "format: ting.microapp/2\ndescription: Test.\n"

    private func runner() -> MicroAppRunner {
        var runner = MicroAppRunner()
        runner.path = { "/usr/bin:/bin:/usr/sbin:/sbin" }
        runner.workingDirectory = NSTemporaryDirectory()
        runner.timeLimit = 20
        return runner
    }

    private func context(_ values: [(MicroAppContextSource, String, String)]) -> MicroAppContext {
        var context = MicroAppContext()
        for (source, name, value) in values { context.set(source, name, value) }
        return context
    }

    func testContextReachesTemplatesAndCode() async throws {
        let app = try MicroAppChecker.check(header + """
            context: [app, selection]
            input: none
            steps:
              - text: ${context.app.name}|${context.selection.text}
              - command: printf '%s>%s' "$(cat)" "$TING_CONTEXT_APP_BUNDLE"

            """, fileName: "c.yaml").get()
        let result = await runner().run(app, context: context([(.app, "name", "Editor"), (.app, "bundle", "com.example.Editor"),
                                                               (.selection, "text", "picked")]))
        XCTAssertEqual(result, .success(MicroAppRunOutput(stdout: "Editor|picked>com.example.Editor")))
    }

    func testAMicroAppWithoutContextGetsNoContextVariables() async throws {
        let app = try MicroAppChecker.check(header + "input: none\ncommand: env | grep '^TING_CONTEXT_' || echo none\n",
                                            fileName: "n.yaml").get()
        let result = await runner().run(app, context: context([(.app, "name", "Editor")]))
        XCTAssertEqual(result, .success(MicroAppRunOutput(stdout: "none")))
    }

    func testLibrariesReadTheContextOfTheStart() async throws {
        let library = MicroAppLibrarySource(name: "who", file: "libs/who.yaml", text: """
            format: ting.microlib/1
            description: Who.
            context: [app]
            steps:
              - text: from ${context.app.name}

            """)
        let app = try MicroAppChecker.check(header + "input: none\nsteps:\n  - call: who\n", fileName: "l.yaml",
                                            libraries: MicroAppLibraries([library])).get()
        XCTAssertEqual(app.requiredContext, [.app])
        let result = await runner().run(app, context: context([(.app, "name", "Editor")]))
        XCTAssertEqual(result, .success(MicroAppRunOutput(stdout: "from Editor")))
    }

    func testRunnerWithoutAKeyboardRefusesToSend() async throws {
        let app = try MicroAppChecker.check(header + "input: none\nsteps:\n  - paste: x\n", fileName: "p.yaml").get()
        guard case .stepFailed(let failure) = await runner().run(app) else { return XCTFail("expected a failed step") }
        XCTAssertEqual(failure.note, "not sent")
        XCTAssertTrue(failure.output.stderr.contains("only SwiftKey sends"), failure.output.stderr)
    }
}
