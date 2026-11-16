// Layout-aware key translation.
import AppKit
import Carbon
import SwiftKeyCore

/// Translates physical key codes through keyboard layouts.
/// Menu keys are the characters of the user's ASCII-capable layout: with the Russian layout
/// active, the key labelled Ф/A still means "a", and with Shift it means "A".
@MainActor
enum KeyTranslator {
    private struct Layout {
        let id: String
        let data: Data
    }

    /// A physical key with or without Shift.
    private struct Stroke: Equatable {
        let keyCode: UInt16
        let shift: Bool
    }

    private static var latinStrokes: (layoutID: String, strokes: [String: Stroke])?
    private static var hints: (key: String, hints: [String: String])?

    private static func layout(_ source: TISInputSource?) -> Layout? {
        guard let source,
              let dataPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData),
              let idPointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(dataPointer).takeUnretainedValue() as Data
        let id = Unmanaged<CFString>.fromOpaque(idPointer).takeUnretainedValue() as String
        return Layout(id: id, data: data)
    }

    private static var asciiLayout: Layout? {
        layout(TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue())
    }

    private static var currentLayout: Layout? {
        layout(TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue())
    }

    private static func translate(_ keyCode: UInt16, shift: Bool, data: Data) -> String? {
        data.withUnsafeBytes { raw -> String? in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return nil }
            var dead: UInt32 = 0
            var length = 0
            var chars = [UniChar](repeating: 0, count: 4)
            // UCKeyTranslate takes the Carbon modifier bits shifted right by 8.
            let modifiers = shift ? UInt32(shiftKey >> 8) & 0xFF : 0
            let status = UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDown), modifiers, UInt32(LMGetKbdType()),
                                        OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, 4, &length, &chars)
            guard status == noErr, length > 0 else { return nil }
            return String(utf16CodeUnits: chars, count: length)
        }
    }

    /// Character of the ASCII-capable layout for a key code, with Shift when `shift` is true.
    static func latin(_ keyCode: UInt16, shift: Bool) -> String? {
        asciiLayout.flatMap { translate(keyCode, shift: shift, data: $0.data) }
    }

    /// The key code and Shift state that type `latin` in the ASCII-capable layout.
    private static func stroke(forLatin latin: String) -> Stroke? {
        guard let ascii = asciiLayout else { return nil }
        if latinStrokes?.layoutID != ascii.id {
            var strokes: [String: Stroke] = [:]
            for shift in [false, true] {
                for code in (0..<128).map(UInt16.init) {
                    if let text = translate(code, shift: shift, data: ascii.data), strokes[text] == nil {
                        strokes[text] = Stroke(keyCode: code, shift: shift)
                    }
                }
            }
            latinStrokes = (ascii.id, strokes)
        }
        return latinStrokes?.strokes[latin]
    }

    /// Key code that produces `latin` in the ASCII-capable layout, with or without Shift.
    static func keyCode(forLatin latin: String) -> UInt16? {
        stroke(forLatin: latin)?.keyCode
    }

    /// The character printed in the active non-Latin layout for a menu key, e.g. "w" → "ц",
    /// "W" → "Ц". nil when the active layout is the ASCII-capable one or gives the same or an
    /// ASCII character.
    static func localHint(forLatin latin: String) -> String? {
        guard latin.count == 1, let ascii = asciiLayout, let current = currentLayout, current.id != ascii.id else { return nil }
        let cacheKey = ascii.id + "|" + current.id
        if hints?.key != cacheKey { hints = (cacheKey, [:]) }
        if let cached = hints?.hints[latin] { return cached.isEmpty ? nil : cached }
        var hint = ""
        if let stroke = stroke(forLatin: latin), let local = translate(stroke.keyCode, shift: stroke.shift, data: current.data),
           local != latin, local.count == 1, let scalar = local.unicodeScalars.first, !scalar.isASCII {
            hint = local
        }
        hints?.hints[latin] = hint
        return hint.isEmpty ? nil : hint
    }

    /// The key name the menu uses for a key press: "return", "tab", "escape", "delete", the arrows
    /// ("cmd+up" with Command), "space", "f1"…"f20", or the character of the ASCII-capable
    /// layout with Shift applied. Option, Control and Command do not change the character.
    /// `characters` is the event's text without modifiers, used when no layout gives a character.
    static func keyName(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, characters: String?) -> String? {
        switch keyCode {
        case 36, 76: return "return"
        case 48: return "tab"
        case 53: return "escape"
        case 51: return "delete"
        case 126: return modifiers.contains(.command) ? "cmd+up" : "up"
        case 125: return "down"
        case 123: return "left"
        case 124: return "right"
        default: break
        }
        let latin = latin(keyCode, shift: modifiers.contains(.shift))
        if let name = SequenceKey.name(keyCode: keyCode, latin: latin) { return name }
        if let latin, !latin.isEmpty { return latin }
        if let characters, !characters.isEmpty { return characters }
        return nil
    }

    static func keyName(for event: NSEvent) -> String? {
        keyName(keyCode: event.keyCode, modifiers: event.modifierFlags, characters: event.charactersIgnoringModifiers)
    }
}
