// Runs a micro-app: checks its tools, then runs its steps in the home folder, with the user's
// login-shell environment and the `TING_<NAME>` variables. A `command` file is one command step.
// No UI.
import Darwin
import Foundation
import SwiftKeyCore

/// What the user's login shell reports: its PATH and its whole environment.
public struct UserShellEnvironment: Equatable, Sendable {
    public var path: String
    public var source: UserPATH.Source
    /// The login shell's variables; `nil` when the shell did not give them (SwiftKey's own are used then).
    public var variables: [String: String]?
}

/// The PATH and environment of the user's login shell, read with one call of the shell.
public enum UserPATH {
    public enum Source: Equatable, Sendable {
        case loginShell
        case fallback
    }

    /// The login shell gets this long to print its PATH.
    public static let timeLimit: TimeInterval = 5

    /// The user's login shell from the user database, then `$SHELL`, then zsh.
    public static func loginShell() -> String {
        if let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell {
            let path = String(cString: shell)
            if !path.isEmpty { return path }
        }
        if let shell = ProcessInfo.processInfo.environment["SHELL"], !shell.isEmpty { return shell }
        return "/bin/zsh"
    }

    /// Runs `shell` once as an interactive login shell and returns the PATH and the environment it
    /// prints. When the shell fails, is slow or prints no PATH, returns SwiftKey's PATH with
    /// `/opt/homebrew/bin` and `/usr/local/bin`, and no variables.
    public static func read(shell: String = loginShell(),
                     environment: [String: String] = ProcessInfo.processInfo.environment,
                     home: String = NSHomeDirectory(),
                     timeLimit: TimeInterval = timeLimit) async -> UserShellEnvironment {
        let request = ChildProcessRequest(executable: shell, arguments: MicroAppRunRules.pathShellArguments,
                                          environment: environment, workingDirectory: home, timeLimit: timeLimit,
                                          outputLimit: 1024 * 1024)
        let outcome = await ChildProcess.run(request)
        if outcome.end == .exited(0), !outcome.stdoutCut,
           let path = MicroAppRunRules.pathFromShellOutput(String(decoding: outcome.stdout, as: UTF8.self)) {
            var variables = MicroAppRunRules.environmentFromShellOutput(outcome.stdout)
            variables?["PATH"] = path
            return UserShellEnvironment(path: path, source: .loginShell, variables: variables)
        }
        return UserShellEnvironment(path: MicroAppRunRules.fallbackPATH(tingPATH: environment["PATH"]), source: .fallback, variables: nil)
    }

    /// The user's PATH: the last read that `refresh` started, or a first read now.
    public static func shared() async -> String {
        await sharedEnvironment().path
    }

    /// The user's login-shell environment, from the same read as `shared`.
    public static func sharedEnvironment() async -> UserShellEnvironment {
        await userShellCache.value()
    }

    /// Reads the PATH from the login shell again, in the background: at SwiftKey's start and on each
    /// load of the micro-apps folder. A run that asks after the new read began waits for it.
    public static func refresh() {
        Task { await userShellCache.refresh() }
    }
}

let userShellCache = UserPATHCache<UserShellEnvironment>(reader: { await UserPATH.read() })

/// Keeps the newest read. A new read replaces the old one; `value` waits for the newest.
actor UserPATHCache<Value: Sendable> {
    private let reader: @Sendable () async -> Value
    private var task: Task<Value, Never>?

    init(reader: @escaping @Sendable () async -> Value) {
        self.reader = reader
    }

    func value() async -> Value {
        if let task { return await task.value }
        return await refresh().value
    }

    @discardableResult
    func refresh() -> Task<Value, Never> {
        let reader = self.reader
        let task = Task.detached { await reader() }
        self.task = task
        return task
    }
}

