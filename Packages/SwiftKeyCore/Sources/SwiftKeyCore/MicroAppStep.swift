import Foundation

/// One step of a micro-app script. The output of a step is the input (stdin) of the next one.
public struct MicroAppStep: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable, CaseIterable {
        case command, python, url, ai, text, json, open, notify, call, keys, paste
    }

    /// A `key: template` line of `env`, `query`, `headers` or `form`, in file order.
    public struct Field: Equatable, Sendable {
        public var name: String
        public var value: MicroAppTemplate

        public init(name: String, value: MicroAppTemplate) {
            self.name = name
            self.value = value
        }
    }

    public struct URLRequestStep: Equatable, Sendable {
        public enum Body: Equatable, Sendable {
            /// The body text as written, after the variables.
            case text(MicroAppTemplate)
            /// A map or list, sent as JSON.
            case json(MicroAppJSONTemplate)
            /// `application/x-www-form-urlencoded`.
            case form([Field])
        }

        public static let methods = ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD"]

        public var url: MicroAppTemplate
        public var method: String
        public var query: [Field]
        public var headers: [Field]
        public var body: Body?

        public init(url: MicroAppTemplate, method: String = "GET", query: [Field] = [], headers: [Field] = [], body: Body? = nil) {
            self.url = url
            self.method = method
            self.query = query
            self.headers = headers
            self.body = body
        }
    }

    public struct AIStep: Equatable, Sendable {
        public enum Provider: String, Equatable, Sendable, CaseIterable {
            case openai, anthropic
        }

        /// The user message.
        public var prompt: MicroAppTemplate
        public var provider: Provider
        public var model: MicroAppTemplate
        /// `nil`: `${OPENAI_API_KEY}` or `${ANTHROPIC_API_KEY}` for the provider's own address,
        /// no key for a `base_url`.
        public var key: MicroAppTemplate?
        public var system: MicroAppTemplate?
        public var baseURL: MicroAppTemplate?
        public var temperature: MicroAppTemplate?
        public var maxTokens: MicroAppTemplate?

        public init(prompt: MicroAppTemplate, provider: Provider, model: MicroAppTemplate, key: MicroAppTemplate? = nil,
                    system: MicroAppTemplate? = nil, baseURL: MicroAppTemplate? = nil, temperature: MicroAppTemplate? = nil,
                    maxTokens: MicroAppTemplate? = nil) {
            self.prompt = prompt
            self.provider = provider
            self.model = model
            self.key = key
            self.system = system
            self.baseURL = baseURL
            self.temperature = temperature
            self.maxTokens = maxTokens
        }

        /// The key used when the step has no `key`: the provider's environment variable for its own
        /// address; nothing for a `base_url`.
        public var effectiveKey: MicroAppTemplate? {
            if let key { return key }
            guard baseURL == nil else { return nil }
            switch provider {
            case .openai: return MicroAppTemplate(parts: [.variable(.env("OPENAI_API_KEY"), filters: [])], source: "${OPENAI_API_KEY}")
            case .anthropic: return MicroAppTemplate(parts: [.variable(.env("ANTHROPIC_API_KEY"), filters: [])], source: "${ANTHROPIC_API_KEY}")
            }
        }
    }

    public enum Action: Equatable, Sendable {
        /// Shell code for `/bin/sh -c`, as written.
        case command(String)
        /// Python code for `python3 -I -c`, as written.
        case python(String)
        case url(URLRequestStep)
        case ai(AIStep)
        case text(MicroAppTemplate)
        case json(MicroAppJSONPath)
        case open(target: MicroAppTemplate, app: MicroAppTemplate?)
        case notify(message: MicroAppTemplate, title: MicroAppTemplate?)
        /// Runs the steps of a library; the step's `params` are the library's params.
        case call(MicroAppLibrary)
        /// Presses keys in the app where the micro-app started, one after another.
        case keys([Hotkey])
        /// Pastes the text into the app where the micro-app started, then puts the clipboard back.
        case paste(MicroAppTemplate)
    }

    /// `a-z`, `0-9` and `_`; later steps read the output as `${steps.ID}` or `$TING_STEP_ID`.
    public var id: String?
    public var action: Action
    /// Replaces the input of the step.
    public var stdin: MicroAppTemplate?
    /// Extra environment variables of a command or python step.
    public var env: [Field]
    /// The step's own time limit in seconds; `nil` uses what is left of the micro-app's limit.
    public var timeLimit: TimeInterval?
    /// Starts together with the step before it and reads its output while it comes.
    public var stream: Bool
    /// Values for this step only: `${params.NAME}` and `$TING_NAME` of the step see them over the
    /// micro-app's params. For a `call` step, the params of the library.
    public var params: [Field]
    /// The line of the step in the file.
    public var line: Int

    public init(id: String? = nil, action: Action, stdin: MicroAppTemplate? = nil, env: [Field] = [], timeLimit: TimeInterval? = nil,
                stream: Bool = false, params: [Field] = [], line: Int = 0) {
        self.id = id
        self.params = params
        self.action = action
        self.stdin = stdin
        self.env = env
        self.timeLimit = timeLimit
        self.stream = stream
        self.line = line
    }

    public var kind: Kind {
        switch action {
        case .command: .command
        case .python: .python
        case .url: .url
        case .ai: .ai
        case .text: .text
        case .json: .json
        case .open: .open
        case .notify: .notify
        case .call: .call
        case .keys: .keys
        case .paste: .paste
        }
    }

    /// `keys` and `paste` steps send input to the app where the micro-app started.
    public var sendsInput: Bool { kind == .keys || kind == .paste }

    /// Command and python steps run a program; only they can stream their input.
    public var runsProgram: Bool { kind == .command || kind == .python }

    /// The environment variable of a step output: `TING_STEP_` + upper-case id.
    public static func environmentName(forStep id: String) -> String { "TING_STEP_" + id.uppercased() }

    /// Every template of the step, in file order.
    public var templates: [MicroAppTemplate] {
        var result: [MicroAppTemplate] = []
        if let stdin { result.append(stdin) }
        result += env.map(\.value) + params.map(\.value)
        switch action {
        case .command, .python, .json, .call, .keys:
            break
        case .url(let u):
            result.append(u.url)
            result += u.query.map(\.value) + u.headers.map(\.value)
            switch u.body {
            case .text(let t): result.append(t)
            case .json(let j): result += j.templates
            case .form(let fields): result += fields.map(\.value)
            case nil: break
            }
        case .ai(let a):
            result += [a.prompt, a.model] + [a.key, a.system, a.baseURL, a.temperature, a.maxTokens].compactMap { $0 }
        case .text(let t):
            result.append(t)
        case .open(let target, let app):
            result += [target] + [app].compactMap { $0 }
        case .notify(let message, let title):
            result += [message] + [title].compactMap { $0 }
        case .paste(let text):
            result.append(text)
        }
        return result
    }
}

