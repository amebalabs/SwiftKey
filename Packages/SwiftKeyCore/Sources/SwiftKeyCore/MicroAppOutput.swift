import Foundation

// The output styles of the result panel as a neutral model: the SwiftKey target only draws it.
// `console` text becomes styled runs (ANSI colour and style codes); `markdown` text becomes blocks.

// MARK: - Console (ANSI)

/// A terminal colour from an ANSI SGR code. The SwiftKey target maps it to the Theme colours.
public enum ConsoleColor: Equatable, Sendable {
    /// One of the 16 basic colours: 0–7 normal (black, red, green, yellow, blue, magenta, cyan, white), 8–15 bright.
    case basic(Int)
    /// A colour of the 256-colour palette above the basic 16: 16–231 the 6×6×6 cube, 232–255 the grey ramp.
    case palette(Int)
    case rgb(UInt8, UInt8, UInt8)
}

public struct ConsoleStyle: Equatable, Sendable {
    public var foreground: ConsoleColor?
    public var background: ConsoleColor?
    public var bold = false
    public var dim = false
    public var italic = false
    public var underline = false
    public var inverse = false
    public var strikethrough = false

    public init(foreground: ConsoleColor? = nil, background: ConsoleColor? = nil, bold: Bool = false, dim: Bool = false,
                italic: Bool = false, underline: Bool = false, inverse: Bool = false, strikethrough: Bool = false) {
        self.foreground = foreground
        self.background = background
        self.bold = bold
        self.dim = dim
        self.italic = italic
        self.underline = underline
        self.inverse = inverse
        self.strikethrough = strikethrough
    }

    public static let plain = ConsoleStyle()
}

/// A piece of console text in one style.
public struct ConsoleRun: Equatable, Sendable {
    public var text: String
    public var style: ConsoleStyle

    public init(_ text: String, _ style: ConsoleStyle = .plain) {
        self.text = text
        self.style = style
    }
}

public enum ConsoleText {
    private static let escape: Unicode.Scalar = "\u{1B}"
    private static let bell: Unicode.Scalar = "\u{07}"
    /// `ESC ]` (OSC), `ESC P` (DCS), `ESC X` (SOS), `ESC ^` (PM), `ESC _` (APC): each starts a control string.
    private static let escStringIntroducers: Set<UInt32> = [0x5D, 0x50, 0x58, 0x5E, 0x5F]
    /// The one-character C1 forms of the same: DCS, SOS, OSC, PM, APC.
    private static let c1StringIntroducers: Set<UInt32> = [0x90, 0x98, 0x9D, 0x9E, 0x9F]
    /// ST, the C1 string terminator (the one-character form of `ESC \`).
    private static let stringTerminator: UInt32 = 0x9C

    /// The text without any escape or control code (only line breaks and tabs stay):
    /// what Enter, ⌘C and the clipboard target get.
    public static func plain(_ text: String) -> String {
        parse(text).map(\.text).joined()
    }

