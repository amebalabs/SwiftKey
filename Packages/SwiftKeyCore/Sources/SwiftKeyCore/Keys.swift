import Foundation

/// Names of keys that can appear in a binding sequence:
/// the named keys "space", "return", "f1"..."f20" (always lower case), or one printable
/// character such as "a", "B", "7", "!" or "§". Single characters keep their case: "a" and "A"
/// are different keys (A is typed with Shift).
public enum SequenceKey {
    /// macOS virtual key codes of F1...F20 → "f1"..."f20".
    /// F1=122 F2=120 F3=99 F4=118 F5=96 F6=97 F7=98 F8=100 F9=101 F10=109
    /// F11=103 F12=111 F13=105 F14=107 F15=113 F16=106 F17=64 F18=79 F19=80 F20=90
    public static let functionKeyCodes: [UInt16: String] = [
        122: "f1", 120: "f2", 99: "f3", 118: "f4", 96: "f5", 97: "f6", 98: "f7", 100: "f8",
        101: "f9", 109: "f10", 103: "f11", 111: "f12", 105: "f13", 107: "f14", 113: "f15",
        106: "f16", 64: "f17", 79: "f18", 80: "f19", 90: "f20",
    ]

    private static let functionKeyNames = Set(functionKeyCodes.values)

    /// True for a named key in lower case, or one printable character other than whitespace.
    public static func isValid(_ name: String) -> Bool {
        if isNamed(name) { return true }
        return isCharacter(name)
    }

    private static func isNamed(_ name: String) -> Bool {
        name == "space" || name == "return" || functionKeyNames.contains(name)
    }

    private static func isCharacter(_ name: String) -> Bool {
        guard name.count == 1, let character = name.first else { return false }
        return !character.isWhitespace && !character.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }

    /// Validates a key from the config. A single character is kept as it is ("A" stays "A");
    /// a single space is the space key; a longer name is a named key in any case
    /// ("Space" → "space", "F5" → "f5"). Returns nil for anything else ("", "ab", "f0", "f21", "tab").
    public static func normalize(_ raw: String) -> String? {
        if raw == " " { return "space" }
        if isCharacter(raw) { return raw }
        let lower = raw.lowercased()
        return isNamed(lower) ? lower : nil
    }

    /// Label for UI: "space" → "␣", "return" → "↩", "f1" → "F1", other characters as they are.
    public static func display(_ name: String) -> String {
        switch name {
        case "space": return "␣"
        case "return": return "↩"
        default: return functionKeyNames.contains(name) ? name.uppercased() : name
        }
    }

    /// Spoken/plain label: "space" → "Space", "return" → "Return", "f1" → "F1", others as they are.
    public static func spoken(_ name: String) -> String {
        switch name {
        case "space": return "Space"
        case "return": return "Return"
        default: return functionKeyNames.contains(name) ? name.uppercased() : name
        }
    }

    /// Key name for a key press.
    /// keyCode 49 → "space"; 36 or 76 → "return"; F-key codes → "fN" (ignores `latin`).
    /// Otherwise `latin` (the character of the ASCII-capable layout with Shift applied, supplied
    /// by the app) when it is one printable character; else nil.
    public static func name(keyCode: UInt16, latin: String?) -> String? {
        switch keyCode {
        case 49: return "space"
        case 36, 76: return "return"
        default: break
        }
        if let function = functionKeyCodes[keyCode] { return function }
        guard let latin, isCharacter(latin) else { return nil }
        return latin
    }
}

/// Physical modifier keys. Raw value is the config token.
public enum ModifierKey: String, CaseIterable, Codable, Sendable {
    case leftCommand = "left-cmd", rightCommand = "right-cmd"
    case leftShift = "left-shift", rightShift = "right-shift"
    case leftOption = "left-option", rightOption = "right-option"
    case leftControl = "left-ctrl", rightControl = "right-ctrl"
    case function = "fn"

    /// Virtual key code: leftCommand 55, rightCommand 54, leftShift 56, rightShift 60,
    /// leftOption 58, rightOption 61, leftControl 59, rightControl 62, function 63.
    public var keyCode: UInt16 {
        switch self {
        case .leftCommand: 55
        case .rightCommand: 54
        case .leftShift: 56
        case .rightShift: 60
        case .leftOption: 58
        case .rightOption: 61
        case .leftControl: 59
        case .rightControl: 62
        case .function: 63
        }
    }

    public init?(keyCode: UInt16) {
        guard let key = ModifierKey.allCases.first(where: { $0.keyCode == keyCode }) else { return nil }
        self = key
    }

    /// The modifier flag this key sets.
    public var flag: ModifierSet {
        switch self {
        case .leftCommand, .rightCommand: .command
        case .leftShift, .rightShift: .shift
        case .leftOption, .rightOption: .option
        case .leftControl, .rightControl: .control
        case .function: .function
        }
    }

