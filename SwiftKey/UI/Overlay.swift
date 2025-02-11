import SwiftUI

class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    
    static func makeWindow(view: some View) -> OverlayWindow {
        let overlayWindow = OverlayWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        overlayWindow.isOpaque = false
        overlayWindow.backgroundColor = NSColor.clear
        overlayWindow.center()
        overlayWindow.level = .floating
        overlayWindow.contentView = CustomHostingView(rootView: view)
        overlayWindow.orderOut(nil)
        return overlayWindow
    }
}

class CustomHostingView<Content: View>: NSHostingView<Content> {
    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window = window, window.firstResponder !== self {
            window.makeFirstResponder(self)
        }
    }
}
