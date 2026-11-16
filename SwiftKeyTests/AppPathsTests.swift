import XCTest
@testable import SwiftKey

final class AppPathsTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)

    func testWithoutOverrideDataGoesToApplicationSupport() {
        let paths = AppPaths(environment: [:], home: home)
        XCTAssertNil(paths.configOverride)
        XCTAssertEqual(paths.url(for: "approvals.json").path,
                       "/Users/someone/Library/Application Support/SwiftKey/approvals.json")
        XCTAssertNil(paths.defaultsSuiteName)
    }

    func testEmptyOverrideIsIgnored() {
        XCTAssertNil(AppPaths(environment: ["SWIFTKEY_CONFIG": ""], home: home).configOverride)
    }

    func testOverrideMovesDataNextToTheConfig() {
        let paths = AppPaths(environment: ["SWIFTKEY_CONFIG": "/tmp/x/config.yaml"], home: home)
        XCTAssertEqual(paths.configOverride?.path, "/tmp/x/config.yaml")
        XCTAssertEqual(paths.url(for: "approvals.json").path, "/tmp/x/config.yaml.approvals.json")
        XCTAssertEqual(paths.url(for: "launcha-history.json").path, "/tmp/x/config.yaml.launcha-history.json")
    }

    func testOverrideExpandsTilde() {
        let paths = AppPaths(environment: ["SWIFTKEY_CONFIG": "~/test.yaml"], home: home)
        XCTAssertEqual(paths.configOverride?.path, (("~/test.yaml") as NSString).expandingTildeInPath)
    }

    func testMicroFolder() {
        let plain = AppPaths(environment: [:], home: home)
        XCTAssertEqual(plain.microFolder(config: URL(fileURLWithPath: "/Users/someone/.config/swiftkey/menu.yaml")).path,
                       "/Users/someone/.config/swiftkey/micro")
        let override = AppPaths(environment: ["SWIFTKEY_CONFIG": "/tmp/x/config.yaml"], home: home)
        XCTAssertEqual(override.microFolder(config: URL(fileURLWithPath: "/tmp/x/config.yaml")).path,
                       "/tmp/x/config.yaml.micro")
        // Another config than the override keeps the folder next to it.
        XCTAssertEqual(override.microFolder(config: URL(fileURLWithPath: "/tmp/y/menu.yaml")).path, "/tmp/y/micro")
    }

    func testOverrideHasItsOwnDefaultsSuite() {
        let one = AppPaths(environment: ["SWIFTKEY_CONFIG": "/tmp/x/config.yaml"], home: home)
        let two = AppPaths(environment: ["SWIFTKEY_CONFIG": "/tmp/y/config.yaml"], home: home)
        XCTAssertNotNil(one.defaultsSuiteName)
        XCTAssertNotEqual(one.defaultsSuiteName, two.defaultsSuiteName)
        XCTAssertNotEqual(one.defaultsSuiteName, "com.ameba.SwiftKey")
    }

    /// The test scheme sets the override, so hosted tests never touch the person's files or settings.
    func testHostedTestsRunWithTheOverride() {
        XCTAssertEqual(AppPaths.current.configOverride?.path, "/tmp/swiftkey-tests/config.yaml")
        XCTAssertNotEqual(AppPaths.defaults, UserDefaults.standard)
    }
}
