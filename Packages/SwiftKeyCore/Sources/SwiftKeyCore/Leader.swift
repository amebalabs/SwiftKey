import Foundation

public enum LeaderEvent: Equatable, Sendable {
    /// The leader hotkey fired.
    case leader
    /// A sequence key name (`SequenceKey`). `option` is true while ⌥ is held: it inverts the
    /// sticky flag of an action and runs a group as a batch.
    case key(String, option: Bool = false)
    /// ⌫: back one level; at the top level the menu closes.
    case back
    /// ⌘↑: up one level; at the top level nothing happens.
    case up
    /// Esc
    case escape
}

public enum LeaderEffect: Equatable, Sendable {
    /// Nothing to do (event ignored).
    case none
    /// Menu opened at the top level.
    case open
    /// Now showing the group at `path` (after entering a group or going back).
    case show(path: [String])
    /// Run this action; the menu is now closed.
    case run(Item)
    /// Run this sticky action; the menu stays open at the same path.
    case runAndStay(Item)
    /// Run the actions of `group` in order (groups and dynamic items among its children are
    /// skipped); the menu is now closed.
    case runBatch(group: Item, actions: [Item])
    /// Load the children of this dynamic item, then pass them to `enterLoaded(_:forKey:)`.
    /// The menu stays open at the same path.
    case loadDynamic(Item)
    /// No binding for this key. `closed` is true when the menu closed because of it.
    case reject(key: String, closed: Bool)
    /// Menu closed.
    case close
}

/// Leader-menu state machine: closed → open(path) → run or close.
public struct LeaderMachine: Sendable {
    public private(set) var isOpen: Bool
    /// Keys of the groups entered so far.
    public private(set) var path: [String]
    /// Replacing the items forgets loaded dynamic levels; the path is checked at the next event.
    public var items: [Item] {
        didSet { loaded = [:] }
    }
    public var unknownKey: UnknownKeyBehavior
    /// Sticky actions keep the menu open only where the overlay can stay; false makes every
    /// action close the menu.
    public var stickyAllowed: Bool
    /// Children of entered dynamic items, by the path that leads to them.
    private var loaded: [[String]: [Item]] = [:]

    public init(items: [Item], unknownKey: UnknownKeyBehavior = .shake, stickyAllowed: Bool = true) {
        self.isOpen = false
        self.path = []
        self.items = items
        self.unknownKey = unknownKey
        self.stickyAllowed = stickyAllowed
    }

    /// A machine that is already open at `path`, where `levels[i]` are the children shown after
    /// entering `path[0...i]`. Lets an app that keeps the open levels itself ask what a key does.
    public init(items: [Item], openAt path: [String], levels: [[Item]], unknownKey: UnknownKeyBehavior = .shake,
                stickyAllowed: Bool = true) {
        self.init(items: items, unknownKey: unknownKey, stickyAllowed: stickyAllowed)
        isOpen = true
        self.path = path
        for (index, children) in levels.enumerated() where index < path.count {
            loaded[Array(path[...index])] = children
        }
    }

    /// Children of the current group (top level when `path` is empty).
    public var currentItems: [Item] {
        level(at: path) ?? items
    }

    /// The children shown at `path`: loaded dynamic levels first, else the groups of `items`.
    private func level(at path: [String]) -> [Item]? {
        var level = items
        for index in path.indices {
            let prefix = Array(path[...index])
            if let children = loaded[prefix] {
                level = children
                continue
            }
            guard let children = level.first(where: { $0.key == path[index] })?.children else { return nil }
            level = children
        }
        return level
    }

    /// True when `path` still leads to a group in `items` or a loaded level.
    private var pathExists: Bool {
        level(at: path) != nil
    }

    /// Rules:
    /// - closed + .leader → open with empty path, `.open`. closed + anything else → `.none`.
    /// - open + .leader → close, `.close` (the leader toggles the menu).
    /// - open + .escape → close, `.close`.
    /// - open + .back → pop one level and `.show(path:)`; at the top level close and `.close`.
    /// - open + .up → pop one level and `.show(path:)`; at the top level `.none`.
    /// - open + .key(k, option):
    ///   - group with `batch` or ⌥ → close, `.runBatch`; other group → push, `.show(path:)`;
    ///   - dynamic item → `.loadDynamic(item)`, still open;
    ///   - action that is sticky (its flag inverted by ⌥) where sticky is allowed → `.runAndStay(item)`;
    ///   - other action → close, `.run(item)`;
    ///   - no match → `.reject(key: k, closed:)`, closing only when `unknownKey == .close`.
    /// Setting `items` while open does not change `path`; if `path` no longer exists, the next
    /// event treats the machine as at the top level.
    public mutating func handle(_ event: LeaderEvent) -> LeaderEffect {
        guard isOpen else {
            guard event == .leader else { return .none }
            isOpen = true
            path = []
            return .open
        }
        if !pathExists {
            path = []
            loaded = [:]
        }
        switch event {
        case .leader, .escape:
            reset()
            return .close
        case .back:
            guard !path.isEmpty else {
                reset()
                return .close
            }
            pop()
            return .show(path: path)
        case .up:
            guard !path.isEmpty else { return .none }
            pop()
            return .show(path: path)
        case .key(let key, let option):
            guard let item = currentItems.first(where: { $0.key == key }) else {
                let closes = unknownKey == .close
                if closes { reset() }
                return .reject(key: key, closed: closes)
            }
            switch item.action {
            case .group(let children):
                if option || item.flags.batch {
                    reset()
                    return .runBatch(group: item, actions: children.filter(\.isBatchAction))
                }
                path.append(key)
                return .show(path: path)
            case .dynamic:
                return .loadDynamic(item)
            default:
                if item.flags.sticky != option, stickyAllowed {
                    return .runAndStay(item)
                }
                reset()
                return .run(item)
            }
        }
    }

    /// Enters the dynamic item `key` of the current level with its loaded `children`.
    /// `.none` when the menu is closed or the current level has no dynamic item with that key.
    public mutating func enterLoaded(_ children: [Item], forKey key: String) -> LeaderEffect {
        guard isOpen, let item = currentItems.first(where: { $0.key == key }),
              case .dynamic = item.action else { return .none }
        path.append(key)
        loaded[path] = children
        return .show(path: path)
    }

    /// Opens the menu at the item reached by `keys` from the top level, as a global item hotkey
    /// or a deep link does. A group opens the menu there (`.show(path:)`); an action is returned
    /// as `.run(item)` with the menu left closed; a path that leads nowhere gives `.none`.
    public mutating func open(at keys: [String]) -> LeaderEffect {
        let parentKeys = Array(keys.dropLast())
        let parent = parentKeys.isEmpty ? items : BindingTree.item(at: parentKeys, in: items)?.children
        guard let last = keys.last, let item = parent?.first(where: { $0.key == last }) else { return .none }
        if item.isGroup {
            isOpen = true
            path = keys
            loaded = [:]
            return .show(path: path)
        }
        reset()
        return .run(item)
    }

    /// Close without an effect (e.g. the panel lost focus).
    public mutating func reset() {
        isOpen = false
        path = []
        loaded = [:]
    }

    private mutating func pop() {
        loaded[path] = nil
        path.removeLast()
    }
}

private extension Item {
    /// A child that a batch runs: an action that is neither a group nor a dynamic menu.
    var isBatchAction: Bool {
        switch action {
        case .group, .dynamic: return false
        default: return true
        }
    }
}
