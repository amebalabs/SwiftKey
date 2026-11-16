import Foundation
import Testing
@testable import SwiftKeyCore

private let examples = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("docs/micro-apps/examples")

private func lib(_ name: String, _ text: String) -> MicroAppLibrarySource {
    MicroAppLibrarySource(name: name, file: MicroAppLibraries.file(for: name), text: text)
}

private let shout = lib("shout", """
format: ting.microlib/1
description: Shout the input.
params:
  - name: mark
    type: choice
    required: false
    default: "!"
    choices: ["!", "?", "#"]
  - name: who
    type: text
    required: true
input: clipboard
steps:
  - command: tr a-z A-Z
    id: upper
  - text: ${input}${params.mark} ${params.who}
    id: finish
output:
  to: [panel]
  as: code

""")

private func check(_ text: String, _ libraries: [MicroAppLibrarySource] = [shout], file: String = "app.yaml") -> Result<MicroApp, MicroAppFailure> {
    MicroAppChecker.check(text, fileName: file, libraries: MicroAppLibraries(libraries))
}

private func issues(_ text: String, _ libraries: [MicroAppLibrarySource] = [shout]) -> [MicroAppIssue] {
    if case .failure(let f) = check(text, libraries) { return f.issues }
    return []
}

private func has(_ found: [MicroAppIssue], line: Int, _ fragment: String) -> Bool {
    found.contains { $0.line == line && $0.message.contains(fragment) }
}

private let head = "format: ting.microapp/2\ndescription: d\ninput: clipboard\n"

@Suite struct MicroAppCallTests {
    @Test func callGivesTheLibraryAndItsParams() throws {
        let app = try check(head + "steps:\n  - call: shout\n    params:\n      who: me\n      mark: \"?\"\noutput:\n  to: [panel]\n").get()
        guard case .call(let library) = app.steps[0].action else { Issue.record("not a call"); return }
        #expect(library.name == "shout")
        #expect(library.steps.map(\.id) == ["upper", "finish"])
        #expect(app.steps[0].params.map(\.name) == ["who", "mark"])
        #expect(app.libraries.map(\.file) == ["libs/shout.yaml"])
        #expect(app.approvalText.contains("# ---- libs/shout.yaml ----\nformat: ting.microlib/1"))
        #expect(app.allSteps.map(\.kind) == [.call, .command, .text])
    }

    @Test(arguments: [
        ("  - call: shout\n", 5, "library `shout` needs `params:` with `who`"),
        ("  - call: shout\n    params:\n      who: me\n      loud: yes\n", 8, "library `shout` has no param `loud`; its params: mark, who"),
        ("  - call: shout\n    params:\n      who: me\n      mark: x\n", 8, "`mark` of library `shout` must be one of: !, ?, #"),
        ("  - call: whisper\n", 5, "no library `whisper`: add the file `libs/whisper.yaml`"),
        ("  - call: Shout\n", 5, "is not a library name"),
        ("  - call: shout\n    params:\n      who: ${params.nope}\n", 7, "`${params.nope}` is not a declared param"),
    ] as [(String, Int, String)])
    func callProblems(_ steps: String, _ line: Int, _ fragment: String) {
        let found = issues(head + "steps:\n" + steps)
        #expect(has(found, line: line, fragment), "\(found)")
    }