/// The output of a step: kept whole (up to the limit) for the steps after it, and handed to a
/// streaming step while it comes.
final class MicroAppByteChannel: ChildProcessStdinSource, @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private var everything = Data()
    private var pending = Data()
    private var isCut = false
    private var finished = false
    private var hasReader = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var observer: (@Sendable (Data) -> Void)?
    private var errorText = ""

    init(limit: Int) {
        self.limit = limit
    }

    /// A streaming step reads this channel; from now on chunks are kept for `takeAvailable`.
    func attachReader() {
        lock.lock(); hasReader = true; lock.unlock()
    }

    /// Called with the whole output so far after each chunk.
    func observe(_ observer: @escaping @Sendable (Data) -> Void) {
        lock.lock(); self.observer = observer; lock.unlock()
    }

    func write(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        if MicroAppRunRules.append(data, to: &everything, limit: limit) { isCut = true }
        if hasReader { pending.append(data) }
        let observer = self.observer
        let snapshot = observer == nil ? Data() : everything
        lock.unlock()
        observer?(snapshot)
    }

    func finish() {
        lock.lock()
        finished = true
        let waiting = waiters
        waiters = []
        lock.unlock()
        waiting.forEach { $0.resume() }
    }

    func takeAvailable() -> (data: Data, finished: Bool) {
        lock.lock(); defer { lock.unlock() }
        let data = pending
        pending = Data()
        return (data, finished)
    }

    /// Waits until the step has finished writing.
    func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if finished {
                lock.unlock()
                continuation.resume()
            } else {
                waiters.append(continuation)
                lock.unlock()
            }
        }
    }

    /// The stderr of a program step that ended well.
    var stderr: String {
        get { lock.lock(); defer { lock.unlock() }; return errorText }
        set { lock.lock(); errorText = newValue; lock.unlock() }
    }

    /// Everything the step wrote, up to the limit.
    var output: (data: Data, cut: Bool) {
        lock.lock(); defer { lock.unlock() }
        return (everything, isCut)
    }
}

/// Why a step did not end well.
struct MicroAppStepError: Error, Sendable {
    enum Reason: Sendable, Equatable {
        /// A program ended with this exit code.
        case exit(Int32)
        /// The step's own limit (`total == false`) or the micro-app's limit passed.
        case timedOut(seconds: TimeInterval, total: Bool)
        case cancelled
        /// Any other failure, with its short note.
        case failed(String)
    }

    var reason: Reason
    /// The error text.
    var message: String = ""
    /// What the step printed before it failed.
    var stdout: String = ""
    var stdoutCut = false
    var stderrCut = false

    static func failed(_ note: String, _ message: String) -> MicroAppStepError {
        MicroAppStepError(reason: .failed(note), message: message)
    }
}

/// An HTTP response with its body as it comes.
public struct MicroAppHTTPResponse: Sendable {
    public var status: Int
    public var body: AsyncThrowingStream<Data, Error>
}

public struct MicroAppRunner: Sendable {
    public init() {}

    /// Gives the PATH for the steps and the `tools` check.
    public var path: @Sendable () async -> String = { await UserPATH.shared() }
    /// The base environment of the steps and the `${NAME}` variables; `nil` uses the login shell's,
    /// or SwiftKey's own when the shell gave none.
    public var environment: [String: String]?
    public var workingDirectory: String = NSHomeDirectory()
    /// Overrides the time limit of every micro-app (for tests); `nil` uses the file's `timeout`.
    public var timeLimit: TimeInterval?
    public var outputLimit: Int = MicroAppRunRules.outputLimit
    /// Runs a command step as `shell -c command`.
    public var shell = "/bin/sh"
    /// Reads `${keychain.SERVICE}`.
    public var keychain: @Sendable (String) throws -> String = { try MicroAppKeychain.password(service: $0) }
    /// Sends the request of a `url` or `ai` step.
    public var http: @Sendable (MicroAppHTTPRequest) async throws -> MicroAppHTTPResponse = { try await MicroAppHTTP.send($0) }
    /// Shows the notification of a `notify` step.
    public var notify: @Sendable (_ title: String, _ message: String) async throws -> Void = { try await MicroAppNotifier.post(title: $0, message: $1) }
    /// Opens the URL or file of an `open` step (with an app name, or `nil`).
    public var open: (@Sendable (_ target: String, _ app: String?) async throws -> Void)?
    /// Sends the key presses of a `keys` step and the text of a `paste` step to the app where the
    /// micro-app started. `nil`: such a step fails, because only SwiftKey can send them.
    public var keyboard: (@Sendable (MicroAppKeyboardAction) async throws -> Void)?
    /// `true` when `/usr/bin/python3` is a real Python, not the stub that asks for the Command Line Tools.
    public var commandLineToolsInstalled: @Sendable () async -> Bool = { await MicroAppRunner.hasCommandLineTools() }

    /// The time limit of `app` for this runner.
    public func timeLimit(for app: MicroApp) -> TimeInterval { timeLimit ?? app.timeLimit }

