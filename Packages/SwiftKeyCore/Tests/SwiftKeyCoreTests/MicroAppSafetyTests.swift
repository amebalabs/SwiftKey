import Foundation
import Testing
@testable import SwiftKeyCore

/// Files in the micro-apps folder are loaded at launch, so no file may crash SwiftKey, and the
/// approval panel must show everything that will run.
@Suite struct MicroAppSafetyTests {
    @Test func deepNestingIsAnErrorNotACrash() {
        let line = String(repeating: "- ", count: 100_000) + "x"
        #expect(throws: YAMLError.self) { try YAMLSubset.parse("steps:\n  " + line + "\n") }
    }

    @Test func nestingDeeperThanTheLimitNamesTheLine() throws {
        let line = String(repeating: "- ", count: YAMLSubset.maxDepth + 1) + "x"
        do {
            _ = try YAMLSubset.parse("a: 1\nsteps:\n  " + line + "\n")
            Issue.record("expected a nesting error")
        } catch let error as YAMLError {
            #expect(error.line == 3)
            #expect(error.message.contains("nesting"))
        }
    }

    @Test func nestingAtTheLimitParses() throws {
        let line = String(repeating: "- ", count: YAMLSubset.maxDepth - 4) + "x"
        _ = try YAMLSubset.parse("steps:\n  " + line + "\n")
    }

    @Test func approvalOfACommandWithLibrariesShowsTheCommand() {
        var app = MicroApp(id: "say", description: "Say.", input: .none, command: "rm -rf ~/important",
                           output: .init(targets: []))
        app.libraries = [MicroAppLibrarySource(name: "up", file: "libs/up.yaml", text: "steps:\n  - command: tr a-z A-Z\n")]
        #expect(app.approvalText.contains("rm -rf ~/important"))
        #expect(app.approvalText.contains("tr a-z A-Z"))
    }

    @Test func approvalOfACommandWithoutLibrariesIsTheCommand() {
        let app = MicroApp(id: "say", description: "Say.", input: .none, command: "echo hi", output: .init(targets: []))
        #expect(app.approvalText == "echo hi")
    }
}
