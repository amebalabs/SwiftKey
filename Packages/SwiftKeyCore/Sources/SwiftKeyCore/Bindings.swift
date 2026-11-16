import Foundation

/// One row of the "Sequences" table.
public struct FlatBinding: Equatable, Sendable {
    public var sequence: [String]
    public var item: Item

    public init(sequence: [String], item: Item) {
        self.sequence = sequence
        self.item = item
    }
}

public enum SequenceProblem: Error, Equatable {
    case empty
    /// A key in the sequence is not a valid `SequenceKey` name.
    case invalidKey(String)
    /// A prefix of the sequence is an action, so it cannot start a longer sequence.
    case prefixIsAction(prefix: [String], label: String)
    /// The full sequence already belongs to another item.
    case taken(label: String)
    /// A group cannot move inside itself.
    case insideItself
    /// The source sequence of a move or remove does not exist.
    case notFound
}

/// Pure edits of the binding tree. All functions keep item order: new items are appended.
public enum BindingTree {
    /// Item at `sequence`, or nil. Empty sequence → nil.
    public static func item(at sequence: [String], in items: [Item]) -> Item? {
        guard let first = sequence.first, let item = items.first(where: { $0.key == first }) else { return nil }
        if sequence.count == 1 { return item }
        guard let children = item.children else { return nil }
        return self.item(at: Array(sequence.dropFirst()), in: children)
    }

    /// Every item depth-first, groups before their children, in item order.
    public static func flatten(_ items: [Item]) -> [FlatBinding] {
        flatten(items, prefix: [])
    }

    private static func flatten(_ items: [Item], prefix: [String]) -> [FlatBinding] {
        items.flatMap { item -> [FlatBinding] in
            let sequence = prefix + [item.key]
            return [FlatBinding(sequence: sequence, item: item)] + flatten(item.children ?? [], prefix: sequence)
        }
    }

    /// Checks whether an item can be placed at `sequence`.
    /// `moving` is the current sequence of the item being moved (nil for a new item):
    /// the item itself does not count as `.taken`, and a group may not move to a sequence that
    /// starts with its own sequence (`.insideItself`). Missing groups are not a problem.
    /// Order of checks: empty, invalidKey, insideItself, prefixIsAction (shortest prefix first), taken.
    public static func problem(placing sequence: [String], moving: [String]?, in items: [Item]) -> SequenceProblem? {
        guard !sequence.isEmpty else { return .empty }
        if let invalid = sequence.first(where: { !SequenceKey.isValid($0) }) { return .invalidKey(invalid) }
        if let moving, !moving.isEmpty, sequence.count > moving.count, sequence.starts(with: moving) {
            return .insideItself
        }
        for length in 1..<sequence.count {
            let prefix = Array(sequence.prefix(length))
            guard let item = item(at: prefix, in: items) else { break }
            if !item.isGroup { return .prefixIsAction(prefix: prefix, label: item.label) }
        }
        if sequence != moving, let existing = item(at: sequence, in: items) { return .taken(label: existing.label) }
        return nil
    }

    /// Adds `item` at `sequence` (its key becomes `sequence.last`). Creates missing groups
    /// with label "Group " + SequenceKey.display(key). Throws the `problem(...)` result.
    public static func insert(_ item: Item, at sequence: [String], in items: inout [Item]) throws {
        if let problem = problem(placing: sequence, moving: nil, in: items) { throw problem }
        place(item, at: sequence, in: &items)
    }

    /// Moves the item at `from` to `to`. Creates missing groups, then removes groups that became
    /// empty along the old path. Moving to the same sequence is a no-op.
    /// Throws `.notFound` or the `problem(...)` result; on throw `items` is unchanged.
    public static func move(from: [String], to: [String], in items: inout [Item]) throws {
        guard let moved = item(at: from, in: items) else { throw SequenceProblem.notFound }
        if from == to { return }
        if let problem = problem(placing: to, moving: from, in: items) { throw problem }
        var result = items
        _ = detach(at: from, in: &result)
        place(moved, at: to, in: &result)
        pruneEmptyGroups(along: Array(from.dropLast()), in: &result)
        items = result
    }

