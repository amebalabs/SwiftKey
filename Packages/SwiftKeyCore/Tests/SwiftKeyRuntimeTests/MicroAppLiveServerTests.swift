@testable import SwiftKeyRuntime
import Darwin
import Foundation
import XCTest
import SwiftKeyCore

/// A real `fm serve` (Apple's on-device Foundation Model behind an OpenAI-compatible Chat
/// Completions server) for the `ai` and `url` steps: no key, no cost, nothing leaves the Mac.
/// One server runs for the whole test class on a free local port.
final class LiveModelServer: @unchecked Sendable {
    let port: Int
    private let process: Process

    var baseURL: String { "http://127.0.0.1:\(port)" }

    private init(port: Int, process: Process) {
        self.port = port
        self.process = process
    }

    func stop() {
        guard process.isRunning else { return }
        process.terminate()
        process.waitUntilExit()
    }

    /// Starts `fm serve` and waits until `GET /health` answers. Throws a message that says what to
    /// install or turn on when `fm` or its model is missing.
    static func start() async throws -> LiveModelServer {
        guard let fm = executable() else {
            throw Failure("`fm` (Apple Foundation Models CLI) was not found on the PATH or in /usr/bin. "
                + "The live AI and HTTP tests need it: install a macOS with Apple Intelligence and the `fm` tool.")
        }
        let available = try run(fm, ["available"])
        guard available.status == 0, available.output.contains("available"), !available.output.contains("unavailable") else {
            throw Failure("`fm available` says the on-device model cannot be used (\(available.output.trimmingCharacters(in: .whitespacesAndNewlines))). "
                + "Turn on Apple Intelligence in System Settings and let the model download, then run the tests again.")
        }
        let port = try freePort()
        let process = Process()
        process.executableURL = fm
        process.arguments = ["serve", "--host", "127.0.0.1", "--port", String(port)]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        let server = LiveModelServer(port: port, process: process)
        let health = URL(string: "\(server.baseURL)/health")!
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            if let (_, response) = try? await URLSession.shared.data(from: health),
               (response as? HTTPURLResponse)?.statusCode == 200 { return server }
            guard process.isRunning else { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        server.stop()
        throw Failure("`fm serve` did not answer GET /health on port \(port) within 20 seconds.")
    }

    struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    private static func executable() -> URL? {
        let path = (ProcessInfo.processInfo.environment["PATH"] ?? "") + ":/usr/bin"
        for folder in path.split(separator: ":") {
            let url = URL(fileURLWithPath: String(folder)).appendingPathComponent("fm")
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        return nil
    }

    private static func run(_ executable: URL, _ arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        // The tool colours its output; the words are what matters.
        let text = String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: "\u{1B}\\[[0-9;]*m", with: "", options: .regularExpression)
        return (process.terminationStatus, text.lowercased())
    }

    /// A port the system has just given out and taken back.
    private static func freePort() throws -> Int {
        let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard socket >= 0 else { throw Failure("cannot open a socket to find a free port") }
        defer { close(socket) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(socket, $0, length) == 0 && getsockname(socket, $0, &length) == 0 }
        }
        guard bound else { throw Failure("cannot find a free local port") }
        return Int(UInt16(bigEndian: address.sin_port))
    }
}

/// The `ai` and `url` steps against the live model server: real HTTP, real streaming, real errors.
/// Answers of the model vary, so the checks look at structure and flow, not at wording.
final class MicroAppLiveServerTests: XCTestCase {
    private static var server: LiveModelServer?
    private static var startFailure: String?

    override class func setUp() {
        super.setUp()
        let started = DispatchSemaphore(value: 0)
        Task {
            do { server = try await LiveModelServer.start() } catch { startFailure = String(describing: error) }
            started.signal()
        }
        started.wait()
    }

    override class func tearDown() {
        server?.stop()
        server = nil
        super.tearDown()
    }

    private var server: LiveModelServer!

    override func setUp() async throws {
        guard let server = Self.server else {
            XCTFail(Self.startFailure ?? "the live model server did not start")
            throw LiveModelServer.Failure("no live model server")
        }
        self.server = server
    }

