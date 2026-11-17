import Foundation

// MARK: - Candidates

/// One thing launcha can open: an app, a URL, a micro-app or an item of the menu.
public struct LaunchaCandidate: Hashable, Sendable, Identifiable {
    public enum Target: Hashable, Sendable {
        /// Bundle identifier, e.g. "com.apple.Safari".
        case app(String)
        /// Absolute URL string.
        case url(String)
        /// Micro-app id: what a `micro` binding to it would hold.
        case micro(String)
        /// The key path of a menu item, from the top level.
        case menu([String])
    }

    /// Stable identity. Launch history is stored under this value, so it must not change
    /// between runs for the same app or URL.
    public var id: String
    /// Name shown in the list and used for matching.
    public var name: String
    public var target: Target

    public init(id: String, name: String, target: Target) {
        self.id = id
        self.name = name
        self.target = target
    }

    /// App candidate. Identity is "app:" + the bundle identifier in lower case
    /// (bundle identifiers are case-insensitive).
    public static func app(bundleID: String, name: String) -> LaunchaCandidate {
        LaunchaCandidate(id: "app:" + bundleID.lowercased(), name: name, target: .app(bundleID))
    }

    /// URL candidate. Identity is "url:" + the URL string as given.
    public static func url(_ url: String, name: String) -> LaunchaCandidate {
        LaunchaCandidate(id: "url:" + url, name: name, target: .url(url))
    }

    /// Micro-app candidate. Identity is "micro:" + the micro-app id.
    public static func micro(id: String, name: String) -> LaunchaCandidate {
        LaunchaCandidate(id: "micro:" + id, name: name, target: .micro(id))
    }

    /// Menu item candidate. Identity is "menu:" + the key path joined by spaces. Keys never
    /// contain a space (Space is the named key "space"), so the identity is unambiguous and stays
    /// the same across reloads while the item keeps its keys.
    public static func menu(path: [String], name: String) -> LaunchaCandidate {
        LaunchaCandidate(id: "menu:" + path.joined(separator: " "), name: name, target: .menu(path))
    }
}

// MARK: - Menu candidates

/// An item of the menu as launcha lists it.
public struct LaunchaMenuCandidate: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable {
        /// An action: choosing it runs it like its key in the menu.
        case action
        /// A group: choosing it opens the menu there.
        case group
        /// A group with `batch`: choosing it runs its actions.
        case batch
        /// A `dynamic://` item: choosing it loads its menu and opens it. Its items are not listed.
        case dynamic
    }

    public var candidate: LaunchaCandidate
    /// Keys from the top level to the item.
    public var path: [String]
    /// Titles of the groups above the item, from the top level.
    public var breadcrumb: [String]
    /// The app's identifier of the item, from `Item.id`.
    public var itemID: String?
    public var kind: Kind

    public init(candidate: LaunchaCandidate, path: [String], breadcrumb: [String], itemID: String?, kind: Kind) {
        self.candidate = candidate
        self.path = path
        self.breadcrumb = breadcrumb
        self.itemID = itemID
        self.kind = kind
    }

    public var id: String { candidate.id }

    /// Every item of `items` that launcha lists, depth-first: actions, groups (and their items),
    /// batch groups and dynamic items. A hidden item and everything under it is left out. The
    /// name is the label, or the keys of the path when the label is empty. A second item with the
    /// same keys (a config error) is left out.
    public static func from(_ items: [Item]) -> [LaunchaMenuCandidate] {
        var result: [LaunchaMenuCandidate] = []
        var seen: Set<String> = []
        func visit(_ items: [Item], path: [String], breadcrumb: [String]) {
            for item in items where !item.flags.hidden {
                let itemPath = path + [item.key]
                let name = item.label.isEmpty ? itemPath.map(SequenceKey.display).joined(separator: " ") : item.label
                let kind: Kind
                switch item.action {
                case .group: kind = item.flags.batch ? .batch : .group
                case .dynamic: kind = .dynamic
                case .app, .url, .micro, .shell, .shortcut: kind = .action
                }
                let candidate = LaunchaCandidate.menu(path: itemPath, name: name)
                if seen.insert(candidate.id).inserted {
                    result.append(LaunchaMenuCandidate(candidate: candidate, path: itemPath, breadcrumb: breadcrumb,
                                                       itemID: item.id, kind: kind))
                }
                if case .group(let children) = item.action {
                    visit(children, path: itemPath, breadcrumb: breadcrumb + [name])
                }
            }
        }
        visit(items, path: [], breadcrumb: [])
        return result
    }
}

