import Foundation

/// The text of one library file, as read: part of the approval of every micro-app that uses it.
public struct MicroAppLibrarySource: Equatable, Sendable {
    /// The library name: the file name without `.yaml`, such as `translate`.
    public var name: String
    /// The file as shown in messages, such as `libs/translate.yaml`.
    public var file: String
    public var text: String

    public init(name: String, file: String, text: String) {
        self.name = name
        self.file = file
        self.text = text
    }
}

/// The library files a micro-app can use: `libs/*.yaml` next to the micro-app files.
public struct MicroAppLibraries: Equatable, Sendable {
    public static let folderName = "libs"
    public static let format = "ting.microlib/1"
    /// The deepest chain of `call` steps and `inherit` keys.
    public static let maxDepth = 8

    /// By library name.
    public var sources: [String: MicroAppLibrarySource]

    public init(_ sources: [MicroAppLibrarySource] = []) {
        self.sources = Dictionary(sources.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
    }

    public static func file(for name: String) -> String { "\(folderName)/\(name).\(MicroAppChecker.fileExtension)" }

    /// A library name: kebab-case, like a micro-app id.
    public static func isName(_ s: String) -> Bool { MicroAppChecker.isKebabCase(s) }

    /// Reads `libs/*.yaml` of `folder`. Unreadable, too large and non-UTF-8 files are left out,
    /// so a micro-app that uses them reports the library as missing; `MicroAppChecker.checkLibrary`
    /// reports their own problems.
    public static func read(folder: URL) -> MicroAppLibraries {
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: folder.path) else { return MicroAppLibraries() }
        var sources: [MicroAppLibrarySource] = []
        for name in names.sorted() where !name.hasPrefix(".") && name.hasSuffix("." + MicroAppChecker.fileExtension) {
            let url = folder.appendingPathComponent(name)
            guard let size = (try? manager.attributesOfItem(atPath: url.path))?[.size] as? Int, size <= MicroAppChecker.maxFileSize,
                  let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else { continue }
            let stem = String(name.dropLast(MicroAppChecker.fileExtension.count + 1))
            sources.append(MicroAppLibrarySource(name: stem, file: file(for: stem), text: text))
        }
        return MicroAppLibraries(sources)
    }
}

/// A checked library: what a `call` step runs.
public struct MicroAppLibrary: Equatable, Sendable {
    public var name: String
    public var file: String
    public var description: String
    public var tools: [String]
    public var params: [MicroApp.Param]
    /// The context its steps read: its own `context` and that of the libraries it calls.
    public var context: [MicroAppContextSource]
    public var steps: [MicroAppStep]
    /// This library and every library it uses, without repeats, in the order they were found.
    public var sources: [MicroAppLibrarySource]

    public init(name: String, file: String, description: String, tools: [String] = [], params: [MicroApp.Param] = [],
                context: [MicroAppContextSource] = [], steps: [MicroAppStep], sources: [MicroAppLibrarySource] = []) {
        self.name = name
        self.file = file
        self.description = description
        self.tools = tools
        self.params = params
        self.context = context
        self.steps = steps
        self.sources = sources
    }
}

extension Array where Element == MicroAppLibrarySource {
    /// Adds the sources that are not there yet, keeping the order.
    mutating func addMissing(_ more: [MicroAppLibrarySource]) {
        for source in more where !contains(where: { $0.name == source.name }) { append(source) }
    }
}

extension MicroApp {
    /// The steps of the micro-app and, in place of each `call`, the steps of its library, also nested.
    public var allSteps: [MicroAppStep] { steps.flattened }
}

extension Array where Element == MicroAppStep {
    var flattened: [MicroAppStep] {
        flatMap { step -> [MicroAppStep] in
            if case .call(let library) = step.action { return [step] + library.steps.flattened }
            return [step]
        }
    }

    /// `tools` of every called library and `python3` for a python step anywhere, without repeats.
    var requiredTools: [String] {
        var result: [String] = []
        for step in self {
            switch step.action {
            case .python:
                if !result.contains("python3") { result.append("python3") }
            case .call(let library):
                for tool in library.tools + library.steps.requiredTools where !result.contains(tool) { result.append(tool) }
            default:
                break
            }
        }
        return result
    }
}

// MARK: Inheritance

/// Lines of an inherited library are moved by this much, so a problem found in the merged file
/// can be told apart and reported with the library file and its own line.
let inheritedLineOffset = 1_000_000

extension YAMLNode {
    /// The same node with every line moved by `offset`.
    func relocated(by offset: Int) -> YAMLNode {
        switch self {
        case .scalar(var s):
            s.line += offset
            s.contentLine += offset
            return .scalar(s)
        case .sequence(let items, let line):
            return .sequence(items.map { $0.relocated(by: offset) }, line: line + offset)
        case .mapping(let entries, let line):
            return .mapping(entries.map { YAMLEntry(key: $0.key, keyLine: $0.keyLine + offset, value: $0.value.relocated(by: offset)) },
                            line: line + offset)
        case .null(let line):
            return .null(line: line + offset)
        }
    }

