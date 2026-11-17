import Foundation
import Testing
@testable import SwiftKeyCore

private func check(_ text: String, libraries: [MicroAppLibrarySource] = []) -> Result<MicroApp, MicroAppFailure> {
    MicroAppChecker.check(text, fileName: "sample.yaml", libraries: MicroAppLibraries(libraries))
}

private func issues(_ text: String, libraries: [MicroAppLibrarySource] = []) -> [MicroAppIssue] {
    if case .failure(let f) = check(text, libraries: libraries) { return f.issues }
    return []
}

private func has(_ found: [MicroAppIssue], line: Int, _ fragment: String) -> Bool {
    found.contains { $0.line == line && $0.message.contains(fragment) }
}

/// A file with `context` and the step lines (already indented). Line 3 is `context`, steps start on line 6.
private func file(context: String = "[app]", steps: String, output: String = "output:\n  to: [panel]\n", params: String = "") -> String {
    "format: ting.microapp/2\ndescription: d\ncontext: \(context)\n" + (params.isEmpty ? "" : "params:\n" + params) +
        "input: none\nsteps:\n" + steps + output
}

private func field(_ source: MicroAppContextSource, _ name: String) -> MicroAppContextField {
    MicroAppContextField(source: source, name: name)!
}

@Suite struct MicroAppContextTemplateTests {
    @Test func parsesContextVariables() throws {
        let t = try MicroAppTemplate.parse("${context.app.name|url} in ${context.finder.selection}").get()
        #expect(t.variables == [.context(field(.app, "name")), .context(field(.finder, "selection"))])
        let text = t.render { v in
            if case .context(let f) = v { return f == field(.app, "name") ? "Visual Studio" : "/a" }
            return ""
        }
        #expect(text == "Visual%20Studio in /a")
        #expect(MicroAppVariable.context(field(.browser, "url")).description == "context.browser.url")
    }

    @Test(arguments: [
        ("${context.app}", "write `${context.SOURCE.FIELD}`"),
        ("${context.clipboard.text}", "the sources are app, finder, browser, selection, window"),
        ("${context.app.title}", "`app` has the fields name, bundle, path, pid"),
        ("${context.app.name.x}", "write `${context.SOURCE.FIELD}`"),
    ])
    func refusesBadContextVariables(text: String, fragment: String) {
        guard case .failure(let error) = MicroAppTemplate.parse(text) else { Issue.record("\(text) parsed"); return }
        #expect(error.message.contains(fragment), "\(error.message)")
    }

    @Test func fieldsAndEnvironmentNames() {
        #expect(MicroAppContextField.all.map(\.description) == ["app.name", "app.bundle", "app.path", "app.pid", "finder.selection",
                                                                "finder.folder", "browser.url", "browser.title", "browser.name",
                                                                "selection.text", "window.title", "window.document"])
        #expect(field(.finder, "selection").environmentName == "TING_CONTEXT_FINDER_SELECTION")
        #expect(MicroAppContextField(environmentName: "TING_CONTEXT_WINDOW_DOCUMENT") == field(.window, "document"))
        #expect(MicroAppContextField(environmentName: "TING_CONTEXT_APP") == nil)
        #expect(MicroAppContextField(source: .app, name: "url") == nil)
        var context = MicroAppContext()
        context.set(.app, "name", "Finder")
        context.set(.app, "nope", "x")
        #expect(context.values.count == 1)
        // Every field of a listed source is set, an unread one empty; other sources are left out.
        #expect(context.environment(for: [.app]) == ["TING_CONTEXT_APP_NAME": "Finder", "TING_CONTEXT_APP_BUNDLE": "",
                                                     "TING_CONTEXT_APP_PATH": "", "TING_CONTEXT_APP_PID": ""])
        #expect(context.environment(for: []).isEmpty)
        #expect(MicroAppContextSource.allCases.sorted() == [.app, .finder, .browser, .selection, .window])
        #expect([MicroAppContextSource.window, .app].sorted() == [.app, .window])
    }
}

@Suite struct MicroAppContextCheckTests {
    @Test func contextIsReadByTemplatesShellAndPython() throws {
        let text = file(context: "[window, app, finder]", steps: """
              - text: ${context.app.name}
              - command: echo "$TING_CONTEXT_WINDOW_TITLE" "${TING_CONTEXT_WINDOW_DOCUMENT}"
              - python: |
                  import os
                  print(os.environ["TING_CONTEXT_FINDER_FOLDER"])

            """)
        let app = try check(text).get()
        #expect(app.context == [.window, .app, .finder])
        #expect(app.requiredContext == [.app, .finder, .window])
        #expect(!app.sendsInput)
    }