// MARK: - Micro-app candidates

/// What a launcha start of a micro-app candidate hands to the micro-app flow.
public enum LaunchaMicroStart: Hashable, Sendable {
    /// A working micro-app: the same start as a binding to this id.
    case id(String)
    /// A broken file: show this file's own errors (or start it, if it works by now).
    case file(String)
}

/// A micro-app as launcha lists it: the searchable candidate and what the row shows.
public struct LaunchaMicroCandidate: Equatable, Sendable, Identifiable {
    public var candidate: LaunchaCandidate
    public var start: LaunchaMicroStart
    /// The file name in the micro-apps folder, such as `dns-lookup.yaml`.
    public var file: String
    /// The `description` of a working micro-app; empty for a broken file.
    public var description: String
    /// Why a broken file does not work, in one line; `nil` for a working micro-app.
    public var problem: String?

    public init(candidate: LaunchaCandidate, start: LaunchaMicroStart, file: String, description: String, problem: String?) {
        self.candidate = candidate
        self.start = start
        self.file = file
        self.description = description
        self.problem = problem
    }

    public var id: String { candidate.id }
    public var isWorking: Bool { problem == nil }
}

extension LaunchaCandidate {
    /// Candidate of a broken micro-app file. Identity is "micro-file:" + the file name, so it
    /// never collides with a working micro-app or another broken file that claims the same id.
    public static func brokenMicroFile(_ file: String, name: String) -> LaunchaCandidate {
        LaunchaCandidate(id: "micro-file:" + file, name: name, target: .micro(file))
    }
}

extension MicroAppCatalog {
    /// The micro-apps launcha lists, in file-name order: every file of the folder except those
    /// with `hidden: true`. A working micro-app starts by its id; a broken file is listed as not
    /// working and starts by its file name, so its own errors are shown, also when its `id`
    /// collides with another file. A broken file counts as hidden when its `hidden` key could be read.
    /// Bindings do not matter for the list. The name is the label of the first `micro` binding
    /// (depth-first) with a label that finds this file, else the `name` key (also of a broken
    /// file, when it could be read), else the id.
    public func launchaCandidates(bindings items: [Item]) -> [LaunchaMicroCandidate] {
        var labels: [String: String] = [:]
        for binding in BindingTree.flatten(items) {
            if case .micro(let id) = binding.item.action, !binding.item.label.isEmpty, labels[id] == nil {
                labels[id] = binding.item.label
            }
        }
        /// The label of a binding whose id finds `entry`.
        func label(for entry: MicroAppEntry) -> String? {
            let ids = [entry.bindingID, entry.explicitID, entry.fileID].compactMap { $0 }
            for id in ids {
                guard let label = labels[id] else { continue }
                switch resolve(id) {
                case .working(_, let found), .broken(let found): if found.file == entry.file { return label }
                case .missing: continue
                }
            }
            return nil
        }
        return entries.compactMap { entry in
            guard !entry.isHidden else { return nil }
            let id = entry.bindingID
            if let app = entry.app {
                let name = label(for: entry) ?? app.shownName
                return LaunchaMicroCandidate(candidate: .micro(id: app.id, name: name), start: .id(app.id),
                                             file: entry.file, description: app.description, problem: nil)
            }
            let name = label(for: entry) ?? entry.brokenName ?? id
            let problem = entry.issues.first.map { "line \($0.line): \($0.message)" } ?? "the file has errors"
            return LaunchaMicroCandidate(candidate: .brokenMicroFile(entry.file, name: name), start: .file(entry.file),
                                         file: entry.file, description: "", problem: problem)
        }
    }
}

