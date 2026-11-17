import SwiftKeyCore
import XCTest
@testable import SwiftKey

/// The config editor's micro-app picker: choices, the file to reveal and the problem line.
final class MicroAppDirectoryTests: XCTestCase {
    private let folder = URL(fileURLWithPath: "/tmp/swiftkey-tests/config.yaml.micro", isDirectory: true)

    private func directory() -> MicroAppDirectory {
        let catalog = MicroAppCatalog.load([
            (name: "say-hi.yaml", text: "format: ting.microapp/2\nname: Say hi\ndescription: Say hi.\ninput: none\ncommand: echo hi\n"),
            (name: "broken.yaml", text: "format: ting.microapp/2\ndescription: Broken.\n"),
        ])
        let directory = MicroAppDirectory()
        directory.update(catalog, folder: folder)
        return directory
    }

    func testChoicesListWorkingMicroAppsAndKeepTheCurrentBrokenOne() {
        let directory = directory()
        XCTAssertEqual(directory.choices(current: nil).map(\.title), ["Say hi · say-hi"])
        XCTAssertEqual(directory.choices(current: "broken").map(\.title), ["broken (broken)", "Say hi · say-hi"])
        XCTAssertEqual(directory.choices(current: "gone").map(\.title), ["gone (missing)", "Say hi · say-hi"])
    }

    func testFileToRevealIsInTheMicroAppsFolder() {
        let directory = directory()
        XCTAssertEqual(directory.fileURL(for: "say-hi"), folder.appendingPathComponent("say-hi.yaml"))
        XCTAssertEqual(directory.fileURL(for: "broken"), folder.appendingPathComponent("broken.yaml"))
        XCTAssertNil(directory.fileURL(for: "gone"))
    }

    func testProblemNamesTheFileOrTheFolder() throws {
        let directory = directory()
        XCTAssertNil(directory.problem(for: "say-hi"))
        XCTAssertNil(directory.problem(for: ""))
        let broken = try XCTUnwrap(directory.problem(for: "broken"))
        XCTAssertTrue(broken.hasPrefix("Micro-app broken.yaml, line "), broken)
        XCTAssertEqual(directory.problem(for: "gone"), "Micro-app `gone` not found in /tmp/swiftkey-tests/config.yaml.micro")
    }

    func testWithoutAFolderNothingCanBeRevealed() {
        let directory = MicroAppDirectory()
        directory.update(MicroAppCatalog.load([
            (name: "say-hi.yaml", text: "format: ting.microapp/2\ndescription: Say hi.\ninput: none\ncommand: echo hi\n"),
        ]), folder: nil)
        XCTAssertNil(directory.fileURL(for: "say-hi"))
        XCTAssertEqual(directory.problem(for: "gone"), "Micro-app `gone` not found in the micro-apps folder")
    }
}