    /// Splits `text` into styled runs. SGR codes (`ESC[…m`) set the colour and style; every other
    /// escape sequence (cursor moves, erase, OSC titles and links, charset switches) and every other
    /// control character is dropped. Adjacent runs of one style are merged; empty runs are left out.
    public static func parse(_ text: String) -> [ConsoleRun] {
        var runs: [ConsoleRun] = []
        var style = ConsoleStyle.plain
        var current = String.UnicodeScalarView()
        func flush() {
            guard !current.isEmpty else { return }
            let piece = String(current)
            current = String.UnicodeScalarView()
            if let last = runs.last, last.style == style {
                runs[runs.count - 1].text += piece
            } else {
                runs.append(ConsoleRun(piece, style))
            }
        }

        let scalars = Array(text.unicodeScalars)
        var i = 0
        while i < scalars.count {
            let scalar = scalars[i]
            // A control string: OSC, DCS, SOS, PM or APC, as ESC + letter or as one C1 character.
            // Its whole payload is dropped, up to BEL, ESC \ or the C1 string terminator.
            let stringStart: Int?
            if c1StringIntroducers.contains(scalar.value) {
                stringStart = i + 1
            } else if scalar == escape, i + 1 < scalars.count, escStringIntroducers.contains(scalars[i + 1].value) {
                stringStart = i + 2
            } else {
                stringStart = nil
            }
            if let stringStart {
                var j = stringStart
                while j < scalars.count {
                    if scalars[j] == bell || scalars[j].value == stringTerminator { j += 1; break }
                    if scalars[j] == escape, j + 1 < scalars.count, scalars[j + 1] == "\\" { j += 2; break }
                    j += 1
                }
                i = j
                continue
            }
            if scalar == escape || scalar.value == 0x9B {
                // 0x9B is the one-byte CSI.
                var j = i + 1
                let isCSI: Bool
                if scalar.value == 0x9B {
                    isCSI = true
                } else if j < scalars.count, scalars[j] == "[" {
                    isCSI = true
                    j += 1
                } else {
                    isCSI = false
                }
                if isCSI {
                    // Parameter bytes 0x30–0x3F, intermediate bytes 0x20–0x2F, one final byte 0x40–0x7E.
                    let start = j
                    while j < scalars.count, (0x30...0x3F).contains(scalars[j].value) { j += 1 }
                    let parameters = String(String.UnicodeScalarView(scalars[start..<j]))
                    while j < scalars.count, (0x20...0x2F).contains(scalars[j].value) { j += 1 }
                    if j < scalars.count, (0x40...0x7E).contains(scalars[j].value) {
                        if scalars[j] == "m" {
                            flush()
                            applySGR(parameters, to: &style)
                        }
                        j += 1
                    }
                    i = j
                    continue
                }
                guard j < scalars.count else { i = j; continue }
                // ESC, intermediate bytes, one final byte (such as `ESC ( B` or `ESC 7`).
                while j < scalars.count, (0x20...0x2F).contains(scalars[j].value) { j += 1 }
                if j < scalars.count { j += 1 }
                i = j
                continue
            }
            if scalar == "\n" || scalar == "\t" {
                current.append(scalar)
            } else if scalar.value < 0x20 || scalar.value == 0x7F || (0x80...0x9F).contains(scalar.value) {
                // Other control characters (carriage return, backspace, bell) are dropped.
            } else {
                current.append(scalar)
            }
            i += 1
        }
        flush()
        return runs
    }

    private static func applySGR(_ parameters: String, to style: inout ConsoleStyle) {
        // A private sequence (`ESC[?…m`, `ESC[>…m`) is not a style.
        if let first = parameters.unicodeScalars.first, (0x3C...0x3F).contains(first.value) { return }
        let codes = parameters.split(separator: ";", omittingEmptySubsequences: false)
            .flatMap { $0.split(separator: ":", omittingEmptySubsequences: false) }
            .map { Int($0) ?? 0 }
        var k = 0
        func extended() -> ConsoleColor? {
            guard k + 1 < codes.count else { k = codes.count; return nil }
            switch codes[k + 1] {
            case 5:
                guard k + 2 < codes.count else { k = codes.count; return nil }
                let n = codes[k + 2]
                k += 2
                guard (0...255).contains(n) else { return nil }
                return n < 16 ? .basic(n) : .palette(n)
            case 2:
                guard k + 4 < codes.count else { k = codes.count; return nil }
                let parts = codes[(k + 2)...(k + 4)].map { UInt8(clamping: $0) }
                k += 4
                return .rgb(parts[0], parts[1], parts[2])
            default:
                k += 1
                return nil
            }
        }
        while k < codes.count {
            let code = codes[k]
            switch code {
            case 0: style = .plain
            case 1: style.bold = true
            case 2: style.dim = true
            case 3: style.italic = true
            case 4: style.underline = true
            case 7: style.inverse = true
            case 9: style.strikethrough = true
            case 21: style.underline = true
            case 22: style.bold = false; style.dim = false
            case 23: style.italic = false
            case 24: style.underline = false
            case 27: style.inverse = false
            case 29: style.strikethrough = false
            case 30...37: style.foreground = .basic(code - 30)
            case 38: if let color = extended() { style.foreground = color }
            case 39: style.foreground = nil
            case 40...47: style.background = .basic(code - 40)
            case 48: if let color = extended() { style.background = color }
            case 49: style.background = nil
            case 90...97: style.foreground = .basic(code - 90 + 8)
            case 100...107: style.background = .basic(code - 100 + 8)
            default: break
            }
            k += 1
        }
    }
}

// MARK: - Markdown

/// A piece of inline markdown text in one style.
public struct MarkdownSpan: Equatable, Sendable {
    public var text: String
    public var bold: Bool
    public var italic: Bool
    public var code: Bool

    public init(_ text: String, bold: Bool = false, italic: Bool = false, code: Bool = false) {
        self.text = text
        self.bold = bold
        self.italic = italic
        self.code = code
    }
}

