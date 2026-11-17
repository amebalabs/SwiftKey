import Foundation
import Testing
@testable import SwiftKeyCore

private func check(_ text: String, file: String = "sample.yaml") -> Result<MicroApp, MicroAppFailure> {
    MicroAppChecker.check(text, fileName: file)
}

private func issues(_ text: String) -> [MicroAppIssue] {
    if case .failure(let f) = check(text) { return f.issues }
    return []
}

private func has(_ found: [MicroAppIssue], line: Int, _ fragment: String) -> Bool {
    found.contains { $0.line == line && $0.message.contains(fragment) }
}

/// A file with `params` (already indented) and `steps` (the list items, already indented).
private func file(params: String = "", steps: String, output: String = "output:\n  to: [panel]\n", top: String = "") -> String {
    "format: ting.microapp/2\ndescription: d\n" + top + (params.isEmpty ? "" : "params:\n" + params) + "input: clipboard\nsteps:\n" + steps + output
}

private func template(_ text: String) throws -> MicroAppTemplate {
    try MicroAppTemplate.parse(text).get()
}

@Suite struct MicroAppTemplateTests {
    @Test func parsesVariablesFiltersAndText() throws {
        let t = try template("q=${input|trim|url}&k=${OPENAI_API_KEY} ${params.mode}${steps.page} ${keychain.api.example-1} $HOME $${x}")
        #expect(t.variables == [.input, .env("OPENAI_API_KEY"), .param("mode"), .step("page"), .keychain("api.example-1")])
        let text = t.render { v in
            switch v {
            case .input: "  a b/ä  "
            case .env: "KEY"
            case .param: "upper"
            case .step: "P"
            case .keychain: "S"
            case .context: "C"
            }
        }
        #expect(text == "q=a%20b%2F%C3%A4&k=KEY upperP S $HOME ${x}")
        #expect(try template("plain $text").isLiteral)
        #expect(try template("a $${b} c").literalText == "a ${b} c")
        #expect(MicroAppTemplate(literal: "a ${b}").source == "a $${b}")
    }

    @Test func filters() {
        #expect(MicroAppFilter.json.apply("a\"b\\c\nd\u{1}") == #"a\"b\\c\nd\u0001"#)
        #expect(MicroAppFilter.base64.apply("user:pass") == "dXNlcjpwYXNz")
        #expect(MicroAppFilter.trim.apply("\n x \n") == "x")
        #expect(MicroAppFilter.url.apply("a-b_c.d~e f+g") == "a-b_c.d~e%20f%2Bg")
    }

    @Test(arguments: [
        ("${input", "without a closing"),
        ("${in put}", "is not a variable"),
        ("${input|upper}", "unknown filter `upper`"),
        ("${params.Mode}", "a param name uses only"),
        ("${steps.}", "a step id uses only"),
        ("${keychain.a b}", "keychain service name"),
        ("${1X}", "is not a variable"),
        ("a\n${input\n}", "without a closing"),
    ])
    func refusesBadVariables(_ text: String, _ fragment: String) {
        guard case .failure(let error) = MicroAppTemplate.parse(text) else { Issue.record("accepted \(text)"); return }
        #expect(error.message.contains(fragment), "\(error.message)")
    }

    @Test func errorLineOffset() {
        guard case .failure(let error) = MicroAppTemplate.parse("one\ntwo ${x|nope}") else { Issue.record("accepted"); return }
        #expect(error.lineOffset == 1)
    }
}

