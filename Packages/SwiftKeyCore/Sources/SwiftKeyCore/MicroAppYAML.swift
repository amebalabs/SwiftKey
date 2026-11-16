import Foundation

// A strict YAML subset for micro-app files. It keeps the line number of every node, so the
// checker can point at the line of a mistake. Supported: block mappings with plain keys, block
// sequences, plain / 'single' / "double" quoted one-line scalars, one-line flow lists of scalars
// (`[a, b]`), literal blocks (`|`, `|-`, `|+`) and `#` comments. Everything else is refused with
// a line number: anchors, aliases, tags, directives, more than one document, folded blocks,
// flow mappings, nested flow collections, complex or quoted keys, multi-line plain or quoted
// values, tabs in indentation and duplicate keys.

public struct YAMLError: Error, Equatable, Sendable, CustomStringConvertible {
    /// 1-based line number.
    public var line: Int
    public var message: String

    public init(line: Int, message: String) {
        self.line = line
        self.message = message
    }

    public var description: String { "line \(line): \(message)" }
}

public struct YAMLScalar: Equatable, Sendable {
    public enum Style: Equatable, Sendable { case plain, singleQuoted, doubleQuoted, literal }

    public var value: String
    public var style: Style
    /// Line of the value (for a literal block: the line of `|`).
    public var line: Int
    /// Line of the first character of `value` (for a literal block: the line after `|`).
    public var contentLine: Int

    public init(value: String, style: Style, line: Int, contentLine: Int? = nil) {
        self.value = value
        self.style = style
        self.line = line
        self.contentLine = contentLine ?? line
    }
}

public struct YAMLEntry: Equatable, Sendable {
    public var key: String
    public var keyLine: Int
    public var value: YAMLNode

    public init(key: String, keyLine: Int, value: YAMLNode) {
        self.key = key
        self.keyLine = keyLine
        self.value = value
    }
}

public indirect enum YAMLNode: Equatable, Sendable {
    case scalar(YAMLScalar)
    case sequence([YAMLNode], line: Int)
    case mapping([YAMLEntry], line: Int)
    /// An empty value (`key:` with nothing under it), `~` or `null`.
    case null(line: Int)

    public var line: Int {
        switch self {
        case .scalar(let s): return s.line
        case .sequence(_, let line), .mapping(_, let line), .null(let line): return line
        }
    }
}

public enum YAMLSubset {
    /// The deepest nesting of maps and lists a file may have. Micro-app files need a few levels;
    /// the limit keeps a hostile file from overflowing the stack of the recursive parser.
    public static let maxDepth = 32

    /// Parses one document of the subset. Throws the first error found.
    public static func parse(_ text: String) throws -> YAMLNode {
        var parser = YAMLSubsetParser(text: text)
        return try parser.parseDocument()
    }
}

private struct YAMLLine {
    var number: Int
    /// Leading spaces (for a list item opened on the same line, the column of its content).
    var indent: Int
    /// Text after the indentation.
    var text: Substring
    /// The original line, without the line break.
    var raw: Substring
}

private struct YAMLSubsetParser {
    var lines: [YAMLLine] = []
    var index = 0
    var sawContent = false
    var sawDocumentStart = false
    /// How many blocks are open around the current one.
    var depth = 0

    init(text: String) {
        var body = Substring(text)
        if body.hasPrefix("\u{FEFF}") { body = body.dropFirst() }
        var number = 0
        for rawLine in body.split(separator: "\n", omittingEmptySubsequences: false) {
            number += 1
            var raw = rawLine
            if raw.hasSuffix("\r") { raw = raw.dropLast() }
            let spaces = raw.prefix { $0 == " " }.count
            lines.append(YAMLLine(number: number, indent: spaces, text: raw.dropFirst(spaces), raw: raw))
        }
    }

    // MARK: Lines

    private static func isInsignificant(_ line: YAMLLine) -> Bool {
        let trimmed = line.text.drop { $0 == " " || $0 == "\t" }
        return trimmed.isEmpty || trimmed.first == "#"
    }

