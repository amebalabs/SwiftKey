import Foundation

/// A micro-app: one shell command or a list of steps, with a name, parameters, an input and an output.
/// The format is described in `docs/micro-apps/FORMAT.md`.
public struct MicroApp: Equatable, Sendable {
    public enum Input: String, Equatable, Sendable, CaseIterable {
        /// The clipboard text goes to the command's stdin.
        case clipboard
        /// The command gets an empty stdin.
        case none
    }

    public enum OutputTarget: String, Equatable, Sendable, CaseIterable {
        case clipboard, panel
        /// Pasted into the app where the micro-app started.
        case app
    }

    /// How the result panel shows stdout.
    public enum OutputStyle: String, Equatable, Sendable, CaseIterable {
        case text, markdown, code, console
    }

    public struct Output: Equatable, Sendable {
        /// In file order, without duplicates.
        public var targets: [OutputTarget]
        public var style: OutputStyle

        public init(targets: [OutputTarget], style: OutputStyle = .markdown) {
            self.targets = targets
            self.style = style
        }
    }

    public struct Param: Equatable, Sendable {
        public enum Kind: Equatable, Sendable {
            case text
            /// The allowed values, in file order.
            case choice([String])
        }

        /// `a-z`, `0-9` and `_` only.
        public var name: String
        public var kind: Kind
        public var required: Bool
        /// Set for an optional parameter, never for a required one; one of the choices for a choice.
        public var defaultValue: String?
        public var prompt: String?

        public init(name: String, kind: Kind, required: Bool, defaultValue: String? = nil, prompt: String? = nil) {
            self.name = name
            self.kind = kind
            self.required = required
            self.defaultValue = defaultValue
            self.prompt = prompt
        }

        /// The environment variable the command reads: `TING_` + upper-case name.
        public var environmentName: String { MicroApp.environmentName(for: name) }
        /// The prompt, or the name when the file has no prompt.
        public var shownPrompt: String { prompt ?? name }
    }

    /// From the file, or the file name without `.yaml`.
    public var id: String
    /// From the file; `nil` when the file has no `name`.
    public var name: String?
    public var description: String
    public var tools: [String]
    /// Not listed in launcha; still starts from a key binding.
    public var hidden: Bool
    /// Offer the last used parameter values next time (default `true`).
    public var remember: Bool
    public var params: [Param]
    /// The parts of the context the file reads (`context:`), in file order.
    public var context: [MicroAppContextSource]
    public var input: Input
    /// The shell code of a `command` file, exactly as written; `nil` for a `steps` file.
    public var command: String?
    /// The steps, in order. A `command` file has one command step.
    public var steps: [MicroAppStep]
    /// The time limit of the whole run, in seconds.
    public var timeLimit: TimeInterval
    /// `targets` is empty when the file has no `output`: the result is not shown or copied.
    public var output: Output
    /// The whole file text of a `steps` file, shown in the approval panel; empty for a `command` file.
    public var source: String
    /// Every library the micro-app inherits or calls, also through other libraries. Their text
    /// is part of the approval.
    public var libraries: [MicroAppLibrarySource] = []

    /// A micro-app of one shell command.
    public init(id: String, name: String? = nil, description: String, tools: [String] = [], hidden: Bool = false, remember: Bool = true,
                params: [Param] = [], context: [MicroAppContextSource] = [], input: Input, command: String, output: Output,
                timeLimit: TimeInterval = MicroAppRunRules.timeLimit) {
        self.id = id
        self.name = name
        self.description = description
        self.tools = tools
        self.hidden = hidden
        self.remember = remember
        self.params = params
        self.context = context
        self.input = input
        self.command = command
        self.steps = [MicroAppStep(action: .command(command))]
        self.timeLimit = timeLimit
        self.output = output
        self.source = ""
    }

    /// A micro-app of steps.
    public init(id: String, name: String? = nil, description: String, tools: [String] = [], hidden: Bool = false, remember: Bool = true,
                params: [Param] = [], context: [MicroAppContextSource] = [], input: Input, steps: [MicroAppStep], output: Output,
                timeLimit: TimeInterval = MicroAppRunRules.timeLimit, source: String = "") {
        self.id = id
        self.name = name
        self.description = description
        self.tools = tools
        self.hidden = hidden
        self.remember = remember
        self.params = params
        self.context = context
        self.input = input
        self.command = nil
        self.steps = steps
        self.timeLimit = timeLimit
        self.output = output
        self.source = source
    }

    /// What the approval panel shows: the command of a `command` file, the whole text of a `steps`
    /// file, then the text of every library it uses. What the file itself runs is always shown.
    public var approvalText: String {
        let own = source.isEmpty ? (command ?? "") : source
        return libraries.reduce(own) { text, library in
            text + (text.hasSuffix("\n") ? "" : "\n") + "\n# ---- \(library.file) ----\n" + library.text
        }
    }

    /// The programs that must be on the PATH: `tools`, the `tools` of the called libraries, and
    /// `python3` for a python step.
    public var requiredTools: [String] {
        var result = tools
        for tool in steps.requiredTools where !result.contains(tool) { result.append(tool) }
        return result
    }

    /// The context the run needs: the file's own `context` and that of every library it calls,
    /// in documentation order.
    public var requiredContext: [MicroAppContextSource] {
        var sources = Set(context)
        for step in allSteps { if case .call(let library) = step.action { sources.formUnion(library.context) } }
        return sources.sorted()
    }

    /// `true` when a step (also of a called library) or the output sends input to the app
    /// where the micro-app started.
    public var sendsInput: Bool {
        output.targets.contains(.app) || allSteps.contains(where: \.sendsInput)
    }

    /// The name shown in menus: `name`, or the id when the file has no name.
    public var shownName: String { name ?? id }

    public static func environmentName(for paramName: String) -> String { "TING_" + paramName.uppercased() }
}

/// One mistake in a micro-app file.
public struct MicroAppIssue: Equatable, Sendable, CustomStringConvertible {
    /// The file name, as given to the checker.
    public var file: String
    /// 1-based line number.
    public var line: Int
    public var message: String

    public init(file: String, line: Int, message: String) {
        self.file = file
        self.line = line
        self.message = message
    }

    public var description: String { "\(file):\(line): \(message)" }
}

public struct MicroAppFailure: Error, Equatable, Sendable, CustomStringConvertible {
    /// Sorted by line; never empty.
    public var issues: [MicroAppIssue]
    /// The `id` the checker could read from the file: a kebab-case text value. `nil` when the file
    /// is not valid YAML or its `id` is missing or not valid.
    public var id: String?
    /// The `name` the checker could read from the file: a one-line text value; `nil` otherwise.
    public var name: String?
    /// The `hidden` value the checker could read from the file; `nil` when it is missing or not valid.
    public var hidden: Bool?

    public init(issues: [MicroAppIssue], id: String? = nil, name: String? = nil, hidden: Bool? = nil) {
        self.issues = issues
        self.id = id
        self.name = name
        self.hidden = hidden
    }

    public var description: String { issues.map(\.description).joined(separator: "\n") }
}