/// A map or list of a `body:` key, sent as JSON. Plain `true`, `false`, numbers and `null` keep
/// their JSON type; every other value is a string template.
public indirect enum MicroAppJSONTemplate: Equatable, Sendable {
    case string(MicroAppTemplate)
    /// The number as written.
    case number(String)
    case bool(Bool)
    case null
    case array([MicroAppJSONTemplate])
    case object([(key: String, value: MicroAppJSONTemplate)])

    public static func == (lhs: MicroAppJSONTemplate, rhs: MicroAppJSONTemplate) -> Bool {
        switch (lhs, rhs) {
        case (.string(let a), .string(let b)): a == b
        case (.number(let a), .number(let b)): a == b
        case (.bool(let a), .bool(let b)): a == b
        case (.null, .null): true
        case (.array(let a), .array(let b)): a == b
        case (.object(let a), .object(let b)): a.count == b.count && zip(a, b).allSatisfy { $0.key == $1.key && $0.value == $1.value }
        default: false
        }
    }

    public var templates: [MicroAppTemplate] {
        switch self {
        case .string(let t): [t]
        case .number, .bool, .null: []
        case .array(let items): items.flatMap(\.templates)
        case .object(let entries): entries.flatMap(\.value.templates)
        }
    }

    /// Compact JSON text, keys in file order.
    public func render(_ resolve: (MicroAppVariable) throws -> String) rethrows -> String {
        switch self {
        case .string(let t): return MicroAppJSON.quote(try t.render(resolve))
        case .number(let n): return n
        case .bool(let b): return b ? "true" : "false"
        case .null: return "null"
        case .array(let items): return "[" + (try items.map { try $0.render(resolve) }).joined(separator: ",") + "]"
        case .object(let entries):
            return "{" + (try entries.map { MicroAppJSON.quote($0.key) + ":" + (try $0.value.render(resolve)) }).joined(separator: ",") + "}"
        }
    }
}