    /// Runs `app` with parameter values by name and an optional stdin text. `progress` hears which
    /// step runs and, once the last step runs and the result goes to the panel, its output so far.
    /// Cancelling the task stops the running step (and its program) and gives `.cancelled`.
    public func run(_ app: MicroApp, values: [String: String] = [:], stdin: String? = nil, context: MicroAppContext = MicroAppContext(),
             progress: (@Sendable (MicroAppRunProgress) -> Void)? = nil) async -> MicroAppRunResult {
        let path = await self.path()
        let base: [String: String]
        if let environment {
            base = environment
        } else {
            base = await UserPATH.sharedEnvironment().variables ?? ProcessInfo.processInfo.environment
        }
        for tool in app.requiredTools {
            guard let found = Self.find(tool, inPATH: path) else { return .toolNotFound(tool) }
            if tool == "python3", found == "/usr/bin/python3", !(await commandLineToolsInstalled()) {
                return .toolNotFound("python3 (install the Command Line Tools: run `xcode-select --install` in Terminal)")
            }
        }
        let limit = timeLimit(for: app)
        var pipeline = MicroAppPipeline(runner: self, app: app, path: path, base: base,
                                        params: MicroAppRunRules.paramValues(app.params, values: values),
                                        context: context, contextEnvironment: context.environment(for: app.requiredContext),
                                        deadline: Date().addingTimeInterval(limit), limit: limit, progress: progress)
        let result = await pipeline.run(stdin: Data((stdin ?? "").utf8))
        return app.command == nil ? result : Self.commandResult(result, shell: shell)
    }

    /// The result of a `command` file as before steps: exit codes and timeouts without a step note.
    public static func commandResult(_ result: MicroAppRunResult, shell: String) -> MicroAppRunResult {
        guard case .stepFailed(let failure) = result else { return result }
        if failure.note.hasPrefix("exit "), let code = Int32(failure.note.dropFirst(5)) {
            return .failure(exitCode: code, failure.output)
        }
        if failure.note == "not started" { return .failure(exitCode: 127, failure.output) }
        return .failure(exitCode: 1, failure.output)
    }

    /// The first executable file named `tool` in the PATH directories, or `nil`.
    public static func find(_ tool: String, inPATH path: String) -> String? {
        guard !tool.isEmpty, !tool.contains("/") else { return nil }
        for directory in MicroAppRunRules.directories(ofPATH: path) {
            let candidate = (directory as NSString).appendingPathComponent(tool)
            var info = stat()
            if stat(candidate, &info) == 0, info.st_mode & S_IFMT == S_IFREG, access(candidate, X_OK) == 0 {
                return candidate
            }
        }
        return nil
    }

    /// `xcode-select -p` succeeds only when Xcode or the Command Line Tools are installed.
    public static func hasCommandLineTools() async -> Bool {
        let request = ChildProcessRequest(executable: "/usr/bin/xcode-select", arguments: ["-p"], environment: [:],
                                          workingDirectory: "/", timeLimit: 5)
        return await ChildProcess.run(request).end == .exited(0)
    }
}

/// One run of the steps of a micro-app.
struct MicroAppPipeline: Sendable {
    let runner: MicroAppRunner
    let app: MicroApp
    let path: String
    let base: [String: String]
    /// The values of the params by name; inside a step also its own `params`.
    var params: [String: String]
    /// The context of the start, the same for every step and library.
    let context: MicroAppContext
    /// `TING_CONTEXT_…` of every source the micro-app and its libraries read.
    let contextEnvironment: [String: String]
    let deadline: Date
    let limit: TimeInterval
    let progress: (@Sendable (MicroAppRunProgress) -> Void)?
    /// The outputs of the finished steps with an `id`.
    var outputs: [String: String] = [:]

    init(runner: MicroAppRunner, app: MicroApp, path: String, base: [String: String], params: [String: String],
         context: MicroAppContext = MicroAppContext(), contextEnvironment: [String: String] = [:],
         deadline: Date, limit: TimeInterval, progress: (@Sendable (MicroAppRunProgress) -> Void)?) {
        self.runner = runner
        self.app = app
        self.path = path
        self.base = base
        self.params = params
        self.context = context
        self.contextEnvironment = contextEnvironment
        self.deadline = deadline
        self.limit = limit
        self.progress = progress
    }