    /// Collects the progress of a run.
    private final class Progress: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [MicroAppRunProgress] = []
        func add(_ item: MicroAppRunProgress) { lock.withLock { items.append(item) } }
        var live: [String] { lock.withLock { items.compactMap(\.liveOutput) } }
    }

    private func app(_ steps: String) throws -> MicroApp {
        let text = "format: ting.microapp/2\ndescription: d\ninput: clipboard\nsteps:\n" + steps + "output:\n  to: [panel]\n"
        return try MicroAppChecker.check(text, fileName: "live.yaml").get()
    }

    private func runner() throws -> MicroAppRunner {
        var runner = MicroAppRunner()
        runner.path = { "/usr/bin:/bin:/usr/sbin:/sbin" }
        runner.environment = ["HOME": NSHomeDirectory(), "API_TOKEN": "tok-1"]
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("swiftkey-live-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        runner.workingDirectory = dir.path
        runner.timeLimit = 60
        return runner
    }

    private func aiStep(_ extra: String = "") -> String {
        "  - ai: ${input}\n    provider: openai\n    model: system\n    base_url: \(server.baseURL)/v1\n" + extra
    }

    // MARK: AI

    func testAIStepGivesTheFullAnswer() async throws {
        let result = try await runner().run(try app(aiStep()), stdin: "Name one planet of the solar system. Answer with one word.")
        guard case .success(let output) = result else { return XCTFail("\(result)") }
        XCTAssertFalse(output.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertLessThan(output.stdout.count, 400, output.stdout)
    }

    func testAIStepStreamsTheAnswerWhileItComes() async throws {
        let progress = Progress()
        let result = try await runner().run(try app(aiStep()), stdin: "Write three short sentences about the sea.",
                                            progress: { progress.add($0) })
        guard case .success(let output) = result else { return XCTFail("\(result)") }
        let live = progress.live.filter { !$0.isEmpty }
        XCTAssertGreaterThan(Set(live).count, 1, "the answer arrives in more than one piece: \(live)")
        // Each piece grows the text of the one before; the last is the whole answer.
        for (earlier, later) in zip(live, live.dropFirst()) {
            XCTAssertTrue(later.hasPrefix(earlier), "\(earlier) → \(later)")
        }
        XCTAssertEqual(live.last?.trimmingCharacters(in: .whitespacesAndNewlines),
                       output.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func testAIStepTimeoutStopsALongAnswer() async throws {
        let start = Date()
        let result = try await runner().run(try app(aiStep("    timeout: 1\n")),
                                            stdin: "Write a story of at least eight hundred words about a lighthouse keeper.")
        XCTAssertLessThan(Date().timeIntervalSince(start), 10)
        guard case .stepFailed(let failure) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(failure.note, "stopped after 1 s")
    }

    func testAIStepErrorNamesTheServerAndItsMessage() async throws {
        let steps = "  - ai: ${input}\n    provider: openai\n    model: no-such-model\n    base_url: \(server.baseURL)/v1\n"
        let result = try await runner().run(try app(steps), stdin: "x")
        guard case .stepFailed(let failure) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(failure.note, "HTTP 400")
        XCTAssertTrue(failure.output.stderr.hasPrefix("openai at \(server.baseURL)/v1/chat/completions: "), failure.output.stderr)
        XCTAssertTrue(failure.output.stderr.contains("no-such-model"), failure.output.stderr)
    }

    // MARK: HTTP

    func testURLStepGetsJSONForALaterStep() async throws {
        let steps = "  - url: \(server.baseURL)/v1/models\n  - json: data.0.id\n"
        let result = try await runner().run(try app(steps), stdin: "")
        guard case .success(let output) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(output.stdout, "system")
    }

    func testURLStepFailsOnAnErrorStatusWithoutShowingTheQuery() async throws {
        let steps = "  - url: \(server.baseURL)/no-such-page\n    query:\n      key: ${API_TOKEN}\n"
        let result = try await runner().run(try app(steps), stdin: "")
        guard case .stepFailed(let failure) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(failure.note, "HTTP 404")
        XCTAssertTrue(failure.output.stdout.contains("not_found"), failure.output.stdout)
        XCTAssertEqual(failure.output.stderr, "GET \(server.baseURL)/no-such-page?… answered HTTP 404 not found")
        // SwiftKey's own message hides the query; the body is the server's answer, shown as sent.
        XCTAssertFalse(failure.output.stderr.contains("tok-1"))
    }

    func testURLStepPostsAJSONBody() async throws {
        let steps = """
          - url: \(server.baseURL)/v1/chat/completions
            headers:
              Accept: application/json
            body:
              model: system
              stream: false
              messages:
                - role: user
                  content: ${input}
          - json: object

        """
        let result = try await runner().run(try app(steps), stdin: "Say hi.")
        guard case .success(let output) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(output.stdout, "chat.completion", "a whole, not streamed, answer to the posted body")
    }
}
