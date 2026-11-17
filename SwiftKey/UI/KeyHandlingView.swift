import SwiftUI

struct KeyHandlingView: NSViewRepresentable {
    var onKeyDown: (String, NSEvent.ModifierFlags?) -> Void

    class KeyView: NSView {
        var onKeyDown: (String, NSEvent.ModifierFlags?) -> Void

        init(onKeyDown: @escaping (String, NSEvent.ModifierFlags?) -> Void) {
            self.onKeyDown = onKeyDown
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window = window, window.firstResponder !== self {
                window.makeFirstResponder(self)
            }
        }

        override func keyDown(with event: NSEvent) {
            switch event.keyCode {
            case 59, 62: onKeyDown("control", event.modifierFlags)
                return
            default: break
            }

            if let key = KeyTranslator.keyName(for: event) {
                onKeyDown(key, event.modifierFlags)
            }
        }
    }

    func makeNSView(context: Context) -> NSView {
        KeyView(onKeyDown: onKeyDown)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
