import Foundation

/// A part of the context of a micro-app start: what was in front when the person started it.
/// A file lists the parts it reads in `context:`; SwiftKey reads only those.
public enum MicroAppContextSource: String, Equatable, Hashable, Sendable, CaseIterable, Comparable {
    /// The active app. Needs no permission.
    case app
    /// The items selected in the front Finder window, and its folder. Needs Automation for Finder.
    case finder
    /// The front tab of the active browser, or of the browser used last. Needs Automation for it.
    case browser
    /// The text selected in the active app. Needs Accessibility.
    case selection
    /// The front window of the active app: its title and its document. Needs Accessibility.
    case window

    /// The fields of the source, as `${context.SOURCE.FIELD}` names them, in documentation order.
    public var fields: [String] {
        switch self {
        case .app: ["name", "bundle", "path", "pid"]
        case .finder: ["selection", "folder"]
        case .browser: ["url", "title", "name"]
        case .selection: ["text"]
        case .window: ["title", "document"]
        }
    }

    /// `true` for the sources SwiftKey reads with the Accessibility permission.
    public var needsAccessibility: Bool { self == .selection || self == .window }

    /// What the approval panel says the micro-app reads.
    public var summary: String {
        switch self {
        case .app: "the active app"
        case .finder: "the Finder selection"
        case .browser: "the browser tab"
        case .selection: "the selected text"
        case .window: "the front window"
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }

    /// `app, finder, browser, selection, window`.
    public static var listed: String { allCases.map(\.rawValue).joined(separator: ", ") }
}

/// One value of the context, such as `app.name`: `${context.app.name}` in a template,
/// `$TING_CONTEXT_APP_NAME` in code.
public struct MicroAppContextField: Hashable, Sendable, CustomStringConvertible {
    public let source: MicroAppContextSource
    public let name: String

    /// `nil` when `source` has no field `name`.
    public init?(source: MicroAppContextSource, name: String) {
        guard source.fields.contains(name) else { return nil }
        self.source = source
        self.name = name
    }

    /// The field of a `TING_CONTEXT_…` variable name, or `nil`.
    public init?(environmentName: String) {
        guard let field = Self.all.first(where: { $0.environmentName == environmentName }) else { return nil }
        self = field
    }

    public var description: String { "\(source.rawValue).\(name)" }

    /// `TING_CONTEXT_` + upper-case source + `_` + upper-case field.
    public var environmentName: String { Self.environmentPrefix + source.rawValue.uppercased() + "_" + name.uppercased() }

    public static let environmentPrefix = "TING_CONTEXT_"

    /// Every field of every source, in documentation order.
    public static let all: [MicroAppContextField] = MicroAppContextSource.allCases.flatMap { source in
        source.fields.compactMap { MicroAppContextField(source: source, name: $0) }
    }
}

/// The context values of one start. A field that SwiftKey could not read is the empty text.
public struct MicroAppContext: Equatable, Sendable {
    public var values: [MicroAppContextField: String]

    public init(_ values: [MicroAppContextField: String] = [:]) {
        self.values = values
    }

    public subscript(field: MicroAppContextField) -> String {
        get { values[field] ?? "" }
        set { values[field] = newValue }
    }

    /// Sets `source.name`; does nothing for a field the source does not have.
    public mutating func set(_ source: MicroAppContextSource, _ name: String, _ value: String) {
        if let field = MicroAppContextField(source: source, name: name) { values[field] = value }
    }

    /// `TING_CONTEXT_…` for every field of `sources`; a value SwiftKey could not read is empty.
    public func environment(for sources: [MicroAppContextSource]) -> [String: String] {
        var result: [String: String] = [:]
        for field in MicroAppContextField.all where sources.contains(field.source) {
            result[field.environmentName] = self[field]
        }
        return result
    }
}

/// What a `keys` or `paste` step, or the `app` output, sends to the app where the micro-app started.
public enum MicroAppKeyboardAction: Equatable, Sendable {
    /// Key presses, one after another.
    case keys([Hotkey])
    /// Text that SwiftKey pastes with ⌘V. `keepOnClipboard: false` puts the clipboard back afterwards.
    case paste(String, keepOnClipboard: Bool)

    /// `keys cmd+a, delete` or `paste 12 characters`, for notes and the console tool.
    public var summary: String {
        switch self {
        case .keys(let keys): "keys " + keys.map(\.string).joined(separator: ", ")
        case .paste(let text, _): "paste \(text.count) character" + (text.count == 1 ? "" : "s")
        }
    }
}

/// The AppleScript texts that read the Finder and browser context, and what their output means.
/// SwiftKey runs them with `/usr/bin/osascript`.
public enum MicroAppContextScripts {
    public static let finderBundleID = "com.apple.finder"

    /// The dialect of a browser's AppleScript dictionary.
    public enum BrowserDialect: Equatable, Sendable {
        /// Safari: `front document`.
        case safari
        /// Chrome and the browsers built on Chromium: `active tab of front window`.
        case chromium
    }

