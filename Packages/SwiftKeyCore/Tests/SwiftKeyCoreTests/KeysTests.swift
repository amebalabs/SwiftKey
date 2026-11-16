import Foundation
import Testing
@testable import SwiftKeyCore

@Suite struct SequenceKeyTests {
    static let named = ["space", "return"] + (1...20).map { "f\($0)" }
    static let characters = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()-_=+[]{};:'\",.<>/?`~\\|").map(String.init)

    @Test(arguments: named) func namedKeys(_ name: String) {
        #expect(SequenceKey.isValid(name))
        #expect(SequenceKey.normalize(name.uppercased()) == name)
        #expect(!SequenceKey.isValid(name.uppercased()))
        let label = name == "space" ? "␣" : name == "return" ? "↩" : name.uppercased()
        #expect(SequenceKey.display(name) == label)
        #expect(SequenceKey.spoken(name) == (name == "space" ? "Space" : name == "return" ? "Return" : name.uppercased()))
    }

    @Test(arguments: characters) func charactersKeepTheirCase(_ name: String) {
        #expect(SequenceKey.isValid(name))
        #expect(SequenceKey.normalize(name) == name)
        #expect(SequenceKey.display(name) == name)
        #expect(SequenceKey.spoken(name) == name)
    }

    @Test func upperAndLowerCaseAreDifferentKeys() {
        #expect(SequenceKey.normalize("A") == "A")
        #expect(SequenceKey.normalize("a") == "a")
        #expect(SequenceKey.normalize("F") == "F")
        #expect(SequenceKey.normalize("F5") == "f5")
    }

    @Test(arguments: ["", "ab", "f0", "f21", "ф", "tab", " ", " a", "a ", "\n", "é"])
    func invalidNames(_ name: String) {
        #expect(!SequenceKey.isValid(name))
        #expect(SequenceKey.normalize(name) == nil)
    }

    @Test func specialPhysicalKeysIgnoreLatin() {
        let pairs: [(UInt16, String)] = [(49, "space"), (36, "return"), (76, "return")] + SequenceKey.functionKeyCodes.map { ($0.key, $0.value) }
        #expect(SequenceKey.functionKeyCodes.count == 20)
        for (code, name) in pairs {
            #expect(SequenceKey.name(keyCode: code, latin: nil) == name)
            #expect(SequenceKey.name(keyCode: code, latin: "ф") == name)
        }
    }

    @Test(arguments: characters) func latinInputIsKeptAsTyped(_ latin: String) {
        #expect(SequenceKey.name(keyCode: 0, latin: latin) == latin)
    }

