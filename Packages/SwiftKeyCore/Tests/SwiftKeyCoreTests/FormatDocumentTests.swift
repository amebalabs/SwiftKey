import Foundation
import Testing
import SwiftKeyCore

private let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
private let documentURL = root.appendingPathComponent("docs/micro-apps/FORMAT.md")
private let examplesURL = root.appendingPathComponent("docs/micro-apps/examples", isDirectory: true)
/// The example libraries: the micro-app blocks of FORMAT.md may call or inherit them.
private let libraries = MicroAppLibraries.read(folder: examplesURL.appendingPathComponent("libs"))

/// The text of every fenced `yaml` block of a markdown document, in order, with its final line break.
private func yamlBlocks(of markdown: String) -> [String] {
    var blocks: [String] = []
    var current: [Substring]?
    for line in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
        if var lines = current {
            if line == "```" {
                blocks.append(lines.map { $0 + "\n" }.joined())
                current = nil
            } else {
                lines.append(line)
                current = lines
            }
        } else if line == "```yaml" {
            current = []
        }
    }
    return blocks
}

/// The top-level keys that only a whole micro-app file has: the required keys of `ting.microapp/2`, `command` and `steps`.
private let fileKeys: Set<String> = ["format", "description", "input", "command", "steps", "output"]

/// A complete micro-app block: a `yaml` block with a top-level line (not indented, not a comment)
/// for any required key of a file, wherever it stands: after comments, blank lines, `---` or other
/// keys, and also as a quoted key. A fragment, such as a `params:` list alone, has none of them.
private func isCompleteMicroApp(_ block: String) -> Bool {
    block.split(separator: "\n", omittingEmptySubsequences: false).contains { line in
        guard let first = line.first, first != " ", first != "\t", first != "#", first != "-",
              let colon = line.firstIndex(of: ":") else { return false }
        var key = line[..<colon].trimmingCharacters(in: .whitespaces)
        if key.count >= 2, let quote = key.first, quote == "\"" || quote == "'", key.last == quote {
            key = String(key.dropFirst().dropLast())
        }
        return fileKeys.contains(key)
    }
}

/// Every complete micro-app block of `markdown` that `MicroAppChecker` refuses, with its problems.
/// A block equal to an example file is checked under that file name, another under a neutral one.
private func refusedBlocks(of markdown: String, examples: [(name: String, text: String)] = [])
    -> [(index: Int, fileName: String, issues: [MicroAppIssue])] {
    yamlBlocks(of: markdown).filter(isCompleteMicroApp).enumerated().compactMap { index, block in
        if block.hasPrefix("format: \(MicroAppLibraries.format)") {
            guard case .failure(let failure) = MicroAppChecker.checkLibrary(block, fileName: "libs/format-block-\(index + 1).yaml",
                                                                             libraries: libraries) else { return nil }
            return (index, "library", failure.issues)
        }
        let fileName = examples.first { $0.text == block }?.name ?? "format-block-\(index + 1).yaml"
        guard case .failure(let failure) = MicroAppChecker.check(block, fileName: fileName, libraries: libraries) else { return nil }
        return (index, fileName, failure.issues)
    }
}

/// `docs/micro-apps/FORMAT.md` is self-contained: it holds every example file word for word,
/// and every complete micro-app in it is a good file.
@Suite struct FormatDocumentTests {
    private func document() throws -> String {
        try String(contentsOf: documentURL, encoding: .utf8)
    }

    private func examples() throws -> [(name: String, text: String)] {
        let libraryNames = try FileManager.default.contentsOfDirectory(atPath: examplesURL.appendingPathComponent("libs").path)
            .filter { $0.hasSuffix(".yaml") }.map { "libs/" + $0 }
        let names = try (FileManager.default.contentsOfDirectory(atPath: examplesURL.path)
            .filter { $0.hasSuffix(".yaml") } + libraryNames).sorted()
        return try names.map { ($0, try String(contentsOf: examplesURL.appendingPathComponent($0), encoding: .utf8)) }
    }