    /// Removes the item at `sequence` and then every ancestor group that became empty.
    /// Throws `.notFound`.
    public static func remove(at sequence: [String], in items: inout [Item]) throws {
        guard item(at: sequence, in: items) != nil else { throw SequenceProblem.notFound }
        _ = detach(at: sequence, in: &items)
        pruneEmptyGroups(along: Array(sequence.dropLast()), in: &items)
    }

    /// Turns the action at `prefix` into a group with the same key and label; the action
    /// moves inside under the same key (`t` → `t t`). Throws `.notFound` if there is no item, and
    /// does nothing if the item is already a group.
    public static func convertToGroup(at prefix: [String], in items: inout [Item]) throws {
        guard let action = item(at: prefix, in: items) else { throw SequenceProblem.notFound }
        if action.isGroup { return }
        modify(at: prefix, in: &items) { item in
            item = Item(key: action.key, label: action.label, action: .group([action]))
        }
    }

    /// Applies `change` to the item at `sequence` (label or action target). The key is not
    /// changed even if `change` changes it; use `move` for that. Throws `.notFound`.
    public static func update(at sequence: [String], in items: inout [Item], _ change: (inout Item) -> Void) throws {
        guard item(at: sequence, in: items) != nil else { throw SequenceProblem.notFound }
        modify(at: sequence, in: &items) { item in
            let key = item.key
            change(&item)
            item.key = key
        }
    }

    // MARK: - Helpers (callers have already checked the path)

    /// Calls `body` on the item at an existing `sequence`.
    private static func modify(at sequence: [String], in items: inout [Item], _ body: (inout Item) -> Void) {
        guard let first = sequence.first, let index = items.firstIndex(where: { $0.key == first }) else { return }
        if sequence.count == 1 {
            body(&items[index])
            return
        }
        guard var children = items[index].children else { return }
        modify(at: Array(sequence.dropFirst()), in: &children, body)
        items[index].action = .group(children)
    }

    /// Puts `item` at `sequence`, creating missing groups. Assumes `problem(...)` returned nil.
    private static func place(_ item: Item, at sequence: [String], in items: inout [Item]) {
        guard let first = sequence.first else { return }
        if sequence.count == 1 {
            var placed = item
            placed.key = first
            items.append(placed)
            return
        }
        let index: Int
        if let existing = items.firstIndex(where: { $0.key == first }) {
            index = existing
        } else {
            items.append(Item(key: first, label: "Group " + SequenceKey.display(first), action: .group([])))
            index = items.count - 1
        }
        var children = items[index].children ?? []
        place(item, at: Array(sequence.dropFirst()), in: &children)
        items[index].action = .group(children)
    }

    /// Removes and returns the item at `sequence` without pruning groups.
    private static func detach(at sequence: [String], in items: inout [Item]) -> Item? {
        var removed: Item?
        let parent = Array(sequence.dropLast())
        guard let last = sequence.last else { return nil }
        if parent.isEmpty {
            guard let index = items.firstIndex(where: { $0.key == last }) else { return nil }
            return items.remove(at: index)
        }
        modify(at: parent, in: &items) { group in
            guard var children = group.children, let index = children.firstIndex(where: { $0.key == last }) else { return }
            removed = children.remove(at: index)
            group.action = .group(children)
        }
        return removed
    }

    /// Removes empty groups at `path` and its ancestors, deepest first; stops at the first non-empty one.
    private static func pruneEmptyGroups(along path: [String], in items: inout [Item]) {
        var path = path
        while !path.isEmpty, let group = item(at: path, in: items), group.children?.isEmpty == true {
            _ = detach(at: path, in: &items)
            path.removeLast()
        }
    }
}
