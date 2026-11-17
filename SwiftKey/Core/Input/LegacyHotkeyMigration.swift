import Carbon
import Foundation
import SwiftKeyCore

/// Moves the main hotkey recorded by older versions (through the KeyboardShortcuts library) into
/// the `MainHotkey` setting, once.
///
/// The library stored it under `KeyboardShortcuts_toggleApp` as a JSON string
/// `{"carbonKeyCode": 3, "carbonModifiers": 768}`, or `false` when it was turned off.
enum LegacyHotkeyMigration {
    static let legacyKey = "KeyboardShortcuts_toggleApp"
    static let doneKey = "MainHotkeyMigrated"

    private struct Shortcut: Decodable {
        var carbonKeyCode: Int
        var carbonModifiers: Int
    }

    /// The hotkey the old value describes; nil for a missing, turned-off or unreadable value.
    static func hotkey(fromLegacy value: Any?) -> Hotkey? {
        guard let text = value as? String, let data = text.data(using: .utf8),
              let shortcut = try? JSONDecoder().decode(Shortcut.self, from: data),
              let keyCode = UInt16(exactly: shortcut.carbonKeyCode) else { return nil }
        var modifiers: ModifierSet = []
        if shortcut.carbonModifiers & cmdKey != 0 { modifiers.insert(.command) }
        if shortcut.carbonModifiers & shiftKey != 0 { modifiers.insert(.shift) }
        if shortcut.carbonModifiers & optionKey != 0 { modifiers.insert(.option) }
        if shortcut.carbonModifiers & controlKey != 0 { modifiers.insert(.control) }
        let hotkey = Hotkey.combo(keyCode: keyCode, modifiers: modifiers)
        return hotkey.isValid ? hotkey : nil
    }

    /// Writes the old hotkey to `MainHotkey` when that is still empty. Runs once per defaults
    /// domain; the old value stays, so an older version keeps working after a downgrade.
    static func migrate(_ defaults: UserDefaults) {
        guard !defaults.bool(forKey: doneKey) else { return }
        defaults.set(true, forKey: doneKey)
        guard (defaults.string(forKey: SettingsStore.mainHotkeyKey) ?? "").isEmpty,
              let hotkey = hotkey(fromLegacy: defaults.object(forKey: legacyKey)) else { return }
        defaults.set(hotkey.string, forKey: SettingsStore.mainHotkeyKey)
    }
}
