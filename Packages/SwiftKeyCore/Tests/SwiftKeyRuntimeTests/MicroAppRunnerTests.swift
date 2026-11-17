@testable import SwiftKeyRuntime
import Darwin
import XCTest
import SwiftKeyCore

final class MicroAppRunnerTests: XCTestCase {
    private func temporary() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("swiftkey-runner-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    /// Writes an executable script and returns its path.
    private func script(_ text: String, in directory: URL, name: String = "fake-shell") throws -> String {
        let url = directory.appendingPathComponent(name)
        try ("#!/bin/sh\n" + text + "\n").write(to: url, atomically: false, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url.path
    }

    private func app(_ command: String, params: [String] = [], tools: [String] = []) -> MicroApp {
        MicroApp(id: "test", description: "Test", tools: tools,
                 params: params.map { MicroApp.Param(name: $0, kind: .text, required: true) },
                 input: .clipboard, command: command, output: MicroApp.Output(targets: [.panel]))
    }

    private func runner(timeLimit: TimeInterval = 10, path: String = "/usr/bin:/bin:/usr/sbin:/sbin") throws -> MicroAppRunner {
        var runner = MicroAppRunner()
        runner.path = { path }
        runner.workingDirectory = try temporary().path
        runner.timeLimit = timeLimit
        return runner
    }

    private func isGone(_ pid: pid_t, within seconds: TimeInterval = 3) -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if kill(pid, 0) == -1 && errno == ESRCH { return true }
            usleep(20_000)
        }
        return false
    }

    // MARK: Runs

    func testStdinReachesTheCommand() async throws {
        let result = try await runner().run(app("tr a-z A-Z"), stdin: "hello\nworld\n")
        XCTAssertEqual(result, .success(MicroAppRunOutput(stdout: "HELLO\nWORLD")))
    }

    func testNoStdinGivesEmptyInput() async throws {
        let result = try await runner().run(app("wc -c | tr -d ' '"))
        XCTAssertEqual(result, .success(MicroAppRunOutput(stdout: "0")))
    }

    func testParamVariablesAndPATHAreSet() async throws {
        var r = try runner(path: "/usr/bin:/bin:/custom/bin")
        r.environment = ["HOME": NSHomeDirectory(), "TING_STRAY": "no", "PATH": "/ignored"]
        let command = #"printf '%s|%s|%s|%s' "$TING_DOMAIN" "$TING_RECORD" "${TING_STRAY-unset}" "$PATH""#
        let result = await r.run(app(command, params: ["domain", "record"]),
                                 values: ["domain": "example.com", "record": "a b; $(echo no)"])
        XCTAssertEqual(result, .success(MicroAppRunOutput(stdout: "example.com|a b; $(echo no)|unset|/usr/bin:/bin:/custom/bin")))
    }

    func testRunsInTheWorkingDirectory() async throws {
        let r = try runner()
        let result = await r.run(app("pwd -P"))
        let expected = try XCTUnwrap(realpath(r.workingDirectory, nil).map { p in defer { free(p) }; return String(cString: p) })
        XCTAssertEqual(result, .success(MicroAppRunOutput(stdout: expected)))
        XCTAssertEqual(MicroAppRunner().workingDirectory, NSHomeDirectory())
    }

    func testExitZeroGivesStdoutOnly() async throws {
        let result = try await runner().run(app("echo out; echo err >&2"))
        XCTAssertEqual(result, .success(MicroAppRunOutput(stdout: "out", stderr: "err\n")))
        guard case .success(let output) = result else { return XCTFail() }
        XCTAssertEqual(output.stdout, "out")
    }

    func testNonZeroExitGivesCodeStderrAndStdout() async throws {
        let result = try await runner().run(app("echo partial; echo broke >&2; exit 3"))
        XCTAssertEqual(result, .failure(exitCode: 3, MicroAppRunOutput(stdout: "partial\n", stderr: "broke\n")))
    }