    private static func isSequenceItem(_ text: Substring) -> Bool {
        text == "-" || text.hasPrefix("- ") || text.hasPrefix("-\t")
    }

    /// The next line with content, skipping blank and comment lines. Checks indentation tabs,
    /// directives and document markers on the way.
    mutating func peek() throws -> YAMLLine? {
        while index < lines.count {
            let line = lines[index]
            if Self.isInsignificant(line) { index += 1; continue }
            if line.text.first == "\t" {
                throw YAMLError(line: line.number, message: "tabs are not allowed in indentation; use spaces")
            }
            if line.indent == 0 {
                if line.text.first == "%" {
                    throw YAMLError(line: line.number, message: "YAML directives (`%…`) are not supported")
                }
                if line.text == "---" || line.text.hasPrefix("--- ") {
                    if line.text == "---" && !sawContent && !sawDocumentStart {
                        sawDocumentStart = true
                        index += 1
                        continue
                    }
                    throw YAMLError(line: line.number, message: "multi-document files are not supported; write one micro-app per file")
                }
                if line.text == "..." || line.text.hasPrefix("... ") {
                    throw YAMLError(line: line.number, message: "document end markers (`...`) are not supported")
                }
            }
            sawContent = true
            return line
        }
        return nil
    }

    // MARK: Structure

    mutating func parseDocument() throws -> YAMLNode {
        guard let first = try peek() else {
            throw YAMLError(line: 1, message: "the file is empty")
        }
        let node = try parseBlock(indent: first.indent)
        if let extra = try peek() {
            throw YAMLError(line: extra.number, message: extra.indent > 0
                ? "unexpected indentation"
                : "unexpected text after the end of the document")
        }
        return node
    }

    mutating func parseBlock(indent: Int) throws -> YAMLNode {
        guard let line = try peek() else { return .null(line: lines.last?.number ?? 1) }
        depth += 1
        defer { depth -= 1 }
        guard depth <= YAMLSubset.maxDepth else {
            throw YAMLError(line: line.number, message: "nesting deeper than \(YAMLSubset.maxDepth) levels is not supported")
        }
        if Self.isSequenceItem(line.text) { return try parseSequence(indent: indent) }
        return try parseMapping(indent: indent)
    }

    mutating func parseMapping(indent: Int) throws -> YAMLNode {
        var entries: [YAMLEntry] = []
        var seen: [String: Int] = [:]
        let startLine = try peek()?.number ?? 1
        while let line = try peek() {
            if line.indent < indent { break }
            if line.indent > indent {
                throw YAMLError(line: line.number, message: "unexpected indentation (a plain or quoted value must fit on one line; use `|` for multi-line text)")
            }
            if Self.isSequenceItem(line.text) {
                throw YAMLError(line: line.number, message: "a list item is not expected here")
            }
            let (key, rest) = try splitKey(line)
            if let previous = seen[key] {
                throw YAMLError(line: line.number, message: "duplicate key `\(key)` (first on line \(previous))")
            }
            seen[key] = line.number
            index += 1
            let value = try parseValue(rest, line: line, parentIndent: indent, sequenceAtSameIndent: true)
            entries.append(YAMLEntry(key: key, keyLine: line.number, value: value))
        }
        return .mapping(entries, line: startLine)
    }