@Suite struct MicroAppStepsCheckerTests {
    @Test func allStepKinds() throws {
        let text = file(params: "  - name: mode\n    type: text\n    required: true\n", steps: """
          - command: tr a-z A-Z
            id: upper
            env:
              API_KEY: ${keychain.example}
          - python: |
              import os, sys
              sys.stdout.write(os.environ["TING_MODE"] + os.environ["TING_STEP_UPPER"])
            stream: false
            timeout: 5
          - command: cat
            stream: true
          - url: https://example.com/api/${params.mode|url}
            method: PUT
            query:
              q: ${input}
            headers:
              Authorization: Bearer ${API_TOKEN}
            body:
              text: ${steps.upper}
              count: 2
              ok: true
              none: null
              quoted: "3"
              list:
                - a
                - 1
          - url: https://example.com/form
            form:
              a: ${input}
          - ai: ${input}
            provider: anthropic
            model: claude-haiku-5-5
            system: Be short.
            max_tokens: 100
            temperature: 0.5
          - json: content.0.text
          - text: "Result: ${input}"
          - open: https://example.com/?q=${input|url}
            app: Safari
          - notify: Done
            title: ${params.mode}

        """, top: "timeout: 120\n")
        guard case .success(let app) = check(text) else { Issue.record("\(check(text))"); return }
        #expect(app.timeLimit == 120)
        #expect(app.steps.map(\.kind) == [.command, .python, .command, .url, .url, .ai, .json, .text, .open, .notify])
        #expect(app.steps[0].env == [MicroAppStep.Field(name: "API_KEY", value: try template("${keychain.example}"))])
        #expect(app.steps[1].timeLimit == 5)
        #expect(app.steps[2].stream)
        #expect(app.requiredTools == ["python3"])
        guard case .url(let put) = app.steps[3].action, case .url(let form) = app.steps[4].action,
              case .ai(let ai) = app.steps[5].action else { Issue.record("kinds"); return }
        #expect(put.method == "PUT")
        #expect(form.method == "POST")
        #expect(ai.provider == .anthropic)
        let request = try MicroAppHTTPRequest.build(put) { v in
            switch v {
            case .input: "x&y"
            case .param: "a b"
            case .step: "S\"1"
            case .env: "T"
            case .keychain: ""
            case .context: ""
            }
        }
        #expect(request.url == "https://example.com/api/a%20b?q=x%26y")
        #expect(request.header("authorization") == "Bearer T")
        #expect(request.header("Content-Type") == "application/json")
        #expect(String(decoding: request.body ?? Data(), as: UTF8.self)
            == #"{"text":"S\"1","count":2,"ok":true,"none":null,"quoted":"3","list":["a",1]}"#)
        let formRequest = try MicroAppHTTPRequest.build(form) { _ in "a=1 ü" }
        #expect(String(decoding: formRequest.body ?? Data(), as: UTF8.self) == "a=a%3D1%20%C3%BC")
        #expect(formRequest.header("Content-Type") == "application/x-www-form-urlencoded")
    }

    @Test func outputIsOptional() throws {
        let app = try check(file(steps: "  - open: https://example.com\n", output: "")).get()
        #expect(app.output.targets.isEmpty)
        let plan = MicroAppResultPlan.make(app: app, result: .success(MicroAppRunOutput(stdout: "x")))
        #expect(plan == MicroAppResultPlan(show: .nothing))
    }

    @Test func stepFailurePlan() throws {
        let app = try check(file(steps: "  - text: a\n  - url: https://example.com\n")).get()
        let failure = MicroAppStepFailure(index: 1, count: 2, kind: .url, note: "HTTP 404",
                                          output: MicroAppRunOutput(stdout: "not here", stderr: "GET https://example.com answered HTTP 404"))
        let plan = MicroAppResultPlan.make(app: app, result: .stepFailed(failure))
        guard case .panel(let content) = plan.show else { Issue.record("\(plan)"); return }
        #expect(content.isError)
        #expect(content.notes == ["step 2 of 2 · url", "HTTP 404"])
        #expect(content.text == "GET https://example.com answered HTTP 404\n\nnot here")
        #expect(plan.clipboard == nil)
    }

