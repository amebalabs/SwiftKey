// The micro-app panels in SwiftKey's style: a thin-material card like launcha, with the keys that
// work at the bottom. The result text is drawn by `MicroAppOutputRenderer` in the style of `output.as`.
import AppKit
import SwiftKeyCore
import SwiftUI

struct MicroAppFlowView: View {
    let session: MicroAppFlowSession
    let onCopyAll: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            // A click beside the card works like Esc.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)
            switch session.state {
            case .closed:
                EmptyView()
            case .form:
                if let model = session.form {
                    Card(title: model.app.shownName, footer: formFooter(model.form)) {
                        MicroAppFormBody(model: model, maxHeight: session.formMaxHeight)
                    }
                    .padding(.top, 8)
                }
            case .working(let app):
                Card(title: app.shownName, footer: ["esc stop"]) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text("Running \(app.shownName)…").font(.callout)
                            Spacer()
                            if let progress = session.progress, progress.count > 1 {
                                Text(progress.label).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                        .accessibilityElement(children: .combine)
                        if let live = session.progress?.liveOutput, !live.isEmpty {
                            LiveOutput(text: live, style: app.output.style)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .padding(.top, 8)
            case .result(let content):
                Card(title: content.title, footer: ["↩ copy all and close", "⌘C copy", "esc close"]) {
                    ResultBody(content: content, onCopyAll: onCopyAll)
                }
                .padding(.top, 8)
            }
        }
    }
}

private func formFooter(_ form: MicroAppForm) -> [String] {
    if form.isSingleChoiceList { return ["↑↓ choose", "↩ run", "esc cancel"] }
    var footer = ["↩ run"]
    if form.visibleIndexes.count > 1 || form.hasOptionalToggle { footer.append("tab next") }
    if form.hasOptionalToggle { footer.append("⌘O options") }
    footer.append("esc cancel")
    return footer
}

private struct Card<Content: View>: View {
    let title: String
    let footer: [String]
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "puzzlepiece.extension")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            content.padding(.top, 12)
            Divider().padding(.top, 10)
            HStack(spacing: 14) {
                ForEach(footer, id: \.self) { Text($0) }
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 8)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .frame(width: 580)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("micro-app \(title)")
    }
}

private struct ResultBody: View {
    let content: MicroAppPanelContent
    let onCopyAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if content.isError || !content.notes.isEmpty {
                HStack(spacing: 8) {
                    if content.isError {
                        Image(systemName: "xmark.octagon.fill").foregroundStyle(Color.red)
                            .accessibilityLabel("Error")
                    }
                    ForEach(content.notes, id: \.self) { note in
                        Text(note).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            if !content.text.isEmpty {
                let rendered = MicroAppOutputRenderer.render(content)
                SelectableText(text: rendered, plainText: content.plainText, takesFocus: true)
                    .frame(height: height(rendered))
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                HStack {
                    Spacer()
                    Button("Copy All and Close", action: onCopyAll)
                        .controlSize(.small)
                }
            }
        }
    }

    /// Grows with the text, then scrolls.
    private func height(_ rendered: NSAttributedString) -> CGFloat {
        let measured: CGFloat
        if rendered.length <= 20_000 {
            measured = ceil(rendered.boundingRect(with: NSSize(width: SelectableText.textWidth, height: .greatestFiniteMagnitude),
                                                  options: [.usesLineFragmentOrigin, .usesFontLeading]).height)
        } else {
            measured = CGFloat(content.text.split(separator: "\n", omittingEmptySubsequences: false).count) * 17
        }
        return min(440, max(44, measured + 20))
    }
}

/// The output of the last step while it comes, kept scrolled to its end.
private struct LiveOutput: View {
    let text: String
    let style: MicroApp.OutputStyle

    var body: some View {
        let rendered = MicroAppOutputRenderer.render(text, style: style)
        SelectableText(text: rendered, plainText: text, takesFocus: false, followsEnd: true)
            .frame(height: height(rendered))
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
            .accessibilityLabel("output so far")
    }

    /// Grows with the text up to the height of the result panel, then scrolls.
    private func height(_ rendered: NSAttributedString) -> CGFloat {
        let measured: CGFloat
        if rendered.length <= 20_000 {
            measured = ceil(rendered.boundingRect(with: NSSize(width: SelectableText.textWidth, height: .greatestFiniteMagnitude),
                                                  options: [.usesLineFragmentOrigin, .usesFontLeading]).height)
        } else {
            measured = 440
        }
        return min(440, max(44, measured + 20))
    }
}

/// Read-only, selectable, scrolling text: ⌘C copies the selection as plain text (the whole plain
/// text when nothing is selected), ⌘A selects all.
private struct SelectableText: NSViewRepresentable {
    let text: NSAttributedString
    let plainText: String
    /// The text view becomes the first responder, so ⌘C and the arrow keys reach it at once.
    let takesFocus: Bool
    /// A new text scrolls to the end, not to the beginning: for output that grows.
    var followsEnd = false

    /// The width the text gets inside the card: the card minus its padding, the inset and the line padding.
    static let textWidth: CGFloat = 580 - 40 - 12 - 10

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        let view = PlainCopyTextView(frame: NSRect(x: 0, y: 0, width: SelectableText.textWidth, height: 0))
        view.minSize = .zero
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.isEditable = false
        view.isSelectable = true
        view.isRichText = true
        view.drawsBackground = false
        view.textContainerInset = NSSize(width: 6, height: 8)
        view.isAutomaticLinkDetectionEnabled = false
        scroll.documentView = view
        update(scroll)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        update(scroll)
    }

    private func update(_ scroll: NSScrollView) {
        guard let view = scroll.documentView as? PlainCopyTextView else { return }
        view.plainText = plainText
        if let storage = view.textStorage, !storage.isEqual(to: text) {
            storage.setAttributedString(text)
            if followsEnd { view.scrollToEndOfDocument(nil) } else { view.scrollToBeginningOfDocument(nil) }
        }
        if takesFocus {
            DispatchQueue.main.async {
                if let window = view.window, window.firstResponder !== view { window.makeFirstResponder(view) }
            }
        }
    }
}

/// Copies plain text only, never the styling: the selection as shown, or `plainText` without a selection.
private final class PlainCopyTextView: NSTextView {
    var plainText = ""

    override func copy(_ sender: Any?) {
        let range = selectedRange()
        let text = range.length == 0 ? plainText : (string as NSString).substring(with: range)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