    /// The steps in groups: a step with `stream: true` runs together with the step before it.
    static func groups(_ steps: [MicroAppStep]) -> [[Int]] {
        var groups: [[Int]] = []
        for (i, step) in steps.enumerated() {
            if step.stream, !groups.isEmpty { groups[groups.count - 1].append(i) } else { groups.append([i]) }
        }
        return groups
    }

    mutating func run(stdin: Data) async -> MicroAppRunResult {
        let steps = app.steps
        var input = stdin
        var last = MicroAppRunOutput()
        let showsLive = app.output.targets.contains(.panel)
        for group in Self.groups(steps) {
            if Task.isCancelled { return .cancelled(last) }
            let first = group[0]
            progress?(MicroAppRunProgress(index: first, count: steps.count, kind: steps[first].kind))
            let channels = group.map { _ in MicroAppByteChannel(limit: runner.outputLimit) }
            for k in 1..<max(1, group.count) { channels[k - 1].attachReader() }
            // Delivers the live output held back by the throttle before the run returns, so the
            // last live piece is the whole output and nothing arrives after the result.
            var finishLive: (() -> Void)?
            if group.last == steps.count - 1, showsLive, let progress {
                let index = group.last!
                let kind = steps[index].kind
                let throttle = MicroAppThrottle(interval: 0.08)
                let deliver: @Sendable (Data) -> Void = { latest in
                    progress(MicroAppRunProgress(index: first, count: steps.count, kind: kind,
                                                 liveOutput: MicroAppRunRules.text(latest, cut: true)))
                }
                channels[channels.count - 1].observe { data in
                    throttle.submit(data, deliver: deliver)
                }
                finishLive = { throttle.finish(deliver: deliver) }
            }
            let snapshot = self
            let groupInput = input
            let errors: [Int: MicroAppStepError] = await withTaskGroup(of: (Int, MicroAppStepError?).self) { tasks in
                for (k, index) in group.enumerated() {
                    let source: MicroAppByteChannel? = k > 0 ? channels[k - 1] : nil
                    tasks.addTask {
                        defer { channels[k].finish() }
                        do {
                            try await snapshot.runStep(index, input: groupInput, source: source, output: channels[k])
                            return (index, nil)
                        } catch let error as MicroAppStepError {
                            return (index, error)
                        } catch {
                            return (index, .failed("error", "\(error)"))
                        }
                    }
                }
                var errors: [Int: MicroAppStepError] = [:]
                for await (index, error) in tasks { if let error { errors[index] = error } }
                return errors
            }
            finishLive?()
            if let index = errors.keys.min(), let error = errors[index] {
                return failure(error, index: index)
            }
            if Task.isCancelled { return .cancelled(last) }
            for (k, index) in group.enumerated() {
                let (data, cut) = channels[k].output
                if cut && index != steps.count - 1 {
                    return .stepFailed(MicroAppStepFailure(index: index, count: steps.count, kind: steps[index].kind, note: "output too large",
                        output: MicroAppRunOutput(stderr: "The output of this step is larger than \(MicroAppResultPlan.cutNote(limit: runner.outputLimit).dropFirst("output cut at ".count)); the next step needs all of it.")))
                }
                // Like `$(…)` in the shell, a step output loses its end line breaks as a variable.
                if let id = steps[index].id { outputs[id] = MicroAppRunRules.removingEndNewlines(String(decoding: data, as: UTF8.self)) }
            }
            let (data, cut) = channels[channels.count - 1].output
            input = data
            last = MicroAppRunOutput(stdout: MicroAppRunRules.text(data, cut: cut), stderr: channels[channels.count - 1].stderr, stdoutCut: cut)
        }
        last.stdout = MicroAppRunRules.removingEndNewlines(last.stdout)
        return .success(last)
    }

    private func failure(_ error: MicroAppStepError, index: Int) -> MicroAppRunResult {
        let output = MicroAppRunOutput(stdout: error.stdout, stderr: error.message, stdoutCut: error.stdoutCut, stderrCut: error.stderrCut)
        let note: String
        switch error.reason {
        case .cancelled:
            return .cancelled(output)
        case .timedOut(_, true):
            return .timeout(output)
        case .timedOut(let seconds, false):
            note = MicroAppResultPlan.timeoutNote(seconds: seconds)
        case .exit(let code):
            note = "exit \(code)"
        case .failed(let text):
            note = text
        }
        return .stepFailed(MicroAppStepFailure(index: index, count: app.steps.count, kind: app.steps[index].kind, note: note, output: output))
    }