    @Test(arguments: [
        // (steps, line, message fragment); the steps start on line 5.
        ("  - run: x\n", 5, "a step needs one of: command, python, url, ai, text, json, open, notify"),
        ("  - command: x\n    python: y\n", 6, "a step has one kind"),
        ("  - command: x\n    method: GET\n", 6, "unknown key `method` in steps[0] (command)"),
        ("  - text: ${params.nope}\n", 5, "`${params.nope}` is not a declared param"),
        ("  - text: ${steps.later}\n  - text: x\n    id: later\n", 5, "is not an earlier step"),
        ("  - text: a\n    id: Bad\n", 6, "step id `Bad` may only use"),
        ("  - text: a\n    id: x\n  - text: b\n    id: x\n", 8, "step id `x` is already used on line 6"),
        ("  - command: cat\n    stream: true\n", 6, "the first step has no step before it"),
        ("  - text: a\n  - url: https://x.org\n    stream: true\n", 7, "only a command or python step can have `stream: true`"),
        ("  - command: echo a\n    id: a\n  - command: echo \"$TING_STEP_A\"\n    stream: true\n", 7, "still runs when this `stream: true` step starts"),
        ("  - text: a\n  - command: cat\n    stream: true\n    stdin: x\n", 7, "it cannot have `stdin`"),
        ("  - command: echo ${params.x}\n", 5, "is not replaced in shell code"),
        ("  - command: echo ${input}\n", 5, "the input of the step is its stdin"),
        ("  - command: echo $TING_STEP_NOPE\n", 5, "`$TING_STEP_NOPE` is not the output of an earlier step"),
        ("  - python: print(os.environ['TING_NOPE'])\n", 5, "`TING_NOPE` is not a declared param"),
        ("  - json: a..b\n", 5, "write keys and list indexes joined by `.`"),
        ("  - ai: ${input}\n    model: m\n", 5, "an ai step needs `provider`"),
        ("  - ai: ${input}\n    provider: openai\n", 5, "an ai step needs `model`"),
        ("  - ai: ${input}\n    provider: gemini\n    model: m\n", 6, "`steps[0].provider` is `gemini`"),
        ("  - ai: x\n    provider: openai\n    model: m\n    max_tokens: 0\n", 8, "must be a whole number above 0"),
        ("  - ai: x\n    provider: openai\n    model: m\n    temperature: warm\n", 8, "must be a number"),
        ("  - ai: x\n    provider: openai\n    model: m\n    base_url: localhost\n", 8, "is not an http or https URL"),
        ("  - url: ftp://example.com\n", 5, "is not an http or https URL"),
        ("  - url: https://x.org\n    method: GET\n    body: x\n", 6, "a GET request cannot have a `body` or `form`"),
        ("  - url: https://x.org\n    body: x\n    form:\n      a: b\n", 7, "either `body` or `form`, not both"),
        ("  - url: https://x.org\n    method: get\n", 6, "`steps[0].method` is `get`"),
        ("  - command: x\n    env:\n      TING_X: y\n", 7, "names that start with `TING_` belong to SwiftKey"),
        ("  - command: x\n    env:\n      my-var: y\n", 7, "is not a variable name"),
        ("  - command: x\n    timeout: 61\n", 6, "from 1 to 60"),
        ("  - text: ${input\n", 5, "without a closing `}`"),
        ("  - text: |\n      line one\n      ${nope|x}\n", 7, "unknown filter `x`"),
        ("  - x\n", 5, "must be a map such as `- command: …`"),
    ] as [(String, Int, String)])
    func reportsTheRightLine(_ steps: String, _ line: Int, _ fragment: String) {
        let found = issues(file(steps: steps))
        #expect(has(found, line: line, fragment), "\(steps.debugDescription): \(found)")
    }

    @Test func topLevelRules() {
        #expect(has(issues(file(steps: "  - text: a\n", top: "timeout: 301\n")), line: 3, "from 1 to 300"))
        #expect(has(issues(file(steps: "")), line: 4, "`steps` must be a list"))
        #expect(has(issues("format: ting.microapp/2\ndescription: d\ninput: none\nsteps: []\n"), line: 4, "`steps` must not be empty"))
        #expect(has(issues("format: ting.microapp/2\ndescription: d\ninput: none\ncommand: x\nsteps:\n  - text: a\n"), line: 5,
                    "either `command` or `steps`"))
    }

    @Test func paramsMustBeUsedSomewhere() {
        let params = "  - name: a\n    type: text\n    required: true\n  - name: b\n    type: text\n    required: true\n  - name: c\n    type: text\n    required: true\n"
        let found = issues(file(params: params, steps: "  - text: ${params.a}\n  - python: print(TING_B)\n"))
        #expect(found.map(\.message) == ["param `c` is never used: a step must read `${params.c}` or `$TING_C`"])
        #expect(found.first?.line == 10)
        // A word that only contains TING_B is not a use.
        #expect(issues(file(params: params, steps: "  - text: ${params.a}\n  - python: print(XTING_B, TING_C)\n"))
            .contains { $0.message.contains("param `b` is never used") })
    }
}