// MARK: - Name matching

/// How a query matches a name. Smaller is better. Used only as a tie-breaker after usage.
public enum MatchQuality: Int, Comparable, Sendable, CaseIterable {
    /// The whole name, ignoring case, diacritics, spaces and punctuation.
    case exact
    /// The start of the name.
    case prefix
    /// The start of a later word, or each query word starts a name word in order.
    case wordStart
    /// The first letters of the name words, in order ("vsc" → "Visual Studio Code").
    case initials
    /// Anywhere in the name.
    case substring

    public static func < (lhs: MatchQuality, rhs: MatchQuality) -> Bool { lhs.rawValue < rhs.rawValue }
}

public enum NameMatcher {
    /// Best match of `query` against `name`, or nil. Also tries `query` as if it was typed
    /// with the wrong keyboard layout (Russian or Ukrainian ↔ US), see `KeyboardLayoutSwap`.
    /// An empty query (or one without letters or digits) returns nil.
    public static func match(_ query: String, name: String) -> MatchQuality? {
        let target = MatchName(name)
        guard !target.words.isEmpty else { return nil }
        return KeyboardLayoutSwap.variants(of: query)
            .compactMap { match(words: words(in: $0), target: target) }
            .min()
    }

    /// Lower case without diacritics: "Café" → "cafe", "Ёлка" → "елка".
    public static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil).lowercased()
    }

    /// Folded words of a query: split at every character that is not a letter or a digit.
    static func words(in query: String) -> [String] {
        fold(query).split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    private static func match(words query: [String], target: MatchName) -> MatchQuality? {
        guard !query.isEmpty else { return nil }
        let compact = query.joined()
        if target.compact == compact { return .exact }
        if target.compact.hasPrefix(compact) { return .prefix }
        if target.tails.dropFirst().contains(where: { $0.hasPrefix(compact) }) { return .wordStart }
        if query.count > 1, startsWordsInOrder(query, target.words) { return .wordStart }
        if compact.count > 1, isSubsequence(compact, of: target.initials) { return .initials }
        if target.compact.contains(compact) { return .substring }
        return nil
    }

    private static func startsWordsInOrder(_ query: [String], _ words: [String]) -> Bool {
        var index = words.startIndex
        for token in query {
            guard let found = words[index...].firstIndex(where: { $0.hasPrefix(token) }) else { return false }
            index = words.index(after: found)
        }
        return true
    }

    private static func isSubsequence(_ text: String, of other: String) -> Bool {
        var rest = Substring(other)
        for character in text {
            guard let found = rest.firstIndex(of: character) else { return false }
            rest = rest[rest.index(after: found)...]
        }
        return true
    }
}

/// A name prepared for matching.
private struct MatchName {
    /// Folded words. Split at non-letters/digits and at camel case ("FaceTime" → face, time).
    let words: [String]
    let compact: String
    /// words[i...].joined() for every i.
    let tails: [String]
    let initials: String

    init(_ name: String) {
        var raw: [String] = []
        var current = ""
        var previous: Character?
        for character in name {
            guard character.isLetter || character.isNumber else {
                if !current.isEmpty { raw.append(current) }
                current = ""
                previous = nil
                continue
            }
            if let previous, previous.isLowercase, character.isUppercase, !current.isEmpty {
                raw.append(current)
                current = ""
            }
            current.append(character)
            previous = character
        }
        if !current.isEmpty { raw.append(current) }
        let folded = raw.map(NameMatcher.fold).filter { !$0.isEmpty }
        words = folded
        compact = folded.joined()
        tails = folded.indices.map { folded[$0...].joined() }
        initials = String(folded.compactMap(\.first))
    }
}

