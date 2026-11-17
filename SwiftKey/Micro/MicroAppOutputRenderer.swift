// Draws the result panel text in the style of `output.as`, from the neutral model of SwiftKeyCore,
// with the system label colours. `markdown`: formatted text, tables as aligned columns; `console`: monospaced
// with ANSI colours; `text`: plain; `code`: monospaced. An error is always console text.
import AppKit
import SwiftKeyCore

enum MicroAppOutputRenderer {
    static let bodySize: CGFloat = 13
    static let monoSize: CGFloat = 12
    /// The space between two table columns.
    static let columnGap: CGFloat = 18

    static var ink: NSColor { .labelColor }
    static var muted: NSColor { .secondaryLabelColor }
    static var codeBackground: NSColor { ink.withAlphaComponent(0.08) }

    static func render(_ content: MicroAppPanelContent) -> NSAttributedString {
        render(content.text, style: content.isError ? .console : content.style)
    }

    static func render(_ text: String, style: MicroApp.OutputStyle) -> NSAttributedString {
        switch style {
        case .text: plain(text, font: .systemFont(ofSize: bodySize))
        case .code: plain(text, font: mono())
        case .console: console(text)
        case .markdown: markdown(text)
        }
    }

    private static func mono(_ weight: NSFont.Weight = .regular) -> NSFont {
        .monospacedSystemFont(ofSize: monoSize, weight: weight)
    }

    private static func plain(_ text: String, font: NSFont) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: ink])
    }

    // MARK: Console

    static func console(_ text: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for run in ConsoleText.parse(text) {
            let style = run.style
            var foreground = style.foreground.map(NSColor.console) ?? ink
            var background = style.background.map(NSColor.console)
            if style.inverse {
                let swapped = background ?? NSColor.textBackgroundColor
                background = foreground
                foreground = swapped
            }
            if style.dim { foreground = foreground.withAlphaComponent(0.6) }
            var font = mono(style.bold ? .bold : .regular)
            if style.italic { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
            var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: foreground]
            if let background { attributes[.backgroundColor] = background }
            if style.underline { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            if style.strikethrough { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            result.append(NSAttributedString(string: run.text, attributes: attributes))
        }
        return result
    }

    // MARK: Markdown

    static func markdown(_ text: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let blocks = MarkdownText.parse(text)
        for (index, block) in blocks.enumerated() {
            let isLast = index == blocks.count - 1
            let piece = NSMutableAttributedString()
            switch block {
            case .heading(let level, let spans):
                let sizes: [CGFloat] = [20, 17, 15, 14, 13, 13]
                piece.append(spansString(spans, size: sizes[min(level, 6) - 1], weight: .bold))
                piece.addAttribute(.paragraphStyle, value: paragraph(spacing: 6, before: index == 0 ? 0 : 6),
                                   range: NSRange(location: 0, length: piece.length))
            case .paragraph(let spans):
                piece.append(spansString(spans))
                piece.addAttribute(.paragraphStyle, value: paragraph(spacing: 8), range: NSRange(location: 0, length: piece.length))
            case .quote(let spans):
                piece.append(spansString(spans, color: muted))
                let style = paragraph(spacing: 8)
                style.firstLineHeadIndent = 14
                style.headIndent = 14
                piece.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: piece.length))
            case .list(let items):
                for (itemIndex, item) in items.enumerated() {
                    let marker: String
                    switch item.marker {
                    case .bullet: marker = item.depth % 2 == 0 ? "•" : "◦"
                    case .number(let n): marker = "\(n)."
                    }
                    let indent = CGFloat(item.depth) * 18
                    let line = NSMutableAttributedString(string: "\t\(marker)\t",
                                                         attributes: [.font: NSFont.systemFont(ofSize: bodySize), .foregroundColor: muted])
                    line.append(spansString(item.spans))
                    if itemIndex < items.count - 1 { line.append(NSAttributedString(string: "\n")) }
                    let style = paragraph(spacing: itemIndex == items.count - 1 ? 8 : 2)
                    style.tabStops = [NSTextTab(textAlignment: .right, location: indent + 14),
                                      NSTextTab(textAlignment: .left, location: indent + 22)]
                    style.headIndent = indent + 22
                    line.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: line.length))
                    piece.append(line)
                }
            case .code(_, let code):
                piece.append(NSAttributedString(string: code, attributes: [.font: mono(), .foregroundColor: ink,
                                                                            .backgroundColor: codeBackground]))
                piece.addAttribute(.paragraphStyle, value: paragraph(spacing: 8), range: NSRange(location: 0, length: piece.length))
            case .table(let table):
                piece.append(tableString(table))
            case .rule:
                piece.append(NSAttributedString(string: String(repeating: "─", count: 40),
                                                attributes: [.font: NSFont.systemFont(ofSize: 9), .foregroundColor: muted,
                                                             .paragraphStyle: paragraph(spacing: 8)]))
            }
            if !isLast { piece.append(NSAttributedString(string: "\n", attributes: [.font: NSFont.systemFont(ofSize: bodySize)])) }
            result.append(piece)
        }
        return result
    }

    private static func paragraph(spacing: CGFloat, before: CGFloat = 0) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = spacing
        style.paragraphSpacingBefore = before
        return style
    }

    static func spansString(_ spans: [MarkdownSpan], size: CGFloat = bodySize, weight: NSFont.Weight = .regular,
                            color: NSColor? = nil) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for span in spans {
            var attributes: [NSAttributedString.Key: Any] = [.foregroundColor: color ?? ink]
            if span.code {
                let base = NSFont.monospacedSystemFont(ofSize: max(10, size - 1), weight: span.bold ? .bold : weight)
                attributes[.font] = span.italic ? NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask) : base
                attributes[.backgroundColor] = codeBackground
            } else {
                var font = NSFont.systemFont(ofSize: size, weight: span.bold ? .bold : weight)
                if span.italic { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
                attributes[.font] = font
            }
            result.append(NSAttributedString(string: span.text, attributes: attributes))
        }
        return result
    }

    /// A table as aligned columns: one line per row, the cells separated by tabs, and tab stops at the
    /// measured column widths (right and centre aligned columns get right and centre tab stops).
    static func tableString(_ table: MarkdownTable) -> NSAttributedString {
        var rows: [[NSAttributedString]] = []
        if table.hasHeader { rows.append(table.header.map { spansString($0, weight: .semibold) }) }
        rows += table.rows.map { $0.map { spansString($0) } }
        let columns = table.alignments.count
        var widths = [CGFloat](repeating: 0, count: columns)
        for row in rows {
            for (column, cell) in row.enumerated() where column < columns {
                widths[column] = max(widths[column], ceil(cell.size().width))
            }
        }
        var tabs: [NSTextTab] = []
        // A tab stop at 0 would be skipped: the columns start a little to the right.
        var x: CGFloat = 4
        for column in 0..<columns {
            let width = widths[column]
            switch table.alignments[column] {
            case .left: tabs.append(NSTextTab(textAlignment: .left, location: x))
            case .right: tabs.append(NSTextTab(textAlignment: .right, location: x + width))
            case .center: tabs.append(NSTextTab(textAlignment: .center, location: x + width / 2))
            }
            x += width + columnGap
        }
        let result = NSMutableAttributedString()
        for (index, row) in rows.enumerated() {
            let line = NSMutableAttributedString()
            for cell in row {
                // A tab before every cell moves it to its column's tab stop.
                line.append(NSAttributedString(string: "\t", attributes: [.font: NSFont.systemFont(ofSize: bodySize)]))
                line.append(cell)
            }
            if index < rows.count - 1 { line.append(NSAttributedString(string: "\n")) }
            let style = paragraph(spacing: index == rows.count - 1 ? 8 : 3)
            style.tabStops = tabs
            style.defaultTabInterval = 0
            style.lineBreakMode = .byClipping
            line.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: line.length))
            result.append(line)
        }
        return result
    }
}

