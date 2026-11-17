import XCTest
import SwiftKeyCore
@testable import SwiftKey

/// Every test uses its own temporary folder as the config directory; the real `~/.config/swiftkey`
/// is never touched.
@MainActor
final class MicroAppStoreTests: XCTestCase {
    private static let good = """
    format: ting.microapp/2
    description: Say hi.
    input: none
    command: echo hi
    output:
      to: [panel]

    """

    private func temporaryConfig() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("swiftkey-micro-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("config.yaml")
    }

    private func makeFolder(_ store: MicroAppStore) throws {
        try FileManager.default.createDirectory(at: store.folderURL, withIntermediateDirectories: true)
    }

    private func put(_ text: String, _ name: String, in store: MicroAppStore) throws {
        try Data(text.utf8).write(to: store.folderURL.appendingPathComponent(name))
    }

    private func log(_ store: MicroAppStore) throws -> String {
        try String(contentsOf: store.logURL, encoding: .utf8)
    }

    /// Waits for the next reload that `change` causes.
    private func change(_ store: MicroAppStore, _ what: String,
                        _ change: () throws -> Void) async throws -> (previous: MicroAppCatalog, current: MicroAppCatalog) {
        let reloaded = expectation(description: what)
        var result: (MicroAppCatalog, MicroAppCatalog)?
        store.watch { previous, current in
            guard result == nil else { return }
            result = (previous, current)
            reloaded.fulfill()
        }
        try change()
        await fulfillment(of: [reloaded], timeout: 5)
        return try XCTUnwrap(result)
    }

    func testPathsSitNextToTheConfigFile() throws {
        let config = try temporaryConfig()
        let store = MicroAppStore(configURL: config, paths: AppPaths(environment: [:]))
        XCTAssertEqual(store.folderURL.path, config.deletingLastPathComponent().appendingPathComponent("micro").path)
        XCTAssertEqual(store.logURL.path, config.deletingLastPathComponent().appendingPathComponent("micro-errors.log").path)
        // With SWIFTKEY_CONFIG, the config file name comes first, as for the other data files.
        let paths = AppPaths(environment: ["SWIFTKEY_CONFIG": "/tmp/swiftkey-x/test.yaml"])
        let custom = MicroAppStore(configURL: URL(fileURLWithPath: "/tmp/swiftkey-x/test.yaml"), paths: paths)
        XCTAssertEqual(custom.folderURL.path, "/tmp/swiftkey-x/test.yaml.micro")
        XCTAssertEqual(custom.logURL.path, "/tmp/swiftkey-x/test.yaml.micro-errors.log")
        let other = AppPaths(environment: ["SWIFTKEY_CONFIG": "/tmp/swiftkey-x/other.yaml"])
        XCTAssertNotEqual(MicroAppStore(configURL: URL(fileURLWithPath: "/tmp/swiftkey-x/other.yaml"), paths: other).folderURL,
                          custom.folderURL)
    }

    /// The app reads the user's PATH again on each load: the first one at start and every load
    /// that the watch makes after a file change.
    func testEveryLoadCallsOnLoadAlsoFromTheWatch() async throws {
        let store = MicroAppStore(configURL: try temporaryConfig(), paths: AppPaths(environment: [:]))
        try makeFolder(store)
        var loads = 0
        store.onLoad = { loads += 1 }
        store.load()
        XCTAssertEqual(loads, 1)
        _ = try await change(store, "add a file") { try put(Self.good, "say-hi.yaml", in: store) }
        XCTAssertGreaterThanOrEqual(loads, 2)
        store.stopWatching()
    }

    func testMissingFolderIsAnEmptyList() throws {
        let store = MicroAppStore(configURL: try temporaryConfig(), paths: AppPaths(environment: [:]))
        let catalog = store.load()
        XCTAssertTrue(catalog.entries.isEmpty)
        XCTAssertTrue(catalog.issues.isEmpty)
        XCTAssertEqual(try log(store), "")
    }

    func testLoadsYamlFilesOnly() throws {
        let store = MicroAppStore(configURL: try temporaryConfig(), paths: AppPaths(environment: [:]))
        try makeFolder(store)
        try put(Self.good, "say-hi.yaml", in: store)
        try put(Self.good, "notes.txt", in: store)
        try put(Self.good, ".hidden.yaml", in: store)
        try FileManager.default.createDirectory(at: store.folderURL.appendingPathComponent("dir.yaml"), withIntermediateDirectories: true)
        let catalog = store.load()
        XCTAssertEqual(catalog.entries.map(\.file), ["say-hi.yaml"])
        XCTAssertEqual(catalog.apps.map(\.id), ["say-hi"])
    }

    func testLogListsProblemsAndIsEmptiedWhenFixed() throws {
        let store = MicroAppStore(configURL: try temporaryConfig(), paths: AppPaths(environment: [:]))
        try makeFolder(store)
        try put(Self.good, "fine.yaml", in: store)
        try put("format: ting.microapp/2\nid: Bad\n", "broken.yaml", in: store)
        let catalog = store.load()
        XCTAssertEqual(catalog.brokenFiles, ["broken.yaml"])
        let lines = try log(store).split(separator: "\n")
        XCTAssertEqual(lines.count, catalog.issues.count)
        XCTAssertGreaterThan(lines.count, 1)
        for (line, issue) in zip(lines, catalog.issues) {
            XCTAssertEqual(String(line), "broken.yaml:\(issue.line): \(issue.message)")
        }
        try put(Self.good, "broken.yaml", in: store)
        XCTAssertTrue(store.load().issues.isEmpty)
        XCTAssertEqual(try log(store), "")
    }

    func testLiveAddChangeAndRemove() async throws {
        let store = MicroAppStore(configURL: try temporaryConfig(), paths: AppPaths(environment: [:]))
        defer { store.stopWatching() }
        XCTAssertTrue(store.load().entries.isEmpty)

        // The folder appears with a good file.
        var step = try await change(store, "add") {
            try makeFolder(store)
            try put(Self.good, "say-hi.yaml", in: store)
        }
        if step.current.apps.isEmpty {
            // The folder event can come before the file is written.
            step = try await change(store, "add file") { try put(Self.good + "\n", "say-hi.yaml", in: store) }
        }
        XCTAssertEqual(store.catalog.apps.map(\.id), ["say-hi"])

        // Another file is added.
        step = try await change(store, "add second") { try put(Self.good, "second.yaml", in: store) }
        XCTAssertEqual(step.current.apps.map(\.id), ["say-hi", "second"])
        XCTAssertNil(step.current.toastMessage(since: step.previous))

        // A file is changed in place and breaks: the change brings a toast.
        step = try await change(store, "break") {
            let handle = try FileHandle(forWritingTo: store.folderURL.appendingPathComponent("second.yaml"))
            try handle.seekToEnd()
            try handle.write(contentsOf: Data("unknown: 1\n".utf8))
            try handle.close()
        }
        XCTAssertEqual(step.current.brokenFiles, ["second.yaml"])
        XCTAssertNotNil(step.current.toastMessage(since: step.previous))
        XCTAssertTrue(try log(store).hasPrefix("second.yaml:"))

        // The broken file is removed.
        step = try await change(store, "remove") {
            try FileManager.default.removeItem(at: store.folderURL.appendingPathComponent("second.yaml"))
        }
        XCTAssertEqual(step.current.entries.map(\.file), ["say-hi.yaml"])
        XCTAssertTrue(step.current.issues.isEmpty)
        XCTAssertEqual(try log(store), "")
    }
}
