import Foundation

/// A value that a template can read: `${input}`, `${params.NAME}`, `${steps.ID}`,
/// `${context.SOURCE.FIELD}`, `${keychain.SERVICE}` or an environment variable `${NAME}`.
public enum MicroAppVariable: Hashable, Sendable, CustomStringConvertible {
    /// The input of the step: the output of the step before it, or the micro-app input for the first step.
    case input
    case param(String)
    case step(String)
    /// A value of the context of the start, such as `context.app.name`.
    case context(MicroAppContextField)
    /// A generic password of the login keychain, found by its service name.
    case keychain(String)
    /// A variable of the user's login-shell environment.
    case env(String)

    public var description: String {
        switch self {
        case .input: "input"
        case .param(let name): "params.\(name)"
        case .step(let id): "steps.\(id)"
        case .context(let field): "context.\(field)"
        case .keychain(let service): "keychain.\(service)"
        case .env(let name): name
        }
    }
}

/// A function after `|` in a template variable: `${input|url}`.
public enum MicroAppFilter: String, Equatable, Sendable, CaseIterable {
    /// Percent-encodes everything except `A-Z a-z 0-9 - . _ ~` (UTF-8), for a URL path or query part.
    case url
    /// Escapes the text for the inside of a JSON string, without the quotes.
    case json
    /// Removes white space and line breaks at both ends.
    case trim
    /// Base64 of the UTF-8 text.
    case base64

    public func apply(_ value: String) -> String {
        switch self {
        case .url:
            var allowed = CharacterSet()
            allowed.insert(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
            return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
        case .json:
            return MicroAppJSON.escape(value)
        case .trim:
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        case .base64:
            return Data(value.utf8).base64EncodedString()
        }
    }
}

/// Text with `${…}` variables, such as `Bearer ${OPENAI_API_KEY}` or `q=${input|url}`.
/// `$${` writes a literal `${`; any other `$` is plain text.
public struct MicroAppTemplate: Equatable, Sendable, CustomStringConvertible {
    public enum Part: Equatable, Sendable {
        case literal(String)
        case variable(MicroAppVariable, filters: [MicroAppFilter])
    }

    public struct ParseError: Error, Equatable, Sendable {
        /// Number of line breaks before the mistake in the template text.
        public var lineOffset: Int
        public var message: String
    }

    public var parts: [Part]
    /// The text as written.
    public var source: String

    public init(parts: [Part], source: String) {
        self.parts = parts
        self.source = source
    }

    /// A template that is only text.
    public init(literal: String) {
        self.parts = literal.isEmpty ? [] : [.literal(literal)]
        self.source = literal.replacingOccurrences(of: "${", with: "$${")
    }

    public var description: String { source }

    /// The variables, in order, with repeats.
    public var variables: [MicroAppVariable] {
        parts.compactMap { if case .variable(let v, _) = $0 { v } else { nil } }
    }

    /// `true` when the template has no variable.
    public var isLiteral: Bool { variables.isEmpty }

    /// The text of a literal template.
    public var literalText: String? {
        guard isLiteral else { return nil }
        return parts.map { if case .literal(let s) = $0 { s } else { "" } }.joined()
    }

    public static func isEnvironmentName(_ s: Substring) -> Bool {
        guard let first = s.first, first.isASCII, first.isLetter || first == "_" else { return false }
        return s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
    }