    @Test func brokenLibraryCycleAndDepth() {
        let broken = lib("broken", "format: ting.microlib/1\ndescription: d\nsteps:\n  - text: ${params.x}\n")
        #expect(has(issues(head + "steps:\n  - call: broken\n", [broken]), line: 5,
                    "library `broken` has problems: libs/broken.yaml:4: steps[0].text: `${params.x}` is not a declared param"))
        let a = lib("a", "format: ting.microlib/1\ndescription: d\nsteps:\n  - call: b\n")
        let b = lib("b", "format: ting.microlib/1\ndescription: d\nsteps:\n  - call: a\n")
        let found = issues(head + "steps:\n  - call: a\n", [a, b])
        #expect(found.contains { $0.message.contains("library `a` uses itself: a → b → a") }, "\(found)")
        let chain = (0...MicroAppLibraries.maxDepth).map { i in
            lib("l\(i)", "format: ting.microlib/1\ndescription: d\nsteps:\n  - " + (i == MicroAppLibraries.maxDepth ? "text: end" : "call: l\(i + 1)") + "\n")
        }
        #expect(issues(head + "steps:\n  - call: l0\n", chain).contains { $0.message.contains("nested deeper than") })
    }

    @Test func libraryFileRules() {
        func libraryIssues(_ text: String) -> [MicroAppIssue] {
            if case .failure(let f) = MicroAppChecker.checkLibrary(text, fileName: "libs/x.yaml") { return f.issues }
            return []
        }
        #expect(has(libraryIssues("format: ting.microapp/2\ndescription: d\nsteps:\n  - text: a\n"), line: 1, "`format` must be `ting.microlib/1`"))
        #expect(has(libraryIssues("format: ting.microlib/1\nname: X\ndescription: d\nsteps:\n  - text: a\n"), line: 2, "unknown key `name` in a library"))
        #expect(has(libraryIssues("format: ting.microlib/1\ndescription: d\ninherit: y\nsteps:\n  - text: a\n"), line: 3, "unknown key `inherit`"))
        #expect(libraryIssues("format: ting.microlib/1\ndescription: d\nsteps:\n  - text: a\n").isEmpty)
        #expect(libraryIssues("format: ting.microlib/1\ndescription: d\nsteps:\n  - text: a\n").first?.file == nil)
        if case .failure(let f) = MicroAppChecker.checkLibrary("format: ting.microlib/1\n", fileName: "libs/x.yaml") {
            #expect(f.issues.allSatisfy { $0.file == "libs/x.yaml" })
        }
    }

    @Test func toolsOfCalledLibrariesAreNeeded() throws {
        let py = lib("py", "format: ting.microlib/1\ndescription: d\ntools: [jq]\nsteps:\n  - python: print(1)\n")
        let app = try check(head + "steps:\n  - call: py\n", [py]).get()
        #expect(app.requiredTools == ["jq", "python3"])
    }
}

@Suite struct MicroAppInheritTests {
    @Test func inheritsAndChangesAStepAndAParam() throws {
        let app = try check("""
        format: ting.microapp/2
        inherit: shout
        name: Loud
        params:
          - name: mark
            default: "#"
        steps:
          - id: finish
            text: <${input}${params.mark} ${params.who}>
        output:
          to: [clipboard]

        """).get()
        #expect(app.shownName == "Loud")
        #expect(app.description == "Shout the input.")
        #expect(app.input == .clipboard)
        #expect(app.params.map(\.name) == ["mark", "who"])
        #expect(app.params[0].defaultValue == "#")
        #expect(app.steps.map(\.id) == ["upper", "finish"])
        guard case .text(let text) = app.steps[1].action else { Issue.record("kind"); return }
        #expect(text.source == "<${input}${params.mark} ${params.who}>")
        #expect(app.output == MicroApp.Output(targets: [.clipboard], style: .code), "maps such as output merge key by key")
        #expect(app.libraries.map(\.name) == ["shout"])
        #expect(app.approvalText.hasPrefix("format: ting.microapp/2\ninherit: shout"))
    }

    @Test func stepParamsFixAParamSoItIsNotAsked() throws {
        let app = try check("format: ting.microapp/2\ninherit: shout\nsteps:\n  - id: finish\n    params:\n      who: me\n").get()
        #expect(app.params.map(\.name) == ["mark"], "`who` has a value now")
        #expect(app.steps[1].params == [MicroAppStep.Field(name: "who", value: MicroAppTemplate(literal: "me"))])
    }

