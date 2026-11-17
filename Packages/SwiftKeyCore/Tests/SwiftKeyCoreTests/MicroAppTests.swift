import Foundation
import Testing
@testable import SwiftKeyCore

private let examplesDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // SwiftKeyCoreTests
    .deletingLastPathComponent()  // Tests
    .deletingLastPathComponent()  // repository root
    .appendingPathComponent("docs/micro-apps/examples")

private func loadExample(_ name: String) throws -> String {
    try String(contentsOf: examplesDirectory.appendingPathComponent(name), encoding: .utf8)
}

/// The libraries of the examples, `docs/micro-apps/examples/libs/`.
private let exampleLibraries = MicroAppLibraries.read(folder: examplesDirectory.appendingPathComponent("libs"))

private func check(_ text: String, file: String = "sample.yaml") -> Result<MicroApp, MicroAppFailure> {
    MicroAppChecker.check(text, fileName: file, libraries: exampleLibraries)
}

private func app(_ text: String, file: String = "sample.yaml") throws -> MicroApp {
    try check(text, file: file).get()
}

private func issues(_ text: String, file: String = "sample.yaml") -> [MicroAppIssue] {
    if case .failure(let f) = check(text, file: file) { return f.issues }
    return []
}

/// True when some issue is on `line` and its message contains `fragment`.
private func has(_ found: [MicroAppIssue], line: Int, _ fragment: String) -> Bool {
    found.contains { $0.line == line && $0.message.contains(fragment) }
}

private let minimal = """
format: ting.microapp/2
description: Say hi.
input: none
command: echo hi
output:
  to: [panel]
"""

@Suite struct MicroAppExampleTests {
    static let names = ["app-info.yaml", "ask-claude.yaml", "change-case.yaml", "copy-page-link.yaml", "count-text.yaml",
                        "dns-lookup.yaml", "encode-decode.yaml", "finder-checksum.yaml", "format-json.yaml", "new-tab-search.yaml",
                        "search-web.yaml", "sort-selection.yaml", "translate-ukrainian.yaml", "translate.yaml", "wiki-summary.yaml"]

    @Test func examplesFolderHasExactlyTheFifteen() throws {
        #expect(exampleLibraries.sources.keys.sorted() == ["translate"])
        let files = try FileManager.default.contentsOfDirectory(atPath: examplesDirectory.path)
            .filter { $0.hasSuffix(".yaml") }.sorted()
        #expect(files == Self.names)
    }

    @Test(arguments: names) func examplePasses(_ name: String) throws {
        let result = check(try loadExample(name), file: name)
        if case .failure(let f) = result { Issue.record("\(f)") }
        let app = try result.get()
        #expect(app.id == String(name.dropLast(5)))
        #expect(!app.steps.isEmpty)
        // No example needs Perl any more.
        #expect(!(try loadExample(name)).contains("perl"))
    }

    @Test func dnsLookupModel() throws {
        let a = try app(try loadExample("dns-lookup.yaml"), file: "dns-lookup.yaml")
        #expect(a.shownName == "DNS lookup")
        #expect(a.tools == ["dig", "whois"])
        #expect(a.input == .none)
        #expect(a.output == MicroApp.Output(targets: [.panel], style: .console))
        #expect(a.params.map(\.name) == ["domain", "tool", "record"])
        #expect(a.params[0] == MicroApp.Param(name: "domain", kind: .text, required: true, prompt: "Domain"))
        #expect(a.remember)
        #expect(a.params[2].kind == .choice(["A", "AAAA", "MX", "TXT", "NS", "CNAME"]))
        #expect(a.params[2].defaultValue == "A")
        #expect(a.params[2].environmentName == "TING_RECORD")
        #expect(!a.hidden)
    }

    @Test func countTextDefaultsToMarkdown() throws {
        let a = try app(try loadExample("count-text.yaml"), file: "count-text.yaml")
        #expect(a.output.style == .markdown)
        #expect((a.command ?? "").contains(#"printf "| | |\n|---|---:|\n| Words | %d |"#))
        #expect((a.command ?? "").contains("$2, $3, $1"))
    }