    @Test func everyReadSourceIsListedAndEveryListedSourceIsRead() {
        let notListed = issues(file(context: "[app]", steps: "  - text: ${context.finder.folder}\n  - command: echo $TING_CONTEXT_BROWSER_URL $TING_CONTEXT_APP_NAME\n"))
        #expect(has(notListed, line: 6, "`${context.finder.folder}` needs `finder` in the `context` list"))
        #expect(has(notListed, line: 7, "`$TING_CONTEXT_BROWSER_URL` needs `browser` in the `context` list"))
        let unused = issues(file(context: "[app, selection]", steps: "  - text: ${context.app.pid}\n"))
        #expect(has(unused, line: 3, "context `selection` is never used"))
        #expect(unused.count == 1)
        let unknown = issues(file(context: "[app, app, clipboard]", steps: "  - text: ${context.app.pid}\n"))
        #expect(has(unknown, line: 3, "`app` is listed twice"))
        #expect(has(unknown, line: 3, "`clipboard`; it must be one of: app, finder, browser, selection, window"))
        let notAList = issues(file(context: "app", steps: "  - text: ${context.app.pid}\n"))
        #expect(has(notAList, line: 3, "`context` must be a list"))
    }

    @Test func shellCodeReadsContextOnlyAsVariables() {
        let found = issues(file(steps: "  - command: echo ${context.app.name} $TING_CONTEXT_APP_NAMES\n"))
        #expect(has(found, line: 6, "`${context.…}` is not replaced in shell code"))
        #expect(has(found, line: 6, "`$TING_CONTEXT_APP_NAMES` is not a context value"))
    }

    @Test func paramNamesThatStartWithContextBelongToTing() {
        let found = issues(file(steps: "  - text: ${context.app.name} ${params.context_app_name}\n    params:\n      context_x: y\n",
                                params: "  - name: context_app_name\n    type: text\n    required: true\n"))
        #expect(has(found, line: 5, "names that start with `context` belong to SwiftKey"))
        #expect(has(found, line: 12, "names that start with `context` belong to SwiftKey"))
    }

    @Test func librariesBringTheirContext() throws {
        let library = MicroAppLibrarySource(name: "front", file: "libs/front.yaml", text: """
            format: ting.microlib/1
            description: The active app.
            context: [app]
            input: none
            steps:
              - text: ${context.app.name}
                id: name

            """)
        // A call needs no `context` of its own; the run reads what the library lists.
        let caller = try check("format: ting.microapp/2\ndescription: d\ninput: none\nsteps:\n  - call: front\n", libraries: [library]).get()
        #expect(caller.context == [])
        #expect(caller.requiredContext == [.app])
        // The same source listed in the file counts as used by the call.
        let listed = try check("format: ting.microapp/2\ndescription: d\ncontext: [app]\ninput: none\nsteps:\n  - call: front\n",
                               libraries: [library]).get()
        #expect(listed.requiredContext == [.app])
        // `inherit` takes the library's `context`; a file that replaces it must still cover every read.
        let child = try check("format: ting.microapp/2\ninherit: front\n", libraries: [library]).get()
        #expect(child.context == [.app])
        let replaced = issues("format: ting.microapp/2\ninherit: front\ncontext: [finder]\n", libraries: [library])
        #expect(replaced.contains { $0.message.contains("needs `app` in the `context` list") })
        #expect(replaced.contains { $0.message.contains("context `finder` is never used") })
    }
}

@Suite struct MicroAppSendTests {
    @Test func keysAndPasteSteps() throws {
        let app = try check(file(steps: """
              - keys: cmd+a
              - keys: [Shift+Tab, return, ctrl+option+cmd+f, f5, left]
              - paste: ${context.app.name} - ${input}
            """, output: "")).get()
        guard case .keys(let one) = app.steps[0].action, case .keys(let many) = app.steps[1].action,
              case .paste(let text) = app.steps[2].action else { Issue.record("kinds"); return }
        #expect(one == [Hotkey(string: "cmd+a")!])
        #expect(many.map(\.string) == ["shift+tab", "return", "ctrl+option+cmd+f", "f5", "left"])
        #expect(text.source == "${context.app.name} - ${input}")
        #expect(app.steps.map(\.kind) == [.keys, .keys, .paste])
        #expect(app.sendsInput)
        #expect(MicroAppKeyboardAction.keys(many).summary == "keys shift+tab, return, ctrl+option+cmd+f, f5, left")
        #expect(MicroAppKeyboardAction.paste("é", keepOnClipboard: false).summary == "paste 1 character")
    }

    @Test(arguments: [
        ("  - keys: cmd+\n", "`cmd+` is not a key press"),
        ("  - keys: cmd\n", "`cmd` is not a key press"),
        ("  - keys: right-option\n", "`right-option` is not a key press"),
        ("  - keys: fn+a\n", "`fn+a` is not a key press"),
        ("  - keys: [a, cmd+b+c]\n", "`cmd+b+c` is not a key press"),
        ("  - keys: []\n", "must not be empty"),
        ("  - keys:\n      to: x\n", "must be a key press such as `cmd+s`"),
        ("  - paste: \"\"\n", "must not be empty"),
        ("  - keys: a\n    app: Safari\n", "unknown key `app`"),
    ])
    func refusesBadSends(steps: String, fragment: String) {
        let found = issues(file(context: "[app]", steps: "  - text: ${context.app.name}\n" + steps, output: ""))
        #expect(found.contains { $0.message.contains(fragment) }, "\(found)")
    }

