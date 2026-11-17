import Foundation

/// One file of the micro-apps folder after the checks: a working micro-app or a broken file.
public struct MicroAppEntry: Equatable, Sendable {
    /// The file name, such as `dns-lookup.yaml`.
    public var file: String
    /// `nil` when the file is broken.
    public var app: MicroApp?
    /// Empty for a working micro-app; sorted by line otherwise.
    public var issues: [MicroAppIssue]
    /// `MicroAppApprovals.hash` of the file content that was checked; empty when the file could not be read.
    public var contentHash: String
    /// For a broken file: the kebab-case `id` the checker could read from it; `nil` otherwise.
    public var explicitID: String?
    /// For a broken file: the `name` the checker could read from it; `nil` otherwise.
    public var brokenName: String?
    /// For a broken file: the `hidden` value the checker could read from it; `false` otherwise.
    public var brokenHidden: Bool

    public init(file: String, app: MicroApp?, issues: [MicroAppIssue], contentHash: String = "", explicitID: String? = nil,
                brokenName: String? = nil, brokenHidden: Bool = false) {
        self.file = file
        self.app = app
        self.issues = issues
        self.contentHash = contentHash
        self.explicitID = explicitID
        self.brokenName = brokenName
        self.brokenHidden = brokenHidden
    }

    /// The file name without `.yaml`: the id a binding uses when the file has no `id` key.
    public var fileID: String { (file as NSString).deletingPathExtension }

    public var isBroken: Bool { app == nil }

    /// `hidden: true` of a working micro-app, or of a broken file whose `hidden` key could be read.
    public var isHidden: Bool { app?.hidden ?? brokenHidden }

    /// The id a binding finds this file by: the micro-app id, else the kept `id`, else the file name without `.yaml`.
    public var bindingID: String { app?.id ?? explicitID ?? fileID }
}

/// All files of the micro-apps folder, checked, with the id rules applied.
public struct MicroAppCatalog: Equatable, Sendable {
    /// Sorted by file name.
    public private(set) var entries: [MicroAppEntry]
    /// The problems of the library files (`libs/*.yaml`), by file and line.
    public var libraryIssues: [MicroAppIssue] = []

    public init(entries: [MicroAppEntry] = [], libraryIssues: [MicroAppIssue] = []) {
        self.entries = entries
        self.libraryIssues = libraryIssues
    }

    /// The working micro-apps, in file-name order.
    public var apps: [MicroApp] { entries.compactMap(\.app) }
    /// Every problem, by file name, then by line; the library files after the micro-apps.
    public var issues: [MicroAppIssue] { entries.flatMap(\.issues) + libraryIssues }
    public var brokenFiles: [String] { entries.filter(\.isBroken).map(\.file) }

    /// Checks every file and applies the id rules: when two working files have the same id, the
    /// first by file name works and the later ones are broken with a "duplicate id" issue.
    public static func load(_ files: [(name: String, text: String)], libraries: MicroAppLibraries = MicroAppLibraries()) -> MicroAppCatalog {
        var catalog = build(hashed: files.map { file in
            let name = (file.name as NSString).lastPathComponent
            return (name, MicroAppChecker.check(file.text, fileName: name, libraries: libraries), MicroAppApprovals.hash(Data(file.text.utf8)))
        })
        catalog.libraryIssues = checkLibraries(libraries)
        return catalog
    }

    /// The problems of every library file, checked on its own, by file and line.
    public static func checkLibraries(_ libraries: MicroAppLibraries) -> [MicroAppIssue] {
        libraries.sources.values.sorted { $0.file < $1.file }.flatMap { source -> [MicroAppIssue] in
            if case .failure(let failure) = MicroAppChecker.checkLibrary(source, libraries: libraries, stack: []) { return failure.issues }
            return []
        }
    }

    /// Like `load`, for files that are already checked (or could not be read).
    /// `ownerName` gives the name that a duplicate id issue uses for the file that keeps the id;
    /// the check command keys files by path and names the owner by its file name, as the folder does.
    public static func build(_ checked: [(file: String, result: Result<MicroApp, MicroAppFailure>)],
                             ownerName: (String) -> String = { $0 }) -> MicroAppCatalog {
        build(hashed: checked.map { ($0.file, $0.result, "") }, ownerName: ownerName)
    }

    /// Like `build`, with the `MicroAppApprovals.hash` of each file's content.
    public static func build(hashed checked: [(file: String, result: Result<MicroApp, MicroAppFailure>, hash: String)],
                             ownerName: (String) -> String = { $0 }) -> MicroAppCatalog {
        var owners: [String: String] = [:]
        var entries: [MicroAppEntry] = []
        for (file, result, hash) in checked.sorted(by: { $0.file < $1.file }) {
            switch result {
            case .failure(let failure):
                entries.append(MicroAppEntry(file: file, app: nil, issues: failure.issues, contentHash: hash, explicitID: failure.id,
                                             brokenName: failure.name, brokenHidden: failure.hidden ?? false))
            case .success(let app):
                if let owner = owners[app.id] {
                    let issue = MicroAppIssue(file: file, line: 1,
                                              message: "duplicate id `\(app.id)`: `\(ownerName(owner))` already uses it; rename one of the files")
                    // The file itself is good, so its id, name and hidden flag are known.
                    entries.append(MicroAppEntry(file: file, app: nil, issues: [issue], contentHash: hash, explicitID: app.id,
                                                 brokenName: app.name, brokenHidden: app.hidden))
                } else {
                    owners[app.id] = file
                    // The approval covers the libraries too: a change in one asks again.
                    let combined = hash.isEmpty || app.libraries.isEmpty ? hash : MicroAppApprovals.hash(hash, libraries: app.libraries)
                    entries.append(MicroAppEntry(file: file, app: app, issues: [], contentHash: combined))
                }
            }
        }
        return MicroAppCatalog(entries: entries)
    }

