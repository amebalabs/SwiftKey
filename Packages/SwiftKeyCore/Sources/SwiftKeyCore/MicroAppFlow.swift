import CryptoKit
import Foundation

/// The approved micro-apps: by id, the SHA-256 of the whole file content that was approved.
/// Stored as `micro-approvals.json`, apart from the micro-apps folder and the config file.
/// JSON: {"version": 1, "approvals": {"format-json": "<64 hex digits>"}}.
public struct MicroAppApprovals: Equatable, Sendable, Codable {
    public static let currentVersion = 1

    public var version: Int = MicroAppApprovals.currentVersion
    /// Micro-app id → lower-case hex SHA-256 of the approved file content.
    public var approvals: [String: String] = [:]

    public init(approvals: [String: String] = [:]) {
        self.approvals = approvals
    }

    /// Lower-case hex SHA-256 of `content`.
    public static func hash(_ content: Data) -> String {
        SHA256.hash(data: content).map { String(format: "%02x", $0) }.joined()
    }

    /// The approval hash of a micro-app file with the libraries it uses: any change of the file or
    /// of one of the libraries gives another hash.
    public static func hash(_ fileHash: String, libraries: [MicroAppLibrarySource]) -> String {
        var text = fileHash
        for library in libraries.sorted(by: { $0.name < $1.name }) {
            text += "\n" + library.name + "\n" + hash(Data(library.text.utf8))
        }
        return hash(Data(text.utf8))
    }

    /// `true` only when `id` was approved with exactly this content hash. Any change of the file,
    /// even a comment or a space, asks again. An empty hash (an unread file) is never approved.
    public func isApproved(id: String, hash: String) -> Bool {
        !hash.isEmpty && approvals[id] == hash
    }

    /// Approves this content for `id`; a later approval of the same id replaces the earlier one.
    public mutating func approve(id: String, hash: String) {
        guard !hash.isEmpty else { return }
        approvals[id] = hash
    }

    private enum CodingKeys: String, CodingKey { case version, approvals }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        approvals = try container.decodeIfPresent([String: String].self, forKey: .approvals) ?? [:]
    }

    /// Sorted, pretty-printed JSON ending with "\n".
    public func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = (try? encoder.encode(self)) ?? Data("{}".utf8)
        data.append(contentsOf: Array("\n".utf8))
        return data
    }

    /// The stored approvals. Anything that is not a readable file of this format gives no approvals,
    /// so every micro-app asks again: an unreadable file never approves anything.
    public static func decode(_ data: Data) -> MicroAppApprovals {
        guard let decoded = try? JSONDecoder().decode(MicroAppApprovals.self, from: data),
              decoded.version <= currentVersion else { return MicroAppApprovals() }
        return decoded
    }
}

/// What the result panel shows.
public struct MicroAppPanelContent: Equatable, Sendable {
    /// The micro-app's shown name.
    public var title: String
    public var text: String
    public var style: MicroApp.OutputStyle
    /// A failure, a timeout or a micro-app that cannot start: the panel shows an error mark.
    public var isError: Bool
    /// Short lines above the text, such as "Copied", "exit 1" or the cut note.
    public var notes: [String]

    public init(title: String, text: String, style: MicroApp.OutputStyle, isError: Bool, notes: [String] = []) {
        self.title = title
        self.text = text
        self.style = style
        self.isError = isError
        self.notes = notes
    }
}

/// What SwiftKey does with the end of a micro-app run (or with a micro-app that cannot start).
public struct MicroAppResultPlan: Equatable, Sendable {
    public enum Show: Equatable, Sendable {
        /// Nothing at all: the run was stopped by the person.
        case nothing
        case toast(String)
        case panel(MicroAppPanelContent)
    }

    /// The text that replaces the clipboard; `nil` leaves the clipboard as it was.
    public var clipboard: String?
    /// The text SwiftKey pastes into the app where the micro-app started; `nil` pastes nothing. With
    /// `clipboard` the text stays on the clipboard, else the clipboard is put back.
    public var app: String?
    public var show: Show

    public init(clipboard: String? = nil, app: String? = nil, show: Show) {
        self.clipboard = clipboard
        self.app = app
        self.show = show
    }

    public static let copiedNote = "Copied"
    public static let noOutputNote = "No output"
    /// An error longer than this (or with more than one line break) does not fit the two lines of a toast.
    public static let toastLimit = 100

    /// The cut note: stdout or stderr was longer than the limit and the rest was dropped.
    public static func cutNote(limit: Int = MicroAppRunRules.outputLimit) -> String {
        let megabyte = 1_048_576
        let size = limit >= megabyte && limit % megabyte == 0 ? "\(limit / megabyte) MB" : "\(limit) bytes"
        return "output cut at \(size)"
    }

    /// The timeout note.
    public static func timeoutNote(seconds: TimeInterval = MicroAppRunRules.timeLimit) -> String {
        "stopped after \(Int(seconds.rounded())) s"
    }

    /// `true` when `message` fits the two lines of a toast.
    public static func fitsToast(_ message: String) -> Bool {
        message.count <= toastLimit && message.filter(\.isNewline).count <= 1
    }

    /// A micro-app that cannot start (missing, broken, tool not found): a toast when the message fits
    /// in two lines, else the result panel with an error mark. Never touches the clipboard.
    public static func error(title: String, message: String) -> MicroAppResultPlan {
        if fitsToast(message) { return MicroAppResultPlan(show: .toast(message)) }
        return MicroAppResultPlan(show: .panel(MicroAppPanelContent(title: title, text: message, style: .console, isError: true)))
    }

