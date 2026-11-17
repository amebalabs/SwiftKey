import XCTest
import SwiftKeyCore
@testable import SwiftKey

final class LaunchaServiceTests: XCTestCase {
    private func temporary() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("swiftkey-launcha-services-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return try XCTUnwrap(LaunchaPathPolicy.realURL(url))
    }

    private func app(_ url: URL, id: String? = nil) throws {
        let contents = url.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        var info = ["CFBundleName": "Test", "CFBundleDisplayName": "Localized Test", "CFBundlePackageType": "APPL"]
        info["CFBundleIdentifier"] = id
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
    }

    func testIndexPackagesUtilitiesCyclesAndIdentity() async throws {
        let root = try temporary()
        let apps = root.appendingPathComponent("Applications")
        let a = apps.appendingPathComponent("Utilities/A.app")
        try app(a, id: "com.ameba.test.test")
        try app(a.appendingPathComponent("Contents/Hidden.app"), id: "com.ameba.test.hidden")
        try app(apps.appendingPathComponent("Duplicate.app"), id: "com.ameba.test.test")
        try app(apps.appendingPathComponent("Container.bundle/Nested.app"), id: "com.ameba.test.packaged")
        try app(apps.appendingPathComponent(".hidden/Secret.app"), id: "com.ameba.test.secret")
        let anonymous = apps.appendingPathComponent("NoID.app")
        try app(anonymous)
        try FileManager.default.createSymbolicLink(at: apps.appendingPathComponent("Loop"), withDestinationURL: apps)
        try FileManager.default.createSymbolicLink(at: apps.appendingPathComponent("Alias.app"), withDestinationURL: anonymous)
        let index = LaunchaAppIndex(home: root, roots: [apps])
        let result = await index.refreshOnOpen()
        XCTAssertEqual(result.apps.count, 2)
        XCTAssertTrue(result.apps.contains { $0.candidate.id == "app-path:" + anonymous.path && $0.url.path == anonymous.path })
        XCTAssertTrue(result.apps.allSatisfy { $0.candidate.name == "Localized Test" })
        XCTAssertTrue(result.issues.isEmpty)
        let matches = await index.search("localized", history: LaunchHistory())
        XCTAssertEqual(matches.count, 2)
        try FileManager.default.removeItem(at: anonymous)
        let refreshed = await index.refreshOnOpen()
        XCTAssertEqual(refreshed.apps.count, 1)
    }

    func testRefreshCacheAndCancelledScan() async throws {
        let root = try temporary()
        try app(root.appendingPathComponent("One.app"))
        let index = LaunchaAppIndex(home: root, roots: [root])
        let first = await index.refreshOnOpen()
        XCTAssertEqual(first.apps.count, 1)
        try app(root.appendingPathComponent("Two.app"))
        let cached = await index.refreshIfNeeded()
        XCTAssertEqual(cached.apps.count, 1)
        let cancelled = Task { await index.refreshOnOpen() }
        cancelled.cancel()
        _ = await cancelled.value
        let afterCancel = await index.search("", history: LaunchHistory())
        XCTAssertEqual(afterCancel.count, 1)
        let refreshed = await index.refreshOnOpen()
        XCTAssertEqual(refreshed.apps.count, 2)
    }

    func testDesktopConsent() async throws {
        let home = try temporary()
        let desktop = home.appendingPathComponent("Desktop")
        try app(desktop.appendingPathComponent("Tool.app"))
        let gated = LaunchaAppIndex(home: home, roots: [desktop])
        let skipped = await gated.refreshOnOpen()
        XCTAssertEqual(skipped.issues.map(\.kind), [.needsConsent])
        XCTAssertTrue(skipped.apps.isEmpty)
        let allowed = LaunchaAppIndex(home: home, protectedFolders: .allowed, roots: [desktop])
        let indexed = await allowed.refreshOnOpen()
        XCTAssertEqual(indexed.apps.count, 1)
        XCTAssertTrue(indexed.issues.isEmpty)
    }

