import Foundation

/// What the command printed. Each stream is cut at `MicroAppRunRules.outputLimit` bytes.
public struct MicroAppRunOutput: Equatable, Sendable {
    public var stdout: String
    public var stderr: String
    /// `true` when stdout was longer than the limit and the rest was dropped.
    public var stdoutCut: Bool
    /// `true` when stderr was longer than the limit and the rest was dropped.
    public var stderrCut: Bool

    public init(stdout: String = "", stderr: String = "", stdoutCut: Bool = false, stderrCut: Bool = false) {
        self.stdout = stdout
        self.stderr = stderr
        self.stdoutCut = stdoutCut
        self.stderrCut = stderrCut
    }
}

/// The one result of running a micro-app.
public enum MicroAppRunResult: Equatable, Sendable {
    /// Exit code 0. `stdout` has its end newlines removed.
    case success(MicroAppRunOutput)
    /// A non-zero exit code (128 + the signal number when a signal ended the command).
    case failure(exitCode: Int32, MicroAppRunOutput)
    /// The time limit passed; the command and its children were stopped. The output is what came before.
    case timeout(MicroAppRunOutput)
    /// The run was cancelled; the command and its children were stopped.
    case cancelled(MicroAppRunOutput)
    /// A program of `tools` is not on the PATH; nothing ran.
    case toolNotFound(String)
    /// A step of a `steps` micro-app failed; the steps after it did not run.
    case stepFailed(MicroAppStepFailure)

    public var output: MicroAppRunOutput? {
        switch self {
        case .success(let o), .failure(_, let o), .timeout(let o), .cancelled(let o): return o
        case .stepFailed(let f): return f.output
        case .toolNotFound: return nil
        }
    }
}

/// The failure of one step.
public struct MicroAppStepFailure: Equatable, Sendable {
    /// 0-based.
    public var index: Int
    public var count: Int
    public var kind: MicroAppStep.Kind
    /// A short note, such as `exit 1`, `HTTP 404` or `stopped after 20 s`.
    public var note: String
    /// `stderr` holds the error text; `stdout` what the step printed before.
    public var output: MicroAppRunOutput

    public init(index: Int, count: Int, kind: MicroAppStep.Kind, note: String, output: MicroAppRunOutput) {
        self.index = index
        self.count = count
        self.kind = kind
        self.note = note
        self.output = output
    }

    /// `step 2 of 3 · ai`; just the kind for a micro-app of one step.
    public var stepNote: String {
        count > 1 ? "step \(index + 1) of \(count) · \(kind.rawValue)" : kind.rawValue
    }
}

/// What a running micro-app is doing, for the working panel.
public struct MicroAppRunProgress: Equatable, Sendable {
    /// 0-based index of the first running step.
    public var index: Int
    public var count: Int
    public var kind: MicroAppStep.Kind
    /// The output of the last step so far, once the last step runs; `nil` before.
    public var liveOutput: String?
    /// For a `call` step: the library and its running step, such as `translate › ai`.
    public var detail: String?

    public init(index: Int, count: Int, kind: MicroAppStep.Kind, liveOutput: String? = nil, detail: String? = nil) {
        self.index = index
        self.count = count
        self.kind = kind
        self.liveOutput = liveOutput
        self.detail = detail
    }

    /// `Step 2 of 3 · ai`, or `Step 1 of 1 · call translate › ai`.
    public var label: String { "Step \(index + 1) of \(count) · \(kind.rawValue)" + (detail.map { " " + $0 } ?? "") }
}

/// Pure rules of a micro-app run: limits, environment, output text.
public enum MicroAppRunRules {
    /// Each of stdout and stderr is cut at 1 MB.
    public static let outputLimit = 1_048_576
    /// The command and its children are stopped after 60 seconds.
    public static let timeLimit: TimeInterval = 60
    /// Added after SwiftKey's own PATH when the login shell does not give one.
    public static let fallbackDirectories = ["/opt/homebrew/bin", "/usr/local/bin"]
    /// Used when SwiftKey itself has no PATH.
    public static let defaultPATH = "/usr/bin:/bin:/usr/sbin:/sbin"

    /// The user's environment without locale and stray `TING_` variables, with `PATH`, one `TING_<NAME>`
    /// per parameter and the `extra` variables (step outputs and a step's `env`). A missing value takes
    /// the parameter's default, or the empty text.
    public static func environment(base: [String: String], path: String, params: [MicroApp.Param],
                                   values: [String: String], extra: [String: String] = [:]) -> [String: String] {
        var env = base.filter { key, _ in
            !key.hasPrefix("TING_") && key != "LANG" && !key.hasPrefix("LC_")
        }
        env["PATH"] = path
        for param in params {
            env[param.environmentName] = values[param.name] ?? param.defaultValue ?? ""
        }
        for (key, value) in extra { env[key] = value }
        return env
    }