/// The path of a `json` step: keys and list indexes joined by `.`, such as `choices.0.message.content`.
/// `.` alone is the whole document.
public struct MicroAppJSONPath: Equatable, Sendable, CustomStringConvertible {
    public var segments: [String]

    public init(segments: [String]) {
        self.segments = segments
    }

    /// `nil` for an empty segment, such as in `a..b` or `a.`.
    public init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed == "." { segments = []; return }
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard !trimmed.isEmpty, parts.allSatisfy({ !$0.isEmpty }) else { return nil }
        segments = parts
    }

    public var description: String { segments.isEmpty ? "." : segments.joined(separator: ".") }

    public enum PickError: Error, Equatable, Sendable, CustomStringConvertible {
        case notJSON(String)
        case missing(String)

        public var description: String {
            switch self {
            case .notJSON(let detail): "the input is not JSON: \(detail)"
            case .missing(let path): "the JSON has no `\(path)`"
            }
        }
    }

    /// The value at the path: a string as its text, a number or `true`/`false` as written, `null` as
    /// empty text, a map or list as JSON with two-space indentation and sorted keys.
    public func pick(from data: Data) throws -> String {
        let root: Any
        do {
            root = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            let detail = (error as NSError).userInfo[NSDebugDescriptionErrorKey] as? String ?? error.localizedDescription
            throw PickError.notJSON(detail)
        }
        var value: Any = root
        for (i, segment) in segments.enumerated() {
            let path = segments[...i].joined(separator: ".")
            if let map = value as? [String: Any], let next = map[segment] {
                value = next
            } else if let list = value as? [Any], let index = Int(segment), index >= 0, index < list.count {
                value = list[index]
            } else {
                throw PickError.missing(path)
            }
        }
        return Self.text(of: value)
    }

    static func text(of value: Any) -> String {
        switch value {
        case let s as String:
            return s
        case is NSNull:
            return ""
        case let n as NSNumber where CFGetTypeID(n) == CFBooleanGetTypeID():
            return n.boolValue ? "true" : "false"
        case let n as NSNumber:
            return n.stringValue
        default:
            let data = (try? JSONSerialization.data(withJSONObject: value,
                                                    options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed])) ?? Data()
            return String(decoding: data, as: UTF8.self)
        }
    }
}

/// An HTTP request built from a `url` or `ai` step, without Foundation's URL loading.
public struct MicroAppHTTPRequest: Equatable, Sendable {
    public var method: String
    public var url: String
    /// In order; a later header with the same name replaces an earlier one when sent.
    public var headers: [(name: String, value: String)]
    public var body: Data?

