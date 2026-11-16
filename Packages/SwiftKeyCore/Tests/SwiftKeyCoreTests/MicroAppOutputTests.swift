import Foundation
import Testing
@testable import SwiftKeyCore

@Suite struct ConsoleTextTests {
    @Test func colourCodesBecomeColouredRuns() {
        let runs = ConsoleText.parse("ok \u{1B}[31merror\u{1B}[0m and \u{1B}[1;92mbold green\u{1B}[39m bold\u{1B}[m.")
        #expect(runs == [
            ConsoleRun("ok "),
            ConsoleRun("error", ConsoleStyle(foreground: .basic(1))),
            ConsoleRun(" and "),
            ConsoleRun("bold green", ConsoleStyle(foreground: .basic(10), bold: true)),
            ConsoleRun(" bold", ConsoleStyle(bold: true)),
            ConsoleRun("."),
        ])
    }

    @Test func extendedColours() {
        let runs = ConsoleText.parse("\u{1B}[38;5;208ma\u{1B}[38;5;4mb\u{1B}[48;2;10;20;300mc\u{1B}[38:2:1:2:3md")
        #expect(runs.map(\.text) == ["a", "b", "c", "d"])
        #expect(runs[0].style.foreground == .palette(208))
        #expect(runs[1].style.foreground == .basic(4))
        #expect(runs[2].style.background == .rgb(10, 20, 255))
        #expect(runs[3].style.foreground == .rgb(1, 2, 3))
    }

    @Test func stylesAndResets() {
        let runs = ConsoleText.parse("\u{1B}[2;3;4;7;9mx\u{1B}[22;23;24;27;29my")
        #expect(runs == [
            ConsoleRun("x", ConsoleStyle(dim: true, italic: true, underline: true, inverse: true, strikethrough: true)),
            ConsoleRun("y"),
        ])
    }

    @Test(arguments: [
        ("\u{9D}0;title\u{9C}hello", "hello"),
        ("\u{9D}0;title\u{07}hello", "hello"),
        ("\u{9D}8;;https://x\u{1B}\\link\u{9D}8;;\u{9C}", "link"),
        ("\u{90}q payload\u{9C}a\u{98}sos\u{9C}b\u{9E}pm\u{9C}c\u{9F}apc\u{9C}d", "abcd"),
        ("\u{1B}]0;title\u{9C}x\u{1B}Pdcs\u{9C}y", "xy"),
        ("before\u{9D}never closed", "before"),
    ])
    func c1ControlStringsAreDroppedWithTheirPayload(text: String, plain: String) {
        #expect(ConsoleText.plain(text) == plain)
        #expect(MicroAppPanelContent(title: "t", text: text, style: .console, isError: false).plainText == plain)
        #expect(MicroAppPanelContent(title: "t", text: text, style: .markdown, isError: true).plainText == text)
    }

    @Test func c1ControlStringKeepsTheStyleAroundIt() {
        #expect(ConsoleText.parse("\u{1B}[31mred\u{9D}0;t\u{9C} still\u{9B}0mplain") == [
            ConsoleRun("red still", ConsoleStyle(foreground: .basic(1))),
            ConsoleRun("plain"),
        ])
    }

    @Test func unknownEscapeCodesAreDropped() {
        let text = "\u{1B}[2J\u{1B}[H\u{1B}]0;title\u{07}\u{1B}]8;;https://x\u{1B}\\link\u{1B}]8;;\u{1B}\\ "
            + "\u{1B}(B\u{1B}7\u{1B}[?25lprogress\r50%\u{08}\n\tend\u{1B}[K\u{1B}"
        #expect(ConsoleText.plain(text) == "link progress50%\n\tend")
        #expect(ConsoleText.parse(text).allSatisfy { $0.style == .plain })
    }

    @Test func plainTextKeepsEverythingElse() {
        #expect(ConsoleText.plain("Привет, мир 👋\nline 2") == "Привет, мир 👋\nline 2")
        #expect(ConsoleText.parse("") == [])
    }

    @Test func panelPlainTextDropsCodesOnlyForConsole() {
        let raw = "\u{1B}[32mgreen\u{1B}[0m"
        #expect(MicroAppPanelContent(title: "t", text: raw, style: .console, isError: false).plainText == "green")
        #expect(MicroAppPanelContent(title: "t", text: "**b**", style: .markdown, isError: false).plainText == "**b**")
    }

    @Test func consoleClipboardTargetGetsPlainText() {
        let app = MicroApp(id: "c", name: "C", description: "C.", input: .none, command: "x",
                           output: .init(targets: [.clipboard, .panel], style: .console))
        let output = MicroAppRunOutput(stdout: "\u{1B}[31mred\u{1B}[0m")
        let plan = MicroAppResultPlan.make(app: app, result: .success(output))
        #expect(plan.clipboard == "red")
        guard case .panel(let content) = plan.show else { Issue.record("no panel"); return }
        #expect(content.text == "\u{1B}[31mred\u{1B}[0m")
        #expect(content.plainText == "red")
    }

    @Test func markdownErrorIsConsoleText() {
        let app = MicroApp(id: "m", name: "M", description: "M.", input: .none, command: "x",
                           output: .init(targets: [.panel]))
        #expect(app.output.style == .markdown)
        let plan = MicroAppResultPlan.make(app: app, result: .failure(exitCode: 1, MicroAppRunOutput(stderr: "\u{1B}[31m**bad**\u{1B}[0m")))
        guard case .panel(let content) = plan.show else { Issue.record("no panel"); return }
        #expect(content.style == .console)
        #expect(content.isError)
        #expect(content.plainText == "**bad**")
    }
}