    /// The value of every param by name: the given value, else the default, else the empty text.
    public static func paramValues(_ params: [MicroApp.Param], values: [String: String]) -> [String: String] {
        Dictionary(params.map { ($0.name, values[$0.name] ?? $0.defaultValue ?? "") }, uniquingKeysWith: { a, _ in a })
    }

    /// Appends as much of `chunk` as fits under `limit`. Returns `true` when something was dropped.
    @discardableResult
    public static func append(_ chunk: Data, to buffer: inout Data, limit: Int = outputLimit) -> Bool {
        let room = max(0, limit - buffer.count)
        if chunk.count <= room {
            buffer.append(chunk)
            return false
        }
        buffer.append(chunk.prefix(room))
        return true
    }

    /// The output bytes as text. A cut output loses a last character that the cut split in two.
    public static func text(_ data: Data, cut: Bool) -> String {
        var bytes = [UInt8](data)
        if cut { bytes.removeLast(incompleteUTF8Tail(bytes)) }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// The number of bytes at the end of `bytes` that start a UTF-8 character but do not finish it.
    static func incompleteUTF8Tail(_ bytes: [UInt8]) -> Int {
        var back = 0
        while back < min(4, bytes.count) {
            let byte = bytes[bytes.count - 1 - back]
            back += 1
            if byte & 0xC0 == 0x80 { continue } // continuation byte
            let needed: Int
            if byte & 0x80 == 0 { needed = 1 } else if byte & 0xE0 == 0xC0 { needed = 2 } else if byte & 0xF0 == 0xE0 { needed = 3 } else if byte & 0xF8 == 0xF0 { needed = 4 } else { return 0 }
            return back < needed ? back : 0
        }
        return 0
    }

    /// `text` without the newlines (`\n`, `\r`) at its end.
    public static func removingEndNewlines(_ text: String) -> String {
        var s = Substring(text)
        while let last = s.unicodeScalars.last, last == "\n" || last == "\r" {
            s = Substring(s.unicodeScalars.dropLast())
        }
        return String(s)
    }

    /// The directories of a PATH, in order, without empty entries and repeats.
    public static func directories(ofPATH path: String) -> [String] {
        var seen: Set<String> = []
        return path.split(separator: ":").map(String.init).filter { seen.insert($0).inserted }
    }

    /// SwiftKey's PATH (or `defaultPATH`) with `fallbackDirectories` added at the end, without repeats.
    public static func fallbackPATH(tingPATH: String?) -> String {
        let base = tingPATH.flatMap { $0.isEmpty ? nil : $0 } ?? defaultPATH
        return directories(ofPATH: base + ":" + fallbackDirectories.joined(separator: ":")).joined(separator: ":")
    }

    // MARK: Login shell PATH

    public static let pathBeginMarker = "__TING_PATH_BEGIN__"
    public static let pathEndMarker = "__TING_PATH_END__"

    public static let environmentBeginMarker = "__TING_ENV_BEGIN__"
    public static let environmentEndMarker = "__TING_ENV_END__"

    /// The arguments for the user's login shell: its PATH, then its whole environment.
    /// The same text works in zsh, bash and fish.
    public static let pathShellArguments = ["-l", "-i", "-c",
        "echo \(pathBeginMarker); /usr/bin/printenv PATH; echo \(pathEndMarker); " +
        "echo \(environmentBeginMarker); /usr/bin/env -0; echo; echo \(environmentEndMarker)"]

    /// Shell variables that describe the shell itself, not the user's setup.
    public static let shellOwnVariables: Set<String> = ["PWD", "OLDPWD", "SHLVL", "_"]

    /// The environment between the markers of the shell output (`env -0`), without the shell's own
    /// variables, or `nil` when there is none.
    public static func environmentFromShellOutput(_ output: Data) -> [String: String]? {
        let begin = Data((environmentBeginMarker + "\n").utf8)
        let end = Data(("\n" + environmentEndMarker).utf8)
        guard let b = output.range(of: begin),
              let e = output.range(of: end, options: .backwards, in: b.upperBound..<output.endIndex) else { return nil }
        let bytes = output[b.upperBound..<e.lowerBound]
        var result: [String: String] = [:]
        for entry in bytes.split(separator: 0) {
            let text = String(decoding: entry, as: UTF8.self)
            guard let eq = text.firstIndex(of: "="), eq != text.startIndex else { continue }
            let key = String(text[..<eq])
            guard !shellOwnVariables.contains(key) else { continue }
            result[key] = String(text[text.index(after: eq)...])
        }
        return result.isEmpty ? nil : result
    }

    /// The PATH between the markers of the shell output, or `nil` when there is none.
    /// Anything a shell start-up file prints before or after the markers is ignored.
    public static func pathFromShellOutput(_ output: String) -> String? {
        guard let begin = output.range(of: pathBeginMarker + "\n"),
              let end = output.range(of: "\n" + pathEndMarker, range: begin.upperBound..<output.endIndex)
        else { return nil }
        let path = output[begin.upperBound..<end.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty || path.contains("\n") ? nil : path
    }
}
