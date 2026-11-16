import Foundation

public enum LeaderEvent: Equatable, Sendable {
    /// The leader hotkey fired.
    case leader
    /// A sequence key name (`SequenceKey`).
    case key(String)
    /// ⌫
    case back
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
    public var items: [Item]
    public var unknownKey: UnknownKeyBehavior

    public init(items: [Item], unknownKey: UnknownKeyBehavior = .shake) {
        self.isOpen = false
        self.path = []
        self.items = items
        self.unknownKey = unknownKey
    }

    /// Children of the current group (top level when `path` is empty).
    public var currentItems: [Item] {
        if path.isEmpty { return items }
        return BindingTree.item(at: path, in: items)?.children ?? items
    }

    /// True when `path` still leads to a group in `items`.
    private var pathExists: Bool {
        path.isEmpty || BindingTree.item(at: path, in: items)?.isGroup == true
    }

    /// Rules:
    /// - closed + .leader → open with empty path, `.open`. closed + anything else → `.none`.
    /// - open + .leader → close, `.close` (the leader toggles the menu).
    /// - open + .escape → close, `.close`.
    /// - open + .back → pop one level and `.show(path:)`; at the top level close and `.close`.
    /// - open + .key(k): group → push, `.show(path:)`; action → close, `.run(item)`;
    ///   no match → `.reject(key: k, closed:)`, closing only when `unknownKey == .close`.
    /// Setting `items` while open does not change `path`; if `path` no longer exists, the next
    /// event treats the machine as at the top level.
    public mutating func handle(_ event: LeaderEvent) -> LeaderEffect {
        guard isOpen else {
            guard event == .leader else { return .none }
            isOpen = true
            path = []
            return .open
        }
        if !pathExists { path = [] }
        switch event {
        case .leader, .escape:
            reset()
            return .close
        case .back:
            guard !path.isEmpty else {
                reset()
                return .close
            }
            path.removeLast()
            return .show(path: path)
        case .key(let key):
            guard let item = currentItems.first(where: { $0.key == key }) else {
                let closes = unknownKey == .close
                if closes { reset() }
                return .reject(key: key, closed: closes)
            }
            if item.isGroup {
                path.append(key)
                return .show(path: path)
            }
            reset()
            return .run(item)
        }
    }

    /// Close without an effect (e.g. the panel lost focus).
    public mutating func reset() {
        isOpen = false
        path = []
    }
}