    /// The browsers SwiftKey can read, in the order SwiftKey picks one when none was used yet.
    public static let browsers: [(bundleID: String, dialect: BrowserDialect)] = [
        ("com.apple.Safari", .safari),
        ("com.google.Chrome", .chromium),
        ("company.thebrowser.Browser", .chromium),
        ("com.brave.Browser", .chromium),
        ("com.microsoft.edgemac", .chromium),
        ("com.vivaldi.Vivaldi", .chromium),
        ("org.chromium.Chromium", .chromium),
        ("com.apple.SafariTechnologyPreview", .safari),
        ("com.google.Chrome.beta", .chromium),
        ("com.google.Chrome.dev", .chromium),
        ("com.google.Chrome.canary", .chromium),
    ]

    public static func dialect(of bundleID: String) -> BrowserDialect? {
        browsers.first { $0.bundleID == bundleID }?.dialect
    }

    /// The browser to read: the active app when it is a browser, else the browser that was active
    /// last while it still runs, else the first running browser of `browsers`.
    public static func chooseBrowser(active: String?, lastUsed: String?, running: [String]) -> String? {
        if let active, dialect(of: active) != nil { return active }
        if let lastUsed, dialect(of: lastUsed) != nil, running.contains(lastUsed) { return lastUsed }
        return browsers.first { running.contains($0.bundleID) }?.bundleID
    }

    /// Prints the folder of the front Finder window (the Desktop without one), then one selected
    /// item per line.
    public static let finder = """
        with timeout of 5 seconds
            tell application id "com.apple.finder"
                set out to POSIX path of (insertion location as alias)
                repeat with anItem in (get selection as alias list)
                    set out to out & linefeed & POSIX path of anItem
                end repeat
            end tell
        end timeout
        return out
        """

    /// Prints the URL of the front tab, then its title; nothing without a window.
    public static func browser(bundleID: String, dialect: BrowserDialect) -> String {
        let tab: String
        let title: String
        let windows: String
        switch dialect {
        case .safari:
            windows = "documents"
            tab = "front document"
            title = "name"
        case .chromium:
            windows = "windows"
            tab = "active tab of front window"
            title = "title"
        }
        return """
            with timeout of 5 seconds
                tell application id "\(bundleID)"
                    if (count of \(windows)) is 0 then return ""
                    set theTab to \(tab)
                    set theURL to URL of theTab
                    set theTitle to \(title) of theTab
                end tell
            end timeout
            if theURL is missing value then set theURL to ""
            if theTitle is missing value then set theTitle to ""
            return theURL & linefeed & theTitle
            """
    }

    /// A path of `POSIX path of`, without the `/` that ends a folder (except `/` itself).
    static func trimmedPath(_ path: Substring) -> String {
        var text = String(path)
        while text.count > 1, text.hasSuffix("/") { text.removeLast() }
        return text
    }

    /// The output of `finder`: the folder, then the selected paths.
    public static func parseFinder(_ output: String) -> (folder: String, selection: [String]) {
        let lines = MicroAppRunRules.removingEndNewlines(output).split(separator: "\n", omittingEmptySubsequences: false)
        guard let first = lines.first, !first.isEmpty else { return ("", []) }
        return (trimmedPath(first), lines.dropFirst().filter { !$0.isEmpty }.map(trimmedPath))
    }

    /// The output of `browser`: the URL, then the title (which may hold more lines).
    public static func parseBrowser(_ output: String) -> (url: String, title: String) {
        let text = MicroAppRunRules.removingEndNewlines(output)
        guard let newline = text.firstIndex(of: "\n") else { return (text, "") }
        return (String(text[..<newline]), String(text[text.index(after: newline)...]))
    }

    /// Why a script failed, from the error text of osascript.
    public enum Failure: Equatable, Sendable {
        /// The person did not allow SwiftKey to control the app (error -1743).
        case notAllowed
        /// The app did not answer in time (error -1712).
        case timedOut
        /// The app quit or has no such window: the context is empty (errors -600, -609, -1728, -1719).
        case gone
        /// Anything else, with the error text.
        case other(String)
    }

    public static func failure(stderr: String) -> Failure {
        if stderr.contains("(-1743)") { return .notAllowed }
        if stderr.contains("(-1712)") { return .timedOut }
        for code in ["(-600)", "(-609)", "(-1728)", "(-1719)"] where stderr.contains(code) { return .gone }
        return .other(stderr.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// The message of a failed script that reads `appName`.
    public static func message(_ failure: Failure, appName: String, reading what: String) -> String? {
        switch failure {
        case .gone:
            return nil
        case .notAllowed:
            return "SwiftKey may not read \(what). Allow it in System Settings › Privacy & Security › Automation › SwiftKey › \(appName), then start the micro-app again."
        case .timedOut:
            return "\(appName) did not answer in time, so SwiftKey could not read \(what)."
        case .other(let text):
            return "SwiftKey could not read \(what) from \(appName): \(text.isEmpty ? "unknown error" : text)"
        }
    }

    /// Shown when a micro-app reads the selected text or the window, or sends keys, and SwiftKey
    /// does not have the Accessibility permission.
    public static let accessibilityMessage =
        "SwiftKey needs the Accessibility permission for this micro-app. Turn on SwiftKey in System Settings › Privacy & Security › Accessibility, then start it again."
}