    /// "Left ⌘", "Right ⌘", "Left ⇧", "Right ⇧", "Left ⌥", "Right ⌥", "Left ⌃", "Right ⌃", "fn".
    public var display: String {
        switch self {
        case .leftCommand: "Left ⌘"
        case .rightCommand: "Right ⌘"
        case .leftShift: "Left ⇧"
        case .rightShift: "Right ⇧"
        case .leftOption: "Left ⌥"
        case .rightOption: "Right ⌥"
        case .leftControl: "Left ⌃"
        case .rightControl: "Right ⌃"
        case .function: "fn"
        }
    }
}

/// Modifier flags, independent of AppKit.
public struct ModifierSet: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let control = ModifierSet(rawValue: 1 << 0)
    public static let option = ModifierSet(rawValue: 1 << 1)
    public static let shift = ModifierSet(rawValue: 1 << 2)
    public static let command = ModifierSet(rawValue: 1 << 3)
    public static let function = ModifierSet(rawValue: 1 << 4)

    /// Symbols in macOS order ⌃⌥⇧⌘ (function is not shown). Empty set → "".
    public var symbols: String {
        var text = ""
        if contains(.control) { text += "⌃" }
        if contains(.option) { text += "⌥" }
        if contains(.shift) { text += "⇧" }
        if contains(.command) { text += "⌘" }
        return text
    }
}

/// Physical key codes of a US ANSI keyboard, used to store combo leaders in the config.
/// Names: "a"..."z", "0"..."9", "f1"..."f20", "space", "return", "tab", "escape",
/// "delete", "-", "=", "[", "]", ";", "'", ",", ".", "/", "\\", "`".
public enum KeyCodes {
    /// Name → key code for every name above. Letters: a=0 s=1 d=2 f=3 h=4 g=5 z=6 x=7 c=8 v=9
    /// b=11 q=12 w=13 e=14 r=15 y=16 t=17 1=18 2=19 3=20 4=21 6=22 5=23 ==24 9=25 7=26 -=27
    /// 8=28 0=29 ]=30 o=31 u=32 [=33 i=34 p=35 return=36 l=37 j=38 '=39 k=40 ;=41 \=42 ,=43
    /// /=44 n=45 m=46 .=47 tab=48 space=49 `=50 delete=51 escape=53, F-keys as in SequenceKey.
    public static let ansi: [String: UInt16] = {
        var map: [String: UInt16] = [
            "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
            "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19,
            "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28,
            "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "return": 36, "l": 37,
            "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46,
            ".": 47, "tab": 48, "space": 49, "`": 50, "delete": 51, "escape": 53,
            "home": 115, "end": 119, "pageup": 116, "pagedown": 121,
            "forwarddelete": 117, "help": 114,
            "left": 123, "right": 124, "down": 125, "up": 126,
            "keypad0": 82, "keypad1": 83, "keypad2": 84, "keypad3": 85,
            "keypad4": 86, "keypad5": 87, "keypad6": 88, "keypad7": 89,
            "keypad8": 91, "keypad9": 92, "keypaddecimal": 65,
            "keypadmultiply": 67, "keypadplus": 69, "keypadclear": 71,
            "keypaddivide": 75, "keypadenter": 76, "keypadminus": 78, "keypadequals": 81,
        ]
        for (code, name) in SequenceKey.functionKeyCodes { map[name] = code }
        return map
    }()

    public static func code(for name: String) -> UInt16? {
        if let code = ansi[name] { return code }
        guard name.hasPrefix("key"), let code = UInt16(name.dropFirst(3)), code < 128,
              ModifierKey(keyCode: code) == nil, code != 57 else { return nil }
        return code
    }
    public static func name(for code: UInt16) -> String? {
        guard code < 128, ModifierKey(keyCode: code) == nil, code != 57 else { return nil }
        return namesByCode[code] ?? "key\(code)"
    }

    private static let namesByCode: [UInt16: String] = {
        var map: [UInt16: String] = [:]
        for (name, code) in ansi { map[code] = name }
        return map
    }()
}

/// A leader: any non-modifier key, alone or with modifiers. `modifierTap` is parsed for
/// compatibility but is never a valid leader.
///
/// Config string format:
/// - combo: modifier tokens then the key name from `KeyCodes`, joined by "+".
///   Canonical order and tokens: "ctrl", "option", "shift", "cmd". Example: "option+shift+cmd+f".
///   Parsing is case-insensitive, accepts any order and aliases "control", "alt", "opt", "command",
///   the glyphs "⌃", "⌥", "⇧", "⌘", and the key names "enter", "esc", "backspace".
/// - modifierTap: the `ModifierKey` raw value, e.g. "right-option".
public enum Hotkey: Equatable, Hashable, Sendable, Codable {
    case combo(keyCode: UInt16, modifiers: ModifierSet)
    case modifierTap(ModifierKey)