    mutating func parseSequence(indent: Int) throws -> YAMLNode {
        var items: [YAMLNode] = []
        let startLine = try peek()?.number ?? 1
        while let line = try peek() {
            if line.indent < indent { break }
            if line.indent > indent {
                throw YAMLError(line: line.number, message: "unexpected indentation (a plain or quoted value must fit on one line; use `|` for multi-line text)")
            }
            guard Self.isSequenceItem(line.text) else { break }
            let afterDash = line.text.dropFirst()
            if afterDash.first == "\t" {
                throw YAMLError(line: line.number, message: "tabs are not allowed in indentation; use spaces")
            }
            let spaces = afterDash.prefix { $0 == " " }.count
            let content = afterDash.dropFirst(spaces)
            if content.isEmpty || content.first == "#" {
                index += 1
                if let next = try peek(), next.indent > indent {
                    items.append(try parseBlock(indent: next.indent))
                } else {
                    items.append(.null(line: line.number))
                }
                continue
            }
            if Self.looksLikeKey(content) || Self.isSequenceItem(content) {
                // `- key: value` opens a mapping whose keys sit at the column of `key`.
                lines[index].indent = indent + 1 + spaces
                lines[index].text = content
                items.append(try parseBlock(indent: indent + 1 + spaces))
            } else {
                index += 1
                items.append(try parseValue(content, line: line, parentIndent: indent, sequenceAtSameIndent: false))
            }
        }
        return .sequence(items, line: startLine)
    }

    private static func isKeyCharacter(_ c: Character) -> Bool {
        c.isASCII && (c.isLetter || c.isNumber || c == "_" || c == "-")
    }

    private static func looksLikeKey(_ text: Substring) -> Bool {
        let key = text.prefix(while: isKeyCharacter)
        guard !key.isEmpty else { return false }
        let rest = text.dropFirst(key.count)
        return rest == ":" || rest.hasPrefix(": ") || rest.hasPrefix(":\t")
    }

    private func splitKey(_ line: YAMLLine) throws -> (String, Substring) {
        let text = line.text
        switch text.first {
        case "\"", "'":
            throw YAMLError(line: line.number, message: "quoted keys are not supported; write the key as a plain word")
        case "?":
            throw YAMLError(line: line.number, message: "complex keys (`?`) are not supported")
        case "&":
            throw YAMLError(line: line.number, message: "anchors (`&`) are not supported")
        case "*":
            throw YAMLError(line: line.number, message: "aliases (`*`) are not supported")
        case "!":
            throw YAMLError(line: line.number, message: "tags (`!`) are not supported")
        case "{", "[":
            throw YAMLError(line: line.number, message: "flow collections cannot be used as keys or documents; write `key: value` lines")
        default:
            break
        }
        guard Self.looksLikeKey(text) else {
            throw YAMLError(line: line.number, message: "expected `key: value`; keys use only letters, digits, `_` and `-`")
        }
        let key = text.prefix(while: Self.isKeyCharacter)
        return (String(key), text.dropFirst(key.count + 1))
    }

    // MARK: Values

    /// `rest` is the text after `key:` or `- `. `parentIndent` is the indentation of the key
    /// or of the dash.
    mutating func parseValue(_ rest: Substring, line: YAMLLine, parentIndent: Int, sequenceAtSameIndent: Bool) throws -> YAMLNode {
        let text = rest.drop { $0 == " " || $0 == "\t" }
        if text.isEmpty || text.first == "#" {
            if let next = try peek() {
                if next.indent > parentIndent { return try parseBlock(indent: next.indent) }
                if sequenceAtSameIndent && next.indent == parentIndent && Self.isSequenceItem(next.text) {
                    return try parseSequence(indent: parentIndent)
                }
            }
            return .null(line: line.number)
        }
        let n = line.number
        switch text.first! {
        case "|":
            return try parseLiteral(header: text, line: line, parentIndent: parentIndent)
        case ">":
            throw YAMLError(line: n, message: "folded blocks (`>`) are not supported; use a literal block `|`")
        case "&":
            throw YAMLError(line: n, message: "anchors (`&`) are not supported")
        case "*":
            throw YAMLError(line: n, message: "aliases (`*`) are not supported")
        case "!":
            throw YAMLError(line: n, message: "tags (`!`) are not supported")
        case "{":
            throw YAMLError(line: n, message: "flow mappings (`{…}`) are not supported; write `key: value` lines")
        case "[":
            return try parseFlowSequence(text, line: n)
        case "\"", "'":
            let (value, end, style) = try Self.parseQuoted(text, line: n)
            try Self.expectEndOfLine(text[end...], line: n, after: "the quoted value")
            return .scalar(YAMLScalar(value: value, style: style, line: n))
        case "@", "`", "%":
            throw YAMLError(line: n, message: "a value cannot start with `\(text.first!)`; put it in quotes")
        case "-" where Self.isSequenceItem(text):
            throw YAMLError(line: n, message: "a list cannot start on the line of its key; put `- item` on the next lines or use `[a, b]`")
        case "?" where text == "?" || text.hasPrefix("? "):
            throw YAMLError(line: n, message: "complex keys (`?`) are not supported")
        default:
            return try Self.plainScalar(text, line: n)
        }
    }

