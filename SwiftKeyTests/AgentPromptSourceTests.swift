import AppKit
import SwiftKeyCore
import XCTest
@testable import SwiftKey

/// The real values of the agent prompt and the copy to a private pasteboard. The person's
/// clipboard and config are never touched.
final class AgentPromptSourceTests: XCTestCase {
    func testTheFolderIsNextToTheConfig() {
        let config = URL(fileURLWithPath: "/tmp/swiftkey spec \(UUID().uuidString)/menu.yaml")
        let text = AgentPromptSource.text(configURL: config, paths: AppPaths(environment: [:]))
        let folder = config.deletingLastPathComponent().appendingPathComponent("micro").path
        XCTAssertTrue(text.contains("micro-apps folder `\(folder)`"), text)
        XCTAssertTrue(text.contains("mkdir -p '\(folder)'"), text)
        XCTAssertTrue(text.contains("config file `\(config.path)`"), text)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder))
    }

    func testTheOverrideFolderFollowsSwiftKeyConfig() {
        let config = URL(fileURLWithPath: "/tmp/swiftkey-prompt-\(UUID().uuidString).yaml")
        let paths = AppPaths(environment: [AppPaths.environmentKey: config.path])
        let text = AgentPromptSource.text(configURL: config, paths: paths)
        XCTAssertTrue(text.contains("micro-apps folder `\(config.path).micro`"), text)
    }

    func testABundleWithoutTheDocumentNamesOnlyTheLinkOnMain() {
        // The test bundle has no FORMAT.md and no version of SwiftKey.
        let bundle = Bundle(for: Self.self)
        XCTAssertNil(AgentPromptSource.formatDocument(bundle: bundle))
        let text = AgentPromptSource.text(bundle: bundle, configURL: URL(fileURLWithPath: "/tmp/x.yaml"),
                                          paths: AppPaths(environment: [:]))
        XCTAssertFalse(text.contains("Resources/FORMAT.md"))
        XCTAssertTrue(text.contains("format document \(AgentPrompt.formatLink(version: AgentPromptSource.version(bundle: bundle)))."), text)
    }

    func testTheAppBundleNamesItsFormatDocumentAndTool() throws {
        // The hosted tests run inside the built SwiftKey.app, which bundles FORMAT.md.
        let bundle = Bundle.main
        let document = try XCTUnwrap(AgentPromptSource.formatDocument(bundle: bundle))
        XCTAssertTrue(document.hasSuffix("SwiftKey.app/Contents/Resources/FORMAT.md"), document)
        XCTAssertTrue(FileManager.default.fileExists(atPath: AgentPrompt.guide(forFormat: document)))
        let executable = AgentPromptSource.executable(bundle: bundle)
        let tool = (executable as NSString).deletingLastPathComponent + "/swiftkey-micro"
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: tool), tool)
        let text = AgentPromptSource.text(bundle: bundle, configURL: URL(fileURLWithPath: "/tmp/x.yaml"),
                                          paths: AppPaths(environment: [:]))
        let documentAt = try XCTUnwrap(text.range(of: "`\(document)`")).lowerBound
        let link = AgentPrompt.formatLink(version: AgentPromptSource.version(bundle: bundle))
        let linkAt = try XCTUnwrap(text.range(of: link)).lowerBound
        XCTAssertLessThan(documentAt, linkAt)
    }

    func testCopyUsesTheGivenPasteboard() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.ameba.SwiftKey.tests." + UUID().uuidString))
        addTeardownBlock { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("old", forType: .string)
        let text = AgentPromptSource.text(configURL: URL(fileURLWithPath: "/tmp/x.yaml"), paths: AppPaths(environment: [:]))
        AgentPromptSource.copy(text, to: pasteboard)
        XCTAssertEqual(pasteboard.string(forType: .string), text)
    }
}
