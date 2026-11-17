import Darwin
import Foundation
import SwiftKeyCore

/// Headless front end to the exact engine used by SwiftKey. No config, approvals, remembered values,
/// clipboard reads/writes or panels. Naming a file with `run` explicitly authorizes its execution.
package enum MicroAppCLI {
    package static let usage = """
    Usage:
      swiftkey-micro check [--libs DIR] FILE.yaml [FILE.yaml ...]
      swiftkey-micro run FILE.yaml [--param NAME=VALUE ...] [--context SOURCE.FIELD=VALUE ...] [--input TEXT] [--timeout SECONDS]
                     [--libs DIR] [--verbose] [--allow-effects]

    Libraries (call, inherit) come from libs/ next to FILE.yaml, or from --libs DIR.
    A file inside a folder named libs is checked as a library.

    Input: piped stdin, or --input TEXT; empty when stdin is a terminal.
    Output: the final result on stdout; diagnostics and optional step progress on stderr.
    YAML output.to is ignored: the clipboard is never read or changed.
    Context: run never reads the active app, Finder, the browser or the selection. --context gives
    a value, such as --context app.name=Safari; every other value of the file's context is empty.
    keys and paste steps never send anything: each prints a note on stderr and passes its input on.
    --allow-effects permits open and notify steps (disabled by default).
    Shell/Python and HTTP/AI steps run with your full rights and may change files or cost money.
    Environment variables come from this terminal, not a second login shell.
    No config, approvals or remembered values are read or written.

    Exit codes: 0 success, 1 script/check failure, 2 usage/input error, 124 timeout, 130 cancelled.
    """

    struct Options: Equatable {
        var file: String
        var params: [String: String] = [:]
        var context = MicroAppContext()
        var input: String?
        var timeout: TimeInterval?
        var verbose = false
        var allowEffects = false
        var libs: String?
    }

    struct UsageError: Error, CustomStringConvertible {
        var description: String
        init(_ text: String) { description = text }
    }

    static func parse(_ args: [String]) throws -> Options {
        guard let file = args.first, !file.hasPrefix("-") else { throw UsageError("run needs a YAML file") }
        var options = Options(file: file)
        var i = 1
        while i < args.count {
            let flag = args[i]
            i += 1
            switch flag {
            case "--verbose": options.verbose = true
            case "--allow-effects": options.allowEffects = true
            case "--libs":
                guard i < args.count else { throw UsageError("--libs needs a folder") }
                options.libs = args[i]; i += 1
            case "--param", "--context", "--input", "--timeout":
                guard i < args.count else { throw UsageError("\(flag) needs a value") }
                let value = args[i]; i += 1
                switch flag {
                case "--param":
                    guard let eq = value.firstIndex(of: "="), eq != value.startIndex else {
                        throw UsageError("--param needs NAME=VALUE")
                    }
                    let name = String(value[..<eq])
                    guard options.params[name] == nil else { throw UsageError("duplicate parameter `\(name)`") }
                    options.params[name] = String(value[value.index(after: eq)...])
                case "--context":
                    guard let eq = value.firstIndex(of: "="), eq != value.startIndex else {
                        throw UsageError("--context needs SOURCE.FIELD=VALUE, such as app.name=Safari")
                    }
                    let name = String(value[..<eq])
                    let parts = name.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
                    guard parts.count == 2, let source = MicroAppContextSource(rawValue: parts[0]),
                          let field = MicroAppContextField(source: source, name: parts[1]) else {
                        let known = MicroAppContextField.all.map(\.description).joined(separator: ", ")
                        throw UsageError("unknown context value `\(name)`; use one of: \(known)")
                    }
                    guard options.context.values[field] == nil else { throw UsageError("duplicate context value `\(name)`") }
                    options.context[field] = String(value[value.index(after: eq)...])
                case "--input":
                    guard options.input == nil else { throw UsageError("--input was given twice") }
                    options.input = value
                default:
                    guard let n = Int(value), (1...MicroAppChecker.maxTimeLimit).contains(n) else {
                        throw UsageError("--timeout must be from 1 to \(MicroAppChecker.maxTimeLimit) seconds")
                    }
                    options.timeout = TimeInterval(n)
                }
            default: throw UsageError("unknown option `\(flag)`")
            }
        }
        return options
    }

    static func load(_ file: String, libs: String? = nil) throws -> MicroApp {
        guard file.hasSuffix(".yaml") else { throw UsageError("a script file must end in .yaml") }
        let handle: FileHandle
        do { handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: file)) }
        catch { throw UsageError("cannot read \(file): \(error.localizedDescription)") }
        defer { try? handle.close() }
        let data = try handle.read(upToCount: MicroAppChecker.maxFileSize + 1) ?? Data()
        guard data.count <= MicroAppChecker.maxFileSize else { throw UsageError(MicroAppChecker.tooLargeMessage) }
        guard let text = String(data: data, encoding: .utf8) else { throw UsageError(MicroAppChecker.notUTF8Message) }
        let folder = libs.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? MicroAppCheckCommand.libraryFolder(for: file)
        return try MicroAppChecker.check(text, fileName: file, libraries: MicroAppLibraries.read(folder: folder)).get()
    }

    static func validate(_ options: Options, app: MicroApp) throws {
        for name in options.params.keys.sorted() where !app.params.contains(where: { $0.name == name }) {
            throw UsageError("unknown parameter `\(name)`")
        }
        for param in app.params {
            let value = options.params[param.name] ?? param.defaultValue
            if param.required && (value == nil || value!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                throw UsageError("missing required parameter: --param \(param.name)=VALUE")
            }
            if case .choice(let choices) = param.kind, let value, !choices.contains(value) {
                throw UsageError("parameter `\(param.name)` must be one of: \(choices.joined(separator: ", "))")
            }
        }
        let sources = app.requiredContext
        for field in options.context.values.keys.sorted(by: { $0.description < $1.description }) where !sources.contains(field.source) {
            throw UsageError("the file does not read `\(field.source.rawValue)`: add it to `context:` or leave out --context \(field)")
        }
        if !options.allowEffects, let step = app.allSteps.first(where: { $0.kind == .open || $0.kind == .notify }) {
            throw UsageError("`\(step.kind.rawValue)` requires --allow-effects; no steps were run")
        }
    }

    package static func main(_ args: [String]) async -> Int32 {
        if args.isEmpty || args == ["--help"] || args == ["-h"] {
            out(usage + "\n")
            return 0
        }
        if args.first == MicroAppCheckCommand.option {
            var files = Array(args.dropFirst())
            var libs: String?
            if let at = files.firstIndex(of: "--libs") {
                guard at + 1 < files.count else { err("swiftkey-micro: --libs needs a folder\n"); return 2 }
                libs = files[at + 1]
                files.removeSubrange(at...(at + 1))
            }
            let report = MicroAppCheckCommand.run(files, read: { path in
                let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
                defer { try? handle.close() }
                return try handle.read(upToCount: MicroAppChecker.maxFileSize + 1) ?? Data()
            }, libraries: { path in
                MicroAppLibraries.read(folder: libs.map { URL(fileURLWithPath: $0, isDirectory: true) }
                    ?? MicroAppCheckCommand.libraryFolder(for: path))
            })
            // The checker of the micro-apps folder, including duplicate-id validation.
            report.output.forEach { out($0 + "\n") }
            report.errors.forEach { err($0 + "\n") }
            return report.exitCode
        }
        do {
            guard args.first == "run" else { throw UsageError("expected `run` or `check`; use --help") }
            let options = try parse(Array(args.dropFirst()))
            let app = try load(options.file, libs: options.libs)
            try validate(options, app: app)
            let input: String
            if let text = options.input { input = text }
            else if isatty(STDIN_FILENO) == 0 {
                let bytes = FileHandle.standardInput.readDataToEndOfFile()
                guard let text = String(data: bytes, encoding: .utf8) else { throw UsageError("stdin is not UTF-8 text") }
                input = text
            } else { input = "" }
            var runner = MicroAppRunner()
            let environment = ProcessInfo.processInfo.environment
            let path = environment["PATH"] ?? MicroAppRunRules.defaultPATH
            runner.environment = environment
            runner.path = { path }
            runner.timeLimit = options.timeout
            // CLI runs in the current folder, like other console programs.
            runner.workingDirectory = FileManager.default.currentDirectoryPath
            // Keys and text would go to this terminal: the console tool only says what SwiftKey would send.
            runner.keyboard = { action in err("swiftkey-micro: \(action.summary): not sent; only SwiftKey sends to an app\n") }
            let verbose = options.verbose
            let progress: (@Sendable (MicroAppRunProgress) -> Void)?
            if verbose {
                progress = { update in
                    if update.liveOutput == nil { err(update.label + "\n") }
                }
            } else { progress = nil }
            let task = Task<MicroAppRunResult, Never> {
                await runner.run(app, values: options.params, stdin: input, context: options.context, progress: progress)
            }
            // Dispatch signal handlers cancel the task, which stops child process groups and HTTP.
            signal(SIGINT, SIG_IGN)
            signal(SIGTERM, SIG_IGN)
            let signals = [SIGINT, SIGTERM].map { number in
                let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
                source.setEventHandler { task.cancel() }
                source.resume()
                return source
            }
            let result = await task.value
            signals.forEach { $0.cancel() }
            return report(result)
        } catch let failure as MicroAppFailure {
            err(failure.description + "\n")
            return 1
        } catch {
            err("swiftkey-micro: \(error)\n")
            return 2
        }
    }

    static func report(_ result: MicroAppRunResult) -> Int32 {
        switch result {
        case .success(let output):
            if !output.stdout.isEmpty { out(output.stdout + "\n") }
            if !output.stderr.isEmpty { err(output.stderr) }
            if output.stdoutCut || output.stderrCut { err(MicroAppResultPlan.cutNote() + "\n") }
            return 0
        case .cancelled: err("cancelled\n"); return 130
        case .timeout(let output):
            err("timeout\n" + output.stderr + output.stdout + "\n")
            return 124
        case .toolNotFound(let name): err("tool not found: \(name)\n"); return 1
        case .failure(let code, let output):
            err("exit \(code)\n" + output.stderr + output.stdout + "\n")
            return 1
        case .stepFailed(let failure):
            err("\(failure.stepNote): \(failure.note)\n" + failure.output.stderr + "\n" + failure.output.stdout)
            if !failure.output.stdout.isEmpty { err("\n") }
            if failure.note.hasPrefix("stopped after ") { return 124 }
            return 1
        }
    }

    static func out(_ text: String) { FileHandle.standardOutput.write(Data(text.utf8)) }
    static func err(_ text: String) { FileHandle.standardError.write(Data(text.utf8)) }
}