    @Test(arguments: [nil, "", "ab", "é", "ф", "İ", " ", "\n"] as [String?])
    func rejectedLatin(_ latin: String?) { #expect(SequenceKey.name(keyCode: 0, latin: latin) == nil) }
}

@Suite struct ModifierKeyTests {
    @Test func physicalMappings() {
        let cases: [(ModifierKey, UInt16, ModifierSet, String)] = [
            (.leftCommand, 55, .command, "Left ⌘"), (.rightCommand, 54, .command, "Right ⌘"),
            (.leftShift, 56, .shift, "Left ⇧"), (.rightShift, 60, .shift, "Right ⇧"),
            (.leftOption, 58, .option, "Left ⌥"), (.rightOption, 61, .option, "Right ⌥"),
            (.leftControl, 59, .control, "Left ⌃"), (.rightControl, 62, .control, "Right ⌃"),
            (.function, 63, .function, "fn")]
        #expect(cases.count == ModifierKey.allCases.count)
        for (key, code, flag, label) in cases {
            #expect(key.keyCode == code)
            #expect(ModifierKey(keyCode: code) == key)
            #expect(key.flag == flag)
            #expect(key.display == label)
        }
        #expect(ModifierKey(keyCode: 0) == nil)
        #expect(ModifierKey(keyCode: UInt16.max) == nil)
    }
    @Test func symbols() {
        #expect(ModifierSet().symbols == "")
        #expect(ModifierSet.function.symbols == "")
        #expect(ModifierSet([.command, .shift, .option, .control, .function]).symbols == "⌃⌥⇧⌘")
        #expect(ModifierSet([.command, .option]).symbols == "⌥⌘")
    }
}

@Suite struct KeyCodesTests {
    @Test func ansiRoundTrips() {
        #expect(KeyCodes.ansi.count == 100)
        for (name, code) in KeyCodes.ansi {
            #expect(KeyCodes.code(for: name) == code)
            #expect(KeyCodes.name(for: code) == name)
        }
        #expect(KeyCodes.code(for: "unknown") == nil)
        #expect(KeyCodes.code(for: "") == nil)
        #expect(KeyCodes.name(for: UInt16.max) == nil)
    }
}

@Suite struct HotkeyTests {
    @Test(arguments: ["option+shift+cmd+f", "Cmd+Shift+Option+F", "f+COMMAND+alt+SHIFT", "shift+opt+command+f"])
    func realLeader(_ text: String) throws {
        let h = try #require(Hotkey(string: text))
        #expect(h == .combo(keyCode: 3, modifiers: [.option, .shift, .command]))
        #expect(h.string == "option+shift+cmd+f")
        #expect(h.display == "⌥⇧⌘F")
        #expect(h.isValid)
    }
    @Test func displaysAndCanonicalOrder() {
        let cases: [(String, Hotkey, String)] = [
            ("shift+f15", .combo(keyCode: 113, modifiers: .shift), "⇧F15"),
            ("f13", .combo(keyCode: 105, modifiers: []), "F13"),
            ("control+space", .combo(keyCode: 49, modifiers: .control), "⌃Space"),
            ("right-option", .modifierTap(.rightOption), "Right ⌥"),
            ("cmd+return", .combo(keyCode: 36, modifiers: .command), "⌘↩"),
            ("cmd+tab", .combo(keyCode: 48, modifiers: .command), "⌘⇥"),
            ("cmd+escape", .combo(keyCode: 53, modifiers: .command), "⌘⎋"),
            ("cmd+delete", .combo(keyCode: 51, modifiers: .command), "⌘⌫")]
        for (text, h, label) in cases {
            #expect(Hotkey(string: text) == h)
            #expect(h.display == label)
            if case .modifierTap = h { #expect(!h.isValid) } else { #expect(h.isValid) }
        }
        #expect(Hotkey.combo(keyCode: 0, modifiers: [.command, .shift, .control, .option]).string == "ctrl+option+shift+cmd+a")
    }
    @Test(arguments: ["", "unknown+a", "cmd+unknown", "cmd+a+b", "cmd+", "+cmd+a"])
    func invalidParsing(_ text: String) { #expect(Hotkey(string: text) == nil) }

    @Test func validity() {
        #expect(Hotkey.combo(keyCode: 0, modifiers: []).isValid)
        #expect(!Hotkey.combo(keyCode: 0, modifiers: [.function, .command]).isValid)
        for code in SequenceKey.functionKeyCodes.keys { #expect(Hotkey.combo(keyCode: code, modifiers: []).isValid) }
        for key in ModifierKey.allCases {
            #expect(!Hotkey.modifierTap(key).isValid)
            #expect(!Hotkey.combo(keyCode: key.keyCode, modifiers: []).isValid)
        }
        #expect(!Hotkey.combo(keyCode: 57, modifiers: []).isValid)
    }
    @Test(arguments: ["home", "end", "pageup", "pagedown", "space", "return", "a", "1", "left", "keypad0", "escape"])
    func bareLeader(_ name: String) throws {
        let hotkey = try #require(Hotkey(string: name))
        #expect(hotkey.isValid)
        #expect(hotkey.string == name)
        #expect(try JSONDecoder().decode(Hotkey.self, from: JSONEncoder().encode(hotkey)) == hotkey)
    }
    @Test func homeLeader() {
        #expect(Hotkey(string: "home") == .combo(keyCode: 115, modifiers: []))
        #expect(Hotkey(string: "HOME")?.display == "Home")
        #expect(Hotkey(string: "shift+home")?.isValid == true)
    }
    @Test func roundTripsAndCodable() throws {
        var hotkeys = ModifierKey.allCases.map(Hotkey.modifierTap)
        hotkeys += SequenceKey.functionKeyCodes.keys.map { .combo(keyCode: $0, modifiers: []) }
        for code in KeyCodes.ansi.values {
            for flags: ModifierSet in [.control, .option, .shift, .command, [.control, .option, .shift, .command]] {
                hotkeys.append(.combo(keyCode: code, modifiers: flags))
            }
        }
        for h in hotkeys {
            #expect(Hotkey(string: h.string) == h)
            let data = try JSONEncoder().encode(h)
            #expect(try JSONDecoder().decode(String.self, from: data) == h.string)
            #expect(try JSONDecoder().decode(Hotkey.self, from: data) == h)
        }
        #expect(throws: (any Error).self) { try JSONDecoder().decode(Hotkey.self, from: Data("\"nonsense\"".utf8)) }
    }
}

@Suite struct ModifierTapDetectorTests {
    @Test(arguments: ModifierKey.allCases) func consecutiveTaps(_ key: ModifierKey) {
        var d = ModifierTapDetector()
        for time in [0.0, 1.0] {
            #expect(d.flagsChanged(keyCode: key.keyCode, modifiers: key.flag, time: time) == nil)
            #expect(d.flagsChanged(keyCode: key.keyCode, modifiers: [], time: time + 0.1) == key)
        }
    }
    @Test func noCandidate() {
        var d = ModifierTapDetector()
        #expect(d.flagsChanged(keyCode: 61, modifiers: [], time: 0) == nil)
        #expect(d.flagsChanged(keyCode: 61, modifiers: [.option, .shift], time: 1) == nil)
        #expect(d.flagsChanged(keyCode: 61, modifiers: [], time: 1.1) == nil)
    }
    @Test(arguments: ["slow", "second", "normal", "different", "unknown"])
    func cancellations(_ scenario: String) {
        var d = ModifierTapDetector(maxDuration: 0.2)
        #expect(d.flagsChanged(keyCode: 61, modifiers: .option, time: 0) == nil)
        switch scenario {
        case "second": #expect(d.flagsChanged(keyCode: 56, modifiers: [.shift, .option], time: 0.05) == nil)
        case "normal": d.keyDown()
        case "different": #expect(d.flagsChanged(keyCode: 58, modifiers: [], time: 0.1) == nil); return
        case "unknown": #expect(d.flagsChanged(keyCode: 0, modifiers: .option, time: 0.05) == nil)
        default: break
        }
        #expect(d.flagsChanged(keyCode: 61, modifiers: [], time: scenario == "slow" ? 0.3 : 0.15) == nil)
    }
}
