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
            case 36: onKeyDown("return", event.modifierFlags)
                return
            case 48: onKeyDown("tab", event.modifierFlags)
                return
            case 53: onKeyDown("escape", event.modifierFlags)
                return
            case 59, 62: onKeyDown("control", event.modifierFlags)
                return
            case 126:
                if event.modifierFlags.contains(.command) {
                    onKeyDown("cmd+up", event.modifierFlags)
                } else {
                    onKeyDown("up", event.modifierFlags)
                }
                return
            case 125:
                onKeyDown("down", event.modifierFlags)
                return
            case 123:
                onKeyDown("left", event.modifierFlags)
                return
            case 124:
                onKeyDown("right", event.modifierFlags)
                return
            default: break
            }

            if let key = englishCharactersForKeyEvent(event: event), !key.isEmpty {
                onKeyDown(key, event.modifierFlags)
            } else if let fallback = event.charactersIgnoringModifiers, !fallback.isEmpty {
                onKeyDown(fallback, event.modifierFlags)
            }
        }
    }

    func makeNSView(context: Context) -> NSView {
        KeyView(onKeyDown: onKeyDown)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
