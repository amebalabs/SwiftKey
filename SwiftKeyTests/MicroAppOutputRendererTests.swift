@testable import SwiftKeyRuntime
import AppKit
import XCTest
import SwiftKeyCore
@testable import SwiftKey

/// The result panel drawing: the example micro-apps run for real and their output is drawn.
final class MicroAppOutputRendererTests: XCTestCase {
    private var examples: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Packages/SwiftKeyCore/docs/micro-apps/examples")
    }

    private func example(_ name: String) throws -> MicroApp {
        let text = try String(contentsOf: examples.appendingPathComponent(name), encoding: .utf8)
        switch MicroAppChecker.check(text, fileName: name) {
        case .success(let app): return app
        case .failure(let failure): throw NSError(domain: "example", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(failure)"])
        }
    }

    private func runner() -> MicroAppRunner {
        var runner = MicroAppRunner()
        runner.path = { "/usr/bin:/bin:/usr/sbin:/sbin" }
        runner.workingDirectory = FileManager.default.temporaryDirectory.path
        return runner
    }

    private func panel(_ app: MicroApp, stdin: String?) async throws -> MicroAppPanelContent {
        let result = await runner().run(app, stdin: stdin)
        guard case .panel(let content) = MicroAppResultPlan.make(app: app, result: result).show else {
            throw NSError(domain: "example", code: 2, userInfo: [NSLocalizedDescriptionKey: "no panel: \(result)"])
        }
        return content
    }

    /// A dynamic Theme colour in the dark appearance, as sRGB components.
    private func resolved(_ color: NSColor) -> [CGFloat] {
        var components: [CGFloat] = []
        NSAppearance(named: .darkAqua)!.performAsCurrentDrawingAppearance {
            let rgb = color.usingColorSpace(.sRGB)!
            components = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent, rgb.alphaComponent]
        }
        return components
    }

    /// The tab stops of the paragraph that holds `text`.
    private func tabStops(of text: String, in rendered: NSAttributedString) throws -> [NSTextTab] {
        let range = (rendered.string as NSString).range(of: text)
        XCTAssertNotEqual(range.location, NSNotFound, "\(text) is not shown")
        let style = try XCTUnwrap(rendered.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle)
        return style.tabStops
    }

    func testCountExampleShowsItsTableAsAlignedColumns() async throws {
        let app = try example("count-text.yaml")
        // The file has no `output.as`: it is shown as markdown.
        XCTAssertEqual(app.output.style, .markdown)
        let content = try await panel(app, stdin: "two words\nПривет\n")
        XCTAssertFalse(content.isError, content.text)
        let rendered = MicroAppOutputRenderer.render(content)
        XCTAssertFalse(rendered.string.contains("|"), rendered.string)
        XCTAssertFalse(rendered.string.contains("---"), rendered.string)
        let lines = rendered.string.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines, ["\tWords\t3", "\tCharacters\t17", "\tLines\t2"])
        for label in ["Words", "Characters", "Lines"] {
            let tabs = try tabStops(of: label, in: rendered)
            XCTAssertEqual(tabs.map(\.alignment), [.left, .right])
        }
        // Every row has the same stops, so the numbers end at one right edge past the longest label.
        let tabs = try tabStops(of: "Words", in: rendered)
        XCTAssertEqual(try tabStops(of: "Characters", in: rendered), tabs)
        let labelWidth = MicroAppOutputRenderer.spansString([MarkdownSpan("Characters")]).size().width
        XCTAssertGreaterThan(tabs[1].location, tabs[0].location + labelWidth)
        // Enter copies the result as it is.
        XCTAssertEqual(content.plainText, content.text)
    }

    func testConsoleOutputShowsColoursWithoutEscapeCodes() async throws {
        let app = MicroApp(id: "colours", description: "Colours", input: .none,
                           command: #"printf '\033[31mred\033[0m plain \033[1;32mgreen\033[0m\033[2K\n'"#,
                           output: .init(targets: [.panel], style: .console))
        let content = try await panel(app, stdin: nil)
        XCTAssertTrue(content.text.contains("\u{1B}["))
        let rendered = MicroAppOutputRenderer.render(content)
        XCTAssertEqual(rendered.string, "red plain green")
        XCTAssertFalse(rendered.string.unicodeScalars.contains { $0.value == 0x1B })
        let red = try XCTUnwrap(rendered.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
        let plain = try XCTUnwrap(rendered.attribute(.foregroundColor, at: 4, effectiveRange: nil) as? NSColor)
        XCTAssertEqual(resolved(red), resolved(NSColor.console(.basic(1))))
        XCTAssertEqual(resolved(plain), resolved(MicroAppOutputRenderer.ink))
        XCTAssertNotEqual(resolved(red), resolved(plain))
        let font = try XCTUnwrap(rendered.attribute(.font, at: 10, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.monoSpace))
        XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.bold))
        // Enter and ⌘C copy the plain text.
        XCTAssertEqual(content.plainText, "red plain green")
    }

    func testMarkdownErrorIsShownAsConsoleText() async throws {
        let app = MicroApp(id: "fails", description: "Fails", input: .none,
                           command: "printf '# not a heading\\n\\033[31m**bad**\\033[0m' >&2; exit 3",
                           output: .init(targets: [.panel]))
        XCTAssertEqual(app.output.style, .markdown)
        let content = try await panel(app, stdin: nil)
        XCTAssertTrue(content.isError)
        let rendered = MicroAppOutputRenderer.render(content)
        XCTAssertEqual(rendered.string, "# not a heading\n**bad**")
        let font = try XCTUnwrap(rendered.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.monoSpace))
        XCTAssertEqual(content.plainText, "# not a heading\n**bad**")
    }

    func testMarkdownBlocksAreFormatted() throws {
        let rendered = MicroAppOutputRenderer.render("# Title\n\nSome **bold** and `code`.\n\n- item", style: .markdown)
        XCTAssertEqual(rendered.string, "Title\nSome bold and code.\n\t•\titem")
        let title = try XCTUnwrap(rendered.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertGreaterThan(title.pointSize, MicroAppOutputRenderer.bodySize)
        let bold = try XCTUnwrap(rendered.attribute(.font, at: 11, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(bold.fontDescriptor.symbolicTraits.contains(.bold))
        let code = try XCTUnwrap(rendered.attribute(.font, at: 20, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(code.fontDescriptor.symbolicTraits.contains(.monoSpace))
    }

    func testC1ControlStringsAreNotShownOrCopied() async throws {
        let app = MicroApp(id: "title", description: "Title", input: .none,
                           command: #"printf '\302\2350;title\302\234hello \033[32mgreen\033[0m\302\2208;;x\302\234\n'"#,
                           output: .init(targets: [.panel], style: .console))
        let content = try await panel(app, stdin: nil)
        XCTAssertTrue(content.text.unicodeScalars.contains { $0.value == 0x9D }, content.text)
        let rendered = MicroAppOutputRenderer.render(content)
        XCTAssertEqual(rendered.string, "hello green")
        XCTAssertEqual(content.plainText, "hello green")
    }

    func testNestedEmphasisIsDrawn() throws {
        let rendered = MicroAppOutputRenderer.render("**bold *italic***", style: .markdown)
        XCTAssertEqual(rendered.string, "bold italic")
        let bold = try XCTUnwrap(rendered.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(bold.fontDescriptor.symbolicTraits.contains(.bold))
        XCTAssertFalse(bold.fontDescriptor.symbolicTraits.contains(.italic))
        let both = try XCTUnwrap(rendered.attribute(.font, at: 6, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(both.fontDescriptor.symbolicTraits.contains(.bold))
        XCTAssertTrue(both.fontDescriptor.symbolicTraits.contains(.italic))
    }

    func testTextAndCodeStyles() throws {
        let text = MicroAppOutputRenderer.render("**x** \u{1B}[1m", style: .text)
        XCTAssertEqual(text.string, "**x** \u{1B}[1m")
        let textFont = try XCTUnwrap(text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertFalse(textFont.fontDescriptor.symbolicTraits.contains(.monoSpace))
        let code = MicroAppOutputRenderer.render("# x", style: .code)
        XCTAssertEqual(code.string, "# x")
        let codeFont = try XCTUnwrap(code.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(codeFont.fontDescriptor.symbolicTraits.contains(.monoSpace))
    }
}