    public init(method: String, url: String, headers: [(name: String, value: String)] = [], body: Data? = nil) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
    }

    public static func == (lhs: MicroAppHTTPRequest, rhs: MicroAppHTTPRequest) -> Bool {
        lhs.method == rhs.method && lhs.url == rhs.url && lhs.body == rhs.body
            && lhs.headers.map(\.name) == rhs.headers.map(\.name) && lhs.headers.map(\.value) == rhs.headers.map(\.value)
    }

    public func header(_ name: String) -> String? {
        headers.last { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    public enum BuildError: Error, Equatable, Sendable, CustomStringConvertible {
        case badURL(String)
        case badNumber(key: String, value: String)
        case missingKey(String)

        public var description: String {
            switch self {
            case .badURL(let url): "`\(url)` is not an http or https URL"
            case .badNumber(let key, let value): "`\(key)` is `\(value)`, not a number"
            case .missingKey(let name): "no API key: set `key:` in the step or the environment variable \(name)"
            }
        }
    }

    /// `true` for an absolute `http` or `https` URL with a host.
    public static func isWebURL(_ text: String) -> Bool {
        guard let components = URLComponents(string: text), let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https", let host = components.host, !host.isEmpty else { return false }
        return true
    }

    /// `url` with `query` added: each name and value percent-encoded, after any query it has.
    public static func url(_ url: String, adding query: [(String, String)]) -> String {
        guard !query.isEmpty else { return url }
        let encoded = query.map { MicroAppFilter.url.apply($0.0) + "=" + MicroAppFilter.url.apply($0.1) }.joined(separator: "&")
        var base = url
        var fragment = ""
        if let hash = base.firstIndex(of: "#") {
            fragment = String(base[hash...])
            base = String(base[..<hash])
        }
        let separator = base.contains("?") ? (base.hasSuffix("?") || base.hasSuffix("&") ? "" : "&") : "?"
        return base + separator + encoded + fragment
    }

    /// The request of a `url` step. Variables come from `resolve`.
    public static func build(_ step: MicroAppStep.URLRequestStep, resolve: (MicroAppVariable) throws -> String) throws -> MicroAppHTTPRequest {
        let base = try step.url.render(resolve)
        let query = try step.query.map { ($0.name, try $0.value.render(resolve)) }
        let url = Self.url(base, adding: query)
        guard isWebURL(url) else { throw BuildError.badURL(url) }
        var headers: [(name: String, value: String)] = []
        var body: Data?
        switch step.body {
        case .text(let t):
            body = Data(try t.render(resolve).utf8)
        case .json(let j):
            headers.append(("Content-Type", "application/json"))
            body = Data(try j.render(resolve).utf8)
        case .form(let fields):
            headers.append(("Content-Type", "application/x-www-form-urlencoded"))
            let text = try fields.map { MicroAppFilter.url.apply($0.name) + "=" + MicroAppFilter.url.apply(try $0.value.render(resolve)) }
            body = Data(text.joined(separator: "&").utf8)
        case nil:
            break
        }
        for field in step.headers {
            headers.append((field.name, try field.value.render(resolve)))
        }
        return MicroAppHTTPRequest(method: step.method, url: url, headers: headers, body: body)
    }

    public static let openAIBaseURL = "https://api.openai.com/v1"
    public static let anthropicBaseURL = "https://api.anthropic.com/v1"
    public static let anthropicVersion = "2023-06-01"
    /// Anthropic needs `max_tokens`; this is used when the step has none.
    public static let anthropicDefaultMaxTokens = 8192

    /// The streaming request of an `ai` step.
    public static func build(_ step: MicroAppStep.AIStep, resolve: (MicroAppVariable) throws -> String) throws -> MicroAppHTTPRequest {
        let customBase = try step.baseURL.map { try $0.render(resolve) }
        var base = customBase ?? (step.provider == .openai ? openAIBaseURL : anthropicBaseURL)
        while base.hasSuffix("/") { base.removeLast() }
        let model = try step.model.render(resolve)
        let prompt = try step.prompt.render(resolve)
        let system = try step.system.map { try $0.render(resolve) }
        var key = ""
        if let template = step.effectiveKey {
            do {
                key = try template.render(resolve)
            } catch {
                if step.key == nil, case .variable(.env(let name), _)? = template.parts.first { throw BuildError.missingKey(name) }
                throw error
            }
        }
        func number(_ template: MicroAppTemplate?, _ name: String, integer: Bool) throws -> String? {
            guard let template else { return nil }
            let text = try template.render(resolve).trimmingCharacters(in: .whitespaces)
            let ok = integer ? (Int(text).map { $0 > 0 } ?? false) : MicroAppJSON.isNumber(text)
            guard ok else { throw BuildError.badNumber(key: name, value: text) }
            return text
        }
        let temperature = try number(step.temperature, "temperature", integer: false)
        let maxTokens = try number(step.maxTokens, "max_tokens", integer: true)

        var fields: [String] = ["\"model\":" + MicroAppJSON.quote(model)]
        var headers: [(name: String, value: String)] = [("Content-Type", "application/json"), ("Accept", "text/event-stream")]
        let url: String
        switch step.provider {
        case .openai:
            url = base + "/chat/completions"
            var messages: [String] = []
            if let system { messages.append("{\"role\":\"system\",\"content\":" + MicroAppJSON.quote(system) + "}") }
            messages.append("{\"role\":\"user\",\"content\":" + MicroAppJSON.quote(prompt) + "}")
            fields.append("\"messages\":[" + messages.joined(separator: ",") + "]")
            if let maxTokens {
                // OpenAI's own API wants `max_completion_tokens`; compatible servers know `max_tokens`.
                fields.append((customBase == nil ? "\"max_completion_tokens\":" : "\"max_tokens\":") + maxTokens)
            }
            if !key.isEmpty { headers.append(("Authorization", "Bearer " + key)) }
        case .anthropic:
            url = base + "/messages"
            if let system { fields.append("\"system\":" + MicroAppJSON.quote(system)) }
            fields.append("\"messages\":[{\"role\":\"user\",\"content\":" + MicroAppJSON.quote(prompt) + "}]")
            fields.append("\"max_tokens\":" + (maxTokens ?? String(anthropicDefaultMaxTokens)))
            headers.append(("anthropic-version", anthropicVersion))
            if !key.isEmpty { headers.append(("x-api-key", key)) }
        }
        if let temperature { fields.append("\"temperature\":" + temperature) }
        fields.append("\"stream\":true")
        guard isWebURL(url) else { throw BuildError.badURL(url) }
        return MicroAppHTTPRequest(method: "POST", url: url, headers: headers, body: Data(("{" + fields.joined(separator: ",") + "}").utf8))
    }
}

/// Splits a `text/event-stream` body into events. Feed it bytes as they come.
public struct MicroAppSSEParser: Sendable {
    public struct Event: Equatable, Sendable {
        public var name: String
        public var data: String

        public init(name: String = "message", data: String) {
            self.name = name
            self.data = data
        }
    }

    private var buffer = Data()
    private var name = ""
    private var data: [String] = []

    public init() {}

    /// The events completed by `chunk`.
    public mutating func feed(_ chunk: Data) -> [Event] {
        buffer.append(chunk)
        var events: [Event] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            var lineData = buffer[buffer.startIndex..<newline]
            if lineData.last == 0x0D { lineData = lineData.dropLast() }
            buffer = Data(buffer[buffer.index(after: newline)...])
            let line = String(decoding: lineData, as: UTF8.self)
            if let event = take(line) { events.append(event) }
        }
        return events
    }

    /// The last event when the body ends without a blank line.
    public mutating func finish() -> [Event] {
        var events: [Event] = []
        if !buffer.isEmpty {
            let line = String(decoding: buffer, as: UTF8.self)
            buffer = Data()
            if let event = take(line) { events.append(event) }
        }
        if let event = take("") { events.append(event) }
        return events
    }

    private mutating func take(_ line: String) -> Event? {
        if line.isEmpty {
            defer { name = ""; data = [] }
            guard !data.isEmpty else { return nil }
            return Event(name: name.isEmpty ? "message" : name, data: data.joined(separator: "\n"))
        }
        if line.hasPrefix(":") { return nil }
        let field: Substring
        var value: Substring
        if let colon = line.firstIndex(of: ":") {
            field = line[..<colon]
            value = line[line.index(after: colon)...]
            if value.first == " " { value = value.dropFirst() }
        } else {
            field = Substring(line)
            value = ""
        }
        switch field {
        case "event": name = String(value)
        case "data": data.append(String(value))
        default: break
        }
        return nil
    }
}

