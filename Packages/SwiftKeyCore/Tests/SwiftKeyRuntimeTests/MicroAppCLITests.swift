import Foundation
import XCTest
import SwiftKeyCore
@testable import SwiftKeyRuntime

final class MicroAppCLITests: XCTestCase {
    func testOptions() throws {
        let parsed = try MicroAppCLI.parse(["test.yaml", "--param", "a=x=y", "--param", "b=", "--input", "Hi", "--timeout", "12", "--verbose"])
        XCTAssertEqual(parsed.params, ["a": "x=y", "b": ""])
        XCTAssertEqual(parsed.input, "Hi")
        XCTAssertEqual(parsed.timeout, 12)
        XCTAssertTrue(parsed.verbose)
        for args in [[String](), ["x.yaml", "--param", "a"], ["x.yaml", "--timeout", "301"],
                     ["x.yaml", "--input"], ["x.yaml", "--wrong"], ["x.yaml", "--param", "a=1", "--param", "a=2"]] {
            XCTAssertThrowsError(try MicroAppCLI.parse(args), "\(args)")
        }
    }

    private func file(_ code: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("swiftkey-cli-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("test.yaml")
        try code.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private let header = "format: ting.microapp/2\ndescription: Test CLI.\ninput: clipboard\n"

    func testValidation() throws {
        let url = try file(header + "params:\n  - name: mode\n    type: choice\n    required: true\n    choices: [a, b]\nsteps:\n  - text: ${params.mode}\n  - open: https://example.com\n")
        let app = try MicroAppCLI.load(url.path)
        XCTAssertThrowsError(try MicroAppCLI.validate(.init(file: url.path), app: app))
        XCTAssertThrowsError(try MicroAppCLI.validate(.init(file: url.path, params: ["mode": "c"], allowEffects: true), app: app))
        XCTAssertThrowsError(try MicroAppCLI.validate(.init(file: url.path, params: ["mode": "a"]), app: app))
        XCTAssertThrowsError(try MicroAppCLI.validate(.init(file: url.path, params: ["mode": "a", "other": "x"], allowEffects: true), app: app))
        XCTAssertNoThrow(try MicroAppCLI.validate(.init(file: url.path, params: ["mode": "a"], allowEffects: true), app: app))
    }

    private func run(_ arguments: [String], input: String = "") async throws -> ChildProcessOutcome {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let executable = root.appendingPathComponent(".build/debug/swiftkey-micro").path
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: executable))
        return await ChildProcess.run(.init(executable: executable, arguments: arguments,
                                            environment: ["PATH": "/usr/bin:/bin", "CLI_TEST_VALUE": "secret"],
                                            workingDirectory: "/tmp", stdin: Data(input.utf8), timeLimit: 10))
    }

    func testRunCheckAndNoUserState() async throws {
        // output.to must not copy anything: stdout is the console interface.
        let url = try file(header + "steps:\n  - command: tr a-z A-Z\n  - text: ${input}/${CLI_TEST_VALUE}\noutput:\n  to: [clipboard]\n")
        let check = try await run(["check", url.path])
        XCTAssertEqual(check.end, .exited(0))
        XCTAssertEqual(String(decoding: check.stdout, as: UTF8.self), url.path + ": ok\n")
        let result = try await run(["run", url.path, "--verbose"], input: "hello\n")
        XCTAssertEqual(result.end, .exited(0))
        XCTAssertEqual(String(decoding: result.stdout, as: UTF8.self), "HELLO/secret\n")
        XCTAssertTrue(String(decoding: result.stderr, as: UTF8.self).contains("Step 2 of 2"))
        let files = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
        XCTAssertEqual(files, ["test.yaml"])
    }