public struct MarkdownListItem: Equatable, Sendable {
    public enum Marker: Equatable, Sendable {
        case bullet
        case number(Int)
    }

    /// 0 for a top item, 1 for an item under it, and so on.
    public var depth: Int
    public var marker: Marker
    public var spans: [MarkdownSpan]

    public init(depth: Int = 0, marker: Marker, spans: [MarkdownSpan]) {
        self.depth = depth
        self.marker = marker
        self.spans = spans
    }
}

public struct MarkdownTable: Equatable, Sendable {
    public enum Alignment: Equatable, Sendable { case left, center, right }

    /// One entry per column.
    public var alignments: [Alignment]
    /// The header cells; every cell empty means a table without a shown header.
    public var header: [[MarkdownSpan]]
    /// Every row has exactly one cell per column.
    public var rows: [[[MarkdownSpan]]]

    public init(alignments: [Alignment], header: [[MarkdownSpan]], rows: [[[MarkdownSpan]]]) {
        self.alignments = alignments
        self.header = header
        self.rows = rows
    }

    public var hasHeader: Bool {
        header.contains { cell in cell.contains { !$0.text.isEmpty } }
    }
}

public enum MarkdownBlock: Equatable, Sendable {
    case heading(level: Int, spans: [MarkdownSpan])
    /// The line breaks inside a paragraph stay: command output is line based.
    case paragraph([MarkdownSpan])
    case list([MarkdownListItem])
    case code(language: String, text: String)
    case quote([MarkdownSpan])
    case table(MarkdownTable)
    case rule
}