    /// The rules of the result:
    /// - success: `panel` shows stdout in the output style; `clipboard` replaces the clipboard and
    ///   shows the "Copied" toast; both show the panel with a "Copied" note;
    /// - success with empty stdout: the clipboard stays as it was; a panel target shows the panel
    ///   with the "No output" note, a micro-app without the panel shows the toast "No output";
    /// - `app` pastes stdout into the app where the micro-app started, without a toast unless it
    ///   also goes to the clipboard ("Copied") or was cut;
    /// - failure and timeout: always the result panel as console text (stderr, then stdout) with an
    ///   error mark and the exit code or "stopped after 60 s"; nothing goes to the clipboard;
    /// - a cut stdout or stderr adds the cut note;
    /// - cancelled: nothing;
    /// - tool not found: like `error`.
    public static func make(app: MicroApp, result: MicroAppRunResult,
                            outputLimit: Int = MicroAppRunRules.outputLimit,
                            timeLimit: TimeInterval = MicroAppRunRules.timeLimit) -> MicroAppResultPlan {
        let title = app.shownName
        func cut(_ output: MicroAppRunOutput) -> [String] {
            output.stdoutCut || output.stderrCut ? [cutNote(limit: outputLimit)] : []
        }
        func errorPanel(_ output: MicroAppRunOutput, note: String, step: String? = nil) -> MicroAppResultPlan {
            let text = [output.stderr, output.stdout]
                .map { MicroAppRunRules.removingEndNewlines($0) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
            let notes = [step, note].compactMap { $0 } + cut(output) + (text.isEmpty ? [noOutputNote] : [])
            return MicroAppResultPlan(show: .panel(MicroAppPanelContent(title: title, text: text, style: .console,
                                                                        isError: true, notes: notes)))
        }
        switch result {
        case .cancelled:
            return MicroAppResultPlan(show: .nothing)
        case .toolNotFound(let tool):
            return error(title: title, message: "\(title): tool not found: \(tool)")
        case .failure(let code, let output):
            return errorPanel(output, note: "exit \(code)")
        case .timeout(let output):
            return errorPanel(output, note: timeoutNote(seconds: timeLimit))
        case .stepFailed(let failure):
            return errorPanel(failure.output, note: failure.note, step: failure.count > 1 ? failure.stepNote : nil)
        case .success(let output):
            // A micro-app without `output`: nothing is shown or copied.
            if app.output.targets.isEmpty { return MicroAppResultPlan(show: .nothing) }
            let toPanel = app.output.targets.contains(.panel)
            let toClipboard = app.output.targets.contains(.clipboard)
            let toApp = app.output.targets.contains(.app)
            let text = output.stdout
            if text.isEmpty {
                guard toPanel else { return MicroAppResultPlan(show: .toast(noOutputNote)) }
                return MicroAppResultPlan(show: .panel(MicroAppPanelContent(title: title, text: "", style: app.output.style,
                                                                            isError: false, notes: [noOutputNote] + cut(output))))
            }
            // Console text goes to the clipboard and the app without its escape codes.
            let plain = app.output.style == .console ? ConsoleText.plain(text) : text
            let clipboard = toClipboard ? plain : nil
            if toApp {
                let notes = (toClipboard ? [copiedNote] : []) + cut(output)
                return MicroAppResultPlan(clipboard: clipboard, app: plain, show: notes.isEmpty ? .nothing : .toast(notes.joined(separator: ", ")))
            }
            guard toPanel else {
                let toast = ([copiedNote] + cut(output)).joined(separator: ", ")
                return MicroAppResultPlan(clipboard: clipboard, show: .toast(toast))
            }
            let notes = (toClipboard ? [copiedNote] : []) + cut(output)
            return MicroAppResultPlan(clipboard: clipboard,
                                      show: .panel(MicroAppPanelContent(title: title, text: text, style: app.output.style,
                                                                        isError: false, notes: notes)))
        }
    }
}

/// The steps of one micro-app start, in order. Only one flow is open at a time.
public enum MicroAppStartStep: Equatable, Sendable {
    /// The binding does not work: show this error and start nothing.
    case error(String)
    /// The file content is not approved: show the approval panel first.
    case approve(MicroApp, hash: String)
    /// Approved: run the command.
    case run(MicroApp)

    /// The first step of a start of the micro-app bound as `id`.
    public static func first(id: String, catalog: MicroAppCatalog, approvals: MicroAppApprovals, folder: String) -> MicroAppStartStep {
        let resolution = catalog.resolve(id)
        guard case .working(let app, let entry) = resolution else {
            return .error(resolution.problem(id: id, folder: folder) ?? "Micro-app `\(id)` cannot start")
        }
        return approvals.isApproved(id: app.id, hash: entry.contentHash) ? .run(app) : .approve(app, hash: entry.contentHash)
    }

    /// The first step of a start of the file `file` of the folder, as launcha starts a broken
    /// file: its own errors, or the normal start when the file works by now.
    public static func first(file: String, catalog: MicroAppCatalog, approvals: MicroAppApprovals, folder: String) -> MicroAppStartStep {
        switch catalog.resolve(file: file) {
        case .working(let app, _):
            return first(id: app.id, catalog: catalog, approvals: approvals, folder: folder)
        case .broken(let entry):
            return .error(MicroAppResolution.broken(entry).problem(id: entry.bindingID, folder: folder) ?? "Micro-app \(file) has errors")
        case .missing:
            return .error("Micro-app file `\(file)` not found in \(folder)")
        }
    }
}