    // MARK: One step

    /// The time this step may take: its own limit or what is left of the micro-app's.
    private func timeBudget(_ step: MicroAppStep) -> (seconds: TimeInterval, total: Bool) {
        let left = max(0.05, deadline.timeIntervalSinceNow)
        if let own = step.timeLimit, own < left { return (own, false) }
        return (left, true)
    }

    /// The value of a template variable.
    func resolve(_ variable: MicroAppVariable, input: Data) throws -> String {
        switch variable {
        case .input:
            return MicroAppRunRules.removingEndNewlines(String(decoding: input, as: UTF8.self))
        case .param(let name):
            return params[name] ?? ""
        case .step(let id):
            return outputs[id] ?? ""
        case .context(let field):
            return context[field]
        case .env(let name):
            guard let value = base[name] else {
                throw MicroAppStepError.failed("error", "`${\(name)}` is not set: add it to the environment of your login shell and reload the micro-apps folder")
            }
            return value
        case .keychain(let service):
            do {
                return try runner.keychain(service)
            } catch {
                throw MicroAppStepError.failed("error", "`${keychain.\(service)}`: \(error)")
            }
        }
    }

    func render(_ template: MicroAppTemplate, input: Data) throws -> String {
        try template.render { try resolve($0, input: input) }
    }

    /// Runs step `index`. Its input is `source` while it streams, else the `stdin` template or `input`.
    /// The step's own `params` are read first, with the micro-app's params; then the step sees them
    /// over the micro-app's params. A `call` step gives them to the library instead.
    func runStep(_ index: Int, input: Data, source: MicroAppByteChannel?, output: MicroAppByteChannel) async throws {
        let step = app.steps[index]
        var values: [String: String] = [:]
        for field in step.params { values[field.name] = try render(field.value, input: input) }
        if case .call(let library) = step.action {
            try await call(library, index: index, arguments: values, input: input, output: output)
            return
        }
        var scoped = self
        scoped.params.merge(values) { _, own in own }
        try await scoped.runAction(index, input: input, source: source, output: output)
    }

    /// Runs the steps of `library` as one step, with their own params, step ids and outputs.
    private func call(_ library: MicroAppLibrary, index: Int, arguments: [String: String], input: Data,
                      output: MicroAppByteChannel) async throws {
        let step = app.steps[index]
        var stepInput = input
        if let stdin = step.stdin { stepInput = Data(try render(stdin, input: input).utf8) }
        let budget = timeBudget(step)
        // The output of the library reaches the panel while it comes when this is the last step.
        let isLive = index == app.steps.count - 1 && app.output.targets.contains(.panel) && progress != nil
        let inner = MicroApp(id: library.name, description: library.description, params: library.params, input: .none,
                             steps: library.steps, output: MicroApp.Output(targets: isLive ? [.panel] : []))
        let outer = progress
        let count = app.steps.count
        var mapped: (@Sendable (MicroAppRunProgress) -> Void)?
        if let outer {
            let name = library.name
            mapped = { @Sendable inside in
                outer(MicroAppRunProgress(index: index, count: count, kind: .call, liveOutput: inside.liveOutput,
                                          detail: "\(name) › " + (inside.detail ?? inside.kind.rawValue)))
            }
        }
        var nested = MicroAppPipeline(runner: runner, app: inner, path: path, base: base,
                                      params: MicroAppRunRules.paramValues(library.params, values: arguments),
                                      context: context, contextEnvironment: contextEnvironment,
                                      deadline: Date().addingTimeInterval(budget.seconds), limit: budget.seconds, progress: mapped)
        let result = await nested.run(stdin: stepInput)
        switch result {
        case .success(let out):
            output.write(Data(out.stdout.utf8))
        case .cancelled:
            throw MicroAppStepError(reason: .cancelled)
        case .timeout(let out):
            var error = MicroAppStepError(reason: .timedOut(seconds: budget.seconds.rounded(), total: budget.total), message: out.stderr)
            error.stdout = out.stdout
            throw error
        case .stepFailed(let failure):
            var error = MicroAppStepError.failed(failure.note, "\(library.name) › \(failure.stepNote): \(failure.output.stderr)")
            error.stdout = failure.output.stdout
            error.stdoutCut = failure.output.stdoutCut
            throw error
        case .failure(let code, let out):
            var error = MicroAppStepError(reason: .exit(code), message: out.stderr)
            error.stdout = out.stdout
            throw error
        case .toolNotFound(let tool):
            throw MicroAppStepError.failed("not started", "tool not found: \(tool)")
        }
    }