    /// What a binding to `id` finds, in this order: the working micro-app with that id; a broken
    /// file whose kept explicit `id` is `id`; a broken file whose name without `.yaml` is `id`;
    /// else nothing. A broken file never owns an id, so a working micro-app always wins.
    public func resolve(_ id: String) -> MicroAppResolution {
        if let entry = entries.first(where: { $0.app?.id == id }), let app = entry.app { return .working(app, entry) }
        if let entry = entries.first(where: { $0.isBroken && $0.explicitID == id }) { return .broken(entry) }
        if let entry = entries.first(where: { $0.isBroken && $0.fileID == id }) { return .broken(entry) }
        return .missing
    }

    /// What the file `file` of the folder is now: working, broken or gone.
    public func resolve(file: String) -> MicroAppResolution {
        guard let entry = entries.first(where: { $0.file == file }) else { return .missing }
        if let app = entry.app { return .working(app, entry) }
        return .broken(entry)
    }

    /// The name a binding shows: its label, else the micro-app's `name`, else the id.
    public func bindingName(label: String, id: String) -> String {
        if !label.isEmpty { return label }
        if case .working(let app, _) = resolve(id) { return app.shownName }
        return id
    }

    /// The text of `micro-errors.log`: one `file:line: message` line per problem; empty when all is good.
    public var logText: String {
        issues.map { "\($0.file):\($0.line): \(Self.logMessage($0.message))\n" }.joined()
    }

    /// A problem message as one line of the error log.
    public static func logMessage(_ message: String) -> String {
        message.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
    }

    /// The files that are broken now and were not broken the same way in `previous`: files that
    /// became broken, broken files that changed, and new broken files.
    public func newlyBroken(since previous: MicroAppCatalog) -> [MicroAppEntry] {
        let before = Dictionary(previous.entries.map { ($0.file, $0.issues) }, uniquingKeysWith: { first, _ in first })
        return entries.filter { $0.isBroken && before[$0.file] != $0.issues }
    }

    /// The toast for a live change that brought broken files; `nil` when it brought none.
    public func toastMessage(since previous: MicroAppCatalog) -> String? {
        let broken = newlyBroken(since: previous)
        guard let first = broken.first, let issue = first.issues.first else { return nil }
        if broken.count == 1 { return "Micro-app \(issue.file), line \(issue.line): \(issue.message)" }
        return "\(broken.count) micro-app files have errors, first \(issue.file), line \(issue.line)"
    }
}

/// What a micro-app binding points to.
public enum MicroAppResolution: Equatable, Sendable {
    case working(MicroApp, MicroAppEntry)
    case broken(MicroAppEntry)
    case missing

    public var isWorking: Bool {
        if case .working = self { return true }
        return false
    }

    /// Why a binding does not work, in one line; `nil` for a working micro-app.
    /// `folder` is the micro-apps folder as shown to the user.
    public func problem(id: String, folder: String) -> String? {
        switch self {
        case .working:
            return nil
        case .broken(let entry):
            guard let issue = entry.issues.first else { return "Micro-app \(entry.file) has errors" }
            let more = entry.issues.count > 1 ? " (+\(entry.issues.count - 1) more)" : ""
            return "Micro-app \(issue.file), line \(issue.line): \(issue.message)\(more)"
        case .missing:
            return "Micro-app `\(id)` not found in \(folder)"
        }
    }
}

/// One entry of the micro-app picker of the bindings editor.
public struct MicroAppChoice: Equatable, Sendable, Identifiable {
    public enum State: Equatable, Sendable {
        /// A loaded micro-app.
        case working
        /// The binding's current id, which only a broken file has.
        case broken
        /// The binding's current id, which no file has.
        case missing
    }

    public var id: String
    /// The shown name: the micro-app's `name`, else its id.
    public var name: String
    public var state: State

    public init(id: String, name: String, state: State) {
        self.id = id
        self.name = name
        self.state = state
    }

    /// `name · id`, or the id with its state when it does not work.
    public var title: String {
        switch state {
        case .working: name == id ? id : "\(name) · \(id)"
        case .broken: "\(id) (broken)"
        case .missing: "\(id) (missing)"
        }
    }
}

extension MicroAppCatalog {
    /// The picker of a micro-app binding: every working micro-app in file-name order; when
    /// `current` is not one of them (a broken file or no file), it comes first, marked, so the
    /// editor can show it and the person can pick another one. An empty `current` adds nothing.
    public func bindingChoices(current: String? = nil) -> [MicroAppChoice] {
        let working = apps.map { MicroAppChoice(id: $0.id, name: $0.shownName, state: .working) }
        guard let current, !current.isEmpty, !working.contains(where: { $0.id == current }) else { return working }
        let state: MicroAppChoice.State = if case .broken = resolve(current) { .broken } else { .missing }
        return [MicroAppChoice(id: current, name: current, state: state)] + working
    }
}
