import Foundation
import SwiftKeyCore

/// Builds the core menu tree (`SwiftKeyCore.Item`) from the config's `MenuItem`s, for the leader
/// state machine and launcha. Items that cannot become a node are left out and reported.
enum MenuItemTree {
    /// An item that was left out of the tree.
    struct Problem: Equatable {
        /// Titles from the top level down to the item.
        var path: [String]
        var message: String
    }

    struct Result: Equatable {
        var items: [Item]
        var problems: [Problem]
    }

    /// Action prefixes and the core action each one makes.
    private static let prefixes: [(prefix: String, make: (String) -> Item.Action)] = [
        ("launch://", Item.Action.app),
        ("open://", Item.Action.url),
        ("shell://", Item.Action.shell),
        ("shortcut://", Item.Action.shortcut),
        ("dynamic://", Item.Action.dynamic),
        ("micro://", Item.Action.micro),
    ]

    static func build(_ menu: [MenuItem]) -> Result {
        var problems: [Problem] = []
        let items = build(menu, path: [], problems: &problems)
        return Result(items: items, problems: problems)
    }

    /// The core action of `action`, or nil for an unknown prefix.
    static func action(for action: String) -> Item.Action? {
        for entry in prefixes where action.hasPrefix(entry.prefix) {
            return entry.make(String(action.dropFirst(entry.prefix.count)))
        }
        return nil
    }

    private static func build(_ menu: [MenuItem], path: [String], problems: inout [Problem]) -> [Item] {
        var items: [Item] = []
        for menuItem in menu {
            let itemPath = path + [menuItem.title]
            guard let key = SequenceKey.normalize(menuItem.key) else {
                problems.append(Problem(path: itemPath,
                                        message: "Invalid key \"\(menuItem.key)\". Use one character, space, return or f1…f20."))
                continue
            }
            let nodeAction: Item.Action
            // A submenu wins over an action, as in the menu.
            if let submenu = menuItem.submenu {
                nodeAction = .group(build(submenu, path: itemPath, problems: &problems))
            } else if let action = menuItem.action {
                guard let mapped = Self.action(for: action) else {
                    problems.append(Problem(path: itemPath, message: "Unknown action \"\(action)\"."))
                    continue
                }
                nodeAction = mapped
            } else {
                problems.append(Problem(path: itemPath, message: "No action or submenu."))
                continue
            }
            let flags = Item.Flags(sticky: menuItem.sticky ?? false, notify: menuItem.notify ?? false,
                                   batch: menuItem.batch ?? false, hidden: menuItem.hidden ?? false)
            items.append(Item(key: key, label: menuItem.title, action: nodeAction, flags: flags,
                              id: menuItem.id.uuidString))
        }
        return items
    }
}