extension NSColor {
    /// The 16 basic terminal colours: readable on the light and the dark panel.
    private static let consoleBasic: [(light: UInt32, dark: UInt32)] = [
        (0x222A2E, 0x6B767C), // black
        (0xB3261E, 0xE57373), // red
        (0x2E7D32, 0x8FC97A), // green
        (0x885500, 0xE7BB74), // yellow
        (0x1F5FA8, 0x6FA8DC), // blue
        (0x8E3A9E, 0xC792D9), // magenta
        (0x00727A, 0x6CC4C4), // cyan
        (0x8A9296, 0xD5DAD6), // white
        (0x59666C, 0x95A0A5), // bright black
        (0xD3392F, 0xFF8A80), // bright red
        (0x3D9A41, 0xB5E39F), // bright green
        (0xA86C00, 0xF5D49A), // bright yellow
        (0x2F7BD0, 0x9CC6F0), // bright blue
        (0xA84DBA, 0xDDB3EB), // bright magenta
        (0x008C96, 0x96E0E0), // bright cyan
        (0x6B767C, 0xFFFFFF), // bright white
    ]

    static func console(_ color: ConsoleColor) -> NSColor {
        switch color {
        case .basic(let n):
            let pair = consoleBasic[max(0, min(15, n))]
            return .appearance(light: pair.light, dark: pair.dark)
        case .palette(let n):
            if n >= 232 {
                let level = CGFloat(8 + (n - 232) * 10) / 255
                return NSColor(srgbRed: level, green: level, blue: level, alpha: 1)
            }
            let cube = max(0, n - 16)
            let steps: [CGFloat] = [0, 95, 135, 175, 215, 255]
            return NSColor(srgbRed: steps[(cube / 36) % 6] / 255, green: steps[(cube / 6) % 6] / 255,
                           blue: steps[cube % 6] / 255, alpha: 1)
        case .rgb(let r, let g, let b):
            return NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
        }
    }
}

private extension NSColor {
    /// A colour that follows the light or dark appearance it is drawn in.
    static func appearance(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
    }
}