    /// nil for unknown tokens, an unknown key, a duplicate key, or an empty string.
    public init?(string: String) {
        let text = string.lowercased()
        guard !text.isEmpty else { return nil }
        if let key = ModifierKey(rawValue: text) {
            self = .modifierTap(key)
            return
        }
        var modifiers: ModifierSet = []
        var keyCode: UInt16?
        for token in text.split(separator: "+", omittingEmptySubsequences: false).map(String.init) {
            if let modifier = Hotkey.modifierTokens[token] {
                modifiers.insert(modifier)
            } else if let code = KeyCodes.code(for: Hotkey.keyAliases[token] ?? token) {
                guard keyCode == nil else { return nil }
                keyCode = code
            } else {
                return nil
            }
        }
        guard let keyCode else { return nil }
        self = .combo(keyCode: keyCode, modifiers: modifiers)
    }

    private static let modifierTokens: [String: ModifierSet] = [
        "ctrl": .control, "control": .control, "⌃": .control,
        "option": .option, "alt": .option, "opt": .option, "⌥": .option,
        "shift": .shift, "⇧": .shift,
        "cmd": .command, "command": .command, "⌘": .command,
    ]

    /// Other names of keys, as configs written for other tools spell them.
    private static let keyAliases: [String: String] = [
        "enter": "return", "esc": "escape", "backspace": "delete",
    ]

    /// Canonical config string. `Hotkey(string: h.string) == h` for every valid hotkey.
    public var string: String {
        switch self {
        case .modifierTap(let key):
            return key.rawValue
        case .combo(let keyCode, let modifiers):
            var tokens: [String] = []
            if modifiers.contains(.control) { tokens.append("ctrl") }
            if modifiers.contains(.option) { tokens.append("option") }
            if modifiers.contains(.shift) { tokens.append("shift") }
            if modifiers.contains(.command) { tokens.append("cmd") }
            tokens.append(KeyCodes.name(for: keyCode) ?? "key\(keyCode)")
            return tokens.joined(separator: "+")
        }
    }

    /// UI label: "⌥⇧⌘F", "⇧F15", "F13", "⌃Space", "Right ⌥". Key part: letters/digits upper-cased,
    /// "space" → "Space", "return" → "↩", "tab" → "⇥", "escape" → "⎋", "delete" → "⌫", fN → "FN".
    public var display: String {
        switch self {
        case .modifierTap(let key):
            return key.display
        case .combo(let keyCode, let modifiers):
            return modifiers.symbols + Hotkey.keyDisplay(keyCode)
        }
    }

    private static func keyDisplay(_ keyCode: UInt16) -> String {
        guard let name = KeyCodes.name(for: keyCode) else { return "#\(keyCode)" }
        switch name {
        case "space": return "Space"
        case "return": return "↩"
        case "tab": return "⇥"
        case "escape": return "⎋"
        case "delete": return "⌫"
        case "home": return "Home"
        case "end": return "End"
        case "pageup": return "Page Up"
        case "pagedown": return "Page Down"
        case "left": return "←"
        case "right": return "→"
        case "up": return "↑"
        case "down": return "↓"
        default: return name.uppercased()
        }
    }

    /// Any non-modifier key is valid, with or without modifiers.
    /// Standalone modifiers (including Caps Lock) cannot be leaders.
    public var isValid: Bool {
        switch self {
        case .modifierTap:
            return false
        case .combo(let keyCode, let modifiers):
            return KeyCodes.name(for: keyCode) != nil && !modifiers.contains(.function)
        }
    }

    // Codable: encodes as a single JSON string (`string`); decoding an invalid string throws.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let hotkey = Hotkey(string: text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid hotkey \"\(text)\"")
        }
        self = hotkey
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(string)
    }
}

/// Detects "press one modifier key and release it with nothing in between".
public struct ModifierTapDetector: Sendable {
    private let maxDuration: TimeInterval
    private var candidate: ModifierKey?
    private var pressedAt: TimeInterval = 0

    public init(maxDuration: TimeInterval = 0.5) {
        self.maxDuration = maxDuration
    }

    /// Call for each flagsChanged event. `modifiers` are the flags after the change.
    /// A press is when `modifiers` contains the flag of `ModifierKey(keyCode:)`.
    /// - Press with exactly one flag down starts a candidate (time = `time`).
    /// - A second modifier while a candidate is held cancels it.
    /// - Release to an empty set, of the same key, within `maxDuration`, returns that key.
    /// Returns nil in all other cases. Unknown key codes cancel the candidate.
    public mutating func flagsChanged(keyCode: UInt16, modifiers: ModifierSet, time: TimeInterval) -> ModifierKey? {
        guard let key = ModifierKey(keyCode: keyCode) else {
            candidate = nil
            return nil
        }
        if modifiers.contains(key.flag) {
            if candidate == nil, modifiers.isSingleFlag {
                candidate = key
                pressedAt = time
            } else {
                candidate = nil
            }
            return nil
        }
        defer { candidate = nil }
        if modifiers.isEmpty, candidate == key, time - pressedAt <= maxDuration { return key }
        return nil
    }

    /// Any normal key press cancels the candidate.
    public mutating func keyDown() {
        candidate = nil
    }
}

private extension ModifierSet {
    var isSingleFlag: Bool { rawValue != 0 && rawValue & (rawValue - 1) == 0 }
}
