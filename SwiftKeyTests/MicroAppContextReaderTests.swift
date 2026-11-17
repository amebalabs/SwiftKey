import SwiftKeyCore
import XCTest
@testable import SwiftKey

/// The real context reader for sources that need no permission: it runs no script and reads
/// no other app.
@MainActor
final class MicroAppContextReaderTests: XCTestCase {
    func testTheAppSourceComesFromTheAppInFront() async throws {
        let reader = MicroAppContextReader(copySelection: { _ in nil })
        let target = MicroAppTarget(pid: 4242, bundleID: "com.example.Editor", name: "Editor", path: "/Applications/Editor.app")
        let context = try await reader.read([.app], target: target)
        func value(_ name: String) -> String { context[MicroAppContextField(source: .app, name: name)!] }
        XCTAssertEqual(value("name"), "Editor")
        XCTAssertEqual(value("bundle"), "com.example.Editor")
        XCTAssertEqual(value("path"), "/Applications/Editor.app")
        XCTAssertEqual(value("pid"), "4242")
    }

    func testNoSourcesReadNothing() async throws {
        let reader = MicroAppContextReader(copySelection: { _ in XCTFail("nothing may be copied"); return nil })
        let context = try await reader.read([], target: MicroAppTarget(pid: 1, bundleID: nil, name: "x", path: nil))
        XCTAssertTrue(context.values.isEmpty)
    }
}