    private func runAction(_ index: Int, input: Data, source: MicroAppByteChannel?, output: MicroAppByteChannel) async throws {
        let step = app.steps[index]
        var stepInput = input
        if let stdin = step.stdin { stepInput = Data(try render(stdin, input: input).utf8) }
        let budget = timeBudget(step)
        switch step.action {
        case .command(let code):
            try await runProgram(step, executable: runner.shell, arguments: ["-c", code], code: code, input: stepInput, source: source,
                                 output: output, budget: budget)
        case .python(let code):
            guard let python = MicroAppRunner.find("python3", inPATH: path) else {
                throw MicroAppStepError.failed("not started", "tool not found: python3")
            }
            try await runProgram(step, executable: python, arguments: ["-I", "-c", code], code: code, input: stepInput, source: source,
                                 output: output, budget: budget)
        case .text(let template):
            output.write(Data(try render(template, input: stepInput).utf8))
        case .json(let jsonPath):
            do {
                output.write(Data(try jsonPath.pick(from: stepInput).utf8))
            } catch let error as MicroAppJSONPath.PickError {
                throw MicroAppStepError.failed("error", "json `\(jsonPath)`: \(error)")
            }
        case .open(let target, let appName):
            let resolved = try render(target, input: stepInput).trimmingCharacters(in: .whitespacesAndNewlines)
            let name = try appName.map { try render($0, input: stepInput) }
            try await withDeadline(budget) { try await openTarget(resolved, app: name) }
            output.write(stepInput)
        case .notify(let message, let title):
            let text = try render(message, input: stepInput)
            let heading = try title.map { try render($0, input: stepInput) } ?? app.shownName
            try await withDeadline(budget) {
                do {
                    try await runner.notify(heading, text)
                } catch let error as MicroAppStepError {
                    throw error
                } catch {
                    throw MicroAppStepError.failed("error", "the notification was not shown: \(error.localizedDescription)")
                }
            }
            output.write(stepInput)
        case .url(let urlStep):
            let request: MicroAppHTTPRequest
            do {
                request = try MicroAppHTTPRequest.build(urlStep) { try resolve($0, input: stepInput) }
            } catch let error as MicroAppHTTPRequest.BuildError {
                throw MicroAppStepError.failed("error", error.description)
            }
            try await withDeadline(budget) { try await send(request, output: output) }
        case .call:
            // `runStep` runs a call before it gets here.
            break
        case .keys(let keys):
            try await withDeadline(budget) { try await deliver(.keys(keys)) }
            output.write(stepInput)
        case .paste(let template):
            let text = try render(template, input: stepInput)
            if !text.isEmpty {
                try await withDeadline(budget) { try await deliver(.paste(text, keepOnClipboard: false)) }
            }
            output.write(stepInput)
        case .ai(let aiStep):
            let request: MicroAppHTTPRequest
            do {
                request = try MicroAppHTTPRequest.build(aiStep) { try resolve($0, input: stepInput) }
            } catch let error as MicroAppHTTPRequest.BuildError {
                throw MicroAppStepError.failed("error", error.description)
            }
            try await withDeadline(budget) { try await ask(request, provider: aiStep.provider, output: output) }
        }
    }

    /// Sends a `keys` or `paste` step through the runner's keyboard.
    private func deliver(_ action: MicroAppKeyboardAction) async throws {
        guard let keyboard = runner.keyboard else {
            throw MicroAppStepError.failed("not sent", "only SwiftKey sends key presses and pasted text to an app")
        }
        do {
            try await keyboard(action)
        } catch let error as MicroAppStepError {
            throw error
        } catch is CancellationError {
            throw MicroAppStepError(reason: .cancelled)
        } catch {
            throw MicroAppStepError.failed("not sent", error.localizedDescription)
        }
    }

