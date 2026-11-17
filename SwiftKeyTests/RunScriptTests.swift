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