/// Text typed with the wrong keyboard layout: the same physical keys on the US layout and on
/// the Russian or Ukrainian layout (ЙЦУКЕН, as on macOS "Russian - PC" and "Ukrainian - PC").
public enum KeyboardLayoutSwap {
    /// US key → Russian letter.
    private static let russian: [Character: Character] = [
        "q": "й", "w": "ц", "e": "у", "r": "к", "t": "е", "y": "н", "u": "г", "i": "ш", "o": "щ",
        "p": "з", "[": "х", "]": "ъ", "a": "ф", "s": "ы", "d": "в", "f": "а", "g": "п", "h": "р",
        "j": "о", "k": "л", "l": "д", ";": "ж", "'": "э", "z": "я", "x": "ч", "c": "с", "v": "м",
        "b": "и", "n": "т", "m": "ь", ",": "б", ".": "ю", "`": "ё",
    ]
    /// US key → Ukrainian letter where it differs from Russian.
    private static let ukrainianDifferences: [Character: Character] = [
        "s": "і", "]": "ї", "'": "є",
    ]
    private static let ukrainian: [Character: Character] = russian.merging(ukrainianDifferences) { $1 }
    /// Cyrillic letter → US key, for both layouts.
    private static let latin: [Character: Character] = {
        var map: [Character: Character] = [:]
        for (key, letter) in ukrainian { map[letter] = key }
        for (key, letter) in russian { map[letter] = key }
        return map
    }()

    /// The lower-cased query first, then each distinct re-typed version:
    /// Cyrillic letters on US keys ("ыфафкш" → "safari") and US keys on the Russian and
    /// Ukrainian layouts ("ntktuhfv" → "телеграм"). Characters without a mapping stay.
    public static func variants(of query: String) -> [String] {
        let lower = query.lowercased()
        var result = [lower]
        for map in [latin, russian, ukrainian] {
            var changed = false
            let converted = String(lower.map { character -> Character in
                guard let mapped = map[character] else { return character }
                changed = true
                return mapped
            })
            if changed, !result.contains(converted) { result.append(converted) }
        }
        return result
    }
}

// MARK: - Launch history

/// What happened when launcha tried to open a candidate.
public enum LaunchOutcome: Equatable, Sendable {
    /// SwiftKey opened the app or URL.
    case opened
    /// The app was already running and SwiftKey activated it.
    case activated
    /// Opening failed. Not counted.
    case failed
    /// The candidate was shown in Finder. Not counted.
    case revealed

    /// True for outcomes that count as a launch.
    public var counts: Bool { self == .opened || self == .activated }
}

/// Successful SwiftKey launches per candidate id: event times inside the rolling window, and the
/// last launch time (kept after its events leave the window). Time is always passed in.
public struct LaunchHistory: Equatable, Sendable, Codable {
    /// Events count when they are not older than this: 7 days.
    public static let window: TimeInterval = 7 * 24 * 60 * 60
    /// At most this many events per id. The oldest go first.
    public static let maxEventsPerEntry = 500
    /// At most this many ids. The ids with the oldest last launch go first.
    public static let maxEntries = 1000

    public struct Entry: Equatable, Sendable, Codable {
        /// Launch times inside the window, oldest first.
        public var events: [Date]
        /// Time of the latest successful launch.
        public var lastLaunch: Date

        public init(events: [Date], lastLaunch: Date) {
            self.events = events
            self.lastLaunch = lastLaunch
        }
    }

    public private(set) var entries: [String: Entry]

    public init(entries: [String: Entry] = [:]) {
        self.entries = entries
    }

    /// Records the outcome for `id` at `time`. Only `.opened` and `.activated` change the
    /// history. Returns true when the history changed. Also prunes events older than the window.
    @discardableResult
    public mutating func record(_ outcome: LaunchOutcome, id: String, at time: Date) -> Bool {
        guard outcome.counts else { return false }
        var entry = entries[id] ?? Entry(events: [], lastLaunch: time)
        let index = entry.events.firstIndex { $0 > time } ?? entry.events.endIndex
        entry.events.insert(time, at: index)
        entry.lastLaunch = max(entry.lastLaunch, time)
        if entry.events.count > LaunchHistory.maxEventsPerEntry {
            entry.events.removeFirst(entry.events.count - LaunchHistory.maxEventsPerEntry)
        }
        entries[id] = entry
        prune(now: time)
        return true
    }

