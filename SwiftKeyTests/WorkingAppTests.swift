import AppKit
import XCTest
@testable import SwiftKey

/// Micro-apps act on the app the person works in, also when the HUD, corner toast or menu-bar
/// session made SwiftKey the front app.
final class WorkingAppTests: XCTestCase {
    private let own = NSRunningApplication.current
    private var finder: NSRunningApplication {
        get throws {
            try XCTUnwrap(NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first)
        }
    }

    func testTheFrontAppWhenItIsNotSwiftKey() throws {
        let finder = try finder
        XCTAssertEqual(WorkingApp.choose(front: finder, last: nil, ownPID: own.processIdentifier), finder)
    }

    func testTheLastWorkingAppWhenSwiftKeyIsInFront() throws {
        let finder = try finder
        XCTAssertEqual(WorkingApp.choose(front: own, last: finder, ownPID: own.processIdentifier), finder)
    }

    func testNeverSwiftKeyItself() {
        XCTAssertNil(WorkingApp.choose(front: own, last: own, ownPID: own.processIdentifier))
        XCTAssertNil(WorkingApp.choose(front: own, last: nil, ownPID: own.processIdentifier))
    }
}
