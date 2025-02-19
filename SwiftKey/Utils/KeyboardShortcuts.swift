import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleApp = Self("toggleApp")
}

extension KeyboardShortcuts.Shortcut {
    init?(_ string: String) {
        let components = string.lowercased().split(separator: "+").map(String.init)
        guard let keyStr = components.last else { return nil }
        
        var modifiers: NSEvent.ModifierFlags = []
        
        for modifier in components.dropLast() {
            switch modifier {
                case "cmd", "command", "⌘":
                    modifiers.insert(.command)
                case "ctrl", "control", "⌃":
                    modifiers.insert(.control)
                case "alt", "option", "⌥":
                    modifiers.insert(.option)
                case "shift", "⇧":
                    modifiers.insert(.shift)
                default:
                    continue
            }
        }
        
        // Convert key string to KeyboardShortcuts.Key
        let key: KeyboardShortcuts.Key
        switch keyStr {
            case "a": key = .a
            case "b": key = .b
            case "c": key = .c
            case "d": key = .d
            case "e": key = .e
            case "f": key = .f
            case "g": key = .g
            case "h": key = .h
            case "i": key = .i
            case "j": key = .j
            case "k": key = .k
            case "l": key = .l
            case "m": key = .m
            case "n": key = .n
            case "o": key = .o
            case "p": key = .p
            case "q": key = .q
            case "r": key = .r
            case "s": key = .s
            case "t": key = .t
            case "u": key = .u
            case "v": key = .v
            case "w": key = .w
            case "x": key = .x
            case "y": key = .y
            case "z": key = .z
            case "0": key = .zero
            case "1": key = .one
            case "2": key = .two
            case "3": key = .three
            case "4": key = .four
            case "5": key = .five
            case "6": key = .six
            case "7": key = .seven
            case "8": key = .eight
            case "9": key = .nine
            case "space": key = .space
            case "return", "enter": key = .return
            case "tab": key = .tab
            case "esc", "escape": key = .escape
            case "left": key = .leftArrow
            case "right": key = .rightArrow
            case "up": key = .upArrow
            case "down": key = .downArrow
            case "backspace", "delete": key = .delete
            case "f1": key = .f1
            case "f2": key = .f2
            case "f3": key = .f3
            case "f4": key = .f4
            case "f5": key = .f5
            case "f6": key = .f6
            case "f7": key = .f7
            case "f8": key = .f8
            case "f9": key = .f9
            case "f10": key = .f10
            case "f11": key = .f11
            case "f12": key = .f12
            case "[": key = .leftBracket
            case "]": key = .rightBracket
            case "\\": key = .backslash
            case ";": key = .semicolon
            case "'", "\"": key = .quote
            case ",": key = .comma
            case ".": key = .period
            case "/": key = .slash
            case "-": key = .minus
            case "=": key = .equal
            case "`": key = .backtick
            default: return nil
        }
        
        self.init(key, modifiers: modifiers)
    }
}