    @Test func tooManyKeyPresses() {
        let list = Array(repeating: "a", count: MicroAppChecker.maxKeyPresses + 1).joined(separator: ", ")
        let found = issues(file(context: "[app]", steps: "  - text: ${context.app.name}\n  - keys: [\(list)]\n", output: ""))
        #expect(found.contains { $0.message.contains("more than 100 key presses") })
    }

    @Test func appOutput() throws {
        let both = issues(file(steps: "  - text: ${context.app.name}\n", output: "output:\n  to: [panel, app]\n"))
        #expect(has(both, line: 8, "`app` and `panel` cannot be together"))
        let app = try check(file(steps: "  - text: ${context.app.name}\n", output: "output:\n  to: [app]\n  as: console\n")).get()
        #expect(app.sendsInput)
        let plain = MicroAppResultPlan.make(app: app, result: .success(MicroAppRunOutput(stdout: "\u{1B}[31mred\u{1B}[0m")))
        #expect(plain == MicroAppResultPlan(app: "red", show: .nothing))
        let cut = MicroAppResultPlan.make(app: app, result: .success(MicroAppRunOutput(stdout: "x", stdoutCut: true)))
        #expect(cut == MicroAppResultPlan(app: "x", show: .toast("output cut at 1 MB")))
        let empty = MicroAppResultPlan.make(app: app, result: .success(MicroAppRunOutput(stdout: "")))
        #expect(empty == MicroAppResultPlan(show: .toast("No output")))
        let failed = MicroAppResultPlan.make(app: app, result: .failure(exitCode: 1, MicroAppRunOutput(stderr: "bad")))
        #expect(failed.app == nil)

        var copied = app
        copied.output.targets = [.clipboard, .app]
        #expect(MicroAppResultPlan.make(app: copied, result: .success(MicroAppRunOutput(stdout: "x")))
            == MicroAppResultPlan(clipboard: "x", app: "x", show: .toast("Copied")))
    }
}

@Suite struct MicroAppContextScriptTests {
    @Test func finderOutput() {
        #expect(MicroAppContextScripts.parseFinder("/Users/a/Desktop/\n/Users/a/Desktop/x.txt\n/Users/a/Desktop/Folder/\n") ==
            ("/Users/a/Desktop", ["/Users/a/Desktop/x.txt", "/Users/a/Desktop/Folder"]))
        #expect(MicroAppContextScripts.parseFinder("/\n") == ("/", []))
        #expect(MicroAppContextScripts.parseFinder("") == ("", []))
    }

    @Test func browserOutput() {
        #expect(MicroAppContextScripts.parseBrowser("https://example.com/\nExample: one\ntwo\n") == ("https://example.com/", "Example: one\ntwo"))
        #expect(MicroAppContextScripts.parseBrowser("https://example.com/\n\n") == ("https://example.com/", ""))
        #expect(MicroAppContextScripts.parseBrowser("") == ("", ""))
    }

    @Test func browserChoice() {
        let chrome = "com.google.Chrome", safari = "com.apple.Safari", arc = "company.thebrowser.Browser"
        #expect(MicroAppContextScripts.chooseBrowser(active: chrome, lastUsed: safari, running: [safari, chrome]) == chrome)
        #expect(MicroAppContextScripts.chooseBrowser(active: "com.apple.Terminal", lastUsed: arc, running: [safari, arc]) == arc)
        #expect(MicroAppContextScripts.chooseBrowser(active: "com.apple.Terminal", lastUsed: arc, running: [chrome, safari]) == safari)
        #expect(MicroAppContextScripts.chooseBrowser(active: nil, lastUsed: nil, running: ["org.mozilla.firefox"]) == nil)
        #expect(MicroAppContextScripts.dialect(of: arc) == .chromium)
        #expect(MicroAppContextScripts.browser(bundleID: safari, dialect: .safari).contains("front document"))
        #expect(MicroAppContextScripts.browser(bundleID: arc, dialect: .chromium).contains("tell application id \"\(arc)\""))
    }

    @Test func failures() {
        #expect(MicroAppContextScripts.failure(stderr: "execution error: Not authorized to send Apple events to Finder. (-1743)") == .notAllowed)
        #expect(MicroAppContextScripts.failure(stderr: "execution error: Finder got an error: AppleEvent timed out. (-1712)") == .timedOut)
        #expect(MicroAppContextScripts.failure(stderr: "execution error: Can’t get window 1. (-1719)") == .gone)
        #expect(MicroAppContextScripts.failure(stderr: " odd \n") == .other("odd"))
        #expect(MicroAppContextScripts.message(.gone, appName: "Finder", reading: "x") == nil)
        #expect(MicroAppContextScripts.message(.notAllowed, appName: "Safari", reading: "the browser tab")?
            .contains("Automation › SwiftKey › Safari") == true)
    }
}
