import Foundation
import XCTest

/// Runs the built `swiftkey-micro` executable with `check`: it prints, exits and starts nothing.
final class CheckCommandTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// The executable next to the test bundle in the build products folder.
    private var executable: URL { BuiltTool.swiftkeyMicro }

    private struct Run { var status: Int32; var output: String; var errors: String }

    /// Starts the executable and drains both pipes on their own threads, so a process that keeps
    /// its pipes open cannot block the test; the deadline runs from the start and stops such a process.
    private func run(_ arguments: [String], environment: [String: String]) throws -> Run {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = Self.root
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        try process.run()

        let drained = DispatchGroup()
        let output = Drain(), errors = Drain()
        for (pipe, drain) in [(out, output), (err, errors)] {
            drained.enter()
            DispatchQueue.global().async {
                drain.data = pipe.fileHandleForReading.readDataToEndOfFile()
                drained.leave()
            }
        }

        // The app would keep running; the check returns at once.
        if exited.wait(timeout: .now() + 20) == .timedOut {
            XCTFail("swiftkey-micro check did not exit")
            process.terminate()
            if exited.wait(timeout: .now() + 5) == .timedOut { kill(process.processIdentifier, SIGKILL) }
        }
        process.waitUntilExit()
        // A child that inherited the pipes could keep them open; do not wait on it forever.
        if drained.wait(timeout: .now() + 5) == .timedOut {
            XCTFail("the output pipes of swiftkey-micro check stayed open")
            try? out.fileHandleForReading.close()
            try? err.fileHandleForReading.close()
        }
        return Run(status: process.terminationStatus, output: String(decoding: output.data, as: UTF8.self),
                   errors: String(decoding: errors.data, as: UTF8.self))
    }

    /// The bytes one pipe gave, written by its reading thread.
    private final class Drain: @unchecked Sendable {
        private let lock = NSLock()
        private var bytes = Data()
        var data: Data {
            get { lock.withLock { bytes } }
            set { lock.withLock { bytes = newValue } }
        }
    }

    func testCheckRunsWithoutStartingTheApp() throws {
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: executable.path), executable.path)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("swiftkey-check-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let bad = directory.appendingPathComponent("bad.yaml")
        try "format: nope\n".write(to: bad, atomically: true, encoding: .utf8)
        let before = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        let environment = ProcessInfo.processInfo.environment

        let names = ["change-case", "count-text", "dns-lookup", "encode-decode", "format-json"]
        let good = try run(["check"] + names.map { "docs/micro-apps/examples/\($0).yaml" }, environment: environment)
        XCTAssertEqual(good.status, 0, good.errors)
        XCTAssertEqual(good.output, names.map { "docs/micro-apps/examples/\($0).yaml: ok\n" }.joined())
        XCTAssertEqual(good.errors, "")

        let problems = try run(["check", bad.path], environment: environment)
        XCTAssertEqual(problems.status, 1)
        XCTAssertTrue(problems.output.hasPrefix(bad.path + ":1: "), problems.output)
        XCTAssertEqual(problems.errors, "")

        let wrong = try run(["check", "Package.swift"], environment: environment)
        XCTAssertEqual(wrong.status, 2)
        XCTAssertEqual(wrong.output, "")
        XCTAssertTrue(wrong.errors.contains("Package.swift: the name does not end in .yaml"), wrong.errors)

        // The check made no files: no log, micro-apps folder, approvals or values.
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), before)
    }
}