    @Test func holdsEveryExampleWordForWord() throws {
        let examples = try examples()
        #expect(examples.map(\.name) == ["app-info.yaml", "ask-claude.yaml", "change-case.yaml", "copy-page-link.yaml", "count-text.yaml",
                                         "dns-lookup.yaml", "encode-decode.yaml", "finder-checksum.yaml", "format-json.yaml",
                                         "libs/translate.yaml", "new-tab-search.yaml", "search-web.yaml", "sort-selection.yaml",
                                         "translate-ukrainian.yaml", "translate.yaml", "wiki-summary.yaml"])
        let text = try document()
        let blocks = yamlBlocks(of: text)
        for example in examples {
            let copied = blocks.contains(example.text)
            #expect(copied, "FORMAT.md has no yaml block equal to \(example.name)")
            let named = text.contains("`\(example.name)`")
            #expect(named, "FORMAT.md does not name \(example.name)")
        }
    }

    @Test func everyCompleteMicroAppBlockPassesTheChecker() throws {
        let examples = try examples()
        let text = try document()
        #expect(yamlBlocks(of: text).filter(isCompleteMicroApp).count >= examples.count + 1)
        for refused in refusedBlocks(of: text, examples: examples) {
            Issue.record("block \(refused.index + 1) of FORMAT.md (\(refused.fileName)) is not a good file: \(refused.issues)")
        }
    }

    private static let good = "format: ting.microapp/2\ndescription: Say hi.\ninput: none\ncommand: echo hi\noutput:\n  to: [panel]\n"

    @Test func blockDetectionFindsChangesAndFragments() {
        let good = Self.good
        let markdown = "# T\n\n```yaml\n\(good)```\n\n```yaml\nparams:\n  - name: x\n```\n\n   ```yaml\nindented\n   ```\n"
        let blocks = yamlBlocks(of: markdown)
        #expect(blocks == [good, "params:\n  - name: x\n"])
        #expect(blocks.filter(isCompleteMicroApp) == [good])
        #expect(refusedBlocks(of: markdown).isEmpty)
        // A changed copy is no longer the example.
        #expect(!yamlBlocks(of: markdown.replacingOccurrences(of: "echo hi", with: "echo bye")).contains(good))
    }

    /// Broken complete blocks reach the checker whatever their first line is.
    @Test(arguments: [
        ("format first", Self.good),
        ("a leading comment", "# Sort the lines.\n" + Self.good),
        ("a leading blank line", "\n" + Self.good),
        ("another key first", "description: Say hi.\nformat: ting.microapp/2\ninput: none\ncommand: echo hi\noutput:\n  to: [panel]\n"),
        ("`---` and a comment", "---\n# comment\n" + Self.good),
        ("no format key", "description: Say hi.\ninput: none\ncommand: echo hi\noutput:\n  to: [panel]\n"),
        ("a quoted format key", Self.good.replacingOccurrences(of: "format:", with: "\"format\":")),
        ("a comment after the key", Self.good.replacingOccurrences(of: "input: none", with: "input: none # stdin")),
    ])
    func malformedBlocksReachTheChecker(form: String, block: String) {
        let broken = block.replacingOccurrences(of: "[panel]", with: "[clip]")
        let markdown = "Text.\n\n```yaml\n\(broken)```\n\n```yaml\nparams:\n  - name: x\n```\n"
        #expect(yamlBlocks(of: markdown).filter(isCompleteMicroApp) == [broken], "\(form): not detected")
        let refused = refusedBlocks(of: markdown)
        #expect(refused.count == 1, "\(form): not refused by the checker")
        #expect(refused.first?.issues.isEmpty == false, "\(form)")
    }

    @Test func hasNoLocalPaths() throws {
        let text = try document() + (try String(contentsOf: root.appendingPathComponent("docs/CONFIGURING.md"), encoding: .utf8))
        for path in ["/Users/", "/home/", "/var/folders/"] {
            #expect(!text.contains(path), "FORMAT.md contains \(path)")
        }
    }
}
