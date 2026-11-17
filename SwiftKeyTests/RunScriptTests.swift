import XCTest
@testable import SwiftKey

/// Shell commands run through the real path and always finish: the result arrives by the
/// termination handler, and output is read while the command runs.
final class RunScriptTests: XCTestCase {
    /// Runs `body` and fails instead of hanging when it takes longer than `seconds`.
    private func bounded(_ seconds: TimeInterval = 15, _ body: @escaping @Sendable () async -> Void) {
        let done = expectation(description: "finished")
        Task {
            await body()
            done.fulfill()
        }
        wait(for: [done], timeout: seconds)
    }

    func testCommandOutputArrives() {
        bounded {
            let result = try? await runScript(to: "'echo hello'")
            XCTAssertEqual(result?.out.trimmingCharacters(in: .whitespacesAndNewlines), "hello")
        }
    }

    func testOutputLargerThanAPipeBufferDoesNotBlock() {
        bounded {
            let result = try? await runScript(to: "'head -c 200000 /dev/zero | tr \\\\0 a'")
            XCTAssertEqual(result?.out.count, 200_000)
        }
    }

    func testAFailingCommandThrowsWithItsStatus() {
        bounded {
            do {
                _ = try await runScript(to: "'exit 3'")
                XCTFail("expected a failure")
            } catch let error as ShellOutError {
                XCTAssertEqual(error.terminationStatus, 3)
            } catch {
                XCTFail("unexpected error \(error)")
            }
        }
    }

    /// The command runs as written: spaces in an unquoted command separate its words.
    func testAnUnquotedCommandWithSpacesRuns() {
        bounded {
            let result = try? await runScript(to: "echo hello world")
            XCTAssertEqual(result?.out.trimmingCharacters(in: .whitespacesAndNewlines), "hello world")
        }
    }

    /// The README's form: the whole command in one pair of single quotes.
    func testAFullyQuotedCommandRuns() {
        bounded {
            let result = try? await runScript(to: "'cd /tmp && pwd -P'")
            XCTAssertEqual(result?.out.trimmingCharacters(in: .whitespacesAndNewlines), "/private/tmp")
            let quoted = try? await runScript(to: "'printf \"%s\" \"x y\"'")
            XCTAssertEqual(quoted?.out, "x y")
        }
    }

    func testQuotesInsideACommandKeepTheirMeaning() {
        bounded {
            let result = try? await runScript(to: "printf '%s|' 'a b' \"c d\" e")
            XCTAssertEqual(result?.out, "a b|c d|e|")
        }
    }

    func testArgumentsArePassedAsWholeWords() {
        bounded {
            let result = try? await runScript(to: "printf '%s|'", args: ["a b", "c;echo no", "$HOME"])
            XCTAssertEqual(result?.out, "a b|c;echo no|$HOME|")
        }
    }

    func testCommandLineKeepsTheTextOfTheCommand() {
        XCTAssertEqual(ShellCommandLine.arguments(for: "open -a Safari", args: []), ["-l", "-c", "open -a Safari"])
        XCTAssertEqual(ShellCommandLine.arguments(for: "'cd ~/x && git status'", args: []), ["-l", "-c", "cd ~/x && git status"])
        XCTAssertEqual(ShellCommandLine.command(from: "'a' 'b'"), "'a' 'b'", "an inner quote keeps the outer pair")
        XCTAssertEqual(ShellCommandLine.command(from: "'"), "'")
        XCTAssertEqual(ShellCommandLine.arguments(for: "say", args: ["hi"]), ["-l", "-c", "say \"$@\"", "zsh", "hi"])
    }

    func testShellMenuActionRunsToTheEnd() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("swiftkey-run-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let marker = folder.appendingPathComponent("ran")
        let item = MenuItem(key: "r", title: "Run", action: "shell://'touch \(marker.path)'")
        let action = try XCTUnwrap(item.actionClosure)
        action()
        let made = expectation(for: NSPredicate { _, _ in FileManager.default.fileExists(atPath: marker.path) },
                               evaluatedWith: nil)
        wait(for: [made], timeout: 15)
    }
}