    private static func plainScalar(_ text: Substring, line: Int) throws -> YAMLNode {
        var value = text
        if let comment = commentStart(in: text) { value = text[..<comment] }
        while let last = value.last, last == " " || last == "\t" { value = value.dropLast() }
        if value.contains(": ") || value.contains(":\t") || value.hasSuffix(":") {
            throw YAMLError(line: line, message: "a plain value cannot contain `: `; put it in quotes")
        }
        if value == "~" || value == "null" { return .null(line: line) }
        return .scalar(YAMLScalar(value: String(value), style: .plain, line: line))
    }

    /// Index of a ` #` comment in a plain value.
    private static func commentStart(in text: Substring) -> Substring.Index? {
        var previous: Character = " "
        for i in text.indices {
            if text[i] == "#" && (previous == " " || previous == "\t") && i != text.startIndex { return i }
            previous = text[i]
        }
        return nil
    }

    private static func expectEndOfLine(_ rest: Substring, line: Int, after what: String) throws {
        let trimmed = rest.drop { $0 == " " || $0 == "\t" }
        if trimmed.isEmpty { return }
        if trimmed.first == "#" && trimmed.startIndex != rest.startIndex { return }
        throw YAMLError(line: line, message: "unexpected text after \(what)")
    }

    /// Parses a quoted scalar at the start of `text`. Returns the value and the index after the
    /// closing quote.
    private static func parseQuoted(_ text: Substring, line: Int) throws -> (String, Substring.Index, YAMLScalar.Style) {
        let quote = text.first!
        var value = ""
        var i = text.index(after: text.startIndex)
        while i < text.endIndex {
            let c = text[i]
            if quote == "'" {
                if c == "'" {
                    let next = text.index(after: i)
                    if next < text.endIndex && text[next] == "'" {
                        value.append("'")
                        i = text.index(after: next)
                        continue
                    }
                    return (value, next, .singleQuoted)
                }
                value.append(c)
            } else {
                if c == "\"" { return (value, text.index(after: i), .doubleQuoted) }
                if c == "\\" {
                    i = text.index(after: i)
                    guard i < text.endIndex else { break }
                    switch text[i] {
                    case "\\": value.append("\\")
                    case "\"": value.append("\"")
                    case "/": value.append("/")
                    case "n": value.append("\n")
                    case "t": value.append("\t")
                    case "r": value.append("\r")
                    case "0": value.append("\0")
                    case "u":
                        let start = text.index(after: i)
                        guard let end = text.index(start, offsetBy: 4, limitedBy: text.endIndex),
                              let code = UInt32(text[start..<end], radix: 16),
                              let scalar = Unicode.Scalar(code)
                        else {
                            throw YAMLError(line: line, message: "`\\u` needs four hex digits")
                        }
                        value.unicodeScalars.append(scalar)
                        i = text.index(before: end)
                    default:
                        throw YAMLError(line: line, message: "unsupported escape `\\\(text[i])` in a double-quoted value")
                    }
                } else {
                    value.append(c)
                }
            }
            i = text.index(after: i)
        }
        throw YAMLError(line: line, message: "a quoted value must end on the same line")
    }

