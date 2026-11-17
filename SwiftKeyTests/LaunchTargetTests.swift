import Testing
import Foundation
@testable import SwiftKey

@Suite("Launch targets")
struct LaunchTargetTests {
    let validator = ConfigValidator()

    private func item(_ action: String) -> MenuItem {
        MenuItem(key: "a", title: "App", action: action)
    }

    @Test("Paths and app names are paths; other names are bundle identifiers")
    func parsing() {
        #expect(LaunchTarget("/Applications/Safari.app") == .path("/Applications/Safari.app"))
        #expect(LaunchTarget("~/Applications/X.app") == .path(("~/Applications/X.app" as NSString).expandingTildeInPath))
        #expect(LaunchTarget("Calculator.app") == .path("Calculator.app"))
        #expect(LaunchTarget("com.apple.Safari") == .bundleID("com.apple.Safari"))
    }

    @Test("An installed bundle identifier resolves to its app")
    func resolvesBundleID() throws {
        let url = try #require(LaunchTarget("com.apple.finder").resolve())
        #expect(url.pathExtension == "app")
        #expect(LaunchTarget("io.example.no-such-app").resolve() == nil)
        #expect(LaunchTarget("/System/Applications/Calculator.app").resolve() != nil)
        #expect(LaunchTarget("/Applications/No Such App.app").resolve() == nil)
    }

    @Test("A bundle identifier of an installed app is valid")
    func validBundleID() {
        let issues = validator.validate(item("launch://com.apple.finder"))
        #expect(!issues.contains { $0.type == .invalidPath })
    }

    @Test("An unknown bundle identifier is a warning that names it")
    func unknownBundleID() {
        let issues = validator.validate(item("launch://io.example.no-such-app"))
        let issue = issues.first { $0.type == .invalidPath }
        #expect(issue?.severity == .warning)
        #expect(issue?.message == "No installed application has the bundle identifier io.example.no-such-app")
    }

    @Test("A missing app path is still a warning")
    func missingPath() {
        let issues = validator.validate(item("launch:///Applications/No Such App.app"))
        #expect(issues.contains { $0.type == .invalidPath && $0.severity == .warning })
    }
}