    @Test func encodeDecodeKeepsPythonCode() throws {
        let a = try app(try loadExample("encode-decode.yaml"), file: "encode-decode.yaml")
        #expect(a.command == nil)
        #expect(a.requiredTools == ["python3"])
        guard case .python(let code) = a.steps.first?.action else { Issue.record("not a python step"); return }
        #expect(code.hasPrefix("import base64, os, sys, urllib.parse\n"))
        #expect(code.contains("    result = urllib.parse.unquote_plus(text)\n"))
    }

    @Test func wikiSummaryModel() throws {
        let a = try app(try loadExample("wiki-summary.yaml"), file: "wiki-summary.yaml")
        #expect(a.steps.map(\.kind) == [.url, .json, .json, .text])
        #expect(a.steps.map(\.id) == ["page", "extract", nil, nil])
        #expect(a.steps[2].stdin?.variables == [.step("page")])
        #expect(a.source == (try loadExample("wiki-summary.yaml")))
        #expect(a.approvalText == a.source)
        #expect(a.output == MicroApp.Output(targets: [.panel], style: .markdown))
    }
}

@Suite struct MicroAppModelTests {
    @Test func idComesFromFileName() throws {
        let a = try app(minimal, file: "/some/folder/say-hi.yaml")
        #expect(a.id == "say-hi")
        #expect(a.name == nil)
        #expect(a.shownName == "say-hi")
    }

    @Test func nameIsShownWhenPresent() throws {
        let a = try app("name: Say hi\n" + minimal, file: "say-hi.yaml")
        #expect(a.shownName == "Say hi")
    }

    @Test func defaults() throws {
        let a = try app(minimal)
        #expect(a.output == MicroApp.Output(targets: [.panel], style: .markdown))
        #expect(!a.hidden)
        #expect(a.remember)
        #expect(a.tools.isEmpty)
        #expect(a.params.isEmpty)
        #expect(a.command == "echo hi")
    }

    @Test func hiddenAndRemember() throws {
        let a = try app("""
        format: ting.microapp/2
        hidden: true
        remember: false
        description: Greet.
        params:
          - name: who
            type: text
            required: false
            default: world
        input: none
        command: echo "hi $TING_WHO"
        output:
          to: [clipboard, panel]
          as: text
        """)
        #expect(a.hidden)
        #expect(!a.remember)
        #expect(a.params == [MicroApp.Param(name: "who", kind: .text, required: false, defaultValue: "world")])
        #expect(a.params[0].shownPrompt == "who")
        #expect(a.output.targets == [.clipboard, .panel])
    }

    @Test func issueDescription() {
        let found = issues("format: ting.microapp/1\n" + minimal.dropFirst(24), file: "x.yaml")
        #expect(found.first?.description == "x.yaml:1: `format` must be `ting.microapp/2`, not `ting.microapp/1`")
    }
}

@Suite struct MicroAppLiteralBlockTests {
    @Test func keepsShellCodeExactly() throws {
        let a = try app(#"""
        format: ting.microapp/2
        description: Shell code with every awkward character.
        params:
          - name: mode
            type: choice
            required: true
            choices: [a, b]
        input: clipboard
        command: |
          case "$TING_MODE" in
            a) printf '%s\n' "it's" | sed -e 's/"/\\"/g' ;;
            b) awk '{ printf "%5.1f%%\n", $1 * 100 }' ;;
          esac