    var mappingEntries: [YAMLEntry]? {
        if case .mapping(let entries, _) = self { return entries }
        return nil
    }

    var scalarValue: String? {
        if case .scalar(let s) = self { return s.value }
        return nil
    }
}

/// Merges a micro-app file that has `inherit` into its library.
enum MicroAppInheritance {
    struct Problem: Error {
        var line: Int
        var message: String
    }

    /// Keys of a micro-app that its library cannot give.
    static let ownKeys: Set<String> = ["format", "inherit", "id", "name", "hidden", "remember"]

    /// The library's keys (without `format`), then the file's keys over them:
    /// - `params`: a param with the same `name` takes the file's keys over the library's; new ones are added;
    /// - `steps`: each item names a step of the library by `id` and changes its keys; maps in a step
    ///   (such as `params`, `env`, `headers`) are merged key by key; the kind of a step cannot change;
    /// - `output`: merged key by key;
    /// - every other key replaces the library's.
    static func merge(base: [YAMLEntry], child: [YAMLEntry], childLine: Int, library: String) throws -> YAMLNode {
        var result = base.filter { $0.key != "format" && !ownKeys.contains($0.key) }
        for entry in child where entry.key != "inherit" {
            guard let index = result.firstIndex(where: { $0.key == entry.key }) else {
                result.append(entry)
                continue
            }
            let merged: YAMLNode
            switch entry.key {
            case "params": merged = try mergeParams(result[index].value, entry.value, library: library)
            case "steps": merged = try mergeSteps(result[index].value, entry.value, library: library)
            case "output": merged = deepMerge(result[index].value, entry.value)
            default: merged = entry.value
            }
            result[index] = YAMLEntry(key: entry.key, keyLine: entry.keyLine, value: merged)
        }
        // A `command` of the file replaces the library's steps, and the other way round.
        if child.contains(where: { $0.key == "command" }) { result.removeAll { $0.key == "steps" && !child.contains(where: { $0.key == "steps" }) } }
        return .mapping(result, line: childLine)
    }

    /// Maps merged key by key; anything else is replaced.
    static func deepMerge(_ base: YAMLNode, _ over: YAMLNode) -> YAMLNode {
        guard case .mapping(var entries, let line) = base, case .mapping(let overEntries, _) = over else { return over }
        for entry in overEntries {
            if let index = entries.firstIndex(where: { $0.key == entry.key }) {
                entries[index] = YAMLEntry(key: entry.key, keyLine: entry.keyLine, value: deepMerge(entries[index].value, entry.value))
            } else {
                entries.append(entry)
            }
        }
        return .mapping(entries, line: line)
    }

    static func mergeParams(_ base: YAMLNode, _ over: YAMLNode, library: String) throws -> YAMLNode {
        guard case .sequence(var items, let line) = base else { return over }
        guard case .sequence(let overItems, _) = over else {
            throw Problem(line: over.line, message: "`params` of a file with `inherit` must be a list")
        }
        for item in overItems {
            guard let name = item.mappingEntries?.first(where: { $0.key == "name" })?.value.scalarValue else {
                throw Problem(line: item.line, message: "each param of a file with `inherit` needs a `name`")
            }
            if let index = items.firstIndex(where: { $0.mappingEntries?.first(where: { $0.key == "name" })?.value.scalarValue == name }) {
                items[index] = deepMerge(items[index], item)
            } else {
                items.append(item)
            }
        }
        return .sequence(items, line: line)
    }

    static func mergeSteps(_ base: YAMLNode, _ over: YAMLNode, library: String) throws -> YAMLNode {
        guard case .sequence(var items, let line) = base else { return over }
        guard case .sequence(let overItems, _) = over else {
            throw Problem(line: over.line, message: "`steps` of a file with `inherit` must be a list of changes, each with the `id` of a step of `\(library)`")
        }
        let kinds = Set(MicroAppStep.Kind.allCases.map(\.rawValue))
        for item in overItems {
            guard let entries = item.mappingEntries, let id = entries.first(where: { $0.key == "id" })?.value.scalarValue else {
                throw Problem(line: item.line, message: "each change of `steps` needs the `id` of a step of `\(library)`")
            }
            guard let index = items.firstIndex(where: { $0.mappingEntries?.first(where: { $0.key == "id" })?.value.scalarValue == id }) else {
                throw Problem(line: item.line, message: "`\(library)` has no step with `id: \(id)`")
            }
            let baseKind = items[index].mappingEntries?.first { kinds.contains($0.key) }?.key
            if let kind = entries.first(where: { kinds.contains($0.key) }), kind.key != baseKind {
                throw Problem(line: kind.keyLine, message: "step `\(id)` is a `\(baseKind ?? "?")` step in `\(library)`; a change cannot make it `\(kind.key)`")
            }
            items[index] = deepMerge(items[index], item)
        }
        return .sequence(items, line: line)
    }
}
