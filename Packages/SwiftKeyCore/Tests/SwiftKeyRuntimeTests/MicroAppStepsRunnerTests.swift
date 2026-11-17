@testable import SwiftKeyRuntime
import Foundation
import XCTest
import SwiftKeyCore

/// The steps of a micro-app run by the real runner: real programs for command and python steps,
/// and fakes for HTTP, the keychain, notifications and `open`, so nothing leaves the Mac.
final class MicroAppStepsRunnerTests: XCTestCase {
    /// Collects what the fakes saw.
    final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String] = []
        private var progressItems: [(Date, MicroAppRunProgress)] = []
        func add(_ s: String) { lock.lock(); items.append(s); lock.unlock() }
        func add(_ p: MicroAppRunProgress) { lock.lock(); progressItems.append((Date(), p)); lock.unlock() }
        var all: [String] { lock.lock(); defer { lock.unlock() }; return items }
        var progress: [(Date, MicroAppRunProgress)] { lock.lock(); defer { lock.unlock() }; return progressItems }
    }

    private func app(_ steps: String, params: String = "", output: String = "output:\n  to: [panel]\n", top: String = "") throws -> MicroApp {
        let text = "format: ting.microapp/2\ndescription: d\n" + top + (params.isEmpty ? "" : "params:\n" + params) + "input: clipboard\nsteps:\n" + steps + output
        switch MicroAppChecker.check(text, fileName: "test.yaml") {
        case .success(let app): return app
        case .failure(let failure): throw XCTSkip("bad test file: \(failure)")
        }
    }

    private func runner(_ http: (@Sendable (MicroAppHTTPRequest) async throws -> MicroAppHTTPResponse)? = nil) throws -> MicroAppRunner {
        var runner = MicroAppRunner()
        runner.path = { "/usr/bin:/bin:/usr/sbin:/sbin" }
        runner.environment = ["HOME": NSHomeDirectory(), "API_TOKEN": "tok-1", "LANG": "en_US.UTF-8"]
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("swiftkey-steps-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        runner.workingDirectory = dir.path
        runner.timeLimit = 20
        runner.keychain = { service in
            guard service == "example" else { throw MicroAppServiceError("no keychain item `\(service)`") }
            return "secret-1"
        }
        runner.http = http ?? { _ in throw URLError(.notConnectedToInternet) }
        runner.notify = { _, _ in throw MicroAppServiceError("no notifications in tests") }
        runner.open = { _, _ in throw MicroAppServiceError("nothing opens in tests") }
        return runner
    }

    private static func body(_ chunks: [String], delay: UInt64 = 0) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            Task {
                for chunk in chunks {
                    if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
                    continuation.yield(Data(chunk.utf8))
                }
                continuation.finish()
            }
        }
    }

    private func stdout(_ result: MicroAppRunResult, file: StaticString = #filePath, line: UInt = #line) -> String? {
        guard case .success(let output) = result else {
            XCTFail("not a success: \(result)", file: file, line: line)
            return nil
        }
        return output.stdout
    }

    // MARK: Programs and data flow

    func testOutputFlowsFromStepToStepAndNamedOutputsStay() async throws {
        let app = try app("""
          - command: tr a-z A-Z
            id: upper
          - command: rev
          - text: "${steps.upper}|${input}|${params.mode}"
            id: joined
          - command: printf '%s/%s/%s' "$TING_STEP_UPPER" "$TING_MODE" "$(cat)"

        """, params: "  - name: mode\n    type: text\n    required: true\n")
        let result = try await runner().run(app, values: ["mode": "m"], stdin: "abc")
        XCTAssertEqual(stdout(result), "ABC/m/ABC|CBA|m")
    }

    func testEnvironmentVariablesAndKeychainReachTheSteps() async throws {
        let app = try app("""
          - command: printf '%s %s %s' "$API_KEY" "$API_TOKEN" "${LANG-none}"
            env:
              API_KEY: ${keychain.example}
          - text: ${input} ${API_TOKEN}

        """)
        let result = try await runner().run(app)
        XCTAssertEqual(stdout(result), "secret-1 tok-1 none tok-1", "the locale is not passed on; env and keychain values are")
    }

    func testMissingVariableAndKeychainItemFailTheStep() async throws {
        let missing = try await runner().run(try app("  - text: a\n  - text: ${NOT_SET_ANYWHERE}\n"))
        guard case .stepFailed(let f) = missing else { return XCTFail("\(missing)") }
        XCTAssertEqual(f.index, 1)
        XCTAssertEqual(f.stepNote, "step 2 of 2 · text")
        XCTAssertTrue(f.output.stderr.contains("`${NOT_SET_ANYWHERE}` is not set"), f.output.stderr)

        let keychain = try await runner().run(try app("  - text: ${keychain.other}\n"))
        guard case .stepFailed(let k) = keychain else { return XCTFail("\(keychain)") }
        XCTAssertEqual(k.stepNote, "text")
        XCTAssertTrue(k.output.stderr.contains("no keychain item `other`"), k.output.stderr)
    }

    func testAFailingCommandStopsTheSteps() async throws {
        let app = try app("  - command: echo out; echo bad >&2; exit 3\n  - command: touch should-not-exist\n")
        let r = try runner()
        let result = await r.run(app)
        guard case .stepFailed(let f) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(f.note, "exit 3")
        XCTAssertEqual(f.output.stderr, "bad\n")
        XCTAssertEqual(f.output.stdout, "out\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: r.workingDirectory + "/should-not-exist"))
        let plan = MicroAppResultPlan.make(app: app, result: result)
        guard case .panel(let content) = plan.show else { return XCTFail("\(plan)") }
        XCTAssertEqual(content.notes, ["step 1 of 2 · command", "exit 3"])
    }

    func testJSONStep() async throws {
        let ok = try await runner().run(try app("  - json: items.1.name\n"), stdin: #"{"items":[{"name":"a"},{"name":"бэ"}]}"#)
        XCTAssertEqual(stdout(ok), "бэ")
        let bad = try await runner().run(try app("  - json: items.5\n"), stdin: #"{"items":[]}"#)
        guard case .stepFailed(let f) = bad else { return XCTFail("\(bad)") }
        XCTAssertEqual(f.output.stderr, "json `items.5`: the JSON has no `items.5`")
    }

    func testStreamingStepReadsWhileTheStepBeforeRuns() async throws {
        let app = try app("""
          - command: echo first; sleep 1.5; echo second
          - command: while IFS= read -r line; do printf '%s!\\n' "$line"; done
            stream: true

        """)
        let recorder = Recorder()
        let start = Date()
        let result = try await runner().run(app, progress: { recorder.add($0) })
        let total = Date().timeIntervalSince(start)
        XCTAssertEqual(stdout(result), "first!\nsecond!")
        XCTAssertGreaterThan(total, 1.4)
        // The live output of the last step showed `first!` long before the first step ended.
        let early = recorder.progress.first { $0.1.liveOutput?.contains("first!") == true }
        let firstSeen = try XCTUnwrap(early?.0).timeIntervalSince(start)
        XCTAssertLessThan(firstSeen, 1.0, "streamed after \(firstSeen) s")
        XCTAssertEqual(recorder.progress.first?.1, MicroAppRunProgress(index: 0, count: 2, kind: .command))
    }

    func testStepsWithoutStreamWaitForTheStepBefore() async throws {
        let app = try app("""
          - command: echo first; sleep 1; echo second
          - command: cat

        """)
        let recorder = Recorder()
        let start = Date()
        let result = try await runner().run(app, progress: { recorder.add($0) })
        XCTAssertEqual(stdout(result), "first\nsecond")
        let live = recorder.progress.filter { $0.1.liveOutput != nil }
        XCTAssertTrue(live.allSatisfy { $0.0.timeIntervalSince(start) > 0.9 }, "the second step started early")
        XCTAssertEqual(recorder.progress.first?.1.label, "Step 1 of 2 · command")
    }

    func testPythonStep() async throws {
        guard await MicroAppRunner.hasCommandLineTools() else { throw XCTSkip("python3 needs the Command Line Tools") }
        let app = try app("""
          - python: |
              import os, sys
              sys.stdout.write(sys.stdin.read().title() + os.environ["TING_MODE"])

        """, params: "  - name: mode\n    type: text\n    required: true\n")
        let result = try await runner().run(app, values: ["mode": "!"], stdin: "привет мир")
        XCTAssertEqual(stdout(result), "Привет Мир!")
    }

    func testPythonNeedsTheCommandLineTools() async throws {
        var r = try runner()
        r.commandLineToolsInstalled = { false }
        let result = await r.run(try app("  - python: print(1)\n"))
        guard case .toolNotFound(let message) = result else { return XCTFail("\(result)") }
        XCTAssertTrue(message.hasPrefix("python3 (install the Command Line Tools"), message)
    }

    // MARK: Time limits

    func testStepTimeoutAndTotalTimeout() async throws {
        let own = try await runner().run(try app("  - command: sleep 10\n    timeout: 1\n  - text: never\n"))
        guard case .stepFailed(let f) = own else { return XCTFail("\(own)") }
        XCTAssertEqual(f.note, "stopped after 1 s")

        var r = try runner()
        r.timeLimit = 1
        let start = Date()
        let total = await r.run(try app("  - command: echo partial; sleep 10\n"))
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
        XCTAssertEqual(total, .timeout(MicroAppRunOutput(stdout: "partial\n")))
        XCTAssertEqual(MicroAppResultPlan.make(app: try app("  - text: x\n"), result: total, timeLimit: r.timeLimit(for: try app("  - text: x\n"))).show,
                       .panel(MicroAppPanelContent(title: "test", text: "partial", style: .console, isError: true, notes: ["stopped after 1 s"])))
    }

    func testTimeoutOfAHangingRequest() async throws {
        let r = try runner { _ in
            try await Task.sleep(nanoseconds: 30_000_000_000)
            throw URLError(.timedOut)
        }
        let start = Date()
        let result = await r.run(try app("  - url: https://example.com\n    timeout: 1\n"))
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
        guard case .stepFailed(let f) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(f.note, "stopped after 1 s")
    }

    func testCancelStopsTheRun() async throws {
        let r = try runner()
        let app = try app("  - command: sleep 20\n")
        let task = Task { await r.run(app) }
        try await Task.sleep(nanoseconds: 300_000_000)
        task.cancel()
        let result = await task.value
        guard case .cancelled = result else { return XCTFail("\(result)") }
    }

    func testAnIntermediateOutputOverTheLimitFails() async throws {
        var r = try runner()
        r.outputLimit = 1000
        let result = await r.run(try app("  - command: head -c 5000 /dev/zero | tr '\\\\0' a\n  - command: wc -c\n"))
        guard case .stepFailed(let f) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(f.note, "output too large")
        XCTAssertEqual(f.index, 0)
    }

    // MARK: HTTP and AI

    func testURLStepSendsTheRequestAndStreamsTheBody() async throws {
        let recorder = Recorder()
        let r = try runner { request in
            recorder.add("\(request.method) \(request.url) \(request.header("Authorization") ?? "-") \(String(decoding: request.body ?? Data(), as: UTF8.self))")
            return MicroAppHTTPResponse(status: 200, body: Self.body([#"{"answer":"#, #""ok"}"#]))
        }
        let app = try app("""
          - url: https://api.example.com/v1/${input|trim|url}
            method: POST
            query:
              lang: uk
            headers:
              Authorization: Bearer ${API_TOKEN}
            body:
              text: ${input}
          - json: answer

        """)
        let result = await r.run(app, stdin: "a b\n")
        XCTAssertEqual(stdout(result), "ok")
        XCTAssertEqual(recorder.all, [#"POST https://api.example.com/v1/a%20b?lang=uk Bearer tok-1 {"text":"a b"}"#])
    }

    func testURLStepFailsOnAnErrorStatusWithoutShowingTheQuery() async throws {
        let r = try runner { _ in MicroAppHTTPResponse(status: 404, body: Self.body(["no such page"])) }
        let result = await r.run(try app("  - url: https://api.example.com/x\n    query:\n      key: ${API_TOKEN}\n"))
        guard case .stepFailed(let f) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(f.note, "HTTP 404")
        XCTAssertEqual(f.output.stdout, "no such page")
        XCTAssertEqual(f.output.stderr, "GET https://api.example.com/x?… answered HTTP 404 not found")
        XCTAssertFalse(f.output.stderr.contains("tok-1"))
    }

    func testAIStepStreamsTheAnswerToTheLiveOutput() async throws {
        let recorder = Recorder()
        let r = try runner { request in
            recorder.add(request.url + " " + (request.header("x-api-key") ?? "-"))
            return MicroAppHTTPResponse(status: 200, body: Self.body([
                "event: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"Hel\"}}\n\n",
                "event: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"lo\"}}\n\n",
                "event: message_stop\ndata: {\"type\":\"message_stop\"}\n\n",
            ], delay: 150_000_000))
        }
        let app = try app("""
          - ai: ${input}
            provider: anthropic
            model: claude-haiku-5-5
            key: ${keychain.example}

        """)
        let result = await r.run(app, stdin: "Hi", progress: { recorder.add($0) })
        XCTAssertEqual(stdout(result), "Hello")
        XCTAssertEqual(recorder.all, ["https://api.anthropic.com/v1/messages secret-1"])
        let live = recorder.progress.compactMap(\.1.liveOutput)
        XCTAssertTrue(live.contains("Hel"), "\(live)")
    }

    func testAIStepErrors() async throws {
        let unauthorized = try runner { _ in
            MicroAppHTTPResponse(status: 401, body: Self.body([#"{"error":{"message":"Incorrect API key","type":"invalid_request_error"}}"#]))
        }
        let app = try app("  - ai: ${input}\n    provider: openai\n    model: gpt-4.1-mini\n    key: ${API_TOKEN}\n")
        let result = await unauthorized.run(app, stdin: "x")
        guard case .stepFailed(let f) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(f.note, "HTTP 401")
        XCTAssertEqual(f.output.stderr, "openai at https://api.openai.com/v1/chat/completions: invalid_request_error: Incorrect API key")

        let cut = try runner { _ in
            MicroAppHTTPResponse(status: 200, body: Self.body(["data: {\"choices\":[{\"delta\":{\"content\":\"part\"},\"finish_reason\":\"length\"}]}\n\n"]))
        }
        let cutResult = await cut.run(app, stdin: "x")
        guard case .stepFailed(let c) = cutResult else { return XCTFail("\(cutResult)") }
        XCTAssertTrue(c.output.stderr.contains("cut at the token limit"), c.output.stderr)

        let noKey = try runner()
        let missing = await noKey.run(try self.app("  - ai: x\n    provider: openai\n    model: m\n"))
        guard case .stepFailed(let m) = missing else { return XCTFail("\(missing)") }
        XCTAssertEqual(m.output.stderr, "no API key: set `key:` in the step or the environment variable OPENAI_API_KEY")
    }

    // MARK: Open and notify

    func testOpenAndNotifyPassTheirInputOn() async throws {
        let recorder = Recorder()
        var r = try runner()
        r.open = { target, app in recorder.add("open \(target) \(app ?? "-")") }
        r.notify = { title, message in recorder.add("notify \(title): \(message)") }
        let app = try app("""
          - open: https://duckduckgo.com/?q=${input|trim|url}
          - notify: Searched for ${input}
            title: Search
          - open: ~/Documents
            app: Finder

        """)
        let result = await r.run(app, stdin: "a&b\n")
        XCTAssertEqual(stdout(result), "a&b")
        XCTAssertEqual(recorder.all, ["open https://duckduckgo.com/?q=a%26b -", "notify Search: Searched for a&b",
                                      "open \(NSHomeDirectory())/Documents Finder"])
        let refused = await r.run(try self.app("  - open: ${input}\n"), stdin: "-a Calculator")
        guard case .stepFailed(let f) = refused else { return XCTFail("\(refused)") }
        XCTAssertTrue(f.output.stderr.contains("is not a URL or a file path"))
    }
}

/// `call`, `inherit` and step `params` run by the real runner.
final class MicroAppLibraryRunnerTests: XCTestCase {
    private let library = MicroAppLibrarySource(name: "wrap", file: "libs/wrap.yaml", text: """
    format: ting.microlib/1
    description: Wrap the input.
    params:
      - name: left
        type: text
        required: false
        default: "["
    input: clipboard
    steps:
      - command: tr a-z A-Z
        id: upper
      - text: ${params.left}${steps.upper}]
        id: wrap
    output:
      to: [panel]

    """)

    private func app(_ text: String) throws -> MicroApp {
        try MicroAppChecker.check(text, fileName: "test.yaml", libraries: MicroAppLibraries([library])).get()
    }

    private func runner() -> MicroAppRunner {
        var runner = MicroAppRunner()
        runner.path = { "/usr/bin:/bin" }
        runner.environment = [:]
        runner.workingDirectory = NSTemporaryDirectory()
        runner.timeLimit = 10
        return runner
    }

    func testCallRunsTheLibraryWithItsOwnParamsAndSteps() async throws {
        // The micro-app has its own `upper` step and `left` param; the library does not see them.
        let app = try app("""
        format: ting.microapp/2
        description: d
        params:
          - name: left
            type: text
            required: true
        input: clipboard
        steps:
          - text: ${input}-${params.left}
            id: upper
          - call: wrap
            params:
              left: "<"
          - text: ${input} ${steps.upper}
        output:
          to: [panel]

        """)
        let recorder = MicroAppStepsRunnerTests.Recorder()
        let result = await runner().run(app, values: ["left": "L"], stdin: "abc", progress: { recorder.add($0) })
        XCTAssertEqual(result, .success(MicroAppRunOutput(stdout: "<ABC-L] abc-L")))
        XCTAssertTrue(recorder.progress.map(\.1.label).contains("Step 2 of 3 · call wrap › command"), "\(recorder.progress.map(\.1.label))")
    }

    func testCallFailureNamesTheLibraryStep() async throws {
        let broken = MicroAppLibrarySource(name: "fail", file: "libs/fail.yaml",
                                           text: "format: ting.microlib/1\ndescription: d\nsteps:\n  - text: a\n  - command: echo nope >&2; exit 4\n")
        let app = try MicroAppChecker.check("format: ting.microapp/2\ndescription: d\ninput: none\nsteps:\n  - call: fail\n",
                                            fileName: "t.yaml", libraries: MicroAppLibraries([broken])).get()
        let result = await runner().run(app)
        guard case .stepFailed(let f) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(f.note, "exit 4")
        XCTAssertEqual(f.kind, .call)
        XCTAssertEqual(f.output.stderr, "fail › step 2 of 2 · command: nope\n")
    }

    func testInheritWithAStepParam() async throws {
        let app = try app("format: ting.microapp/2\ninherit: wrap\nsteps:\n  - id: wrap\n    params:\n      left: \"{\"\n")
        XCTAssertTrue(app.params.isEmpty)
        let result = await runner().run(app, stdin: "hi")
        XCTAssertEqual(result, .success(MicroAppRunOutput(stdout: "{HI]")))
    }

    func testStepParamsReachCode() async throws {
        let app = try app("""
        format: ting.microapp/2
        description: d
        input: none
        steps:
          - command: printf '%s' "$TING_WHO"
            params:
              who: shell
          - text: ${input}+${params.who}
            params:
              who: text

        """)
        let result = await runner().run(app)
        XCTAssertEqual(result, .success(MicroAppRunOutput(stdout: "shell+text")))
    }
}
