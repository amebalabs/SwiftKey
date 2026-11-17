import Foundation
import XCTest
import SwiftKeyCore
@testable import SwiftKeyRuntime

/// The example micro-apps of `docs/micro-apps/examples/`, run by the real `swiftkey-micro`
/// console tool, the way a person or a coding agent tries a file. Context values go in with
/// `--context`, as the tool takes them; `keys` and `paste` steps send nothing and say so. The
/// examples that reach the network, cost money or open a browser are checked, not run.
final class MicroAppExamplesTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private static let examples = root.appendingPathComponent("docs/micro-apps/examples", isDirectory: true)

    private struct Run {
        var status: ChildProcessOutcome.End
        var stdout: String
        var stderr: String
    }

    private func run(_ name: String, _ arguments: [String] = [], input: String = "") async throws -> Run {
        let executable = BuiltTool.swiftkeyMicro.path
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: executable), executable)
        let file = Self.examples.appendingPathComponent(name + ".yaml").path
        let outcome = await ChildProcess.run(.init(executable: executable, arguments: ["run", file] + arguments,
                                                   environment: ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": NSHomeDirectory()],
                                                   workingDirectory: NSTemporaryDirectory(), stdin: Data(input.utf8), timeLimit: 30))
        return Run(status: outcome.end, stdout: String(decoding: outcome.stdout, as: UTF8.self),
                   stderr: String(decoding: outcome.stderr, as: UTF8.self))
    }

    func testEveryExampleAndLibraryPassesTheCheck() async throws {
        let names = try FileManager.default.contentsOfDirectory(atPath: Self.examples.path)
            .filter { $0.hasSuffix(".yaml") }.sorted()
        XCTAssertEqual(names.count, 15)
        let executable = BuiltTool.swiftkeyMicro.path
        let files = names.map { Self.examples.appendingPathComponent($0).path }
            + [Self.examples.appendingPathComponent("libs/translate.yaml").path]
        let outcome = await ChildProcess.run(.init(executable: executable, arguments: ["check"] + files,
                                                   environment: ["PATH": "/usr/bin:/bin"], workingDirectory: "/tmp", timeLimit: 30))
        XCTAssertEqual(outcome.end, .exited(0), String(decoding: outcome.stdout, as: UTF8.self))
        XCTAssertEqual(String(decoding: outcome.stdout, as: UTF8.self), files.map { "\($0): ok\n" }.joined())
    }

    func testAppInfoShowsTheContextItIsGiven() async throws {
        let result = try await run("app-info", ["--context", "app.name=TextEdit", "--context", "app.bundle=com.apple.TextEdit",
                                                "--context", "app.path=/System/Applications/TextEdit.app",
                                                "--context", "window.title=Notes", "--context", "window.document=/tmp/notes.txt"])
        XCTAssertEqual(result.status, .exited(0), result.stderr)
        for row in ["| App | TextEdit |", "| Bundle id | com.apple.TextEdit |", "| Path | /System/Applications/TextEdit.app |",
                    "| Window | Notes |", "| Document | /tmp/notes.txt |"] {
            XCTAssertTrue(result.stdout.contains(row), "\(row) in \(result.stdout)")
        }
    }

    func testChangeCase() async throws {
        let upper = try await run("change-case", input: "hello, мир")
        XCTAssertEqual(upper.stdout, "HELLO, МИР\n", upper.stderr)
        let title = try await run("change-case", ["--param", "mode=title"], input: "hello big world")
        XCTAssertEqual(title.stdout, "Hello Big World\n", title.stderr)
        let lower = try await run("change-case", ["--param", "mode=lower"], input: "ПРИВЕТ")
        XCTAssertEqual(lower.stdout, "привет\n", lower.stderr)
    }

    func testCopyPageLinkWithAndWithoutATab() async throws {
        let link = try await run("copy-page-link", ["--context", "browser.url=https://example.com/a",
                                                    "--context", "browser.title=Example page"])
        XCTAssertEqual(link.status, .exited(0), link.stderr)
        XCTAssertEqual(link.stdout, "[Example page](https://example.com/a)\n")
        let none = try await run("copy-page-link")
        XCTAssertEqual(none.status, .exited(1))
        XCTAssertTrue(none.stderr.contains("No browser tab is open."), none.stderr)
    }

    func testCountWordsShowsATable() async throws {
        let result = try await run("count-text", input: "one two\nтри\n")
        XCTAssertEqual(result.status, .exited(0), result.stderr)
        XCTAssertTrue(result.stdout.contains("| Words | 3 |"), result.stdout)
        XCTAssertTrue(result.stdout.contains("| Characters | 12 |"), result.stdout)
        XCTAssertTrue(result.stdout.contains("| Lines | 2 |"), result.stdout)
    }

    func testEncodeDecodeAllFourModes() async throws {
        let cases: [(String, String, String)] = [
            ("base64-encode", "hi there", "aGkgdGhlcmU="), ("base64-decode", "aGkgdGhlcmU=\n", "hi there"),
            ("url-encode", "a b&c", "a%20b%26c"), ("url-decode", "a%20b+c", "a b c"),
        ]
        for (mode, input, expected) in cases {
            let result = try await run("encode-decode", ["--param", "mode=\(mode)"], input: input)
            XCTAssertEqual(result.stdout, expected + "\n", "\(mode): \(result.stderr)")
        }
    }

    func testFinderChecksumOfTheGivenSelection() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("swiftkey-sums-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("a file.txt")
        try "abc".write(to: file, atomically: true, encoding: .utf8)
        let result = try await run("finder-checksum", ["--context", "finder.selection=\(file.path)\n\(directory.path)"])
        XCTAssertEqual(result.status, .exited(0), result.stderr)
        XCTAssertEqual(result.stdout,
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad  \(file.path)\nnot a file: \(directory.path)\n")
        let nothing = try await run("finder-checksum")
        XCTAssertEqual(nothing.stdout, "Nothing is selected in Finder.\n")
    }

    func testFormatJSON() async throws {
        let result = try await run("format-json", input: #"{"b": 1, "a": ["x", "щ"]}"#)
        XCTAssertEqual(result.stdout, "{\n  \"a\": [\n    \"x\",\n    \"щ\"\n  ],\n  \"b\": 1\n}\n", result.stderr)
        let bad = try await run("format-json", input: "{")
        XCTAssertEqual(bad.status, .exited(1))
    }

    func testNewTabSearchSendsNothingFromTheConsole() async throws {
        let result = try await run("new-tab-search", input: "  swift testing  ")
        XCTAssertEqual(result.status, .exited(0), result.stderr)
        let notes = result.stderr.components(separatedBy: "\n").filter { $0.contains("not sent; only SwiftKey sends to an app") }
        XCTAssertEqual(notes.count, 3, result.stderr)
    }

    func testSortSelectionSortsTheGivenText() async throws {
        let result = try await run("sort-selection", ["--context", "selection.text=pear\napple\nfig"])
        XCTAssertEqual(result.status, .exited(0), result.stderr)
        XCTAssertEqual(result.stdout, "apple\nfig\npear\n")
    }
}