    /// Launches of `id` with time ≥ `now` − 7 days. The boundary is inclusive.
    public func recentCount(id: String, now: Date) -> Int {
        guard let events = entries[id]?.events else { return 0 }
        let cutoff = now.addingTimeInterval(-LaunchHistory.window)
        return events.reduce(0) { $1 >= cutoff ? $0 + 1 : $0 }
    }

    public func lastLaunch(id: String) -> Date? {
        entries[id]?.lastLaunch
    }

    /// Drops events older than the window (keeping `lastLaunch`) and the oldest entries
    /// above `maxEntries`.
    public mutating func prune(now: Date) {
        let cutoff = now.addingTimeInterval(-LaunchHistory.window)
        for id in entries.keys {
            entries[id]?.events.removeAll { $0 < cutoff }
        }
        guard entries.count > LaunchHistory.maxEntries else { return }
        let ordered = entries.sorted { lhs, rhs in
            lhs.value.lastLaunch != rhs.value.lastLaunch ? lhs.value.lastLaunch < rhs.value.lastLaunch : lhs.key < rhs.key
        }
        for (id, _) in ordered.prefix(entries.count - LaunchHistory.maxEntries) {
            entries[id] = nil
        }
    }

    /// Removes the history of one id.
    public mutating func forget(id: String) {
        entries[id] = nil
    }

    // Codable: {"entries": {"<id>": {"events": [...], "lastLaunch": ...}}}.
    // `encoded()`/`decode(_:)` write dates as seconds since 1970.

    /// JSON with sorted keys and dates as seconds since 1970, ending with "\n".
    public func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        var data = (try? encoder.encode(self)) ?? Data("{\"entries\":{}}".utf8)
        data.append(contentsOf: Array("\n".utf8))
        return data
    }

    /// Reads data written by `encoded()`. Throws a DecodingError for anything else.
    public static func decode(_ data: Data) throws -> LaunchHistory {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(LaunchHistory.self, from: data)
    }
}

// MARK: - Search

public struct LaunchaMatch: Equatable, Sendable {
    public var candidate: LaunchaCandidate
    /// nil for an empty query: every candidate is listed.
    public var quality: MatchQuality?
    /// Successful launches in the last 7 days.
    public var recentCount: Int
    public var lastLaunch: Date?

    public init(candidate: LaunchaCandidate, quality: MatchQuality?, recentCount: Int, lastLaunch: Date?) {
        self.candidate = candidate
        self.quality = quality
        self.recentCount = recentCount
        self.lastLaunch = lastLaunch
    }
}

public enum LaunchaSearch {
    /// Candidates that match `query`, ranked. A query without letters or digits lists every
    /// candidate. Duplicate ids keep the first candidate. Order:
    /// 1. more successful launches in the last 7 days (at `now`);
    /// 2. later last launch (never launched is last);
    /// 3. better `MatchQuality`;
    /// 4. name (localized, case-insensitive), then id.
    public static func results(for query: String, in candidates: [LaunchaCandidate],
                               history: LaunchHistory, now: Date) -> [LaunchaMatch] {
        let listAll = KeyboardLayoutSwap.variants(of: query).allSatisfy { NameMatcher.words(in: $0).isEmpty }
        var seen: Set<String> = []
        var matches: [LaunchaMatch] = []
        for candidate in candidates where seen.insert(candidate.id).inserted {
            let quality = listAll ? nil : NameMatcher.match(query, name: candidate.name)
            guard listAll || quality != nil else { continue }
            matches.append(LaunchaMatch(candidate: candidate, quality: quality,
                                        recentCount: history.recentCount(id: candidate.id, now: now),
                                        lastLaunch: history.lastLaunch(id: candidate.id)))
        }
        return matches.sorted(by: ranksBefore)
    }

