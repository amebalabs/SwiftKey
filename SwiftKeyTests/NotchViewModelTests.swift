import AppKit
import SwiftUI
import XCTest
@testable import SwiftKey

/// The HUD takes keys from the moment it opens; only its drawing waits for the reveal.
@MainActor
final class NotchViewModelTests: XCTestCase {
    private func model() throws -> NotchViewModel {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        return NotchViewModel(screen: screen, headerLeadingView: AnyView(EmptyView()), headerTrailingView: AnyView(EmptyView()),
                              bodyView: AnyView(Text("Menu")), animated: false)
    }

    func testOpensAtOnceUnrevealedAndRevealsLater() throws {
        let vm = try model()
        vm.open(revealed: false)
        XCTAssertEqual(vm.status, .opened, "the body that takes keys is there at once")
        XCTAssertFalse(vm.revealed)
        vm.reveal()
        XCTAssertTrue(vm.revealed)
    }

    func testClosingIsImmediate() throws {
        let vm = try model()
        vm.open(revealed: false)
        vm.close()
        XCTAssertEqual(vm.status, .closed)
    }
}
