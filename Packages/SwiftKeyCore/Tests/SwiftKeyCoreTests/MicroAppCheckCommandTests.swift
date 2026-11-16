import Foundation
import Testing
@testable import SwiftKeyCore

private let goodApp = """
format: ting.microapp/2
description: Say hi.
input: none
command: echo hi
output:
  to: [panel]
"""

private struct NoFile: LocalizedError {
    var errorDescription: String? { "no such file" }
}

/// A reader over fixed files; any other path cannot be read.
private func reader(_ files: [String: String]) -> (String) throws -> Data {
    { path in
        guard let text = files[path] else { throw NoFile() }
        return Data(text.utf8)
    }
}

@Suite struct MicroAppCheckCommandTests {
    @Test func handlesOnlyTheCheckOption() {
        #expect(MicroAppCheckCommand.handles(["check", "a.yaml"]))
        #expect(MicroAppCheckCommand.handles(["check"]))
        #expect(!MicroAppCheckCommand.handles(["--check", "a.yaml"]))
        #expect(!MicroAppCheckCommand.handles([]))
        #expect(!MicroAppCheckCommand.handles(["-NSDocumentRevisionsDebugMode", "YES"]))
    }

    @Test func goodFilesAreOKInPathOrder() {
        let outcome = MicroAppCheckCommand.run(["check", "dir/zeta.yaml", "dir/alpha.yaml"],
                                               read: reader(["dir/zeta.yaml": goodApp, "dir/alpha.yaml": goodApp]))
        #expect(outcome == .init(output: ["dir/alpha.yaml: ok", "dir/zeta.yaml: ok"], errors: [], exitCode: 0))
    }

    @Test func problemsUseTheErrorLogMessagesSortedByFileAndLine() {
        let bad = "format: nope\n"
        let files = ["b/bad.yaml": bad, "a/good.yaml": goodApp]
        let outcome = MicroAppCheckCommand.run(["check", "b/bad.yaml", "a/good.yaml"], read: reader(files))
        #expect(outcome.exitCode == 1)
        #expect(outcome.errors == [])
        // The same messages as the micro-app error log gives for the file in the folder.
        let log = MicroAppCatalog.load([("bad.yaml", bad)]).logText
        let expected = log.split(separator: "\n").map { "b/" + $0 }
        #expect(outcome.output == ["a/good.yaml: ok"] + expected)
        #expect(expected.count > 1)
        let lines = outcome.output.dropFirst().compactMap { Int($0.split(separator: ":")[1]) }
        #expect(lines == lines.sorted())
    }

    @Test func notUTF8IsAProblemOfTheFile() {
        let outcome = MicroAppCheckCommand.run(["check", "x.yaml"]) { _ in Data([0xFF, 0xFE, 0x00]) }
        #expect(outcome == .init(output: ["x.yaml:1: the file is not UTF-8 text"], errors: [], exitCode: 1))
    }

    @Test func tooLargeIsAProblemOfTheFile() {
        let outcome = MicroAppCheckCommand.run(["check", "x.yaml"]) { _ in Data(count: MicroAppChecker.maxFileSize + 1) }
        #expect(outcome.output == ["x.yaml:1: \(MicroAppChecker.tooLargeMessage)"])
        #expect(outcome.exitCode == 1)
    }

    @Test func duplicateIDIsReportedForTheSecondFile() {
        let withID = "id: hello\n" + goodApp
        let outcome = MicroAppCheckCommand.run(["check", "two.yaml", "one.yaml"],
                                               read: reader(["one.yaml": withID, "two.yaml": withID]))
        #expect(outcome.exitCode == 1)
        #expect(outcome.output == [
            "one.yaml: ok",
            "two.yaml:1: duplicate id `hello`: `one.yaml` already uses it; rename one of the files",
        ])
    }

    @Test func duplicateIDWithDirectoriesHasTheErrorLogMessage() {
        let withID = "id: hello\n" + goodApp
        let outcome = MicroAppCheckCommand.run(["check", "dir/b.yaml", "dir/a.yaml"],
                                               read: reader(["dir/a.yaml": withID, "dir/b.yaml": withID]))
        // The micro-apps folder with the same two files gives this log.
        let log = MicroAppCatalog.load([("a.yaml", withID), ("b.yaml", withID)]).logText
        #expect(log == "b.yaml:1: duplicate id `hello`: `a.yaml` already uses it; rename one of the files\n")
        #expect(outcome.exitCode == 1)
        #expect(outcome.output == ["dir/a.yaml: ok"] + log.split(separator: "\n").map { "dir/" + $0 })
    }

    @Test func noFileIsAWrongCall() {
        let outcome = MicroAppCheckCommand.run(["check"], read: reader([:]))
        #expect(outcome.exitCode == 2)
        #expect(outcome.output == [])
        #expect(outcome.errors.first == "swiftkey-micro check: no file given")
    }

    @Test func nameNotEndingInYAMLIsAWrongCall() {
        var read: [String] = []
        let outcome = MicroAppCheckCommand.run(["check", "good.yaml", "Package.swift"]) { path in
            read.append(path)
            return Data(goodApp.utf8)
        }
        #expect(outcome.exitCode == 2)
        #expect(outcome.output == [])
        #expect(outcome.errors.first == "Package.swift: the name does not end in .yaml")
        #expect(read == ["good.yaml"])
    }

    @Test func unreadableFileIsAWrongCall() {
        let outcome = MicroAppCheckCommand.run(["check", "good.yaml", "gone.yaml"], read: reader(["good.yaml": goodApp]))
        #expect(outcome.exitCode == 2)
        #expect(outcome.output == [])
        #expect(outcome.errors.first == "gone.yaml: cannot read the file: no such file")
    }
}