/// A small markdown reader for the result panel: ATX and setext headings, paragraphs, bullet and
/// numbered lists (nested by indent), fenced code blocks, block quotes, rules, GitHub tables, and inline
/// bold, italic, bold italic, code and backslash escapes. Everything else stays literal text.
public enum MarkdownText {
    public static func parse(_ text: String) -> [MarkdownBlock] {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var items: [MarkdownListItem] = []
        var quote: [String] = []

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(inline(paragraph.joined(separator: "\n"))))
            paragraph = []
        }
        func flushList() {
            guard !items.isEmpty else { return }
            blocks.append(.list(items))
            items = []
        }
        func flushQuote() {
            guard !quote.isEmpty else { return }
            blocks.append(.quote(inline(quote.joined(separator: "\n"))))
            quote = []
        }
        func flushAll() {
            flushParagraph()
            flushList()
            flushQuote()
        }

        var i = 0
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                flushAll()
                i += 1
                continue
            }
            if let fence = fence(trimmed) {
                flushAll()
                var body: [String] = []
                let indent = leadingSpaces(line)
                i += 1
                while i < lines.count {
                    let candidate = lines[i].trimmingCharacters(in: .whitespaces)
                    if candidate.hasPrefix(String(repeating: fence.char, count: fence.count)),
                       candidate.allSatisfy({ $0 == fence.char }) { i += 1; break }
                    body.append(String(lines[i].dropFirst(min(indent, leadingSpaces(lines[i])))))
                    i += 1
                }
                blocks.append(.code(language: fence.info, text: body.joined(separator: "\n")))
                continue
            }
            if let heading = atxHeading(trimmed) {
                flushAll()
                blocks.append(.heading(level: heading.level, spans: inline(heading.text)))
                i += 1
                continue
            }
            // A setext underline turns the paragraph above into a heading.
            if !paragraph.isEmpty, quote.isEmpty, items.isEmpty,
               let level = setextLevel(trimmed) {
                let title = paragraph.joined(separator: "\n")
                paragraph = []
                blocks.append(.heading(level: level, spans: inline(title)))
                i += 1
                continue
            }
            if isRule(trimmed) {
                flushAll()
                blocks.append(.rule)
                i += 1
                continue
            }
            if i + 1 < lines.count, trimmed.contains("|"),
               let alignments = delimiterRow(lines[i + 1]),
               splitRow(trimmed).count == alignments.count {
                flushAll()
                let columns = alignments.count
                let header = splitRow(trimmed).map(inline)
                var rows: [[[MarkdownSpan]]] = []
                i += 2
                while i < lines.count {
                    let row = lines[i].trimmingCharacters(in: .whitespaces)
                    guard !row.isEmpty, row.contains("|") else { break }
                    var cells = splitRow(row).map(inline)
                    if cells.count > columns { cells = Array(cells.prefix(columns)) }
                    while cells.count < columns { cells.append([]) }
                    rows.append(cells)
                    i += 1
                }
                blocks.append(.table(MarkdownTable(alignments: alignments, header: header, rows: rows)))
                continue
            }
            if trimmed.hasPrefix(">") {
                flushParagraph()
                flushList()
                var body = trimmed.dropFirst()
                if body.first == " " { body = body.dropFirst() }
                quote.append(String(body))
                i += 1
                continue
            }
            if let item = listItem(line) {
                flushParagraph()
                flushQuote()
                items.append(item)
                i += 1
                continue
            }
            if !items.isEmpty, leadingSpaces(line) >= 2 {
                // An indented line under a list item continues it.
                let last = items.count - 1
                items[last].spans += [MarkdownSpan("\n")] + inline(trimmed)
                i += 1
                continue
            }
            if !quote.isEmpty {
                quote.append(trimmed)
                i += 1
                continue
            }
            flushList()
            paragraph.append(trimmed)
            i += 1
        }
        flushAll()
        return blocks
    }

    // MARK: Blocks

    private static func leadingSpaces(_ line: String) -> Int {
        var count = 0
        for char in line {
            if char == " " { count += 1 } else if char == "\t" { count += 4 } else { break }
        }
        return count
    }

    private static func fence(_ trimmed: String) -> (char: Character, count: Int, info: String)? {
        guard let first = trimmed.first, first == "`" || first == "~" else { return nil }
        let count = trimmed.prefix { $0 == first }.count
        guard count >= 3 else { return nil }
        let info = trimmed.dropFirst(count).trimmingCharacters(in: .whitespaces)
        if first == "`", info.contains("`") { return nil }
        return (first, count, info)
    }

    private static func atxHeading(_ trimmed: String) -> (level: Int, text: String)? {
        let level = trimmed.prefix { $0 == "#" }.count
        guard (1...6).contains(level) else { return nil }
        let rest = trimmed.dropFirst(level)
        guard rest.isEmpty || rest.first == " " || rest.first == "\t" else { return nil }
        var text = rest.trimmingCharacters(in: .whitespaces)
        // A closing run of # after a space is not part of the title.
        let closing = text.reversed().prefix { $0 == "#" }.count
        if closing > 0 {
            let head = text.dropLast(closing)
            if head.isEmpty || head.last == " " { text = head.trimmingCharacters(in: .whitespaces) }
        }
        return (level, text)
    }

    private static func setextLevel(_ trimmed: String) -> Int? {
        if !trimmed.isEmpty, trimmed.allSatisfy({ $0 == "=" }) { return 1 }
        if !trimmed.isEmpty, trimmed.allSatisfy({ $0 == "-" }) { return 2 }
        return nil
    }

    private static func isRule(_ trimmed: String) -> Bool {
        let chars = trimmed.filter { $0 != " " && $0 != "\t" }
        guard let first = chars.first, "-*_".contains(first), chars.count >= 3 else { return false }
        return chars.allSatisfy { $0 == first }
    }

    private static func listItem(_ line: String) -> MarkdownListItem? {
        let depth = leadingSpaces(line) / 2
        let trimmed = line.drop { $0 == " " || $0 == "\t" }
        if let first = trimmed.first, "-*+".contains(first) {
            let rest = trimmed.dropFirst()
            guard rest.first == " " || rest.first == "\t" else { return nil }
            return MarkdownListItem(depth: depth, marker: .bullet,
                                    spans: inline(rest.trimmingCharacters(in: .whitespaces)))
        }
        let digits = trimmed.prefix { $0.isASCII && $0.isNumber }
        guard (1...9).contains(digits.count), let number = Int(digits) else { return nil }
        let rest = trimmed.dropFirst(digits.count)
        guard let mark = rest.first, mark == "." || mark == ")" else { return nil }
        let body = rest.dropFirst()
        guard body.first == " " || body.first == "\t" else { return nil }
        return MarkdownListItem(depth: depth, marker: .number(number),
                                spans: inline(body.trimmingCharacters(in: .whitespaces)))
    }

    /// The cells of a table row: the outer pipes are dropped, `\|` is a pipe inside a cell.
    private static func splitRow(_ trimmed: String) -> [String] {
        var row = Substring(trimmed)
        if row.hasPrefix("|") { row = row.dropFirst() }
        if row.hasSuffix("|"), !row.hasSuffix("\\|") { row = row.dropLast() }
        var cells: [String] = []
        var cell = ""
        var escaped = false
        for char in row {
            if escaped {
                cell.append(char == "|" ? "|" : "\\\(char)")
                escaped = false
            } else if char == "\\" {
                escaped = true
            } else if char == "|" {
                cells.append(cell.trimmingCharacters(in: .whitespaces))
                cell = ""
            } else {
                cell.append(char)
            }
        }
        if escaped { cell.append("\\") }
        cells.append(cell.trimmingCharacters(in: .whitespaces))
        return cells
    }

    private static func delimiterRow(_ line: String) -> [MarkdownTable.Alignment]? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("-") else { return nil }
        var alignments: [MarkdownTable.Alignment] = []
        for cell in splitRow(trimmed) {
            guard !cell.isEmpty else { return nil }
            let left = cell.hasPrefix(":")
            let right = cell.hasSuffix(":")
            let dashes = cell.dropFirst(left ? 1 : 0).dropLast(right && cell.count > 1 ? 1 : 0)
            guard !dashes.isEmpty, dashes.allSatisfy({ $0 == "-" }) else { return nil }
            alignments.append(left && right ? .center : right ? .right : .left)
        }
        return alignments
    }

    // MARK: Inline

    /// Inline markdown: `code`, **bold**, *italic*, ***both***, the same with underscores (not inside a
    /// word), and backslash escapes. Emphasis follows the CommonMark delimiter-run rules, so runs that
    /// close together (`**bold *italic***`) or open together (`***both** italic*`) are split between
    /// the nested pairs. A delimiter without its pair stays literal.
    public static func inline(_ text: String) -> [MarkdownSpan] {
        var tokens = tokenize(Array(text))
        let matches = matchEmphasis(&tokens)

        // How many bold and italic pairs cover each token: +1 after the opener, −1 at the closer.
        var boldDepth = [Int](repeating: 0, count: tokens.count + 1)
        var italicDepth = [Int](repeating: 0, count: tokens.count + 1)
        for match in matches {
            if match.strong {
                boldDepth[match.opener + 1] += 1
                boldDepth[match.closer] -= 1
            } else {
                italicDepth[match.opener + 1] += 1
                italicDepth[match.closer] -= 1
            }
        }
        var spans: [MarkdownSpan] = []
        var bold = 0
        var italic = 0
        for (index, token) in tokens.enumerated() {
            bold += boldDepth[index]
            italic += italicDepth[index]
            switch token.kind {
            case .text(let text):
                append(text, bold: bold > 0, italic: italic > 0, code: false, to: &spans)
            case .code(let text):
                append(text, bold: bold > 0, italic: italic > 0, code: true, to: &spans)
            case .delimiter(let char):
                // The part of the run that no pair used stays literal.
                append(String(repeating: String(char), count: token.remaining), bold: bold > 0, italic: italic > 0,
                       code: false, to: &spans)
            }
        }
        return spans
    }

    private static func append(_ text: String, bold: Bool, italic: Bool, code: Bool, to spans: inout [MarkdownSpan]) {
        guard !text.isEmpty else { return }
        if let last = spans.last, last.bold == bold, last.italic == italic, last.code == code {
            spans[spans.count - 1].text += text
        } else {
            spans.append(MarkdownSpan(text, bold: bold, italic: italic, code: code))
        }
    }

    private struct InlineToken {
        enum Kind {
            case text(String)
            case code(String)
            case delimiter(Character)
        }

        var kind: Kind
        /// For a delimiter run: its length, whether it can open and close, and how much is used.
        var count = 0
        var canOpen = false
        var canClose = false
        var used = 0

        var remaining: Int { count - used }
    }

    private struct EmphasisMatch {
        var opener: Int
        var closer: Int
        var strong: Bool
    }

    private static func tokenize(_ chars: [Character]) -> [InlineToken] {
        var tokens: [InlineToken] = []
        var literal = ""
        func flush() {
            guard !literal.isEmpty else { return }
            tokens.append(InlineToken(kind: .text(literal)))
            literal = ""
        }
        var i = 0
        while i < chars.count {
            let char = chars[i]
            if char == "\\", i + 1 < chars.count, chars[i + 1].isASCII, chars[i + 1].isPunctuation || chars[i + 1].isSymbol {
                literal.append(chars[i + 1])
                i += 2
                continue
            }
            if char == "`" {
                let count = run(of: "`", in: chars, at: i)
                if let close = closingTicks(count, in: chars, from: i + count) {
                    flush()
                    var body = String(chars[(i + count)..<close])
                    if body.count >= 2, body.first == " ", body.last == " ", body.contains(where: { $0 != " " }) {
                        body = String(body.dropFirst().dropLast())
                    }
                    tokens.append(InlineToken(kind: .code(body)))
                    i = close + count
                } else {
                    literal += String(repeating: "`", count: count)
                    i += count
                }
                continue
            }
            if char == "*" || char == "_" {
                let count = run(of: char, in: chars, at: i)
                let before: Character? = i > 0 ? chars[i - 1] : nil
                let after: Character? = i + count < chars.count ? chars[i + count] : nil
                // Flanking as in CommonMark; the start and the end of the text count as white space.
                let beforeSpace = before.map(\.isWhitespace) ?? true
                let afterSpace = after.map(\.isWhitespace) ?? true
                let beforePunct = before.map(isPunctuation) ?? false
                let afterPunct = after.map(isPunctuation) ?? false
                let left = !afterSpace && (!afterPunct || beforeSpace || beforePunct)
                let right = !beforeSpace && (!beforePunct || afterSpace || afterPunct)
                flush()
                var token = InlineToken(kind: .delimiter(char), count: count)
                if char == "*" {
                    token.canOpen = left
                    token.canClose = right
                } else {
                    token.canOpen = left && (!right || beforePunct)
                    token.canClose = right && (!left || afterPunct)
                }
                tokens.append(token)
                i += count
                continue
            }
            literal.append(char)
            i += 1
        }
        flush()
        return tokens
    }

    private static func isPunctuation(_ char: Character) -> Bool { char.isPunctuation || char.isSymbol }

    /// Pairs the delimiter runs: each closer, from the left, takes the nearest opener of its character;
    /// both give 2 characters (bold) when both have 2 left, else 1 (italic), and the closer goes on
    /// while it has characters left. The runs between a pair can no longer pair with anything outside.
    private static func matchEmphasis(_ tokens: inout [InlineToken]) -> [EmphasisMatch] {
        var stack = tokens.indices.filter { if case .delimiter = tokens[$0].kind { return true } else { return false } }
        var matches: [EmphasisMatch] = []
        var k = 0
        while k < stack.count {
            let closer = stack[k]
            guard tokens[closer].canClose, tokens[closer].remaining > 0,
                  case .delimiter(let char) = tokens[closer].kind else { k += 1; continue }
            var found: Int?
            var m = k - 1
            while m >= 0 {
                let opener = stack[m]
                if case .delimiter(let other) = tokens[opener].kind, other == char, tokens[opener].canOpen,
                   tokens[opener].remaining > 0, !breaksRuleOfThree(tokens[opener], tokens[closer]) {
                    found = m
                    break
                }
                m -= 1
            }
            guard let m = found else {
                // A run that only closes and found no opener will never be used.
                if !tokens[closer].canOpen { stack.remove(at: k) } else { k += 1 }
                continue
            }
            let opener = stack[m]
            let use = tokens[opener].remaining >= 2 && tokens[closer].remaining >= 2 ? 2 : 1
            tokens[opener].used += use
            tokens[closer].used += use
            matches.append(EmphasisMatch(opener: opener, closer: closer, strong: use == 2))
            stack.removeSubrange((m + 1)..<k)
            k = m + 1
            if tokens[opener].remaining == 0 {
                stack.remove(at: m)
                k -= 1
            }
            if tokens[closer].remaining == 0 { stack.remove(at: k) }
        }
        return matches
    }

    /// CommonMark: a run that can both open and close does not pair with one whose lengths add up to a
    /// multiple of 3, unless both lengths are multiples of 3 (so `*a**b*` stays one italic).
    private static func breaksRuleOfThree(_ opener: InlineToken, _ closer: InlineToken) -> Bool {
        guard opener.canClose || closer.canOpen else { return false }
        return (opener.count + closer.count) % 3 == 0 && !(opener.count % 3 == 0 && closer.count % 3 == 0)
    }

    private static func run(of char: Character, in chars: [Character], at index: Int) -> Int {
        var j = index
        while j < chars.count, chars[j] == char { j += 1 }
        return j - index
    }

    private static func closingTicks(_ count: Int, in chars: [Character], from start: Int) -> Int? {
        var j = start
        while j < chars.count {
            if chars[j] == "`" {
                let length = run(of: "`", in: chars, at: j)
                if length == count { return j }
                j += length
            } else {
                j += 1
            }
        }
        return nil
    }
}

extension MicroAppPanelContent {
    /// The text that Enter and ⌘C (with nothing selected) copy: the result without escape codes.
    /// Console text (and so every error) loses its ANSI codes; the other styles copy the output as it is.
    public var plainText: String {
        style == .console ? ConsoleText.plain(text) : text
    }
}