/// Turns the text of a micro-app file into a `MicroApp` or a list of issues.
public enum MicroAppChecker {
    public static let format = "ting.microapp/2"
    public static let fileExtension = "yaml"
    /// Larger files are reported, not read.
    public static let maxFileSize = 256 * 1024
    public static var tooLargeMessage: String { "the file is larger than \(maxFileSize / 1024) KB" }
    public static let notUTF8Message = "the file is not UTF-8 text"
    public static let topKeys = ["format", "inherit", "id", "name", "description", "tools", "hidden", "remember", "timeout", "params",
                                 "context", "input", "command", "steps", "output"]
    /// The keys of a library file (`libs/NAME.yaml`).
    public static let libraryKeys = ["format", "description", "tools", "timeout", "params", "context", "input", "steps", "output"]
    public static let requiredTopKeys = ["format", "description", "input"]
    /// The longest `timeout` a file can ask for, in seconds.
    public static let maxTimeLimit = 300
    /// Keys every step can have, besides its kind key.
    public static let stepCommonKeys = ["id", "stdin", "timeout", "stream", "params"]
    /// Keys of each step kind, besides the kind key and `stepCommonKeys`.
    public static let stepKeys: [MicroAppStep.Kind: [String]] = [
        .command: ["env"], .python: ["env"],
        .url: ["method", "query", "headers", "body", "form"],
        .ai: ["provider", "model", "key", "system", "base_url", "temperature", "max_tokens"],
        .text: [], .json: [], .open: ["app"], .notify: ["title"], .call: [], .keys: [], .paste: [],
    ]
    /// The most key presses of one `keys` step.
    public static let maxKeyPresses = 100
    public static let paramKeys = ["name", "type", "required", "default", "choices", "prompt"]
    public static let paramTypes = ["text", "choice"]
    public static let outputKeys = ["to", "as"]

    /// `fileName` is the file name or path; its last component is used in issues and gives the id
    /// when the file has none.
    public static func check(_ text: String, fileName: String,
                             libraries: MicroAppLibraries = MicroAppLibraries()) -> Result<MicroApp, MicroAppFailure> {
        check(text, file: (fileName as NSString).lastPathComponent, mode: .app, libraries: libraries, stack: [])
    }

    /// Checks a library file on its own. `fileName` is shown in messages, such as
    /// `libs/translate.yaml`; the library name is the file name without `.yaml`.
    public static func checkLibrary(_ text: String, fileName: String,
                                    libraries: MicroAppLibraries = MicroAppLibraries()) -> Result<MicroAppLibrary, MicroAppFailure> {
        let name = ((fileName as NSString).lastPathComponent as NSString).deletingPathExtension
        let source = MicroAppLibrarySource(name: name, file: fileName, text: text)
        return checkLibrary(source, libraries: libraries, stack: [])
    }

    static func checkLibrary(_ source: MicroAppLibrarySource, libraries: MicroAppLibraries,
                             stack: [String]) -> Result<MicroAppLibrary, MicroAppFailure> {
        guard MicroAppLibraries.isName(source.name) else {
            let issue = MicroAppIssue(file: source.file, line: 1, message: "the library name `\(source.name)` must be kebab-case (a-z and 0-9 words joined by `-`)")
            return .failure(MicroAppFailure(issues: [issue]))
        }
        switch check(source.text, file: source.file, mode: .library(source.name), libraries: libraries, stack: stack + [source.name]) {
        case .failure(let failure):
            return .failure(failure)
        case .success(let app):
            var sources = [source]
            sources.addMissing(app.libraries)
            return .success(MicroAppLibrary(name: source.name, file: source.file, description: app.description, tools: app.tools,
                                            params: app.params, context: app.requiredContext, steps: app.steps, sources: sources))
        }
    }

    enum Mode: Equatable {
        case app
        /// A library with this name.
        case library(String)
    }

    private static func check(_ text: String, file: String, mode: Mode, libraries: MicroAppLibraries,
                              stack: [String]) -> Result<MicroApp, MicroAppFailure> {
        var run = Run(file: file)
        run.text = text
        run.mode = mode
        run.libraries = libraries
        run.stack = stack
        let root: YAMLNode
        do {
            root = try YAMLSubset.parse(text)
        } catch let error as YAMLError {
            return .failure(MicroAppFailure(issues: [MicroAppIssue(file: file, line: error.line, message: error.message)]))
        } catch {
            return .failure(MicroAppFailure(issues: [MicroAppIssue(file: file, line: 1, message: "\(error)")]))
        }
        var app = run.check(root)
        if run.issues.isEmpty, app != nil {
            app!.libraries = run.usedLibraries
            return .success(app!)
        }
        let sorted = run.issues.enumerated().sorted { ($0.element.line, $0.offset) < ($1.element.line, $1.offset) }.map(\.element)
        return .failure(MicroAppFailure(issues: sorted, id: run.explicitID, name: run.parsedName, hidden: run.parsedHidden))
    }

