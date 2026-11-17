import AppKit
import XCTest
@testable import SwiftKey

final class LaunchaPanelKeyRouteTests: XCTestCase {
    private func route(_ keyCode: UInt16, _ latin: String? = nil, _ flags: NSEvent.ModifierFlags) -> LaunchaPanel.KeyEquivalentRoute {
        LaunchaPanel.route(keyCode: keyCode, latin: latin, flags: flags)
    }

    func testCommandArrowsAndDeletesGoToTheEditor() {
        let editing: [UInt16] = [51, 117, 123, 124, 125, 126]
        let combos: [NSEvent.ModifierFlags] = [.command, [.command, .shift], [.command, .option],
                                               [.command, .shift, .option]]
        for keyCode in editing {
            for flags in combos {
                XCTAssertEqual(route(keyCode, nil, flags), .editor, "key \(keyCode) flags \(flags)")
            }
        }
    }

    func testPlainEditingIsNotTouched() {
        XCTAssertEqual(route(0, "a", []), .editor)
        XCTAssertEqual(route(51, nil, []), .editor)
        XCTAssertEqual(route(123, nil, .shift), .editor)
        XCTAssertEqual(route(51, nil, .option), .editor)
    }

    func testTextCommandsAndReveal() {
        XCTAssertEqual(route(9, "v", .command), .action(#selector(NSText.paste(_:))))
        XCTAssertEqual(route(6, "z", [.command, .shift]), .action(NSSelectorFromString("redo:")))
        XCTAssertEqual(route(36, nil, .command), .reveal)
        XCTAssertEqual(route(76, nil, .command), .reveal)
        XCTAssertEqual(route(36, nil, [.command, .shift]), .swallow)
    }

    func testAppCommandsAreSwallowed() {
        XCTAssertEqual(route(12, "q", .command), .swallow)
        XCTAssertEqual(route(13, "w", .command), .swallow)
        XCTAssertEqual(route(43, ",", .command), .swallow)
        XCTAssertEqual(route(4, "h", .command), .swallow)
    }
}