    func testIndexBeyondFormerDepthLimit() async throws {
        let root = try temporary()
        var folder = root
        for _ in 0..<32 { folder.appendPathComponent("level") }
        let deepApp = folder.appendingPathComponent("Deep.app")
        try app(deepApp, id: "com.ameba.test.deep")
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("Loop"), withDestinationURL: root)
        let index = LaunchaAppIndex(home: root, roots: [root])
        let result = await index.refreshOnOpen()
        XCTAssertEqual(result.apps.map(\.url.path), [deepApp.path])
        XCTAssertTrue(result.issues.isEmpty)
    }

    func testIndexBeyondFormerEntryLimit() async throws {
        let root = try temporary()
        let files = root.appendingPathComponent("Files")
        try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
        for entry in 0..<20_001 {
            try Data().write(to: files.appendingPathComponent("file-\(entry)"))
        }
        let target = root.appendingPathComponent("Target.app")
        try app(target, id: "com.ameba.test.target")
        // Scan the large root first so the target must come after the former cap.
        let index = LaunchaAppIndex(home: root, roots: [files, target])
        let result = await index.refreshOnOpen()
        XCTAssertEqual(result.apps.map(\.url.path), [target.path])
        XCTAssertTrue(result.issues.isEmpty)
    }

    func testPathRestrictionsIncludeSymlinks() throws {
        let home = try temporary()
        let outside = try temporary()
        let policy = LaunchaPathPolicy(home: home, protectedFolders: .allowed)
        for path in ["Library/a", ".secret/a", "Foo.app/Contents/a", "Desktop/.secret/a"] {
            XCTAssertFalse(policy.searchable(home.appendingPathComponent(path)))
        }
        XCTAssertFalse(policy.searchable(outside.appendingPathComponent("file")))
        for (name, destination) in [("escape", outside), ("library-link", home.appendingPathComponent("Library")), ("app-link", home.appendingPathComponent("Tool.app"))] {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            try Data().write(to: destination.appendingPathComponent("file"))
            try FileManager.default.createSymbolicLink(at: home.appendingPathComponent(name), withDestinationURL: destination)
            XCTAssertFalse(policy.searchable(home.appendingPathComponent(name + "/file")))
        }
        try FileManager.default.createDirectory(at: home.appendingPathComponent("Projects"), withIntermediateDirectories: true)
        try Data().write(to: home.appendingPathComponent("Projects/file"))
        XCTAssertTrue(policy.searchable(home.appendingPathComponent("Projects/file")))
        XCTAssertFalse(LaunchaPathPolicy(home: home).searchable(home.appendingPathComponent("Desktop/file")))
    }

    func testHistoryRecoveryIsolationAndSerializedWrites() async throws {
        let root = try temporary()
        let url = root.appendingPathComponent("history.json")
        let original = Data("broken history".utf8)
        try original.write(to: url)
        let store = LaunchaHistoryStore(url: url)
        let loaded = await store.load()
        XCTAssertEqual(loaded.issues.count, 1)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(loaded.preservedOriginal)), original)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<20 { group.addTask { _ = await store.record(.opened, id: "app:test") } }
        }
        let saved = try LaunchHistory.decode(Data(contentsOf: url))
        XCTAssertEqual(saved.entries["app:test"]?.events.count, 20)
        _ = await store.record(.failed, id: "ignored")
        _ = await store.record(.revealed, id: "ignored")
        XCTAssertEqual(try LaunchHistory.decode(Data(contentsOf: url)), saved)
        let isolated = AppPaths(environment: ["SWIFTKEY_CONFIG": root.appendingPathComponent("config.yaml").path], home: root)
        XCTAssertEqual(isolated.url(for: "launcha-history.json").path, root.path + "/config.yaml.launcha-history.json")
        XCTAssertEqual(AppPaths(environment: [:], home: root).url(for: "launcha-history.json").path,
                       root.appendingPathComponent("Library/Application Support/SwiftKey/launcha-history.json").path)
        // The running tests use the scheme's override, never the real history.
        let defaultURL = await LaunchaHistoryStore().url
        XCTAssertEqual(defaultURL, AppPaths.current.url(for: "launcha-history.json"))
        XCTAssertNotNil(AppPaths.current.configOverride)
    }

    func testFreshHistoryAndWriteFailure() async throws {
        let root = try temporary()
        let fresh = root.appendingPathComponent("new/history.json")
        let store = LaunchaHistoryStore(url: fresh)
        let empty = await store.load()
        XCTAssertTrue(empty.issues.isEmpty)
        _ = await store.record(.failed, id: "not-counted")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fresh.path))
        _ = await store.record(.activated, id: "counted")
        XCTAssertEqual(try LaunchHistory.decode(Data(contentsOf: fresh)).entries.count, 1)
        let blocked = root.appendingPathComponent("blocked")
        try Data().write(to: blocked)
        let failed = LaunchaHistoryStore(url: blocked.appendingPathComponent("history.json"))
        let result = await failed.record(.opened, id: "memory-only")
        XCTAssertFalse(result.issues.isEmpty)
        XCTAssertEqual(result.history.entries.count, 1)
        XCTAssertEqual(LaunchaServiceIssue.access(CocoaError(.fileReadNoPermission), at: root).kind, .denied)
        XCTAssertEqual(LaunchaServiceIssue.access(NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES)), at: root).kind, .denied)
    }

    /// A real file-name search in `folder`, standing in for the Spotlight index, which does not
    /// cover temporary folders. `delay` holds the answer back, ignoring cancellation, to exercise
    /// the generation guard.
    private static func folderSearch(_ folder: URL, delay: @escaping @Sendable (String) -> Duration = { _ in .zero })
        -> LaunchaSpotlight.Provider {
        { text in
            try? await Task.sleep(for: delay(text))
            let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
            return names.filter { $0.localizedCaseInsensitiveContains(text) }.map { folder.appendingPathComponent($0) }
        }
    }

    @MainActor
    func testSpotlightDebounceCancelStaleAndCap() async throws {
        let home = try temporary()
        let old = home.appendingPathComponent("old-notes.txt")
        let newer = home.appendingPathComponent("new-notes.txt")
        let newest = home.appendingPathComponent("newest-notes.txt")
        for file in [old, newer, newest] { try Data().write(to: file) }
        let service = LaunchaSpotlight(home: home, protectedFolders: .allowed, debounce: .milliseconds(10), cap: 1,
                                       provider: Self.folderSearch(home) { $0 == "old" ? .milliseconds(180) : .milliseconds(20) })
        service.search("old")
        try await Task.sleep(for: .milliseconds(30))
        service.search("new")
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(service.state.status, .results)
        // Two files match "new"; the cap keeps one.
        XCTAssertEqual(service.state.files.map(\.url), [newer])
        service.search("old")
        service.cancel()
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(service.state.status, .idle)
        service.search("   ")
        XCTAssertEqual(service.state.status, .idle)
    }

    @MainActor
    func testSpotlightIncompleteEmptyAndFailure() async throws {
        let home = try temporary()
        let service = LaunchaSpotlight(home: home, debounce: .zero, provider: Self.folderSearch(home))
        service.search("missing")
        XCTAssertEqual(service.state.status, .searching)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(service.state.status, .empty)
        XCTAssertEqual(service.state.issues.map(\.kind), [.needsConsent, .needsConsent, .needsConsent])
        // A folder that cannot be listed fails the search with its error.
        let failure = LaunchaSpotlight(home: home, debounce: .zero,
                                       provider: Self.folderSearch(home.appendingPathComponent("no-such-folder")))
        failure.search("failure")
        try await Task.sleep(for: .milliseconds(50))
        guard case .error = failure.state.status else { return XCTFail("Expected search error") }
        XCTAssertEqual(failure.state.issues.last?.kind, .io)
        let timeout = LaunchaSpotlight(home: home, debounce: .zero, timeout: .milliseconds(10),
                                       provider: Self.folderSearch(home) { _ in .milliseconds(100) })
        timeout.search("slow")
        try await Task.sleep(for: .milliseconds(150))
        guard case .error = timeout.state.status else { return XCTFail("Expected timeout, not stale empty") }
    }
}
