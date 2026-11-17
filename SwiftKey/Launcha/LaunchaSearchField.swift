// The launcha search input: a plain NSTextField, so typing, paste, editing, any keyboard
// layout and input methods work as in every Mac text field. Only list commands
// (↑ ↓ ↩ Esc) are taken from it, and never while an input method is composing.
import AppKit
import SwiftUI

struct LaunchaSearchField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    /// Changing this value moves keyboard focus into the field.
    var focusToken: Int
    var onMove: (Int) -> Void
    var onSubmit: () -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 18)
        field.textColor = .labelColor
        field.placeholderString = placeholder
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingTail
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.allowsEditingTextAttributes = false
        field.importsGraphics = false
        field.delegate = context.coordinator
        field.setAccessibilityLabel("Search menu items, apps and files")
        field.setAccessibilityHelp("Up and down arrows choose a result. Return opens it. Command-Return shows it in Finder. Escape closes launcha.")
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        let composing = (field.currentEditor() as? NSTextView)?.hasMarkedText() == true
        if !composing, field.stringValue != text { field.stringValue = text }
        if context.coordinator.focusToken != focusToken {
            context.coordinator.focusToken = focusToken
            DispatchQueue.main.async {
                guard let window = field.window else { return }
                window.makeFirstResponder(field)
                (field.currentEditor() as? NSTextView)?.selectAll(nil)
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: LaunchaSearchField
        var focusToken: Int?

        init(_ parent: LaunchaSearchField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            // Search the committed text only; an input method sends another change on commit.
            if let editor = field.currentEditor() as? NSTextView, editor.hasMarkedText() { return }
            if parent.text != field.stringValue { parent.text = field.stringValue }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard !textView.hasMarkedText() else { return false }
            switch selector {
            case #selector(NSResponder.moveUp(_:)): parent.onMove(-1)
            case #selector(NSResponder.moveDown(_:)): parent.onMove(1)
            case #selector(NSResponder.scrollPageUp(_:)), #selector(NSResponder.pageUp(_:)): parent.onMove(-8)
            case #selector(NSResponder.scrollPageDown(_:)), #selector(NSResponder.pageDown(_:)): parent.onMove(8)
            case #selector(NSResponder.insertNewline(_:)): parent.onSubmit()
            case #selector(NSResponder.cancelOperation(_:)): parent.onCancel()
            default: return false
            }
            return true
        }
    }
}