    private func parseFlowSequence(_ text: Substring, line: Int) throws -> YAMLNode {
        var items: [YAMLNode] = []
        var i = text.index(after: text.startIndex)
        func skipSpaces() {
            while i < text.endIndex && (text[i] == " " || text[i] == "\t") { i = text.index(after: i) }
        }
        while true {
            skipSpaces()
            guard i < text.endIndex else {
                throw YAMLError(line: line, message: "a `[…]` list must end on the same line")
            }
            if text[i] == "]" { break }
            switch text[i] {
            case "[", "{":
                throw YAMLError(line: line, message: "nested flow collections are not supported")
            case "&":
                throw YAMLError(line: line, message: "anchors (`&`) are not supported")
            case "*":
                throw YAMLError(line: line, message: "aliases (`*`) are not supported")
            case "!":
                throw YAMLError(line: line, message: "tags (`!`) are not supported")
            case "#":
                throw YAMLError(line: line, message: "comments are not allowed inside `[…]`")
            case ",":
                throw YAMLError(line: line, message: "empty item in a `[…]` list")
            case "\"", "'":
                let (value, end, style) = try Self.parseQuoted(text[i...], line: line)
                items.append(.scalar(YAMLScalar(value: value, style: style, line: line)))
                i = end
            default:
                let start = i
                while i < text.endIndex && text[i] != "," && text[i] != "]" {
                    if text[i] == "[" || text[i] == "{" {
                        throw YAMLError(line: line, message: "nested flow collections are not supported")
                    }
                    if text[i] == "#" && (text[text.index(before: i)] == " ") {
                        throw YAMLError(line: line, message: "comments are not allowed inside `[…]`")
                    }
                    i = text.index(after: i)
                }
                var value = text[start..<i]
                while let last = value.last, last == " " || last == "\t" { value = value.dropLast() }
                if value.contains(": ") || value.hasSuffix(":") {
                    throw YAMLError(line: line, message: "flow mappings are not supported inside `[…]`; put the item in quotes")
                }
                items.append(.scalar(YAMLScalar(value: String(value), style: .plain, line: line)))
            }
            skipSpaces()
            guard i < text.endIndex else {
                throw YAMLError(line: line, message: "a `[…]` list must end on the same line")
            }
            if text[i] == "]" { break }
            guard text[i] == "," else {
                throw YAMLError(line: line, message: "expected `,` or `]` in a `[…]` list")
            }
            i = text.index(after: i)
        }
        try Self.expectEndOfLine(text[text.index(after: i)...], line: line, after: "the `[…]` list")
        return .sequence(items, line: line)
    }

    private mutating func parseLiteral(header: Substring, line: YAMLLine, parentIndent: Int) throws -> YAMLNode {
        enum Chomping { case clip, strip, keep }
        var chomping = Chomping.clip
        var rest = header.dropFirst()
        if rest.first == "-" { chomping = .strip; rest = rest.dropFirst() }
        else if rest.first == "+" { chomping = .keep; rest = rest.dropFirst() }
        if let c = rest.first, c.isNumber {
            throw YAMLError(line: line.number, message: "indentation indicators (`|2`) are not supported; indent the block by itself")
        }
        try Self.expectEndOfLine(rest, line: line.number, after: "`|`")

        var contentIndent: Int?
        var collected: [Substring] = []
        var j = index
        while j < lines.count {
            let raw = lines[j].raw
            if raw.allSatisfy({ $0 == " " || $0 == "\t" }) {
                collected.append("")
                j += 1
                continue
            }
            let spaces = raw.prefix { $0 == " " }.count
            if contentIndent == nil {
                if spaces <= parentIndent { break }
                contentIndent = spaces
            }
            if spaces < contentIndent! { break }
            collected.append(raw.dropFirst(contentIndent!))
            j += 1
        }
        index = j

        var trailingBlank = 0
        while let last = collected.last, last.isEmpty {
            trailingBlank += 1
            collected.removeLast()
        }
        var value = collected.joined(separator: "\n")
        if !value.isEmpty {
            switch chomping {
            case .strip: break
            case .clip: value += "\n"
            case .keep: value += String(repeating: "\n", count: 1 + trailingBlank)
            }
        }
        return .scalar(YAMLScalar(value: value, style: .literal, line: line.number, contentLine: line.number + 1))
    }
}
