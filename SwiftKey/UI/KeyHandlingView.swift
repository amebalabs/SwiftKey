import SwiftUI

struct KeyHandlingView: NSViewRepresentable {
    var onKeyDown: (String) -> Void
    
    class KeyView: NSView {
        var onKeyDown: (String) -> Void
        
        init(onKeyDown: @escaping (String) -> Void) {
            self.onKeyDown = onKeyDown
            super.init(frame: .zero)
        }
        
        required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }
        
        override var acceptsFirstResponder: Bool { true }
        
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window = self.window, window.firstResponder !== self {
                window.makeFirstResponder(self)
            }
        }
        
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 { onKeyDown("escape"); return }
            if event.keyCode == 126 && event.modifierFlags.contains(.command) { onKeyDown("cmd+up"); return }
            if let key = englishCharactersForKeyEvent(event: event), !key.isEmpty {
                onKeyDown(key)
            } else if let fallback = event.charactersIgnoringModifiers, !fallback.isEmpty {
                onKeyDown(fallback)
            }
        }
    }
    
    func makeNSView(context: Context) -> NSView {
        return KeyView(onKeyDown: onKeyDown)
    }
    
    func updateNSView(_ nsView: NSView, context: Context) { }
}