    static func ranksBefore(_ lhs: LaunchaMatch, _ rhs: LaunchaMatch) -> Bool {
        if lhs.recentCount != rhs.recentCount { return lhs.recentCount > rhs.recentCount }
        if lhs.lastLaunch != rhs.lastLaunch {
            guard let left = lhs.lastLaunch else { return false }
            guard let right = rhs.lastLaunch else { return true }
            return left > right
        }
        if lhs.quality != rhs.quality {
            return (lhs.quality?.rawValue ?? Int.max) < (rhs.quality?.rawValue ?? Int.max)
        }
        let order = lhs.candidate.name.localizedCaseInsensitiveCompare(rhs.candidate.name)
        if order != .orderedSame { return order == .orderedAscending }
        return lhs.candidate.id < rhs.candidate.id
    }
}

// MARK: - Leader double tap

/// What a leader key press means.
public enum LeaderPress: Equatable, Sendable {
    /// A repeat while the key is held, or the leader is not released yet. Ignore it.
    case ignored
    /// An ordinary leader press: pass `.leader` to `LeaderMachine` at once.
    case single
    /// The second press of a double tap: close the leader menu and open launcha.
    case double
}

/// Recognizes a double tap of the leader. It never delays anything: the first press is a
/// `.single` at once (the menu opens), and the second press decides.
///
/// A press is `.double` when all are true:
/// - double tap is enabled;
/// - the previous counted press opened the menu (the menu was closed before it);
/// - the leader was released between the two presses;
/// - the menu is still open at the top level, with no sequence input in between;
/// - the second press comes at most `window` seconds after the first.
/// A press while the leader is still held (no release since the last press) is `.ignored`,
/// so key repeats never count twice. The caller must report releases.
///
/// If a release is lost (for example the hotkey was unregistered while the key was down),
/// a press more than `staleHold` seconds after the previous press counts as a new press.
/// Key repeats come much faster than that, so a held key stays ignored.
public struct LeaderDoubleTap: Sendable {
    /// Seconds without any press after which a missing release is assumed.
    public static let staleHold: TimeInterval = 2

    public var isEnabled: Bool
    public var window: TimeInterval
    public private(set) var isHeld = false
    private var firstPressAt: TimeInterval?
    private var lastPressAt: TimeInterval?

    public init(isEnabled: Bool = true, window: TimeInterval = 0.3) {
        self.isEnabled = isEnabled
        self.window = window
    }

    public init(_ settings: LaunchaSettings) {
        self.init(isEnabled: settings.doubleTap, window: settings.doubleTapWindow)
    }

    /// A leader key-down at `time` (seconds, any monotonic clock).
    /// `menuOpenAtRoot`: the leader menu is open with an empty path, before this press.
    /// `menuOpen`: the leader menu is open at all, before this press.
    public mutating func press(at time: TimeInterval, menuOpen: Bool, menuOpenAtRoot: Bool) -> LeaderPress {
        defer { lastPressAt = time }
        if isHeld, let last = lastPressAt, time - last > LeaderDoubleTap.staleHold || time < last {
            isHeld = false
        }
        guard !isHeld else { return .ignored }
        isHeld = true
        if isEnabled, menuOpen, menuOpenAtRoot, let first = firstPressAt, time >= first, time - first <= window {
            firstPressAt = nil
            return .double
        }
        firstPressAt = isEnabled && !menuOpen ? time : nil
        return .single
    }

    /// Convenience: reads the menu state from `machine`.
    public mutating func press(at time: TimeInterval, machine: LeaderMachine) -> LeaderPress {
        press(at: time, menuOpen: machine.isOpen, menuOpenAtRoot: machine.isOpen && machine.path.isEmpty)
    }

    /// The leader key was released.
    public mutating func release() {
        isHeld = false
    }

    /// Any key, ⌫ or selection in the menu. The next leader press is not a double tap.
    public mutating func sequenceInput() {
        firstPressAt = nil
    }

    /// The menu closed for another reason. Keeps `isHeld`: the key state is physical.
    public mutating func reset() {
        firstPressAt = nil
    }
}
