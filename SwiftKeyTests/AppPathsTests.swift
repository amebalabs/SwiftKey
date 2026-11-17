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

    /// Hosted tests get a config of their own in a new temporary folder, with their settings next
    /// to it, so they never touch the person's files or preferences, whatever the scheme sets.
    func testHostedTestsRunWithAConfigOfTheirOwn() throws {
        let config = try XCTUnwrap(AppPaths.current.configOverride)
        XCTAssertTrue(config.path.hasPrefix(FileManager.default.temporaryDirectory.path), config.path)
        XCTAssertTrue(config.path.contains("swiftkey-tests-\(ProcessInfo.processInfo.processIdentifier)-"))
        XCTAssertNotEqual(AppPaths.defaults, UserDefaults.standard)
        XCTAssertEqual(AppPaths.current.defaultsSuiteName, config.path + ".settings")
    }

    func testEveryTestRunHasItsOwnConfig() {
        let environment = [AppPaths.testEnvironmentKey: "/tmp/x.xctestconfiguration"]
        XCTAssertNotEqual(AppPaths(environment: environment).configOverride, AppPaths(environment: environment).configOverride)
    }

    /// A release build ignores the variable, so a config named from outside cannot bring its own approvals.
    func testReleaseBuildsIgnoreTheOverride() {
        let paths = AppPaths(environment: ["SWIFTKEY_CONFIG": "/tmp/x/config.yaml"], home: home, isDebugBuild: false)
        XCTAssertNil(paths.configOverride)
        XCTAssertTrue(paths.ignoredOverride)
        XCTAssertEqual(paths.url(for: "approvals.json").path, home.path + "/Library/Application Support/SwiftKey/approvals.json")
        XCTAssertNil(paths.defaultsSuiteName)
    }

    func testTestRunsFollowTheOverrideInAnyBuild() {
        let environment = ["SWIFTKEY_CONFIG": "/tmp/x/config.yaml", AppPaths.testEnvironmentKey: "/tmp/x.xctestconfiguration"]
        let paths = AppPaths(environment: environment, home: home, isDebugBuild: false)
        XCTAssertEqual(paths.configOverride?.path, "/tmp/x/config.yaml")
        XCTAssertFalse(paths.ignoredOverride)
    }
}