    @Test func inheritProblems() {
        let base = "format: ting.microapp/2\ninherit: shout\n"
        #expect(has(issues(base + "steps:\n  - id: nope\n    text: x\n"), line: 4, "`shout` has no step with `id: nope`"))
        #expect(has(issues(base + "steps:\n  - id: finish\n    command: x\n"), line: 5, "is a `text` step in `shout`; a change cannot make it `command`"))
        #expect(has(issues(base + "steps:\n  - text: x\n"), line: 4, "needs the `id` of a step of `shout`"))
        #expect(has(issues("format: ting.microapp/2\ninherit: nothing\n"), line: 2, "no library `nothing`"))
        // A problem in the merged library lines is shown on the `inherit` line, with the library line.
        #expect(has(issues(base + "steps:\n  - id: finish\n    text: ${params.nope}\n"), line: 5, "`${params.nope}` is not a declared param"))
        let found = issues(base + "params:\n  - name: mark\n    default: x\n")
        #expect(has(found, line: 5, "params[0]: default `x` is not one of the choices"), "\(found)")
    }

    @Test func approvalHashFollowsTheLibrary() throws {
        let file = "format: ting.microapp/2\ninherit: shout\nsteps:\n  - id: finish\n    params:\n      who: me\n"
        let first = MicroAppCatalog.load([("app.yaml", file)], libraries: MicroAppLibraries([shout]))
        var changed = shout
        changed.text += "# a comment\n"
        let second = MicroAppCatalog.load([("app.yaml", file)], libraries: MicroAppLibraries([changed]))
        let a = try #require(first.entries.first?.contentHash)
        let b = try #require(second.entries.first?.contentHash)
        #expect(!a.isEmpty && a != b)
        #expect(a != MicroAppApprovals.hash(Data(file.utf8)))
        // A broken library is in the log too.
        let broken = MicroAppCatalog.load([], libraries: MicroAppLibraries([lib("bad", "format: x\n")]))
        #expect(broken.logText.hasPrefix("libs/bad.yaml:1: "))
    }
}

@Suite struct MicroAppStepParamsTests {
    @Test func stepParamsAreTheStepsOwnParams() throws {
        let app = try check(head + """
        params:
          - name: lang
            type: text
            required: true
        steps:
          - text: ${params.greeting} ${params.lang}
            params:
              greeting: Hi ${params.lang}
          - command: printf '%s' "$TING_GREETING"
            params:
              greeting: Hey
          - python: print(__import__("os").environ["TING_GREETING"])
            params:
              greeting: Yo

        """ + "output:\n  to: [panel]\n").get()
        #expect(app.steps.map { $0.params.map(\.name) } == [["greeting"], ["greeting"], ["greeting"]])
        #expect(issues(head + "steps:\n  - text: a\n    params:\n      Bad: x\n").contains { $0.message.contains("`Bad` may only use") })
        // A step param of one step is not known in another.
        #expect(has(issues(head + "steps:\n  - text: a\n    params:\n      x: 1\n  - text: ${params.x}\n"), line: 8,
                    "`${params.x}` is not a declared param"))
    }

    @Test func examplesWithTheLibrary() throws {
        let library = try String(contentsOf: examples.appendingPathComponent("libs/translate.yaml"), encoding: .utf8)
        let libraries = MicroAppLibraries([MicroAppLibrarySource(name: "translate", file: "libs/translate.yaml", text: library)])
        let ukrainian = try String(contentsOf: examples.appendingPathComponent("translate-ukrainian.yaml"), encoding: .utf8)
        let app = try MicroAppChecker.check(ukrainian, fileName: "translate-ukrainian.yaml", libraries: libraries).get()
        #expect(app.params.isEmpty, "the language is fixed, so nothing is asked")
        #expect(app.timeLimit == 120)
        #expect(app.output == MicroApp.Output(targets: [.clipboard, .panel], style: .text))
        guard case .ai(let ai) = app.steps.first?.action else { Issue.record("not ai"); return }
        let request = try MicroAppHTTPRequest.build(ai) { variable in
            switch variable {
            case .param("language"): return app.steps[0].params.first?.value.literalText ?? "?"
            case .input: return "Hello"
            default: return "key"
            }
        }
        #expect(String(decoding: request.body ?? Data(), as: UTF8.self).contains("into Ukrainian."))
        let translate = try String(contentsOf: examples.appendingPathComponent("translate.yaml"), encoding: .utf8)
        let chooser = try MicroAppChecker.check(translate, fileName: "translate.yaml", libraries: libraries).get()
        #expect(chooser.steps.map(\.kind) == [.call])
        #expect(chooser.params.map(\.name) == ["language"])
    }
}