    func testCommandTextIsPassedUnchanged() async throws {
        let dir = try temporary()
        var r = try runner()
        r.shell = try script(#"[ "$1" = "-c" ] || exit 9; printf '%s' "$2""#, in: dir)
        let command = "printf '%s' \"$TING_X\" {x} \\\n  `date` $(id) # \"quoted\" 'single' ${TING_X}\n\ttab\\n end\n"
        let result = await r.run(app(command))
        XCTAssertEqual(result, .success(MicroAppRunOutput(stdout: MicroAppRunRules.removingEndNewlines(command))))
    }

    // MARK: Limits

    func testTimeoutKeepsEarlierOutputAndStopsChildren() async throws {
        let start = Date()
        let result = try await runner(timeLimit: 0.5).run(app("echo before; echo warn >&2; sleep 30 & echo $!; wait"))
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
        guard case .timeout(let output) = result else { return XCTFail("\(result)") }
        let lines = output.stdout.split(separator: "\n")
        XCTAssertEqual(lines.first, "before")
        XCTAssertEqual(output.stderr, "warn\n")
        let child = try XCTUnwrap(lines.last.flatMap { pid_t($0) })
        XCTAssertTrue(isGone(child), "the background child \(child) is still running")
    }

    func testTimeoutKillsACommandThatIgnoresTERM() async throws {
        let start = Date()
        let result = try await runner(timeLimit: 0.3).run(app("trap '' TERM; echo stubborn; while :; do sleep 0.05; done"))
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
        XCTAssertEqual(result, .timeout(MicroAppRunOutput(stdout: "stubborn\n")))
    }

    func testCancelStopsTheCommand() async throws {
        let r = try runner(timeLimit: 30)
        let start = Date()
        let task = Task { await r.run(self.app("echo started; sleep 30 & echo $!; wait")) }
        try await Task.sleep(nanoseconds: 400_000_000)
        task.cancel()
        let result = await task.value
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
        guard case .cancelled(let output) = result else { return XCTFail("\(result)") }
        XCTAssertTrue(output.stdout.hasPrefix("started\n"))
        let child = try XCTUnwrap(output.stdout.split(separator: "\n").last.flatMap { pid_t($0) })
        XCTAssertTrue(isGone(child))
    }

    func testCancelBeforeTheStartRunsNothing() async throws {
        let dir = try temporary()
        let marker = dir.appendingPathComponent("ran").path
        let r = try runner()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await r.run(self.app("touch '\(marker)'"))
        }
        let result = await task.value
        XCTAssertEqual(result, .cancelled(MicroAppRunOutput()))
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker))
    }

    func testOutputIsCutAtTheLimitAndTheCommandStillEnds() async throws {
        let limit = MicroAppRunRules.outputLimit
        let command = "head -c \(limit + 500_000) /dev/zero | tr '\\0' a; head -c \(limit * 2) /dev/zero | tr '\\0' e >&2; echo done >&2; exit 4"
        let start = Date()
        let result = try await runner().run(app(command))
        XCTAssertLessThan(Date().timeIntervalSince(start), 9)
        guard case .failure(let code, let output) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(code, 4, "the command ran to its own end")
        XCTAssertEqual(output.stdout.utf8.count, limit)
        XCTAssertEqual(output.stderr.utf8.count, limit)
        XCTAssertTrue(output.stdoutCut)
        XCTAssertTrue(output.stderrCut)

        let small = try await runner().run(app("echo small"))
        XCTAssertEqual(small, .success(MicroAppRunOutput(stdout: "small", stdoutCut: false, stderrCut: false)))
    }

    func testCutSuccessKeepsTheCutFlag() async throws {
        var r = try runner()
        r.outputLimit = 10
        let result = await r.run(app("printf '0123456789abcdef'"))
        XCTAssertEqual(result, .success(MicroAppRunOutput(stdout: "0123456789", stdoutCut: true)))
    }

    // MARK: Tools

    func testMissingToolRunsNothing() async throws {
        let dir = try temporary()
        let marker = dir.appendingPathComponent("ran").path
        let result = try await runner().run(app("touch '\(marker)'", tools: ["sh", "no-such-tool-ting-test"]))
        XCTAssertEqual(result, .toolNotFound("no-such-tool-ting-test"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker))
    }

    func testToolsOnThePATHAreFound() async throws {
        let dir = try temporary()
        _ = try script("echo mine", in: dir, name: "my-tool")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("a-dir"), withIntermediateDirectories: true)
        let result = try await runner(path: "/usr/bin:/bin:" + dir.path).run(app("my-tool", tools: ["sh", "my-tool"]))
        XCTAssertEqual(result, .success(MicroAppRunOutput(stdout: "mine")))
        XCTAssertNil(MicroAppRunner.find("a-dir", inPATH: dir.path))
        XCTAssertNil(MicroAppRunner.find("../bin/sh", inPATH: "/usr/bin"))
        XCTAssertEqual(MicroAppRunner.find("sh", inPATH: "/nowhere::/bin"), "/bin/sh")
    }

    // MARK: User PATH

    /// A changed shell PATH reaches the next run after a refresh; without one the read is kept.
    func testUserPATHCacheKeepsTheReadUntilARefresh() async throws {
        final class Counter: @unchecked Sendable {
            private let lock = NSLock()
            private var n = 0
            func next() -> Int { lock.lock(); defer { lock.unlock() }; n += 1; return n }
        }
        let counter = Counter()
        let cache = UserPATHCache(reader: { "/path/\(counter.next())" })
        let first = await cache.value()
        let again = await cache.value()
        XCTAssertEqual(first, "/path/1")
        XCTAssertEqual(again, "/path/1")
        await cache.refresh()
        let refreshed = await cache.value()
        XCTAssertEqual(refreshed, "/path/2")
    }

    func testUserPATHComesFromTheLoginShell() async throws {
        let dir = try temporary()
        let shell = try script(#"""
        [ "$1 $2 $3" = "-l -i -c" ] || exit 9
        echo "Welcome to the fake shell"
        echo __TING_PATH_BEGIN__
        echo /fake/bin:/usr/bin
        echo __TING_PATH_END__
        """#, in: dir)
        let result = await UserPATH.read(shell: shell, environment: ["PATH": "/usr/bin"], home: dir.path, timeLimit: 3)
        XCTAssertEqual(result.path, "/fake/bin:/usr/bin")
        XCTAssertEqual(result.source, .loginShell)
    }

    func testUserPATHFallsBackWhenTheShellFails() async throws {
        let dir = try temporary()
        let env = ["PATH": "/usr/bin:/bin"]
        let fallback = "/usr/bin:/bin:/opt/homebrew/bin:/usr/local/bin"

        let failing = try script("echo __TING_PATH_BEGIN__; echo /x; echo __TING_PATH_END__; exit 1", in: dir, name: "failing")
        var result = await UserPATH.read(shell: failing, environment: env, home: dir.path, timeLimit: 3)
        XCTAssertEqual(result.path, fallback)
        XCTAssertEqual(result.source, .fallback)

        let silent = try script("echo no path here", in: dir, name: "silent")
        result = await UserPATH.read(shell: silent, environment: env, home: dir.path, timeLimit: 3)
        XCTAssertEqual(result.source, .fallback)

        result = await UserPATH.read(shell: dir.appendingPathComponent("missing").path, environment: env, home: dir.path, timeLimit: 3)
        XCTAssertEqual(result.path, fallback)
        XCTAssertEqual(result.source, .fallback)
    }

    func testUserPATHFallsBackWhenTheShellIsSlow() async throws {
        let dir = try temporary()
        let slow = try script("/bin/sleep 30; echo __TING_PATH_BEGIN__; echo /late; echo __TING_PATH_END__", in: dir)
        let start = Date()
        let result = await UserPATH.read(shell: slow, environment: ["PATH": "/usr/bin"], home: dir.path, timeLimit: 0.3)
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
        XCTAssertEqual(result.path, "/usr/bin:/opt/homebrew/bin:/usr/local/bin")
        XCTAssertEqual(result.source, .fallback)
    }

    func testUserPATHWorksWithRealShells() async throws {
        let dir = try temporary()
        // A clean HOME, so the person's own start-up files do not change the test.
        let env = ["PATH": "/usr/bin:/bin", "HOME": dir.path]
        for shell in ["/bin/zsh", "/bin/bash", "/opt/homebrew/bin/fish", "/usr/local/bin/fish"]
        where FileManager.default.isExecutableFile(atPath: shell) {
            let result = await UserPATH.read(shell: shell, environment: env, home: dir.path, timeLimit: 10)
            XCTAssertEqual(result.source, .loginShell, shell)
            XCTAssertTrue(MicroAppRunRules.directories(ofPATH: result.path).contains("/usr/bin"), "\(shell): \(result.path)")
        }
    }
}