    /// `a-z0-9` words joined by single `-`.
    public static func isKebabCase(_ s: String) -> Bool {
        let words = s.split(separator: "-", omittingEmptySubsequences: false)
        return !s.isEmpty && words.allSatisfy { !$0.isEmpty && $0.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber) } }
    }

    public static func isParamName(_ s: String) -> Bool {
        !s.isEmpty && s.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "_") }
    }

    /// `context` and names that start with `context_`: their `TING_CONTEXT_…` variables belong to SwiftKey.
    public static func isReservedParamName(_ s: String) -> Bool {
        s == "context" || s.hasPrefix("context_")
    }

    public static func isToolName(_ s: String) -> Bool {
        !s.isEmpty && s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "._+-".contains($0)) }
    }

    private struct Run {
        let file: String
        /// The whole file text.
        var text = ""
        var issues: [MicroAppIssue] = []
        /// The `id` key of the file when it is a kebab-case text value.
        var explicitID: String?
        /// The `name` key when it is a valid value, kept for a broken file.
        var parsedName: String?
        /// The `hidden` key when it is a valid value, kept for a broken file.
        var parsedHidden: Bool?
        var mode = Mode.app
        var libraries = MicroAppLibraries()
        /// The libraries being checked, outermost first, to find cycles.
        var stack: [String] = []
        /// Every library this file inherits or calls, also through other libraries.
        var usedLibraries: [MicroAppLibrarySource] = []
        /// Set while the merged text of an `inherit` file is checked: the line of `inherit` and the library file.
        var inherited: (line: Int, file: String)?
        /// The sources of the file's `context` list, known before its steps are checked.
        var declaredContext: [MicroAppContextSource] = []

        init(file: String) { self.file = file }

        mutating func fail(_ line: Int, _ message: String) {
            // A problem in the lines that came from an inherited library: shown on the `inherit`
            // line, with the library file and its own line.
            if let inherited, line >= inheritedLineOffset {
                issues.append(MicroAppIssue(file: file, line: inherited.line,
                                            message: "\(inherited.file):\(line - inheritedLineOffset): \(message)"))
                return
            }
            issues.append(MicroAppIssue(file: file, line: line, message: message))
        }

        /// The checked library `name`, or `nil` after a problem reported on `line`.
        mutating func library(_ name: String, line: Int) -> MicroAppLibrary? {
            guard MicroAppLibraries.isName(name) else {
                fail(line, "`\(name)` is not a library name: use the kebab-case file name of `libs/NAME.yaml` without `.yaml`")
                return nil
            }
            if stack.contains(name) {
                fail(line, "library `\(name)` uses itself: \((stack + [name]).joined(separator: " → "))")
                return nil
            }
            if stack.count >= MicroAppLibraries.maxDepth {
                fail(line, "libraries are nested deeper than \(MicroAppLibraries.maxDepth) levels")
                return nil
            }
            guard let source = libraries.sources[name] else {
                fail(line, "no library `\(name)`: add the file `\(MicroAppLibraries.file(for: name))` next to the micro-apps")
                return nil
            }
            switch MicroAppChecker.checkLibrary(source, libraries: libraries, stack: stack) {
            case .failure(let failure):
                let first = failure.issues.first.map { "\($0.file):\($0.line): \($0.message)" } ?? "problems"
                let more = failure.issues.count > 1 ? " (+\(failure.issues.count - 1) more)" : ""
                fail(line, "library `\(name)` has problems: \(first)\(more)")
                return nil
            case .success(let library):
                usedLibraries.addMissing(library.sources)
                return library
            }
        }

        // MARK: Value helpers

        mutating func string(_ node: YAMLNode, _ what: String, oneLine: Bool = true, nonEmpty: Bool = true) -> String? {
            guard case .scalar(let s) = node else {
                fail(node.line, "`\(what)` must be a text value")
                return nil
            }
            if oneLine && s.value.contains("\n") {
                fail(s.line, "`\(what)` must be one line")
                return nil
            }
            if nonEmpty && s.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                fail(s.line, "`\(what)` must not be empty")
                return nil
            }
            return s.value
        }

        mutating func bool(_ node: YAMLNode, _ what: String) -> Bool? {
            if case .scalar(let s) = node, s.style == .plain {
                if s.value == "true" { return true }
                if s.value == "false" { return false }
            }
            fail(node.line, "`\(what)` must be `true` or `false`")
            return nil
        }

        mutating func list(_ node: YAMLNode, _ what: String) -> [YAMLNode]? {
            guard case .sequence(let items, _) = node else {
                fail(node.line, "`\(what)` must be a list")
                return nil
            }
            return items
        }

        mutating func entries(_ node: YAMLNode, _ what: String, allowed: [String]) -> [String: YAMLEntry]? {
            guard case .mapping(let entries, _) = node else {
                fail(node.line, "`\(what)` must be a map of `key: value` lines")
                return nil
            }
            var result: [String: YAMLEntry] = [:]
            for entry in entries {
                if allowed.contains(entry.key) {
                    result[entry.key] = entry
                } else {
                    fail(entry.keyLine, "unknown key `\(entry.key)` in \(what); allowed: \(allowed.joined(separator: ", "))")
                }
            }
            return result
        }

        mutating func oneOf(_ node: YAMLNode, _ what: String, _ values: [String]) -> String? {
            if case .scalar(let s) = node, values.contains(s.value), !s.value.contains("\n") { return s.value }
            let shown: String
            if case .scalar(let s) = node { shown = "`\(s.value)`" } else { shown = "this value" }
            fail(node.line, "`\(what)` is \(shown); it must be one of: \(values.joined(separator: ", "))")
            return nil
        }

        // MARK: File

        mutating func check(_ root: YAMLNode) -> MicroApp? {
            guard case .mapping(let rootEntries, _) = root else {
                fail(root.line, "a micro-app file must be a map of `key: value` lines")
                return nil
            }
            // `inherit`: the library's keys with this file's keys over them, checked as one file.
            if mode == .app, inherited == nil, let e = rootEntries.first(where: { $0.key == "inherit" }) {
                return checkInherited(root, entries: rootEntries, inherit: e)
            }
            let isLibrary = mode != .app
            let allowed = isLibrary ? MicroAppChecker.libraryKeys : MicroAppChecker.topKeys
            guard let top = entries(root, isLibrary ? "a library" : "the file", allowed: allowed) else { return nil }
            for key in (isLibrary ? ["format", "description"] : MicroAppChecker.requiredTopKeys) where top[key] == nil {
                fail(root.line, "missing required key `\(key)`")
            }

            let expectedFormat = isLibrary ? MicroAppLibraries.format : MicroAppChecker.format
            if let e = top["format"], let value = string(e.value, "format"), value != expectedFormat {
                fail(e.value.line, "`format` must be `\(expectedFormat)`, not `\(value)`")
            }

            var stem: String?
            if case .library(let name) = mode { stem = name } else { stem = fileStem(line: root.line) }
            var id = stem
            if let e = top["id"], let value = string(e.value, "id") {
                if !MicroAppChecker.isKebabCase(value) {
                    fail(e.value.line, "`id` `\(value)` must be kebab-case: a-z and 0-9 words joined by `-`")
                } else {
                    explicitID = value
                }
                id = value
            } else if top["id"] == nil, let stem, !MicroAppChecker.isKebabCase(stem) {
                fail(root.line, "the file name `\(stem)` must be kebab-case (a-z and 0-9 words joined by `-`), because it is the id")
            }

            let name = top["name"].flatMap { string($0.value, "name") }
            parsedName = name
            let description = top["description"].flatMap { string($0.value, "description") }

            var tools: [String] = []
            if let e = top["tools"], let items = list(e.value, "tools") {
                for item in items {
                    guard let tool = string(item, "tools") else { continue }
                    if MicroAppChecker.isToolName(tool) {
                        tools.append(tool)
                    } else {
                        fail(item.line, "`tools`: `\(tool)` is not a command name")
                    }
                }
            }

            let parsedHidden = top["hidden"].flatMap { bool($0.value, "hidden") }
            self.parsedHidden = parsedHidden
            let hidden = parsedHidden ?? false
            let remember = top["remember"].flatMap { bool($0.value, "remember") } ?? true
            var timeLimit = MicroAppRunRules.timeLimit
            var timeOK = true
            if let e = top["timeout"] {
                if let seconds = seconds(e.value, "timeout", max: MicroAppChecker.maxTimeLimit) { timeLimit = seconds } else { timeOK = false }
            }
            let params = top["params"].map { checkParams($0.value) } ?? []
            if let e = top["context"] { declaredContext = checkContext(e.value) }
            var input = top["input"].flatMap { oneOf($0.value, "input", MicroApp.Input.allCases.map(\.rawValue)) }.flatMap(MicroApp.Input.init)
            if isLibrary && top["input"] == nil { input = MicroApp.Input.none }

            var usage = Usage()
            var command: String?
            var steps: [MicroAppStep]?
            switch (top["command"], top["steps"]) {
            case (let c?, let s?):
                fail(max(c.keyLine, s.keyLine), "a micro-app has either `command` or `steps`, not both")
                _ = checkCommand(c.value, params: params, usage: &usage)
            case (let c?, nil):
                command = checkCommand(c.value, params: params, usage: &usage)
                steps = command.map { [MicroAppStep(action: .command($0), line: c.keyLine)] }
            case (nil, let s?):
                steps = checkSteps(s.value, params: params, timeLimit: timeLimit, usage: &usage)
            case (nil, nil):
                fail(root.line, "missing required key `steps` (or `command` for a micro-app of one shell command)")
            }
            // A param of an inherited library that no step reads any more (the file gave it a
            // value with step `params`) is no longer a param of this micro-app: it is not asked.
            var dropped: Set<String> = []
            if inherited != nil {
                for p in params where p.line >= inheritedLineOffset && !usage.params.contains(p.param.name) { dropped.insert(p.param.name) }
            }
            if top["command"] != nil || top["steps"] != nil {
                for p in params where !usage.params.contains(p.param.name) && !dropped.contains(p.param.name) {
                    fail(p.line, command != nil
                        ? "param `\(p.param.name)` is never used: the command must read `$\(p.param.environmentName)`"
                        : "param `\(p.param.name)` is never used: a step must read `${params.\(p.param.name)}` or `$\(p.param.environmentName)`")
                }
            }
            if let e = top["context"], top["command"] != nil || top["steps"] != nil {
                for source in declaredContext where !usage.context.contains(source) {
                    fail(e.keyLine, "context `\(source.rawValue)` is never used: a step must read `${context.\(source.rawValue).…}` or `$\(MicroAppContextField.environmentPrefix)\(source.rawValue.uppercased())_…`")
                }
            }
            var output: MicroApp.Output? = MicroApp.Output(targets: [])
            if let e = top["output"] { output = checkOutput(e.value, keyLine: e.keyLine) }

            let kept = params.filter { !dropped.contains($0.param.name) }
            guard let id, let description, let input, let steps, let output, timeOK, issues.isEmpty else { return nil }
            if let command {
                return MicroApp(id: id, name: name, description: description, tools: tools, hidden: hidden, remember: remember,
                                params: kept.map(\.param), context: declaredContext, input: input, command: command, output: output,
                                timeLimit: timeLimit)
            }
            return MicroApp(id: id, name: name, description: description, tools: tools, hidden: hidden, remember: remember,
                            params: kept.map(\.param), context: declaredContext, input: input, steps: steps, output: output,
                            timeLimit: timeLimit, source: text)
        }

        /// A file with `inherit`: its library and the file merged, then checked as one micro-app.
        mutating func checkInherited(_ root: YAMLNode, entries rootEntries: [YAMLEntry], inherit e: YAMLEntry) -> MicroApp? {
            guard let name = string(e.value, "inherit"), let library = library(name, line: e.value.line),
                  let source = libraries.sources[library.name] else { return nil }
            // The library passed its own check, so its YAML parses.
            guard let parsed = try? YAMLSubset.parse(source.text), case .mapping(let baseEntries, _) = parsed.relocated(by: inheritedLineOffset) else {
                fail(e.value.line, "library `\(name)` must be a map of `key: value` lines")
                return nil
            }
            let merged: YAMLNode
            do {
                merged = try MicroAppInheritance.merge(base: baseEntries, child: rootEntries, childLine: root.line, library: name)
            } catch let problem as MicroAppInheritance.Problem {
                fail(problem.line, problem.message)
                return nil
            } catch {
                return nil
            }
            inherited = (e.value.line, source.file)
            return check(merged)
        }

        /// A whole number of seconds from 1 to `max`.
        mutating func seconds(_ node: YAMLNode, _ what: String, max: Int) -> TimeInterval? {
            if case .scalar(let s) = node, s.style == .plain, let n = Int(s.value), n >= 1, n <= max { return TimeInterval(n) }
            fail(node.line, "`\(what)` must be a whole number of seconds from 1 to \(max)")
            return nil
        }

        mutating func fileStem(line: Int) -> String? {
            let suffix = "." + MicroAppChecker.fileExtension
            guard file.hasSuffix(suffix), file.count > suffix.count else {
                fail(line, "a micro-app file name must end in `\(suffix)`")
                return nil
            }
            return String(file.dropLast(suffix.count))
        }

        // MARK: Context

        /// The `context` list: known sources, each once.
        mutating func checkContext(_ node: YAMLNode) -> [MicroAppContextSource] {
            guard let items = list(node, "context") else { return [] }
            var result: [MicroAppContextSource] = []
            for item in items {
                guard let raw = oneOf(item, "context", MicroAppContextSource.allCases.map(\.rawValue)),
                      let source = MicroAppContextSource(rawValue: raw) else { continue }
                if result.contains(source) {
                    fail(item.line, "`context`: `\(raw)` is listed twice")
                } else {
                    result.append(source)
                }
            }
            return result
        }

        /// A context field that a step reads: it counts as used when its source is in `context`.
        mutating func useContext(_ field: MicroAppContextField, shown: String, what: String, line: Int, usage: inout Usage) -> Bool {
            if declaredContext.contains(field.source) {
                usage.context.insert(field.source)
                return true
            }
            fail(line, "\(what): `\(shown)` needs `\(field.source.rawValue)` in the `context` list")
            return false
        }

        // MARK: Params

        struct CheckedParam {
            var param: MicroApp.Param
            var line: Int
        }

        mutating func checkParams(_ node: YAMLNode) -> [CheckedParam] {
            guard let items = list(node, "params") else { return [] }
            var result: [CheckedParam] = []
            var seen: [String: Int] = [:]
            for (i, item) in items.enumerated() {
                let what = "params[\(i)]"
                guard let keys = entries(item, what, allowed: MicroAppChecker.paramKeys) else { continue }
                var ok = true

                var name: String?
                if let e = keys["name"], let value = string(e.value, "\(what).name") {
                    if !MicroAppChecker.isParamName(value) {
                        fail(e.value.line, "\(what): name `\(value)` may only use a-z, 0-9 and `_`")
                        ok = false
                    } else if MicroAppChecker.isReservedParamName(value) {
                        fail(e.value.line, "\(what): names that start with `context` belong to SwiftKey: `$TING_CONTEXT_…` holds the context")
                        ok = false
                    } else if let first = seen[value] {
                        fail(e.value.line, "\(what): param `\(value)` is already declared on line \(first)")
                        ok = false
                    } else {
                        seen[value] = e.value.line
                        name = value
                    }
                } else if keys["name"] == nil {
                    fail(item.line, "\(what): missing required key `name`")
                }

                let type = keys["type"].flatMap { oneOf($0.value, "\(what).type", MicroAppChecker.paramTypes) }
                if keys["type"] == nil { fail(item.line, "\(what): missing required key `type`") }

                var required: Bool?
                if let e = keys["required"] {
                    required = bool(e.value, "\(what).required")
                } else {
                    fail(item.line, "\(what): `required` must be written out as `true` or `false`")
                }

                let defaultValue = keys["default"].flatMap { string($0.value, "\(what).default", nonEmpty: false) }
                if required == false && keys["default"] == nil {
                    fail(keys["required"]!.value.line, "\(what): an optional param needs a `default`")
                    ok = false
                }
                if required == true, let d = keys["default"] {
                    fail(d.keyLine, "\(what): a required param cannot have a `default`; remembered values already fill it in")
                    ok = false
                }
                let prompt = keys["prompt"].flatMap { string($0.value, "\(what).prompt") }

                var kind: MicroApp.Param.Kind?
                switch type {
                case "text":
                    if let e = keys["choices"] {
                        fail(e.keyLine, "\(what): `choices` is only for `type: choice`")
                        ok = false
                    }
                    kind = .text
                case "choice":
                    guard let e = keys["choices"] else {
                        fail(item.line, "\(what): a choice needs `choices`")
                        break
                    }
                    guard let options = list(e.value, "\(what).choices") else { break }
                    var values: [String] = []
                    for option in options {
                        guard let value = string(option, "\(what).choices") else { continue }
                        if values.contains(value) {
                            fail(option.line, "\(what): choice `\(value)` is listed twice")
                        } else {
                            values.append(value)
                        }
                    }
                    if options.isEmpty { fail(e.value.line, "\(what): `choices` must not be empty") }
                    if let defaultValue, !values.contains(defaultValue), let d = keys["default"] {
                        fail(d.value.line, "\(what): default `\(defaultValue)` is not one of the choices")
                        ok = false
                    }
                    if !values.isEmpty { kind = .choice(values) }
                default:
                    break
                }

                if ok, let name, let kind, let required {
                    let param = MicroApp.Param(name: name, kind: kind, required: required, defaultValue: defaultValue,
                                               prompt: prompt)
                    result.append(CheckedParam(param: param, line: keys["name"]?.keyLine ?? item.line))
                } else if let name, let e = keys["name"] {
                    // Keep the variable known, so the command check does not report it again.
                    result.append(CheckedParam(param: MicroApp.Param(name: name, kind: .text, required: true), line: e.keyLine))
                }
            }
            return result
        }

        // MARK: Command

        /// What the steps read: param names, from the code (`$TING_NAME`) and the templates (`${params.NAME}`).
        struct Usage {
            var params: Set<String> = []
            var context: Set<MicroAppContextSource> = []
        }

        mutating func checkCommand(_ node: YAMLNode, params: [CheckedParam], usage: inout Usage, what: String = "command",
                                   steps: [String: String] = [:], locals: Set<String> = []) -> String? {
            guard case .scalar(let s) = node, !s.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                fail(node.line, "`\(what)` must be one non-empty string; use `\(what): |` for several lines")
                return nil
            }
            let command = s.value
            let before = issues.count

            for p in params {
                if let range = command.range(of: "{\(p.param.name)}"), !command[..<range.lowerBound].hasSuffix("$") {
                    fail(line(of: s, at: range.lowerBound), "\(what): `{\(p.param.name)}` templates are not allowed; use `\"$\(p.param.environmentName)\"`")
                }
            }
            // SwiftKey puts nothing into the shell code: `${…}` of the templates would be shell syntax here.
            let hints: [(String, String)] = [
                ("${params.", "read a param as `\"$TING_NAME\"`"),
                ("${steps.", "read a step output as `\"$TING_STEP_ID\"`"),
                ("${input", "the input of the step is its stdin"),
                ("${keychain.", "put the secret into a variable with `env:` and read that variable"),
                ("${context.", "read a context value as `\"$TING_CONTEXT_SOURCE_FIELD\"`, such as `\"$TING_CONTEXT_APP_NAME\"`"),
            ]
            for (prefix, hint) in hints {
                if let range = command.range(of: prefix) {
                    fail(line(of: s, at: range.lowerBound), "\(what): `\(prefix)…}` is not replaced in shell code; \(hint)")
                }
            }
            scanVariables(s, what: what, params: params, steps: steps, locals: locals, needsDollar: true, usage: &usage)
            return issues.count == before ? command : nil
        }

        func line(of s: YAMLScalar, at index: String.Index) -> Int {
            s.contentLine + s.value[..<index].reduce(0) { $1 == "\n" ? $0 + 1 : $0 }
        }

        /// Finds `TING_…` variables in program code: params (`TING_NAME`) and step outputs
        /// (`TING_STEP_ID`, keyed by variable name in `steps`). Shell code reads them as `$TING_…` or
        /// `${TING_…}`; other code anywhere as a word.
        mutating func scanVariables(_ s: YAMLScalar, what: String, params: [CheckedParam], steps: [String: String],
                                    locals: Set<String> = [], needsDollar: Bool, usage: inout Usage) {
            let code = s.value
            let localVariables = Set(locals.map(MicroApp.environmentName(for:)))
            let byVariable = Dictionary(params.map { ($0.param.environmentName, $0.param.name) }, uniquingKeysWith: { a, _ in a })
            var reported: Set<String> = []
            var search = code.startIndex
            while let range = code.range(of: "TING_", range: search..<code.endIndex) {
                search = range.upperBound
                let prefix = code[..<range.lowerBound]
                if needsDollar {
                    guard prefix.hasSuffix("$") || prefix.hasSuffix("${") else { continue }
                } else if let previous = prefix.last, previous.isASCII && (previous.isLetter || previous.isNumber || previous == "_") {
                    continue
                }
                let nameEnd = code[range.upperBound...].firstIndex { !($0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_")) } ?? code.endIndex
                let variable = String(code[range.lowerBound..<nameEnd])
                if localVariables.contains(variable) { continue }
                if variable.hasPrefix(MicroAppContextField.environmentPrefix) {
                    guard !reported.contains(variable) else { continue }
                    let shown = needsDollar ? "$\(variable)" : variable
                    let at = line(of: s, at: range.lowerBound)
                    if let field = MicroAppContextField(environmentName: variable) {
                        if !useContext(field, shown: shown, what: what, line: at, usage: &usage) { reported.insert(variable) }
                    } else {
                        reported.insert(variable)
                        fail(at, "\(what): `\(shown)` is not a context value; write `$TING_CONTEXT_SOURCE_FIELD`, such as `$TING_CONTEXT_APP_NAME`")
                    }
                    continue
                }
                if let name = byVariable[variable] {
                    usage.params.insert(name)
                    continue
                }
                if steps[variable] != nil || reported.contains(variable) { continue }
                reported.insert(variable)
                let shown = needsDollar ? "$\(variable)" : variable
                if variable.hasPrefix("TING_STEP_") {
                    fail(line(of: s, at: range.lowerBound), "\(what): `\(shown)` is not the output of an earlier step with an `id`")
                } else {
                    fail(line(of: s, at: range.lowerBound), "\(what): `\(shown)` is not a declared param")
                }
            }
        }

        // MARK: Steps

        /// What a step may read of the steps before it.
        struct StepScope {
            /// Ids of earlier steps that have ended when this step starts.
            var done: Set<String> = []
            /// Ids of earlier steps that run together with this step (`stream: true`).
            var running: Set<String> = []
            /// The step reads its input while the step before it runs.
            var streams = false
        }

        mutating func checkSteps(_ node: YAMLNode, params: [CheckedParam], timeLimit: TimeInterval, usage: inout Usage) -> [MicroAppStep]? {
            guard let items = list(node, "steps") else { return nil }
            if items.isEmpty {
                fail(node.line, "`steps` must not be empty")
                return nil
            }
            let before = issues.count
            var steps: [MicroAppStep] = []
            var ids: [String: Int] = [:]
            var done: Set<String> = []
            var group: Set<String> = []
            for (i, item) in items.enumerated() {
                let what = "steps[\(i)]"
                // `stream: true` joins the step to the group of the step before it.
                var streams = false
                if case .mapping(let entries, _) = item, let e = entries.first(where: { $0.key == "stream" }),
                   case .scalar(let v) = e.value, v.style == .plain, v.value == "true" {
                    streams = true
                }
                if !streams {
                    done.formUnion(group)
                    group = []
                }
                let scope = StepScope(done: done, running: group, streams: streams)
                if let step = checkStep(item, what: what, index: i, params: params, scope: scope, timeLimit: timeLimit, usage: &usage) {
                    if let id = step.id {
                        var idLine = step.line
                        if case .mapping(let entries, _) = item, let e = entries.first(where: { $0.key == "id" }) { idLine = e.value.line }
                        if let first = ids[id] {
                            fail(idLine, "\(what): step id `\(id)` is already used on line \(first)")
                        } else {
                            ids[id] = idLine
                            group.insert(id)
                        }
                    }
                    steps.append(step)
                }
            }
            return issues.count == before ? steps : nil
        }

        mutating func checkStep(_ item: YAMLNode, what: String, index: Int, params: [CheckedParam], scope: StepScope,
                                timeLimit: TimeInterval, usage: inout Usage) -> MicroAppStep? {
            guard case .mapping(let stepEntries, let line) = item else {
                fail(item.line, "\(what) must be a map such as `- command: …`")
                return nil
            }
            let kinds = stepEntries.filter { MicroAppStep.Kind(rawValue: $0.key) != nil }
            let allKinds = MicroAppStep.Kind.allCases.map(\.rawValue).joined(separator: ", ")
            guard let kindEntry = kinds.first, let kind = MicroAppStep.Kind(rawValue: kindEntry.key) else {
                fail(line, "\(what): a step needs one of: \(allKinds)")
                return nil
            }
            if kinds.count > 1 {
                fail(kinds[1].keyLine, "\(what): a step has one kind, but it has `\(kindEntry.key)` and `\(kinds[1].key)`")
                return nil
            }
            let allowed = [kind.rawValue] + MicroAppChecker.stepCommonKeys + (MicroAppChecker.stepKeys[kind] ?? [])
            guard let keys = entries(item, "\(what) (\(kind.rawValue))", allowed: allowed) else { return nil }
            let before = issues.count

            var id: String?
            if let e = keys["id"], let value = string(e.value, "\(what).id") {
                if MicroAppChecker.isParamName(value) { id = value } else {
                    fail(e.value.line, "\(what): step id `\(value)` may only use a-z, 0-9 and `_`")
                }
            }
            var stream = false
            if let e = keys["stream"], let value = bool(e.value, "\(what).stream") {
                stream = value
                if value && !(kind == .command || kind == .python) {
                    fail(e.value.line, "\(what): only a command or python step can have `stream: true`")
                } else if value && index == 0 {
                    fail(e.value.line, "\(what): the first step has no step before it to stream from")
                } else if value && keys["stdin"] != nil {
                    fail(e.value.line, "\(what): a step with `stream: true` reads the step before it; it cannot have `stdin`")
                }
            }
            var stepTime: TimeInterval?
            if let e = keys["timeout"] { stepTime = seconds(e.value, "\(what).timeout", max: Int(timeLimit)) }

            var ctx = TemplateContext(what: what, params: params, scope: scope)
            // Step params: their values are read where the step runs; the rest of a step
            // (except a `call`, whose params belong to the library) reads them as its own params.
            var stepParams: [MicroAppStep.Field] = []
            if let e = keys["params"] {
                stepParams = fields(e.value, "\(what).params", ctx: &ctx, usage: &usage)
                for (field, entryLine) in zip(stepParams, fieldLines(e.value)) {
                    if !MicroAppChecker.isParamName(field.name) {
                        fail(entryLine, "\(what).params: `\(field.name)` may only use a-z, 0-9 and `_`")
                    } else if kind != .call && MicroAppChecker.isReservedParamName(field.name) {
                        fail(entryLine, "\(what).params: names that start with `context` belong to SwiftKey")
                    }
                }
                if kind != .call { ctx.locals = Set(stepParams.map(\.name)) }
            }
            let locals = ctx.locals
            let stdin = keys["stdin"].flatMap { template($0.value, "\(what).stdin", oneLine: false, nonEmpty: false, ctx: &ctx, usage: &usage) }
            var env: [MicroAppStep.Field] = []
            if let e = keys["env"] {
                env = fields(e.value, "\(what).env", ctx: &ctx, usage: &usage)
                for (field, entryLine) in zip(env, fieldLines(e.value)) {
                    if !MicroAppTemplate.isEnvironmentName(Substring(field.name)) || field.name.contains("-") {
                        fail(entryLine, "\(what).env: `\(field.name)` is not a variable name: use letters, digits and `_`")
                    } else if field.name.hasPrefix("TING_") {
                        fail(entryLine, "\(what).env: `\(field.name)`: names that start with `TING_` belong to SwiftKey")
                    }
                }
            }
            if stream {
                for field in env where field.value.variables.contains(.input) {
                    fail(keys["env"]!.keyLine, "\(what): a step with `stream: true` reads its input from stdin; `${input}` is not known when it starts")
                    break
                }
            }

            // Step outputs a program step can read as TING_STEP_ID.
            var stepVariables: [String: String] = [:]
            // A running step is reported by `checkRunningStepVariables`, not as unknown.
            for done in scope.done.union(scope.running) { stepVariables[MicroAppStep.environmentName(forStep: done)] = done }

            let value = kindEntry.value
            let k = "\(what).\(kind.rawValue)"
            var action: MicroAppStep.Action?
            switch kind {
            case .command:
                action = checkCommand(value, params: params, usage: &usage, what: k, steps: stepVariables, locals: locals).map { .command($0) }
                if case .scalar(let s) = value { checkRunningStepVariables(s, what: k, scope: scope) }
            case .python:
                if case .scalar(let s) = value, !s.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    scanVariables(s, what: k, params: params, steps: stepVariables, locals: locals, needsDollar: false, usage: &usage)
                    checkRunningStepVariables(s, what: k, scope: scope)
                    action = .python(s.value)
                } else {
                    fail(value.line, "`\(k)` must be one non-empty string; use `python: |` for several lines")
                }
            case .text:
                action = template(value, k, oneLine: false, nonEmpty: false, ctx: &ctx, usage: &usage).map { .text($0) }
            case .json:
                if let raw = string(value, k) {
                    if let path = MicroAppJSONPath(raw) { action = .json(path) } else {
                        fail(value.line, "`\(k)` is `\(raw)`; write keys and list indexes joined by `.`, such as `items.0.name`, or `.` for the whole JSON")
                    }
                }
            case .open:
                let target = template(value, k, ctx: &ctx, usage: &usage)
                let app = keys["app"].flatMap { template($0.value, "\(what).app", ctx: &ctx, usage: &usage) }
                if let target { action = .open(target: target, app: app) }
            case .notify:
                let message = template(value, k, oneLine: false, ctx: &ctx, usage: &usage)
                let title = keys["title"].flatMap { template($0.value, "\(what).title", ctx: &ctx, usage: &usage) }
                if let message { action = .notify(message: message, title: title) }
            case .url:
                action = checkURL(value, keys: keys, what: what, ctx: &ctx, usage: &usage).map { .url($0) }
            case .ai:
                action = checkAI(value, keys: keys, what: what, line: line, ctx: &ctx, usage: &usage).map { .ai($0) }
            case .call:
                if let name = string(value, k), let library = library(name, line: value.line) {
                    let argumentLines = keys["params"].map { fieldLines($0.value) } ?? []
                    checkArguments(stepParams, lines: argumentLines, library: library, what: what, line: line)
                    // The library reads its own context; the same source in this file's list counts as used.
                    usage.context.formUnion(library.context)
                    action = .call(library)
                }
            case .keys:
                action = checkKeys(value, what: k).map { .keys($0) }
            case .paste:
                action = template(value, k, oneLine: false, ctx: &ctx, usage: &usage).map { .paste($0) }
            }
            guard issues.count == before, let action else { return nil }
            return MicroAppStep(id: id, action: action, stdin: stdin, env: env, timeLimit: stepTime, stream: stream, params: stepParams,
                                line: line)
        }

        /// The key presses of a `keys` step: one `cmd+s`, or a one-line list such as `[cmd+a, delete]`.
        mutating func checkKeys(_ node: YAMLNode, what: String) -> [Hotkey]? {
            let items: [YAMLNode]
            switch node {
            case .scalar: items = [node]
            case .sequence(let list, _): items = list
            default:
                fail(node.line, "`\(what)` must be a key press such as `cmd+s`, or a list such as `[cmd+a, delete]`")
                return nil
            }
            if items.isEmpty {
                fail(node.line, "`\(what)` must not be empty")
                return nil
            }
            if items.count > MicroAppChecker.maxKeyPresses {
                fail(node.line, "`\(what)` has more than \(MicroAppChecker.maxKeyPresses) key presses")
                return nil
            }
            var result: [Hotkey] = []
            var ok = true
            for item in items {
                guard let text = string(item, what) else { ok = false; continue }
                guard let hotkey = Hotkey(string: text.trimmingCharacters(in: .whitespaces)), hotkey.isValid else {
                    fail(item.line, "`\(what)`: `\(text)` is not a key press; write modifiers (ctrl, option, shift, cmd) and one key joined by `+`, such as `cmd+s`, `shift+tab` or `return`")
                    ok = false
                    continue
                }
                result.append(hotkey)
            }
            return ok ? result : nil
        }

        /// The `params` of a `call` step: known to the library, every required one given, a
        /// written choice one of the choices.
        mutating func checkArguments(_ arguments: [MicroAppStep.Field], lines: [Int], library: MicroAppLibrary, what: String, line: Int) {
            for (argument, argumentLine) in zip(arguments, lines) {
                guard let param = library.params.first(where: { $0.name == argument.name }) else {
                    let known = library.params.map(\.name).joined(separator: ", ")
                    fail(argumentLine, "\(what): library `\(library.name)` has no param `\(argument.name)`" + (known.isEmpty ? "" : "; its params: \(known)"))
                    continue
                }
                if case .choice(let choices) = param.kind, let literal = argument.value.literalText, !choices.contains(literal) {
                    fail(argumentLine, "\(what): `\(argument.name)` of library `\(library.name)` must be one of: \(choices.joined(separator: ", "))")
                }
            }
            for param in library.params where param.required && !arguments.contains(where: { $0.name == param.name }) {
                fail(line, "\(what): library `\(library.name)` needs `params:` with `\(param.name)`")
            }
        }

        /// A `$TING_STEP_ID` of a step that still runs when a streaming step starts.
        mutating func checkRunningStepVariables(_ s: YAMLScalar, what: String, scope: StepScope) {
            for id in scope.running.sorted() {
                let variable = MicroAppStep.environmentName(forStep: id)
                if let range = s.value.range(of: variable) {
                    fail(line(of: s, at: range.lowerBound),
                         "\(what): `\(variable)`: step `\(id)` still runs when this `stream: true` step starts")
                }
            }
        }

        mutating func checkURL(_ value: YAMLNode, keys: [String: YAMLEntry], what: String, ctx: inout TemplateContext,
                               usage: inout Usage) -> MicroAppStep.URLRequestStep? {
            let before = issues.count
            let url = template(value, "\(what).url", ctx: &ctx, usage: &usage)
            if let url, let literal = url.literalText, !MicroAppHTTPRequest.isWebURL(literal) {
                fail(value.line, "\(what).url: `\(literal)` is not an http or https URL")
            }
            let query = keys["query"].map { fields($0.value, "\(what).query", ctx: &ctx, usage: &usage) } ?? []
            let headers = keys["headers"].map { fields($0.value, "\(what).headers", ctx: &ctx, usage: &usage) } ?? []
            var body: MicroAppStep.URLRequestStep.Body?
            if let b = keys["body"], let f = keys["form"] {
                fail(max(b.keyLine, f.keyLine), "\(what): a request has either `body` or `form`, not both")
            } else if let b = keys["body"] {
                switch b.value {
                case .scalar:
                    body = template(b.value, "\(what).body", oneLine: false, nonEmpty: false, ctx: &ctx, usage: &usage).map { .text($0) }
                case .mapping, .sequence:
                    body = jsonTemplate(b.value, "\(what).body", ctx: &ctx, usage: &usage).map { .json($0) }
                case .null:
                    fail(b.keyLine, "`\(what).body` needs a value: text, or a map or list sent as JSON")
                }
            } else if let f = keys["form"] {
                body = .form(fields(f.value, "\(what).form", ctx: &ctx, usage: &usage))
            }
            var method = body == nil ? "GET" : "POST"
            if let e = keys["method"], let m = oneOf(e.value, "\(what).method", MicroAppStep.URLRequestStep.methods) {
                method = m
                if body != nil && (m == "GET" || m == "HEAD") {
                    fail(e.value.line, "\(what): a \(m) request cannot have a `body` or `form`")
                }
            }
            guard issues.count == before, let url else { return nil }
            return MicroAppStep.URLRequestStep(url: url, method: method, query: query, headers: headers, body: body)
        }

        mutating func checkAI(_ value: YAMLNode, keys: [String: YAMLEntry], what: String, line: Int, ctx: inout TemplateContext,
                              usage: inout Usage) -> MicroAppStep.AIStep? {
            let before = issues.count
            let prompt = template(value, "\(what).ai", oneLine: false, ctx: &ctx, usage: &usage)
            let providers = MicroAppStep.AIStep.Provider.allCases.map(\.rawValue)
            var provider: MicroAppStep.AIStep.Provider?
            if let e = keys["provider"] {
                provider = oneOf(e.value, "\(what).provider", providers).flatMap(MicroAppStep.AIStep.Provider.init)
            } else {
                fail(line, "\(what): an ai step needs `provider`: \(providers.joined(separator: " or "))")
            }
            var model: MicroAppTemplate?
            if let e = keys["model"] {
                model = template(e.value, "\(what).model", ctx: &ctx, usage: &usage)
            } else {
                fail(line, "\(what): an ai step needs `model`, such as `gpt-4.1-mini` or `claude-haiku-5-5`")
            }
            let key = keys["key"].flatMap { template($0.value, "\(what).key", ctx: &ctx, usage: &usage) }
            let system = keys["system"].flatMap { template($0.value, "\(what).system", oneLine: false, ctx: &ctx, usage: &usage) }
            let baseURL = keys["base_url"].flatMap { template($0.value, "\(what).base_url", ctx: &ctx, usage: &usage) }
            if let e = keys["base_url"], let literal = baseURL?.literalText, !MicroAppHTTPRequest.isWebURL(literal) {
                fail(e.value.line, "\(what).base_url: `\(literal)` is not an http or https URL")
            }
            let temperature = keys["temperature"].flatMap { template($0.value, "\(what).temperature", ctx: &ctx, usage: &usage) }
            if let e = keys["temperature"], let literal = temperature?.literalText, !MicroAppJSON.isNumber(literal) {
                fail(e.value.line, "`\(what).temperature` must be a number, such as `0.2`")
            }
            let maxTokens = keys["max_tokens"].flatMap { template($0.value, "\(what).max_tokens", ctx: &ctx, usage: &usage) }
            if let e = keys["max_tokens"], let literal = maxTokens?.literalText, (Int(literal) ?? 0) < 1 {
                fail(e.value.line, "`\(what).max_tokens` must be a whole number above 0")
            }
            guard issues.count == before, let prompt, let provider, let model else { return nil }
            return MicroAppStep.AIStep(prompt: prompt, provider: provider, model: model, key: key, system: system, baseURL: baseURL,
                                       temperature: temperature, maxTokens: maxTokens)
        }

        // MARK: Templates

        struct TemplateContext {
            var what: String
            var params: [CheckedParam]
            var scope: StepScope
            /// The step's own `params`.
            var locals: Set<String> = []
        }

        /// A text value with `${…}` variables. Every variable must be known where the step runs.
        mutating func template(_ node: YAMLNode, _ what: String, oneLine: Bool = true, nonEmpty: Bool = true,
                               ctx: inout TemplateContext, usage: inout Usage) -> MicroAppTemplate? {
            guard let text = string(node, what, oneLine: oneLine, nonEmpty: nonEmpty), case .scalar(let s) = node else { return nil }
            let firstLine = s.style == .literal ? s.contentLine : s.line
            switch MicroAppTemplate.parse(text) {
            case .failure(let error):
                fail(firstLine + error.lineOffset, "\(what): \(error.message)")
                return nil
            case .success(let template):
                var ok = true
                var search = text.startIndex
                for variable in template.variables {
                    // The line of this variable in the text, for the message.
                    let found = text.range(of: "${", range: search..<text.endIndex)
                    let at = found.map { s.value[..<$0.lowerBound].reduce(firstLine) { $1 == "\n" ? $0 + 1 : $0 } } ?? firstLine
                    if let found { search = found.upperBound }
                    switch variable {
                    case .param(let name):
                        if ctx.locals.contains(name) {
                            break
                        } else if ctx.params.contains(where: { $0.param.name == name }) {
                            usage.params.insert(name)
                        } else {
                            fail(at, "\(what): `${params.\(name)}` is not a declared param")
                            ok = false
                        }
                    case .step(let id):
                        if ctx.scope.running.contains(id) {
                            fail(at, "\(what): `${steps.\(id)}`: step `\(id)` still runs when this `stream: true` step starts")
                            ok = false
                        } else if !ctx.scope.done.contains(id) {
                            fail(at, "\(what): `${steps.\(id)}` is not an earlier step; give that step `id: \(id)`")
                            ok = false
                        }
                    case .context(let field):
                        if !useContext(field, shown: "${context.\(field)}", what: what, line: at, usage: &usage) { ok = false }
                    case .input, .env, .keychain:
                        break
                    }
                }
                return ok ? template : nil
            }
        }

        /// A map of `name: template` lines, in file order.
        mutating func fields(_ node: YAMLNode, _ what: String, ctx: inout TemplateContext, usage: inout Usage) -> [MicroAppStep.Field] {
            guard case .mapping(let entries, _) = node else {
                fail(node.line, "`\(what)` must be a map of `name: value` lines")
                return []
            }
            return entries.compactMap { entry in
                template(entry.value, "\(what).\(entry.key)", nonEmpty: false, ctx: &ctx, usage: &usage)
                    .map { MicroAppStep.Field(name: entry.key, value: $0) }
            }
        }

        func fieldLines(_ node: YAMLNode) -> [Int] {
            guard case .mapping(let entries, _) = node else { return [] }
            return entries.map(\.keyLine)
        }

        /// A map or list sent as JSON: plain `true`, `false`, numbers and `null` keep their type.
        mutating func jsonTemplate(_ node: YAMLNode, _ what: String, ctx: inout TemplateContext, usage: inout Usage) -> MicroAppJSONTemplate? {
            switch node {
            case .null:
                return .null
            case .scalar(let s):
                if s.style == .plain {
                    if s.value == "true" { return .bool(true) }
                    if s.value == "false" { return .bool(false) }
                    if MicroAppJSON.isNumber(s.value) { return .number(s.value) }
                }
                return template(node, what, oneLine: false, nonEmpty: false, ctx: &ctx, usage: &usage).map { .string($0) }
            case .sequence(let items, _):
                var result: [MicroAppJSONTemplate] = []
                for (i, item) in items.enumerated() {
                    guard let value = jsonTemplate(item, "\(what)[\(i)]", ctx: &ctx, usage: &usage) else { return nil }
                    result.append(value)
                }
                return .array(result)
            case .mapping(let entries, _):
                var result: [(key: String, value: MicroAppJSONTemplate)] = []
                for entry in entries {
                    guard let value = jsonTemplate(entry.value, "\(what).\(entry.key)", ctx: &ctx, usage: &usage) else { return nil }
                    result.append((entry.key, value))
                }
                return .object(result)
            }
        }

        // MARK: Output

        mutating func checkOutput(_ node: YAMLNode, keyLine: Int) -> MicroApp.Output? {
            guard let keys = entries(node, "output", allowed: MicroAppChecker.outputKeys) else { return nil }
            var targets: [MicroApp.OutputTarget] = []
            var ok = true
            if let e = keys["to"] {
                if let items = list(e.value, "output.to") {
                    if items.isEmpty { fail(e.value.line, "`output.to` must not be empty"); ok = false }
                    for item in items {
                        guard let raw = oneOf(item, "output.to", MicroApp.OutputTarget.allCases.map(\.rawValue)),
                              let target = MicroApp.OutputTarget(rawValue: raw)
                        else { ok = false; continue }
                        if targets.contains(target) {
                            fail(item.line, "`output.to`: `\(raw)` is listed twice")
                            ok = false
                        } else {
                            targets.append(target)
                        }
                    }
                } else {
                    ok = false
                }
            } else {
                fail(keyLine, "`output` needs `to`: a list of `clipboard`, `panel` or `app`")
                ok = false
            }
            if targets.contains(.app) && targets.contains(.panel), let e = keys["to"] {
                fail(e.value.line, "`output.to`: `app` and `panel` cannot be together: SwiftKey pastes the result into the app, and the panel would take its place")
                ok = false
            }
            var style = MicroApp.OutputStyle.markdown
            if let e = keys["as"] {
                if let raw = oneOf(e.value, "output.as", MicroApp.OutputStyle.allCases.map(\.rawValue)),
                   let value = MicroApp.OutputStyle(rawValue: raw) {
                    style = value
                } else {
                    ok = false
                }
            }
            return ok ? MicroApp.Output(targets: targets, style: style) : nil
        }
    }
}
