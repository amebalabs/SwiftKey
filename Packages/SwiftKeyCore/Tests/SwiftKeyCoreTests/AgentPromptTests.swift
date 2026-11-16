import Foundation
import Testing
@testable import SwiftKeyCore

@Suite struct AgentPromptTests {
    private let link = AgentPrompt.formatLink(version: "1.5.0")
    private let document = "/Applications/SwiftKey.app/Contents/Resources/FORMAT.md"
    private let config = "/Users/someone/.config/swiftkey/config.yaml"
    private let folder = "/Users/someone/.config/swiftkey/micro"
    private let executable = "/Applications/SwiftKey.app/Contents/MacOS/SwiftKey"

    private func lines(_ text: String) -> [String] { text.components(separatedBy: "\n") }

    @Test func linkPointsToTheTagOfTheVersion() {
        #expect(link == "https://raw.githubusercontent.com/amebalabs/SwiftKey/v1.5.0/Packages/SwiftKeyCore/docs/micro-apps/FORMAT.md")
    }

    @Test func linkWithoutAVersionPointsToMain() {
        #expect(AgentPrompt.formatLink(version: nil)
            == "https://raw.githubusercontent.com/amebalabs/SwiftKey/main/Packages/SwiftKeyCore/docs/micro-apps/FORMAT.md")
    }

    /// The linked documents exist at these paths in the repository.
    @Test func linkedDocumentsExistInTheRepository() {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let repoRoot = packageRoot.deletingLastPathComponent().deletingLastPathComponent()
        for link in [link, AgentPrompt.guideLink(forFormatLink: link)] {
            let path = link.replacingOccurrences(of: "https://raw.githubusercontent.com/amebalabs/SwiftKey/v1.5.0/", with: "")
            #expect(FileManager.default.fileExists(atPath: repoRoot.appendingPathComponent(path).path), "\(path)")
        }
    }

    @Test func withTheBundledDocumentThePartsComeInOrder() throws {
        let text = AgentPrompt.text(formatDocument: document, link: link, configFile: config, microAppsFolder: folder,
                                    executable: executable)
        let micro = (executable as NSString).deletingLastPathComponent + "/swiftkey-micro"
        let parts = [
            "guide `\(AgentPrompt.guide(forFormat: document))`",
            "use \(AgentPrompt.guideLink(forFormatLink: link)) instead",
            "format document `\(document)`",
            "one file named `<id>.yaml`",
            "temporary folder",
            "`'\(micro)' check --libs '\(folder)/libs' <file>`",
            "no problem",
            "micro-apps folder `\(folder)`",
            "mv <file> '\(folder)'/",
            "config file `\(config)` only for the menu items I ask for",
            "`action: \"micro://<id>\"`",
            "Never put API keys into files",
        ]
        var position = text.startIndex
        for part in parts {
            let range = try #require(text.range(of: part, range: position..<text.endIndex), "\(part) out of order")
            position = range.upperBound
        }
        // The document inside the app comes before the link.
        let documentAt = try #require(text.range(of: document)).lowerBound
        let linkAt = try #require(text.range(of: link)).lowerBound
        #expect(documentAt < linkAt)
        // The last line is open for the person's task.
        #expect(lines(text).last == "My task: ")
        #expect(!text.hasSuffix("\n"))
        #expect(AgentPrompt.guideLink(forFormatLink: link)
            == "https://raw.githubusercontent.com/amebalabs/SwiftKey/v1.5.0/Packages/SwiftKeyCore/docs/CONFIGURING.md")
    }

    @Test func withoutTheBundledDocumentOnlyTheLinkIsNamed() {
        let text = AgentPrompt.text(formatDocument: nil, link: link, configFile: config, microAppsFolder: folder,
                                    executable: executable)
        #expect(text.contains("format document \(link)."))
        #expect(text.contains("guide \(AgentPrompt.guideLink(forFormatLink: link)) and follow it"))
        #expect(!text.contains("FORMAT.md`"))
        #expect(!text.contains("Resources"))
        #expect(!text.contains("cannot be read"))
        #expect(lines(text).last == "My task: ")
    }

    @Test func pathsWithSpacesAreQuotedInCommands() {
        let spaced = "/Users/some one/Apps/My SwiftKey.app/Contents/MacOS/SwiftKey"
        let spacedFolder = "/private/tmp/swiftkey spec.yaml.micro"
        let spacedDocument = "/Users/some one/Apps/My SwiftKey.app/Contents/Resources/FORMAT.md"
        let text = AgentPrompt.text(formatDocument: spacedDocument, link: link, configFile: config,
                                    microAppsFolder: spacedFolder, executable: spaced)
        #expect(text.contains("`\(spacedDocument)`"))
        #expect(text.contains("`'/Users/some one/Apps/My SwiftKey.app/Contents/MacOS/swiftkey-micro' check --libs '\(spacedFolder)/libs' <file>`"))
        #expect(text.contains("`mkdir -p '\(spacedFolder)' && mv <file> '\(spacedFolder)'/`"))
    }

    @Test func shellQuotingKeepsSingleQuotes() {
        #expect(AgentPrompt.shellQuoted("/a b/c") == "'/a b/c'")
        #expect(AgentPrompt.shellQuoted("/it's/here") == "'/it'\\''s/here'")
    }
}