/// Turns the events of an AI stream into text.
public struct MicroAppAIStreamDecoder: Sendable {
    public enum Failure: Error, Equatable, Sendable, CustomStringConvertible {
        /// The provider reported an error inside the stream.
        case api(String)
        /// The answer stopped at the token limit.
        case cut
        /// The stream ended before the answer was complete.
        case incomplete

        public var description: String {
            switch self {
            case .api(let message): message
            case .cut: "the answer was cut at the token limit (`max_tokens`); nothing was copied"
            case .incomplete: "the answer stream ended before the answer was complete"
            }
        }
    }

    public let provider: MicroAppStep.AIStep.Provider
    private var parser = MicroAppSSEParser()
    /// `true` once the provider said the answer is complete.
    public private(set) var done = false

    public init(provider: MicroAppStep.AIStep.Provider) {
        self.provider = provider
    }

    /// The text that `chunk` adds to the answer.
    public mutating func feed(_ chunk: Data) throws -> String {
        try parser.feed(chunk).map { try decode($0) }.joined()
    }

    /// The text of a last event without a blank line; fails when the answer is not complete.
    public mutating func finish() throws -> String {
        let text = try parser.finish().map { try decode($0) }.joined()
        guard done else { throw Failure.incomplete }
        return text
    }

    private mutating func decode(_ event: MicroAppSSEParser.Event) throws -> String {
        if provider == .openai && event.data.trimmingCharacters(in: .whitespaces) == "[DONE]" {
            done = true
            return ""
        }
        guard let object = try? JSONSerialization.jsonObject(with: Data(event.data.utf8)) as? [String: Any] else { return "" }
        if let message = Self.errorMessage(object) { throw Failure.api(message) }
        switch provider {
        case .openai:
            guard let choice = (object["choices"] as? [[String: Any]])?.first else { return "" }
            if let reason = choice["finish_reason"] as? String {
                if reason == "length" { throw Failure.cut }
                done = true
            }
            return (choice["delta"] as? [String: Any])?["content"] as? String ?? ""
        case .anthropic:
            switch object["type"] as? String {
            case "content_block_delta":
                guard let delta = object["delta"] as? [String: Any], delta["type"] as? String == "text_delta" else { return "" }
                return delta["text"] as? String ?? ""
            case "message_delta":
                if (object["delta"] as? [String: Any])?["stop_reason"] as? String == "max_tokens" { throw Failure.cut }
                return ""
            case "message_stop":
                done = true
                return ""
            default:
                return ""
            }
        }
    }

    /// The message of an error object: `{"error": {"message": …}}` or `{"error": "…"}`.
    public static func errorMessage(_ object: [String: Any]) -> String? {
        if let error = object["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "unknown error"
            if let type = error["type"] as? String, !type.isEmpty { return "\(type): \(message)" }
            return message
        }
        if let error = object["error"] as? String { return error }
        return nil
    }

    /// The error message of a failed response body, or the body text itself (cut to 2000 characters).
    public static func errorMessage(body: Data) -> String {
        if let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any], let message = errorMessage(object) {
            return message
        }
        let text = String(decoding: body.prefix(8192), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.count > 2000 ? String(text.prefix(2000)) + "…" : text
    }
}
