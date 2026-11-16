import Foundation

/// One node of the menu tree: a key and what it does. The app builds this tree from its
/// YAML `MenuItem`s; the core uses it for the leader state machine and launcha.
public struct Item: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        case group([Item])
        /// An app to launch: a bundle identifier ("com.apple.Safari") or an app path.
        case app(String)
        /// Absolute URL string, e.g. "https://github.com".
        case url(String)
        /// A micro-app id, e.g. "format-json". The micro-app does not have to be loaded.
        case micro(String)
        /// A shell command.
        case shell(String)
        /// The name of an Apple Shortcut.
        case shortcut(String)
        /// A command whose output is a menu.
        case dynamic(String)
    }

    /// Per-item behaviour from the config.
    public struct Flags: Equatable, Sendable {
        /// The menu stays open after the action runs.
        public var sticky: Bool
        /// Show a notification after the action runs.
        public var notify: Bool
        /// Choosing the group runs every child action.
        public var batch: Bool
        /// Not shown in the menu or launcha, but reachable by its key.
        public var hidden: Bool

        public init(sticky: Bool = false, notify: Bool = false, batch: Bool = false, hidden: Bool = false) {
            self.sticky = sticky
            self.notify = notify
            self.batch = batch
            self.hidden = hidden
        }
    }

    /// A `SequenceKey` name.
    public var key: String
    public var label: String
    public var action: Action
    public var flags: Flags
    /// The app's identifier of the item this node came from, so effects can name it.
    public var id: String?

    public init(key: String, label: String, action: Action, flags: Flags = Flags(), id: String? = nil) {
        self.key = key
        self.label = label
        self.action = action
        self.flags = flags
        self.id = id
    }

    public static func group(_ key: String, _ label: String, _ items: [Item]) -> Item { Item(key: key, label: label, action: .group(items)) }
    public static func app(_ key: String, _ label: String, _ bundleID: String) -> Item { Item(key: key, label: label, action: .app(bundleID)) }
    public static func url(_ key: String, _ label: String, _ url: String) -> Item { Item(key: key, label: label, action: .url(url)) }
    public static func micro(_ key: String, _ label: String, _ id: String) -> Item { Item(key: key, label: label, action: .micro(id)) }
    public static func shell(_ key: String, _ label: String, _ command: String) -> Item { Item(key: key, label: label, action: .shell(command)) }
    public static func shortcut(_ key: String, _ label: String, _ name: String) -> Item { Item(key: key, label: label, action: .shortcut(name)) }
    public static func dynamic(_ key: String, _ label: String, _ command: String) -> Item { Item(key: key, label: label, action: .dynamic(command)) }

    public var isGroup: Bool {
        if case .group = action { return true }
        return false
    }
    /// Children of a group; nil for an action.
    public var children: [Item]? {
        if case .group(let items) = action { return items }
        return nil
    }
}

public enum UnknownKeyBehavior: String, Sendable, CaseIterable {
    case shake, close
}

/// Launcha settings: the name search panel.
public struct LaunchaSettings: Equatable, Sendable {
    /// Allowed range of `doubleTapWindow`.
    public static let doubleTapWindowRange: ClosedRange<Double> = 0.1...1.0

    /// Separate global hotkey for launcha. nil (default) means no separate hotkey.
    public var hotkey: Hotkey? = nil
    /// A double tap of the leader opens launcha. On by default.
    public var doubleTap: Bool = true
    /// Maximum seconds between the two leader presses of a double tap.
    public var doubleTapWindow: Double = 0.3
    /// A query of digits and an operator shows its value first. On by default.
    public var calculator: Bool = true

    public init() {}
}