@Suite struct MicroAppJSONPathTests {
    private let doc = Data(#"{"choices":[{"message":{"content":"Hi"}}],"n":2.5,"ok":false,"z":null,"o":{"b":1,"a":"x/y"}}"#.utf8)

    @Test func picks() throws {
        #expect(try MicroAppJSONPath("choices.0.message.content")?.pick(from: doc) == "Hi")
        #expect(try MicroAppJSONPath("n")?.pick(from: doc) == "2.5")
        #expect(try MicroAppJSONPath("ok")?.pick(from: doc) == "false")
        #expect(try MicroAppJSONPath("z")?.pick(from: doc) == "")
        #expect(try MicroAppJSONPath("o")?.pick(from: doc) == "{\n  \"a\" : \"x/y\",\n  \"b\" : 1\n}")
        #expect(try MicroAppJSONPath(".")?.pick(from: Data("\"just text\"".utf8)) == "just text")
    }

    @Test func failures() {
        #expect(throws: MicroAppJSONPath.PickError.missing("choices.1")) { try MicroAppJSONPath("choices.1.x")?.pick(from: doc) }
        #expect(throws: MicroAppJSONPath.PickError.missing("o.c")) { try MicroAppJSONPath("o.c")?.pick(from: doc) }
        #expect(MicroAppJSONPath("a.") == nil)
        #expect(MicroAppJSONPath("") == nil)
        do {
            _ = try MicroAppJSONPath(".")?.pick(from: Data("{oops".utf8))
            Issue.record("no error")
        } catch {
            #expect("\(error)".hasPrefix("the input is not JSON"))
        }
    }
}

@Suite struct MicroAppAIRequestTests {
    private func ai(_ provider: MicroAppStep.AIStep.Provider, key: String? = nil, base: String? = nil, system: String? = "Be brief.",
                    maxTokens: String? = nil) throws -> MicroAppStep.AIStep {
        MicroAppStep.AIStep(prompt: try template("${input}"), provider: provider, model: try template("m-1"),
                            key: try key.map(template), system: try system.map(template), baseURL: try base.map(template),
                            temperature: nil, maxTokens: try maxTokens.map(template))
    }

    private func resolve(_ v: MicroAppVariable) throws -> String {
        switch v {
        case .input: return "Say \"hi\""
        case .env("OPENAI_API_KEY"): return "sk-env"
        case .env(let name): throw MicroAppHTTPRequest.BuildError.missingKey(name)
        default: return "?"
        }
    }

    @Test func openAI() throws {
        let r = try MicroAppHTTPRequest.build(try ai(.openai, maxTokens: "50"), resolve: resolve)
        #expect(r.url == "https://api.openai.com/v1/chat/completions")
        #expect(r.header("Authorization") == "Bearer sk-env")
        #expect(String(decoding: r.body!, as: UTF8.self) == #"{"model":"m-1","messages":[{"role":"system","content":"Be brief."},{"role":"user","content":"Say \"hi\""}],"max_completion_tokens":50,"stream":true}"#)
    }

    @Test func compatibleServerHasNoDefaultKey() throws {
        let r = try MicroAppHTTPRequest.build(try ai(.openai, base: "http://localhost:11434/v1/", system: nil, maxTokens: "9"), resolve: resolve)
        #expect(r.url == "http://localhost:11434/v1/chat/completions")
        #expect(r.header("Authorization") == nil)
        #expect(String(decoding: r.body!, as: UTF8.self).contains(#""max_tokens":9"#))
    }

    @Test func anthropic() throws {
        let r = try MicroAppHTTPRequest.build(try ai(.anthropic, key: "sk-ant"), resolve: resolve)
        #expect(r.url == "https://api.anthropic.com/v1/messages")
        #expect(r.header("x-api-key") == "sk-ant")
        #expect(r.header("anthropic-version") == "2023-06-01")
        #expect(String(decoding: r.body!, as: UTF8.self) == #"{"model":"m-1","system":"Be brief.","messages":[{"role":"user","content":"Say \"hi\""}],"max_tokens":8192,"stream":true}"#)
    }

    @Test func missingDefaultKey() throws {
        #expect(throws: MicroAppHTTPRequest.BuildError.missingKey("ANTHROPIC_API_KEY")) {
            try MicroAppHTTPRequest.build(try ai(.anthropic), resolve: resolve)
        }
    }

    @Test func queryJoinsAnExistingQuery() {
        #expect(MicroAppHTTPRequest.url("https://x.org/a?b=1#f", adding: [("c d", "é")]) == "https://x.org/a?b=1&c%20d=%C3%A9#f")
        #expect(MicroAppHTTPRequest.url("https://x.org/a", adding: []) == "https://x.org/a")
    }
}