    private func runProgram(_ step: MicroAppStep, executable: String, arguments: [String], code: String, input: Data,
                            source: MicroAppByteChannel?, output: MicroAppByteChannel,
                            budget: (seconds: TimeInterval, total: Bool)) async throws {
        var extra = contextEnvironment
        // Only the step outputs the code reads: a large output in every variable could stop the start.
        for (id, value) in outputs {
            let name = MicroAppStep.environmentName(forStep: id)
            if code.contains(name) { extra[name] = value }
        }
        for field in step.params { extra[MicroApp.environmentName(for: field.name)] = params[field.name] ?? "" }
        for field in step.env { extra[field.name] = try render(field.value, input: input) }
        let request = ChildProcessRequest(
            executable: executable, arguments: arguments,
            environment: MicroAppRunRules.environment(base: base, path: path, params: app.params, values: params, extra: extra),
            workingDirectory: runner.workingDirectory, stdin: source == nil ? input : Data(), timeLimit: budget.seconds,
            outputLimit: runner.outputLimit, stdinSource: source, onStdout: { output.write($0) })
        let outcome = await ChildProcess.run(request)
        var error = MicroAppStepError(reason: .cancelled,
                                      message: MicroAppRunRules.text(outcome.stderr, cut: outcome.stderrCut),
                                      stdout: MicroAppRunRules.text(outcome.stdout, cut: outcome.stdoutCut),
                                      stdoutCut: outcome.stdoutCut, stderrCut: outcome.stderrCut)
        switch outcome.end {
        case .exited(0):
            output.stderr = error.message
            return
        case .exited(let code):
            error.reason = .exit(code)
        case .timedOut:
            error.reason = .timedOut(seconds: budget.seconds.rounded(), total: budget.total)
        case .cancelled:
            error.reason = .cancelled
        case .notStarted(let code):
            error.reason = .failed("not started")
            error.message = "\(executable): \(String(cString: strerror(code)))"
        }
        throw error
    }

    private func openTarget(_ target: String, app name: String?) async throws {
        guard !target.isEmpty, !target.hasPrefix("-") else {
            throw MicroAppStepError.failed("error", "`\(target)` is not a URL or a file path")
        }
        let expanded = target.hasPrefix("~") ? (target as NSString).expandingTildeInPath : target
        if let open = runner.open {
            try await open(expanded, name)
            return
        }
        var arguments: [String] = []
        if let name, !name.isEmpty { arguments += ["-a", name] }
        arguments.append(expanded)
        let request = ChildProcessRequest(executable: "/usr/bin/open", arguments: arguments,
                                          environment: MicroAppRunRules.environment(base: base, path: path, params: [], values: [:]),
                                          workingDirectory: runner.workingDirectory, timeLimit: 30, outputLimit: 64 * 1024)
        let outcome = await ChildProcess.run(request)
        if outcome.end == .cancelled { throw MicroAppStepError(reason: .cancelled) }
        guard outcome.end == .exited(0) else {
            let text = String(decoding: outcome.stderr, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw MicroAppStepError.failed("error", text.isEmpty ? "cannot open `\(expanded)`" : text)
        }
    }

    /// Sends a `url` request and writes the response body while it comes.
    private func send(_ request: MicroAppHTTPRequest, output: MicroAppByteChannel) async throws {
        let response = try await perform(request)
        guard (200..<300).contains(response.status) else {
            let body = try await collect(response.body, limit: runner.outputLimit)
            var error = MicroAppStepError.failed("HTTP \(response.status)",
                                                 "\(request.method) \(Self.shown(request.url)) answered HTTP \(response.status) \(HTTPURLResponse.localizedString(forStatusCode: response.status))")
            error.stdout = String(decoding: body, as: UTF8.self)
            throw error
        }
        do {
            for try await chunk in response.body { output.write(chunk) }
        } catch {
            throw Self.networkError(error, request: request)
        }
    }

    /// Sends an `ai` request and writes the answer while it comes.
    private func ask(_ request: MicroAppHTTPRequest, provider: MicroAppStep.AIStep.Provider, output: MicroAppByteChannel) async throws {
        let response = try await perform(request)
        guard (200..<300).contains(response.status) else {
            let body = try await collect(response.body, limit: 64 * 1024)
            throw MicroAppStepError.failed("HTTP \(response.status)",
                                           "\(provider.rawValue) at \(Self.shown(request.url)): \(MicroAppAIStreamDecoder.errorMessage(body: body))")
        }
        var decoder = MicroAppAIStreamDecoder(provider: provider)
        do {
            for try await chunk in response.body {
                output.write(Data(try decoder.feed(chunk).utf8))
            }
            output.write(Data(try decoder.finish().utf8))
        } catch let failure as MicroAppAIStreamDecoder.Failure {
            var error = MicroAppStepError.failed("error", "\(provider.rawValue): \(failure)")
            error.stdout = MicroAppRunRules.text(output.output.data, cut: true)
            throw error
        } catch {
            throw Self.networkError(error, request: request)
        }
    }

    private func perform(_ request: MicroAppHTTPRequest) async throws -> MicroAppHTTPResponse {
        do {
            return try await runner.http(request)
        } catch let error as MicroAppStepError {
            throw error
        } catch {
            throw Self.networkError(error, request: request)
        }
    }

    private func collect(_ body: AsyncThrowingStream<Data, Error>, limit: Int) async throws -> Data {
        var data = Data()
        do {
            for try await chunk in body {
                MicroAppRunRules.append(chunk, to: &data, limit: limit)
            }
        } catch is CancellationError {
            throw MicroAppStepError(reason: .cancelled)
        } catch {}
        return data
    }

    static func networkError(_ error: Error, request: MicroAppHTTPRequest) -> MicroAppStepError {
        if error is CancellationError || (error as? URLError)?.code == .cancelled { return MicroAppStepError(reason: .cancelled) }
        if let stepError = error as? MicroAppStepError { return stepError }
        return .failed("network error", "\(request.method) \(shown(request.url)): \(error.localizedDescription)")
    }

    /// The URL without its query and fragment, so a key in the query is not shown.
    static func shown(_ url: String) -> String {
        guard var components = URLComponents(string: url) else { return url }
        let hadQuery = components.query != nil
        components.query = nil
        components.fragment = nil
        return (components.string ?? url) + (hadQuery ? "?…" : "")
    }

    /// Runs `operation`; past `budget` it is cancelled and the step times out.
    private func withDeadline(_ budget: (seconds: TimeInterval, total: Bool), _ operation: @escaping @Sendable () async throws -> Void) async throws {
        try await withThrowingTaskGroup(of: Bool.self) { group in
            group.addTask { try await operation(); return true }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(budget.seconds * 1_000_000_000))
                return false
            }
            defer { group.cancelAll() }
            do {
                guard let finished = try await group.next() else { return }
                if !finished { throw MicroAppStepError(reason: .timedOut(seconds: budget.seconds.rounded(), total: budget.total)) }
            } catch is CancellationError {
                throw MicroAppStepError(reason: .cancelled)
            }
        }
    }
}