    static func isKeychainService(_ s: Substring) -> Bool {
        !s.isEmpty && s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "._@-".contains($0)) }
    }

    public static func parse(_ text: String) -> Result<MicroAppTemplate, ParseError> {
        var parts: [Part] = []
        var literal = ""
        var i = text.startIndex
        func offset(_ index: String.Index) -> Int { text[..<index].reduce(0) { $1 == "\n" ? $0 + 1 : $0 } }
        while i < text.endIndex {
            let rest = text[i...]
            if rest.hasPrefix("$${") {
                literal += "${"
                i = text.index(i, offsetBy: 3)
                continue
            }
            guard rest.hasPrefix("${") else {
                literal.append(text[i])
                i = text.index(after: i)
                continue
            }
            let open = i
            let start = text.index(i, offsetBy: 2)
            guard let close = text[start...].firstIndex(of: "}") else {
                return .failure(ParseError(lineOffset: offset(open), message: "`${` without a closing `}`; write `$${` for a literal `${`"))
            }
            let inner = text[start..<close]
            if inner.contains("\n") || inner.contains("${") {
                return .failure(ParseError(lineOffset: offset(open), message: "`${` without a closing `}` on the same line; write `$${` for a literal `${`"))
            }
            let pieces = inner.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            let name = pieces[0]
            let variable: MicroAppVariable
            if name == "input" {
                variable = .input
            } else if name.hasPrefix("params.") {
                let param = name.dropFirst("params.".count)
                guard MicroAppChecker.isParamName(String(param)) else {
                    return .failure(ParseError(lineOffset: offset(open), message: "`${\(name)}`: a param name uses only a-z, 0-9 and `_`"))
                }
                variable = .param(String(param))
            } else if name.hasPrefix("steps.") {
                let id = name.dropFirst("steps.".count)
                guard MicroAppChecker.isParamName(String(id)) else {
                    return .failure(ParseError(lineOffset: offset(open), message: "`${\(name)}`: a step id uses only a-z, 0-9 and `_`"))
                }
                variable = .step(String(id))
            } else if name.hasPrefix("context.") {
                let parts = name.dropFirst("context.".count).split(separator: ".", omittingEmptySubsequences: false)
                guard parts.count == 2, let source = MicroAppContextSource(rawValue: String(parts[0])) else {
                    return .failure(ParseError(lineOffset: offset(open), message:
                        "`${\(name)}`: write `${context.SOURCE.FIELD}`, such as `${context.app.name}`; the sources are \(MicroAppContextSource.listed)"))
                }
                guard let field = MicroAppContextField(source: source, name: String(parts[1])) else {
                    return .failure(ParseError(lineOffset: offset(open), message:
                        "`${\(name)}`: `\(source.rawValue)` has the fields \(source.fields.joined(separator: ", "))"))
                }
                variable = .context(field)
            } else if name.hasPrefix("keychain.") {
                let service = name.dropFirst("keychain.".count)
                guard isKeychainService(service) else {
                    return .failure(ParseError(lineOffset: offset(open),
                                               message: "`${\(name)}`: a keychain service name uses only letters, digits, `.`, `_`, `@` and `-`"))
                }
                variable = .keychain(String(service))
            } else if isEnvironmentName(Substring(name)) {
                variable = .env(name)
            } else {
                return .failure(ParseError(lineOffset: offset(open), message:
                    "`${\(inner)}` is not a variable; use `${input}`, `${params.NAME}`, `${steps.ID}`, `${context.SOURCE.FIELD}`, `${keychain.SERVICE}` or an environment variable such as `${OPENAI_API_KEY}`"))
            }
            var filters: [MicroAppFilter] = []
            for raw in pieces.dropFirst() {
                guard let filter = MicroAppFilter(rawValue: raw) else {
                    let allowed = MicroAppFilter.allCases.map(\.rawValue).joined(separator: ", ")
                    return .failure(ParseError(lineOffset: offset(open), message: "`${\(inner)}`: unknown filter `\(raw)`; use one of: \(allowed)"))
                }
                filters.append(filter)
            }
            if !literal.isEmpty { parts.append(.literal(literal)); literal = "" }
            parts.append(.variable(variable, filters: filters))
            i = text.index(after: close)
        }
        if !literal.isEmpty { parts.append(.literal(literal)) }
        return .success(MicroAppTemplate(parts: parts, source: text))
    }

    /// The text with every variable replaced by `resolve` and passed through its filters.
    public func render(_ resolve: (MicroAppVariable) throws -> String) rethrows -> String {
        var result = ""
        for part in parts {
            switch part {
            case .literal(let s):
                result += s
            case .variable(let variable, let filters):
                result += filters.reduce(try resolve(variable)) { $1.apply($0) }
            }
        }
        return result
    }
}

/// JSON helpers without Foundation's number and slash quirks where they matter.
public enum MicroAppJSON {
    /// The inside of a JSON string for `value`, without the quotes.
    public static func escape(_ value: String) -> String {
        var out = ""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out
    }

    /// A JSON string literal for `value`, with the quotes.
    public static func quote(_ value: String) -> String { "\"" + escape(value) + "\"" }

    /// `true` for a JSON number such as `1`, `-0.5` or `2e10`.
    public static func isNumber(_ s: String) -> Bool {
        s.range(of: #"^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?$"#, options: .regularExpression) != nil
    }
}
