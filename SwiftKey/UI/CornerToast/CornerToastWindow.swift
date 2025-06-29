import Cocoa

/// A custom NSWindow subclass for the corner toast UI.
/// This window appears as a floating panel in the corner of the screen near the mouse cursor.
/// It's borderless, non-activating, and positioned above normal windows.
class CornerToastWindow: NSWindow {
    override init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask,
        backing: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: styleMask,
            backing: backing,
            defer: flag
        )
        
        configureWindow()
    }
    
    private func configureWindow() {
        isOpaque = false
        alphaValue = 1
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = NSColor.clear
        isMovable = false
        hasShadow = true
        
        collectionBehavior = [
            .fullScreenAuxiliary,
            .stationary,
            .canJoinAllSpaces,
            .ignoresCycle
        ]
        
        level = .floating
    }
    
    override var canBecomeKey: Bool {
        true
    }
    
    override var canBecomeMain: Bool {
        false
    }
    
    /// Positions the window in the appropriate corner of the screen where the mouse is located.
    /// The window appears in the top-right corner, with appropriate padding from screen edges.
    func positionInCorner() {
        // Use the screen with the mouse, or main screen as fallback
        let screen = NSScreen.screens.first(where: { NSEvent.mouseLocation.x >= $0.frame.minX && NSEvent.mouseLocation.x < $0.frame.maxX }) ?? NSScreen.main
        guard let screen = screen else { return }
        
        let padding: CGFloat = 20
        let screenFrame = screen.visibleFrame
        
        // Position in bottom-right corner
        // Account for the actual content size
        let x = screenFrame.maxX - frame.width - padding
        let y = screenFrame.minY + padding
        
        setFrameOrigin(NSPoint(x: x, y: y))
    }
    
    /// Updates the window frame to match the given size and repositions it in the corner.
    /// This is called when the SwiftUI content size changes.
    /// - Parameter size: The new size for the window content
    func updateSizeAndPosition(for size: CGSize) {
        let newFrame = NSRect(origin: frame.origin, size: size)
        setFrame(newFrame, display: true, animate: false)
        positionInCorner()
    }
}