    func testSIGINTCancelsTheChildProcess() async throws {
        let url = try file(header + "command: sleep 20\n")
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let process = Process()
        process.executableURL = root.appendingPathComponent(".build/debug/swiftkey-micro")
        process.arguments = ["run", url.path, "--verbose"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        let errors = Pipe()
        process.standardError = errors
        try process.run()
        // Verbose progress arrives before the command ends (stderr of the command is buffered).
        let ready = errors.fileHandleForReading.availableData
        XCTAssertTrue(String(decoding: ready, as: UTF8.self).contains("Step 1 of 1"))
        try await Task.sleep(nanoseconds: 100_000_000)
        process.interrupt()
        let deadline = Date().addingTimeInterval(5)
        while process.isRunning && Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
        if process.isRunning { process.terminate(); XCTFail("SIGINT did not stop the run"); return }
        XCTAssertEqual(process.terminationStatus, 130)
    }

    func testFailedOutputNeverGoesToStdout() async throws {
        let url = try file(header + "steps:\n  - command: echo partial; echo bad >&2; exit 9\n")
        let result = try await run(["run", url.path])
        XCTAssertEqual(result.end, .exited(1))
        XCTAssertTrue(result.stdout.isEmpty)
        XCTAssertTrue(String(decoding: result.stderr, as: UTF8.self).contains("exit 9"))
    }

    func testInputParametersTimeoutAndEffects() async throws {
        let url = try file(header + "params:\n  - name: suffix\n    type: text\n    required: true\nsteps:\n  - text: ${input}${params.suffix}\n")
        let good = try await run(["run", url.path, "--param", "suffix=!", "--input", "hi"])
        XCTAssertEqual(good.end, .exited(0))
        XCTAssertEqual(String(decoding: good.stdout, as: UTF8.self), "hi!\n")
        let missing = try await run(["run", url.path])
        XCTAssertEqual(missing.end, .exited(2))
        let effects = try file(header + "steps:\n  - open: https://example.com\n")
        let refused = try await run(["run", effects.path])
        XCTAssertEqual(refused.end, .exited(2))
        XCTAssertTrue(String(decoding: refused.stderr, as: UTF8.self).contains("no steps were run"))
        let slow = try file(header + "command: sleep 15\n")
        let timeout = try await run(["run", slow.path, "--timeout", "1"])
        XCTAssertEqual(timeout.end, .exited(124))
    }
}

extension MicroAppCLITests {
    func testLibrariesNextToTheFileOrFromLibs() async throws {
        let url = try file("format: ting.microapp/2\ninherit: up\ninput: clipboard\n")
        let libs = url.deletingLastPathComponent().appendingPathComponent("libs")
        try FileManager.default.createDirectory(at: libs, withIntermediateDirectories: true)
        try "format: ting.microlib/1\ndescription: Up.\nsteps:\n  - command: tr a-z A-Z\n".write(to: libs.appendingPathComponent("up.yaml"), atomically: true, encoding: .utf8)
        let check = try await run(["check", url.path, libs.appendingPathComponent("up.yaml").path])
        XCTAssertEqual(check.end, .exited(0), String(decoding: check.stdout, as: UTF8.self))
        let result = try await run(["run", url.path, "--input", "abc"])
        XCTAssertEqual(String(decoding: result.stdout, as: UTF8.self), "ABC\n")
        let other = try await run(["run", url.path, "--input", "abc", "--libs", "/nonexistent"])
        XCTAssertEqual(other.end, .exited(1))
        XCTAssertTrue(String(decoding: other.stderr, as: UTF8.self).contains("no library `up`"))
    }
}

extension MicroAppCLITests {
    func testCheckWithLibs() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("swiftkey-libs-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("micro"), withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let libs = directory.appendingPathComponent("micro/libs")
        try FileManager.default.createDirectory(at: libs, withIntermediateDirectories: true)
        try "format: ting.microlib/1\ndescription: Up.\nsteps:\n  - command: tr a-z A-Z\n".write(to: libs.appendingPathComponent("up.yaml"), atomically: true, encoding: .utf8)
        let app = try file("format: ting.microapp/2\ninherit: up\ninput: none\n")
        let withLibs = try await run(["check", "--libs", libs.path, app.path])
        XCTAssertEqual(withLibs.end, .exited(0))
    }
}

extension MicroAppCLITests {
    func testContextValuesAndKeysThatAreNeverSent() async throws {
        let parsed = try MicroAppCLI.parse(["x.yaml", "--context", "app.name=Safari", "--context", "finder.selection=/a\n/b=c"])
        XCTAssertEqual(parsed.context[MicroAppContextField(source: .app, name: "name")!], "Safari")
        XCTAssertEqual(parsed.context[MicroAppContextField(source: .finder, name: "selection")!], "/a\n/b=c")
        for args in [["x.yaml", "--context", "app=Safari"], ["x.yaml", "--context", "app.title=x"], ["x.yaml", "--context", "=x"],
                     ["x.yaml", "--context", "app.name=a", "--context", "app.name=b"]] {
            XCTAssertThrowsError(try MicroAppCLI.parse(args), "\(args)")
        }

        let url = try file("format: ting.microapp/2\ndescription: Test CLI.\ncontext: [app]\ninput: clipboard\nsteps:\n" +
                           "  - keys: [cmd+a]\n  - paste: ${context.app.name}\n  - command: printf '%s/%s' \"$TING_CONTEXT_APP_NAME\" \"$TING_CONTEXT_APP_PID\"\n" +
                           "output:\n  to: [app]\n")
        let app = try MicroAppCLI.load(url.path)
        XCTAssertThrowsError(try MicroAppCLI.validate(.init(file: url.path, context: MicroAppContext([MicroAppContextField(source: .finder, name: "folder")!: "/"])), app: app))
        let result = try await run(["run", url.path, "--context", "app.name=Notes"])
        XCTAssertEqual(result.end, .exited(0))
        XCTAssertEqual(String(decoding: result.stdout, as: UTF8.self), "Notes/\n")
        XCTAssertEqual(String(decoding: result.stderr, as: UTF8.self),
                       "swiftkey-micro: keys cmd+a: not sent; only SwiftKey sends to an app\nswiftkey-micro: paste 5 characters: not sent; only SwiftKey sends to an app\n")
    }
}
