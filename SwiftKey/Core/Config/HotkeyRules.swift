import Foundation
import SwiftKeyCore

/// The rules for the global hotkeys of menu items (`hotkey:` in the config).
enum HotkeyRules {
    /// What is wrong with one `hotkey:` string, or nil when it is a valid hotkey.
    static func problem(_ text: String) -> String? {
        guard let hotkey = Hotkey(string: text.trimmingCharacters(in: .whitespaces)) else {
            return "Invalid hotkey '\(text)'. Use modifiers (cmd, ctrl, option, shift) and one key, such as cmd+shift+a or f13."
        }
        guard hotkey.isValid else {
            return "Hotkey '\(text)' is a modifier alone. Add a key that is not a modifier."
        }
        return nil
    }

    /// Items whose hotkey is the main SwiftKey hotkey or is used by another item, by item id.
    /// Every item of a duplicate pair is reported.
    static func conflicts(in items: [MenuItem], mainHotkey: Hotkey?) -> [UUID: String] {
        var owners: [Hotkey: [MenuItem]] = [:]
        collect(items, into: &owners)
        var result: [UUID: String] = [:]
        for (hotkey, items) in owners {
            if hotkey == mainHotkey {
                for item in items { result[item.id] = "Hotkey \(hotkey.display) is the SwiftKey hotkey." }
            } else if items.count > 1 {
                for item in items {
                    let others = items.filter { $0.id != item.id }.map { "'\($0.title)'" }.joined(separator: ", ")
                    result[item.id] = "Hotkey \(hotkey.display) is also used by \(others)."
                }
            }
        }
        return result
    }

    private static func collect(_ items: [MenuItem], into owners: inout [Hotkey: [MenuItem]]) {
        for item in items {
            if let text = item.hotkey, let hotkey = Hotkey(string: text), hotkey.isValid {
                owners[hotkey, default: []].append(item)
            }
            if let submenu = item.submenu { collect(submenu, into: &owners) }
        }
    }
}
