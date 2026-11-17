import AppKit
import XCTest
@testable import SwiftKey

@MainActor
final class KeyTranslatorTests: XCTestCase {
    func testNamedKeys() {
        let cases: [(UInt16, NSEvent.ModifierFlags, String)] = [
            (36, [], "return"), (76, [], "return"), (48, [], "tab"), (53, [], "escape"), (51, [], "delete"),
            (126, [], "up"), (126, [.command], "cmd+up"), (125, [], "down"), (123, [], "left"), (124, [], "right"),
            (49, [], "space"), (96, [], "f5"), (105, [], "f13"),
        ]
        for (code, modifiers, name) in cases {
            XCTAssertEqual(KeyTranslator.keyName(keyCode: code, modifiers: modifiers, characters: nil), name, "key code \(code)")
        }
    }

    /// The letter key of the Latin layout gives the letter, Shift gives the capital, and Option,
    /// Control or Command do not change it, whatever the active layout is.
    func testLettersKeepShiftAndIgnoreOtherModifiers() throws {
        let code = try XCTUnwrap(KeyTranslator.keyCode(forLatin: "a"))
        XCTAssertEqual(KeyTranslator.keyName(keyCode: code, modifiers: [], characters: nil), "a")
        XCTAssertEqual(KeyTranslator.keyName(keyCode: code, modifiers: [.shift], characters: nil), "A")
        XCTAssertEqual(KeyTranslator.keyName(keyCode: code, modifiers: [.option], characters: nil), "a")
        XCTAssertEqual(KeyTranslator.keyName(keyCode: code, modifiers: [.shift, .option], characters: nil), "A")
        XCTAssertEqual(KeyTranslator.keyName(keyCode: code, modifiers: [.command], characters: nil), "a")
        XCTAssertEqual(KeyTranslator.keyName(keyCode: code, modifiers: [.control], characters: nil), "a")
    }

    func testShiftedSymbolsComeOutAsTyped() throws {
        // "A" and "!" are typed with Shift in Latin layouts; the stroke that types them gives them back.
        for text in ["A", "!", "7"] {
            let code = try XCTUnwrap(KeyTranslator.keyCode(forLatin: text), text)
            let plain = KeyTranslator.latin(code, shift: false)
            let shifted = KeyTranslator.latin(code, shift: true)
            XCTAssertTrue(plain == text || shifted == text, text)
            let modifiers: NSEvent.ModifierFlags = plain == text ? [] : [.shift]
            XCTAssertEqual(KeyTranslator.keyName(keyCode: code, modifiers: modifiers, characters: nil), text)
        }
    }

    func testHintIsNilOrOneNonLatinCharacter() {
        for key in ["a", "W", "1", "space"] {
            if let hint = KeyTranslator.localHint(forLatin: key) {
                XCTAssertEqual(hint.count, 1, key)
                XCTAssertFalse(hint.unicodeScalars.allSatisfy(\.isASCII), key)
            }
        }
        XCTAssertNil(KeyTranslator.localHint(forLatin: "space"))
    }
}

final class KeyboardManagerBackTests: XCTestCase {
    private func manager() -> KeyboardManager {
        let manager = KeyboardManager()
        manager.menuState.rootMenu = [
            MenuItem(key: "g", title: "Group", submenu: [
                MenuItem(key: "x", title: "Inner", submenu: [MenuItem(key: "y", title: "Leaf", action: "shell://true")]),
            ]),
        ]
        return manager
    }

    func testDeleteGoesBackOneLevelThenCloses() async {
        let manager = manager()
        var result = await manager.handleKey(key: "g")
        XCTAssertEqual(result, .submenuPushed(title: "Group"))
        result = await manager.handleKey(key: "x")
        XCTAssertEqual(result, .submenuPushed(title: "Inner"))
        XCTAssertEqual(manager.menuState.breadcrumbs, ["Group", "Inner"])

        result = await manager.handleKey(key: "delete")
        XCTAssertEqual(result, .up)
        XCTAssertEqual(manager.menuState.breadcrumbs, ["Group"])
        XCTAssertEqual(manager.menuState.currentMenu.map(\.key), ["x"])

        result = await manager.handleKey(key: "delete")
        XCTAssertEqual(result, .up)
        XCTAssertEqual(manager.menuState.menuStack.count, 0)

        result = await manager.handleKey(key: "delete")
        XCTAssertEqual(result, .escape)
    }

    func testNamedKeysInTheConfigMatchTheirKeyName() async {
        let manager = KeyboardManager()
        manager.menuState.rootMenu = [MenuItem(key: "Space", title: "Space group", submenu: [])]
        let result = await manager.handleKey(key: "space")
        XCTAssertEqual(result, .submenuPushed(title: "Space group"))
    }
}