          echo "${TING_MODE}"   # a comment stays part of the code
        output:
          to: [panel]
        """#)
        #expect(a.command == #"""
        case "$TING_MODE" in
          a) printf '%s\n' "it's" | sed -e 's/"/\\"/g' ;;
          b) awk '{ printf "%5.1f%%\n", $1 * 100 }' ;;
        esac

        echo "${TING_MODE}"   # a comment stays part of the code

        """#)
    }

    @Test func chomping() throws {
        let clip = try YAMLSubset.parse("a: |\n  x\n  y\n\n\nb: 1\n")
        let strip = try YAMLSubset.parse("a: |-\n  x\n\nb: 1\n")
        let keep = try YAMLSubset.parse("a: |+\n  x\n\n\nb: 1\n")
        func value(_ node: YAMLNode) -> String? {
            guard case .mapping(let entries, _) = node, case .scalar(let s) = entries[0].value else { return nil }
            return s.value
        }
        #expect(value(clip) == "x\ny\n")
        #expect(value(strip) == "x")
        #expect(value(keep) == "x\n\n\n")
    }

    @Test func moreIndentedLinesKeepTheirExtraSpaces() throws {
        let node = try YAMLSubset.parse("c: |\n    one\n      two\n    three\n")
        guard case .mapping(let entries, _) = node, case .scalar(let s) = entries[0].value else {
            Issue.record("not a mapping"); return
        }
        #expect(s.value == "one\n  two\nthree\n")
        #expect(s.line == 1)
        #expect(s.contentLine == 2)
    }

    @Test func commandIssueLineInsideTheBlock() {
        let found = issues("""
        format: ting.microapp/2
        description: d
        input: none
        command: |
          echo one

          echo "$TING_NOPE"
        output:
          to: [panel]
        """)
        #expect(has(found, line: 7, "`$TING_NOPE` is not a declared param"))
    }
}

@Suite struct MicroAppYAMLSubsetTests {
    private func yamlError(_ text: String) -> YAMLError? {
        do { _ = try YAMLSubset.parse(text); return nil } catch let e as YAMLError { return e } catch { return nil }
    }

    @Test func parsesTheSubset() throws {
        let node = try YAMLSubset.parse("""
        ---
        # comment
        a: plain value # trailing comment
        b: 'it''s'
        c: "say \\"hi\\"\\n"
        d: [x, 'y z', "w"]
        e:
          - one
          - k: v
            m: n
        f:
        - same indent
        g: ~
        h: a#b
        """)
        guard case .mapping(let entries, let line) = node else { Issue.record("not a mapping"); return }
        #expect(line == 3)
        #expect(entries.map(\.key) == ["a", "b", "c", "d", "e", "f", "g", "h"])
        #expect(entries.map(\.keyLine) == [3, 4, 5, 6, 7, 11, 13, 14])
        #expect(entries[0].value == .scalar(YAMLScalar(value: "plain value", style: .plain, line: 3)))
        #expect(entries[1].value == .scalar(YAMLScalar(value: "it's", style: .singleQuoted, line: 4)))
        #expect(entries[2].value == .scalar(YAMLScalar(value: "say \"hi\"\n", style: .doubleQuoted, line: 5)))
        #expect(entries[3].value == .sequence([
            .scalar(YAMLScalar(value: "x", style: .plain, line: 6)),
            .scalar(YAMLScalar(value: "y z", style: .singleQuoted, line: 6)),
            .scalar(YAMLScalar(value: "w", style: .doubleQuoted, line: 6)),
        ], line: 6))
        guard case .sequence(let items, _) = entries[4].value, items.count == 2,
              case .mapping(let inner, let innerLine) = items[1] else {
            Issue.record("bad e"); return
        }
        #expect(innerLine == 9)
        #expect(inner.map(\.key) == ["k", "m"])
        #expect(inner.map(\.keyLine) == [9, 10])
        guard case .sequence(let same, _) = entries[5].value else { Issue.record("bad f"); return }
        #expect(same == [.scalar(YAMLScalar(value: "same indent", style: .plain, line: 12))])
        #expect(entries[6].value == .null(line: 13))
        #expect(entries[7].value == .scalar(YAMLScalar(value: "a#b", style: .plain, line: 14)))
    }

    @Test(arguments: [
        // (text, line, message fragment)
        ("a: 1\nb: &anchor x\n", 2, "anchors"),
        ("a: &x\n  b: 1\n", 1, "anchors"),
        ("a: 1\nb: *alias\n", 2, "aliases"),
        ("a: !!str 1\n", 1, "tags"),
        ("a: [x, !t y]\n", 1, "tags"),
        ("- !t x\n", 1, "tags"),
        ("%YAML 1.2\n---\na: 1\n", 1, "directives"),
        ("a: 1\n---\nb: 2\n", 2, "multi-document"),
        ("---\na: 1\n---\nb: 2\n", 3, "multi-document"),
        ("--- a: 1\n", 1, "multi-document"),
        ("a: 1\n...\n", 2, "document end"),
        ("a: 1\nb: >\n  folded\n", 2, "folded"),
        ("a: 1\nb: >-\n  folded\n", 2, "folded"),
        ("a: [x, [y]]\n", 1, "nested flow"),
        ("a: [x, {y: 1}]\n", 1, "nested flow"),
        ("a: [x, y\n", 1, "same line"),
        ("a: {b: 1}\n", 1, "flow mappings"),
        ("a: 1\n\tb: 2\n", 2, "tabs"),
        ("a: 1\n\"b\": 2\n", 2, "quoted keys"),
        ("? a\n: b\n", 1, "complex keys"),
        ("a: 1\na: 2\n", 2, "duplicate key `a`"),
        ("a: one\n  two\n", 2, "unexpected indentation"),
        ("a: 'one\n  two'\n", 1, "same line"),
        ("a: b: c\n", 1, "`: `"),
        ("a: |2\n   x\n", 1, "indentation indicators"),
        ("a: \"x\" y\n", 1, "unexpected text"),
        ("a: \"\\q\"\n", 1, "escape"),
        ("a: @x\n", 1, "quotes"),
        ("just text\n", 1, "expected `key: value`"),
        ("", 1, "empty"),
        ("# only a comment\n", 1, "empty"),
    ] as [(String, Int, String)])
    func refusesOutsideTheSubset(_ text: String, _ line: Int, _ fragment: String) {
        let error = yamlError(text)
        #expect(error?.line == line, "\(text.debugDescription): \(String(describing: error))")
        #expect(error?.message.contains(fragment) == true, "\(text.debugDescription): \(String(describing: error))")
    }

    @Test func checkerReportsSubsetErrorsWithFileAndLine() {
        let found = issues("format: ting.microapp/2\ndescription: &d x\n", file: "bad.yaml")
        #expect(found == [MicroAppIssue(file: "bad.yaml", line: 2, message: "anchors (`&`) are not supported")])
    }
}

@Suite struct MicroAppCheckerErrorTests {
    /// The prototype's file of typical generation mistakes, one issue per mistake.
    @Test func typicalGenerationMistakes() {
        let found = issues("""
        format: ting.microapp/2
        id: broken-example
        name: Broken on purpose
        description: Typical generation mistakes, for the checker.
        tools: [dig]

        params:
          - name: domain
            type: string
            required: false
          - name: Record Type
            type: choice

        input: stdin
        command: dig {domain} $TING_RECORD_TYPE $TING_DOMAN
        steps:
          - run: [dig]
        output:
          to: [panel, file]
          as: html
        """, file: "broken.yaml")
        #expect(has(found, line: 9, "`params[0].type` is `string`"))
        #expect(has(found, line: 10, "optional param needs a `default`"))
        #expect(has(found, line: 11, "name `Record Type` may only use"))
        #expect(has(found, line: 11, "`required` must be written out"))
        #expect(has(found, line: 11, "a choice needs `choices`"))
        #expect(has(found, line: 14, "`input` is `stdin`"))
        #expect(has(found, line: 15, "`{domain}` templates are not allowed"))
        #expect(has(found, line: 15, "`$TING_RECORD_TYPE` is not a declared param"))
        #expect(has(found, line: 15, "`$TING_DOMAN` is not a declared param"))
        #expect(has(found, line: 16, "either `command` or `steps`, not both"))
        #expect(has(found, line: 19, "`output.to` is `file`"))
        #expect(has(found, line: 20, "`output.as` is `html`"))
        #expect(found.allSatisfy { $0.file == "broken.yaml" })
        #expect(found.map(\.line) == found.map(\.line).sorted())
    }

    @Test(arguments: [
        // (text, line, message fragment)
        ("format: ting.microapp/1\ndescription: d\ninput: none\ncommand: x\noutput:\n  to: [panel]\n", 1, "`format` must be"),
        ("description: d\ninput: none\ncommand: x\noutput:\n  to: [panel]\n", 1, "missing required key `format`"),
        ("format: ting.microapp/2\ninput: none\ncommand: x\noutput:\n  to: [panel]\n", 1, "missing required key `description`"),
        ("format: ting.microapp/2\ndescription: d\ncommand: x\noutput:\n  to: [panel]\n", 1, "missing required key `input`"),
        ("format: ting.microapp/2\ndescription: d\ninput: none\noutput:\n  to: [panel]\n", 1, "missing required key `steps` (or `command`"),
        ("format: ting.microapp/2\nid: Say_Hi\ndescription: d\ninput: none\ncommand: x\noutput:\n  to: [panel]\n", 2, "kebab-case"),
        ("format: ting.microapp/2\nname:\ndescription: d\ninput: none\ncommand: x\noutput:\n  to: [panel]\n", 2, "`name` must be a text value"),
        ("format: ting.microapp/2\ndescription: |\n  two\n  lines\ninput: none\ncommand: x\noutput:\n  to: [panel]\n", 2, "`description` must be one line"),
        ("format: ting.microapp/2\ndescription: d\ntools: dig\ninput: none\ncommand: x\noutput:\n  to: [panel]\n", 3, "`tools` must be a list"),
        ("format: ting.microapp/2\ndescription: d\ntools: [\"rm -rf\"]\ninput: none\ncommand: x\noutput:\n  to: [panel]\n", 3, "not a command name"),
        ("format: ting.microapp/2\ndescription: d\nhidden: yes\ninput: none\ncommand: x\noutput:\n  to: [panel]\n", 3, "`hidden` must be `true` or `false`"),
        ("format: ting.microapp/2\ndescription: d\nhidden: \"true\"\ninput: none\ncommand: x\noutput:\n  to: [panel]\n", 3, "`hidden` must be `true` or `false`"),
        ("format: ting.microapp/2\ndescription: d\ninput: none\ncommand: \"  \"\noutput:\n  to: [panel]\n", 4, "non-empty"),
        ("format: ting.microapp/2\ndescription: d\ninput: none\ncommand: [a, b]\noutput:\n  to: [panel]\n", 4, "non-empty string"),
        ("format: ting.microapp/2\ndescription: d\ninput: none\ncommand: x\noutput: panel\n", 5, "`output` must be a map"),
        ("format: ting.microapp/2\ndescription: d\ninput: none\ncommand: x\noutput:\n  as: text\n", 5, "`output` needs `to`"),
        ("format: ting.microapp/2\ndescription: d\ninput: none\ncommand: x\noutput:\n  to: []\n", 6, "must not be empty"),
        ("format: ting.microapp/2\ndescription: d\ninput: none\ncommand: x\noutput:\n  to: [panel, panel]\n", 6, "listed twice"),
        ("format: ting.microapp/2\ndescription: d\ninput: none\ncommand: x\noutput:\n  to: [panel]\n  file: out.txt\n", 7, "unknown key `file` in output"),
        ("format: ting.microapp/2\ndescription: d\nparams:\n  - name: x\n    type: number\n    required: true\ninput: none\ncommand: echo $TING_X\noutput:\n  to: [panel]\n", 5, "`params[0].type` is `number`"),
        ("format: ting.microapp/2\ndescription: d\nparams:\n  - name: x\n    type: flag\n    required: true\ninput: none\ncommand: echo $TING_X\noutput:\n  to: [panel]\n", 5, "`params[0].type` is `flag`"),
        ("format: ting.microapp/2\ndescription: d\nparams:\n  - type: text\n    required: true\ninput: none\ncommand: x\noutput:\n  to: [panel]\n", 4, "missing required key `name`"),
        ("format: ting.microapp/2\ndescription: d\nparams:\n  - name: x\n    required: true\ninput: none\ncommand: echo $TING_X\noutput:\n  to: [panel]\n", 4, "missing required key `type`"),
        ("format: ting.microapp/2\ndescription: d\nparams:\n  - name: x\n    type: text\n    required: true\n  - name: x\n    type: text\n    required: true\ninput: none\ncommand: echo $TING_X\noutput:\n  to: [panel]\n", 7, "already declared on line 4"),
        ("format: ting.microapp/2\ndescription: d\nparams:\n  - name: x\n    type: text\n    required: true\n    secret: true\ninput: none\ncommand: echo $TING_X\noutput:\n  to: [panel]\n", 7, "unknown key `secret` in params[0]"),
        ("format: ting.microapp/2\ndescription: d\nparams:\n  - name: x\n    type: text\n    required: true\n    choices: [a]\ninput: none\ncommand: echo $TING_X\noutput:\n  to: [panel]\n", 7, "only for `type: choice`"),
        ("format: ting.microapp/2\ndescription: d\nparams:\n  - name: x\n    type: choice\n    required: false\n    default: c\n    choices: [a, b]\ninput: none\ncommand: echo $TING_X\noutput:\n  to: [panel]\n", 7, "default `c` is not one of the choices"),
        ("format: ting.microapp/2\ndescription: d\nparams:\n  - name: x\n    type: choice\n    required: true\n    choices: [a, a]\ninput: none\ncommand: echo $TING_X\noutput:\n  to: [panel]\n", 7, "choice `a` is listed twice"),
        ("format: ting.microapp/2\ndescription: d\nparams:\n  - name: x\n    type: choice\n    required: true\n    choices: []\ninput: none\ncommand: echo $TING_X\noutput:\n  to: [panel]\n", 7, "`choices` must not be empty"),
        ("format: ting.microapp/2\ndescription: d\nparams:\n  - name: x\n    type: text\n    required: true\n    remember: true\ninput: none\ncommand: echo $TING_X\noutput:\n  to: [panel]\n", 7, "unknown key `remember` in params[0]"),
        ("format: ting.microapp/2\ndescription: d\nremember: 1\ninput: none\ncommand: x\noutput:\n  to: [panel]\n", 3, "`remember` must be `true` or `false`"),
        ("format: ting.microapp/2\ndescription: d\nparams:\n  - name: x\n    type: text\n    required: true\n    default: y\ninput: none\ncommand: echo $TING_X\noutput:\n  to: [panel]\n", 7, "a required param cannot have a `default`"),
        ("format: ting.microapp/2\ndescription: d\nparams:\n  - name: x\n    type: choice\n    required: true\n    default: a\n    choices: [a, b]\ninput: none\ncommand: echo $TING_X\noutput:\n  to: [panel]\n", 7, "a required param cannot have a `default`"),
        ("format: ting.microapp/2\ndescription: d\nparams:\n  - name: x\n    type: text\n    required: true\ninput: none\ncommand: echo hi\noutput:\n  to: [panel]\n", 4, "param `x` is never used"),
        ("format: ting.microapp/2\ndescription: d\nparams: x\ninput: none\ncommand: echo hi\noutput:\n  to: [panel]\n", 3, "`params` must be a list"),
        ("format: ting.microapp/2\ndescription: d\nparams:\n  - x\ninput: none\ncommand: echo hi\noutput:\n  to: [panel]\n", 4, "`params[0]` must be a map"),
        ("- a\n- b\n", 1, "must be a map"),
    ] as [(String, Int, String)])
    func reportsTheRightLine(_ text: String, _ line: Int, _ fragment: String) {
        let found = issues(text)
        #expect(has(found, line: line, fragment), "\(text.debugDescription): \(found)")
    }

    @Test func fileNameRules() throws {
        #expect(has(issues(minimal, file: "Say Hi.yaml"), line: 1, "file name `Say Hi` must be kebab-case"))
        #expect(has(issues(minimal, file: "say-hi.yml"), line: 1, "must end in `.yaml`"))
        #expect(issues("id: say-hi\n" + minimal, file: "say-hi.yaml").isEmpty)
        // The `id` key does not have to equal the file name: the link survives a rename.
        #expect(issues("id: other\n" + minimal, file: "say-hi.yaml").isEmpty)
        #expect(try app("id: other\n" + minimal, file: "say-hi.yaml").id == "other")
        #expect(issues("id: say-hi\n" + minimal, file: "Say Hi.yaml").isEmpty)
    }

    @Test func templateOnlyForDeclaredParams() throws {
        // `{print}` is awk code, not a template: `print` is not a param.
        let a = try app("""
        format: ting.microapp/2
        description: d
        params:
          - name: col
            type: text
            required: true
        input: clipboard
        command: awk '{print $'"$TING_COL"'}'
        output:
          to: [panel]
        """)
        #expect(a.command == #"awk '{print $'"$TING_COL"'}'"#)
    }

    @Test func undeclaredVariableReportedOnce() {
        let found = issues("""
        format: ting.microapp/2
        description: d
        input: none
        command: |
          echo $TING_A
          echo ${TING_A}
        output:
          to: [panel]
        """)
        #expect(found.filter { $0.message.contains("TING_A") }.map(\.line) == [5])
    }
}