/// Delivers the latest value at most once per `interval`; a value that comes too early is
/// delivered when the interval has passed, unless a newer one replaced it.
final class MicroAppThrottle: @unchecked Sendable {
    private let lock = NSLock()
    /// Held while a value is delivered, so deliveries never overlap or arrive out of order.
    private let deliveryLock = NSLock()
    private let interval: TimeInterval
    private var last = Date.distantPast
    private var pending: (value: Data, number: Int)?
    private var scheduled = false
    private var finished = false
    /// The number of the last value submitted, and of the last one delivered.
    private var submitted = 0
    private var delivered = 0

    init(interval: TimeInterval) {
        self.interval = interval
    }

    func submit(_ value: Data, deliver: @escaping @Sendable (Data) -> Void) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        submitted += 1
        let number = submitted
        let wait = interval - Date().timeIntervalSince(last)
        if wait <= 0 && !scheduled {
            last = Date()
            lock.unlock()
            send(value, number: number, deliver: deliver)
            return
        }
        pending = (value, number)
        guard !scheduled else { lock.unlock(); return }
        scheduled = true
        lock.unlock()
        DispatchQueue.global().asyncAfter(deadline: .now() + max(0, wait)) { [self] in
            lock.lock()
            let held = pending
            pending = nil
            scheduled = false
            last = Date()
            lock.unlock()
            if let held { send(held.value, number: held.number, deliver: deliver) }
        }
    }

    /// Delivers the value still held back, at once; nothing submitted after arrives, and nothing
    /// older than what was delivered arrives later.
    func finish(deliver: @Sendable (Data) -> Void) {
        lock.lock()
        let held = finished ? nil : pending
        pending = nil
        finished = true
        lock.unlock()
        if let held { send(held.value, number: held.number, deliver: deliver) }
    }

    private func send(_ value: Data, number: Int, deliver: (Data) -> Void) {
        deliveryLock.lock()
        defer { deliveryLock.unlock() }
        guard number > delivered else { return }
        delivered = number
        deliver(value)
    }
}