@Suite struct MicroAppStreamTests {
    @Test func sseSplitsEventsAcrossChunks() {
        var parser = MicroAppSSEParser()
        var events = parser.feed(Data("event: a\ndata: {\"x\"".utf8))
        #expect(events.isEmpty)
        events = parser.feed(Data(":1}\r\n\r\n: comment\ndata: one\ndata: two\n\ndata: last".utf8))
        #expect(events == [.init(name: "a", data: "{\"x\":1}"), .init(data: "one\ntwo")])
        #expect(parser.finish() == [.init(data: "last")])
    }

    private func decode(_ provider: MicroAppStep.AIStep.Provider, _ body: String) throws -> String {
        var decoder = MicroAppAIStreamDecoder(provider: provider)
        var text = ""
        // Odd chunk sizes, so events are split anywhere.
        let bytes = Array(body.utf8)
        var i = 0
        while i < bytes.count {
            let end = min(bytes.count, i + 7)
            text += try decoder.feed(Data(bytes[i..<end]))
            i = end
        }
        return text + (try decoder.finish())
    }

    @Test func openAIStream() throws {
        let body = """
        data: {"choices":[{"delta":{"role":"assistant"}}]}

        data: {"choices":[{"delta":{"content":"При"}}]}

        data: {"choices":[{"delta":{"content":"вет"},"finish_reason":null}]}

        data: {"choices":[{"delta":{},"finish_reason":"stop"}]}

        data: [DONE]


        """
        #expect(try decode(.openai, body) == "Привет")
        #expect(throws: MicroAppAIStreamDecoder.Failure.cut) {
            try decode(.openai, "data: {\"choices\":[{\"delta\":{\"content\":\"a\"},\"finish_reason\":\"length\"}]}\n\n")
        }
        #expect(throws: MicroAppAIStreamDecoder.Failure.incomplete) {
            try decode(.openai, "data: {\"choices\":[{\"delta\":{\"content\":\"a\"}}]}\n\n")
        }
    }

    @Test func anthropicStream() throws {
        let body = """
        event: message_start
        data: {"type":"message_start","message":{}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}

        event: ping
        data: {"type": "ping"}

        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":", world"}}

        event: message_delta
        data: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}

        event: message_stop
        data: {"type":"message_stop"}


        """
        #expect(try decode(.anthropic, body) == "Hello, world")
        #expect(throws: MicroAppAIStreamDecoder.Failure.api("overloaded_error: Overloaded")) {
            try decode(.anthropic, "event: error\ndata: {\"type\":\"error\",\"error\":{\"type\":\"overloaded_error\",\"message\":\"Overloaded\"}}\n\n")
        }
        #expect(throws: MicroAppAIStreamDecoder.Failure.cut) {
            try decode(.anthropic, "data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"max_tokens\"}}\n\n")
        }
    }

    @Test func errorBodies() {
        #expect(MicroAppAIStreamDecoder.errorMessage(body: Data(#"{"error":{"message":"Bad key","type":"invalid_request_error"}}"#.utf8))
            == "invalid_request_error: Bad key")
        #expect(MicroAppAIStreamDecoder.errorMessage(body: Data(" plain text \n".utf8)) == "plain text")
    }
}

@Suite struct MicroAppShellEnvironmentTests {
    @Test func readsTheEnvironmentBetweenTheMarkers() {
        var output = Data("Welcome!\n__TING_PATH_BEGIN__\n/a:/b\n__TING_PATH_END__\n__TING_ENV_BEGIN__\n".utf8)
        output.append(Data("A=1\0MULTI=x\ny=z\0PWD=/tmp\0SHLVL=2\0EMPTY=\0OPENAI_API_KEY=sk-1\0".utf8))
        output.append(Data("\n__TING_ENV_END__\nbye\n".utf8))
        let env = MicroAppRunRules.environmentFromShellOutput(output)
        #expect(env == ["A": "1", "MULTI": "x\ny=z", "EMPTY": "", "OPENAI_API_KEY": "sk-1"])
        #expect(MicroAppRunRules.environmentFromShellOutput(Data("__TING_ENV_BEGIN__\nA=1\0".utf8)) == nil)
        #expect(MicroAppRunRules.pathShellArguments[3].contains("/usr/bin/env -0"))
    }
}
