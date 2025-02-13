import SwiftUI

struct KeyHandlingView: NSViewRepresentable {
    var onKeyDown: (String) -> Void

    class KeyView: NSView {
        var onKeyDown: (String) -> Void

        init(onKeyDown: @escaping (String) -> Void) {
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
            if event.keyCode == 53 { onKeyDown("escape")
                return
            }
            if event.keyCode == 126 && event.modifierFlags.contains(.command) { onKeyDown("cmd+up")
                return
            }
            switch event.keyCode {
            case 36: onKeyDown("return")
                return
            case 48: onKeyDown("tab")
                return
            case 59, 62: onKeyDown("control")
                return
            default: break
            }
            if event.modifierFlags.contains(.shift) || event.modifierFlags.contains(.option) { return }
            if let key = englishCharactersForKeyEvent(event: event), !key.isEmpty {
                onKeyDown(key.lowercased())
            } else if let fallback = event.charactersIgnoringModifiers, !fallback.isEmpty {
                onKeyDown(fallback.lowercased())
            }
        }
    }

    func makeNSView(context: Context) -> NSView {
        KeyView(onKeyDown: onKeyDown)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