@Suite struct MarkdownTextTests {
    private func plain(_ text: String) -> [MarkdownSpan] { [MarkdownSpan(text)] }

    @Test func mixedDocumentBecomesTheRightBlocks() {
        let text = """
        # Report

        Some **bold**, *italic* and `code`.

        - one
        - two
          - nested
        1. first
        2. second

        ```json
        {"a": 1}
        ```

        | Name | Count |
        |:-----|------:|
        | Words | 12 |
        | Lines | 3 |
        """
        let blocks = MarkdownText.parse(text)
        #expect(blocks == [
            .heading(level: 1, spans: plain("Report")),
            .paragraph([MarkdownSpan("Some "), MarkdownSpan("bold", bold: true), MarkdownSpan(", "),
                        MarkdownSpan("italic", italic: true), MarkdownSpan(" and "), MarkdownSpan("code", code: true),
                        MarkdownSpan(".")]),
            .list([
                MarkdownListItem(depth: 0, marker: .bullet, spans: plain("one")),
                MarkdownListItem(depth: 0, marker: .bullet, spans: plain("two")),
                MarkdownListItem(depth: 1, marker: .bullet, spans: plain("nested")),
                MarkdownListItem(depth: 0, marker: .number(1), spans: plain("first")),
                MarkdownListItem(depth: 0, marker: .number(2), spans: plain("second")),
            ]),
            .code(language: "json", text: #"{"a": 1}"#),
            .table(MarkdownTable(alignments: [.left, .right],
                                 header: [plain("Name"), plain("Count")],
                                 rows: [[plain("Words"), plain("12")], [plain("Lines"), plain("3")]])),
        ])
    }

    @Test func countExampleTable() throws {
        let text = "| | |\n|---|---:|\n| Words | 2 |\n| Characters | 11 |\n| Lines | 1 |"
        let blocks = MarkdownText.parse(text)
        #expect(blocks.count == 1)
        guard case .table(let table) = try #require(blocks.first) else { Issue.record("not a table"); return }
        #expect(table.alignments == [.left, .right])
        #expect(!table.hasHeader)
        #expect(table.rows.count == 3)
        #expect(table.rows[1] == [plain("Characters"), plain("11")])
    }

    @Test func tableRowsArePaddedAndCut() throws {
        let blocks = MarkdownText.parse("a | b | c\n--- | :-: | ---\n1\n1 | 2 | 3 | 4\n| x \\| y | `z` |")
        guard case .table(let table) = try #require(blocks.first) else { Issue.record("not a table"); return }
        #expect(table.alignments == [.left, .center, .left])
        #expect(table.hasHeader)
        // A row without a pipe ends the table.
        #expect(table.rows.isEmpty)
        #expect(blocks.count == 2)
        guard case .paragraph(let spans) = blocks[1] else { Issue.record("not a paragraph"); return }
        #expect(spans.first?.text.hasPrefix("1\n") == true)
    }

    @Test func tableCellsAndShape() throws {
        let blocks = MarkdownText.parse("a | b\n--|--\n1 | 2 | 3\n| x \\| y | `z` |\nonly |")
        guard case .table(let table) = try #require(blocks.first) else { Issue.record("not a table"); return }
        #expect(table.rows == [
            [plain("1"), plain("2")],
            [plain("x | y"), [MarkdownSpan("z", code: true)]],
            [plain("only"), []],
        ])
    }

    @Test func headings() {
        #expect(MarkdownText.parse("## Two ##\n###### six\n####### seven\n#nospace") == [
            .heading(level: 2, spans: plain("Two")),
            .heading(level: 6, spans: plain("six")),
            .paragraph(plain("####### seven\n#nospace")),
        ])
        #expect(MarkdownText.parse("Title\n=====\nSub\n---") == [
            .heading(level: 1, spans: plain("Title")),
            .heading(level: 2, spans: plain("Sub")),
        ])
    }

    @Test func paragraphsKeepLineBreaksAndRulesQuotes() {
        #expect(MarkdownText.parse("line one\nline two\n\n***\n> quoted\n> more") == [
            .paragraph(plain("line one\nline two")),
            .rule,
            .quote(plain("quoted\nmore")),
        ])
    }

    @Test func unclosedFenceRunsToTheEnd() {
        #expect(MarkdownText.parse("~~~\n  *not bold*\n\n# no heading") == [
            .code(language: "", text: "  *not bold*\n\n# no heading"),
        ])
    }

    @Test(arguments: [
        ("**bold *italic***", [MarkdownSpan("bold ", bold: true), MarkdownSpan("italic", bold: true, italic: true)]),
        ("*italic **bold***", [MarkdownSpan("italic ", italic: true), MarkdownSpan("bold", bold: true, italic: true)]),
        ("***both** italic*", [MarkdownSpan("both", bold: true, italic: true), MarkdownSpan(" italic", italic: true)]),
        ("***both* bold**", [MarkdownSpan("both", bold: true, italic: true), MarkdownSpan(" bold", bold: true)]),
        ("__bold _italic___", [MarkdownSpan("bold ", bold: true), MarkdownSpan("italic", bold: true, italic: true)]),
        ("*a **b** c*", [MarkdownSpan("a ", italic: true), MarkdownSpan("b", bold: true, italic: true),
                         MarkdownSpan(" c", italic: true)]),
        ("***a**", [MarkdownSpan("*"), MarkdownSpan("a", bold: true)]),
        ("**a***", [MarkdownSpan("a", bold: true), MarkdownSpan("*")]),
        ("x **bold *italic*** y", [MarkdownSpan("x "), MarkdownSpan("bold ", bold: true),
                                   MarkdownSpan("italic", bold: true, italic: true), MarkdownSpan(" y")]),
    ])
    func nestedEmphasisClosingTogether(text: String, spans: [MarkdownSpan]) {
        #expect(MarkdownText.inline(text) == spans)
    }

    @Test func nestedEmphasisInBlocks() {
        #expect(MarkdownText.parse("# **Total *now***\n\n- **a *b***") == [
            .heading(level: 1, spans: [MarkdownSpan("Total ", bold: true), MarkdownSpan("now", bold: true, italic: true)]),
            .list([MarkdownListItem(marker: .bullet, spans: [MarkdownSpan("a ", bold: true),
                                                              MarkdownSpan("b", bold: true, italic: true)])]),
        ])
    }

    @Test func inlineStyles() {
        #expect(MarkdownText.inline("***both*** __b__ _i_ snake_case_name 2 * 3 * 4 \\*lit\\* `` a`b ``") == [
            MarkdownSpan("both", bold: true, italic: true),
            MarkdownSpan(" "),
            MarkdownSpan("b", bold: true),
            MarkdownSpan(" "),
            MarkdownSpan("i", italic: true),
            MarkdownSpan(" snake_case_name 2 * 3 * 4 *lit* "),
            MarkdownSpan("a`b", code: true),
        ])
        #expect(MarkdownText.inline("**bold *and italic* inside**") == [
            MarkdownSpan("bold ", bold: true),
            MarkdownSpan("and italic", bold: true, italic: true),
            MarkdownSpan(" inside", bold: true),
        ])
        #expect(MarkdownText.inline("**open and `code **` end") == [
            MarkdownSpan("**open and "),
            MarkdownSpan("code **", code: true),
            MarkdownSpan(" end"),
        ])
    }
}
