import XCTest
@testable import SwiftKey

/// A config file whose items start micro-apps loads like any other config.
final class MicroAppConfigLoadTests: XCTestCase {
    func testConfigWithMicroItemsLoads() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("swiftkey-micro-config-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("config.yaml")
        try """
        - key: "j"
          title: "Format JSON"
          action: "micro://format-json"
        - key: "t"
          title: "Text"
          submenu:
            - key: "u"
              title: "Translate to Ukrainian"
              action: "micro://translate-ukrainian"
              notify: true
        """.write(to: url, atomically: true, encoding: .utf8)

        let result = await ConfigManager(configURL: url).loadConfig()
        guard case .success(let items) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(items.map(\.action), ["micro://format-json", nil])
        XCTAssertEqual(items.first?.microAppID, "format-json")
        XCTAssertEqual(items.last?.submenu?.first?.microAppID, "translate-ukrainian")
    }
}
