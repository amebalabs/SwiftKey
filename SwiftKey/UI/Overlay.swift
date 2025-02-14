import AppKit
import SwiftUI

class OverlayWindow: NonActivatingPanel {
    static func makeWindow(view: some View) -> OverlayWindow {
        let overlayWindow = OverlayWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [],
            backing: .buffered,
            defer: false
        )
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

class NonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    // Ensure the panel does not activate the app when shown.
    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing bufferingType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        // Use nonactivatingPanel style.
        let nonActivatingStyle: NSWindow.StyleMask = [.nonactivatingPanel, .borderless]
        super.init(contentRect: contentRect, styleMask: nonActivatingStyle, backing: bufferingType, defer: flag)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .transient]
        backgroundColor = NSColor.clear
        isOpaque = false
    }
}
