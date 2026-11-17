import Cocoa
import SwiftUI
import Combine

/// Window controller for the corner toast overlay.
/// Manages the lifecycle of the toast window and coordinates between AppKit and SwiftUI.
/// Provides methods to show/hide the toast and handles proper window setup.
class CornerToastWindowController: NSWindowController {
    private var hostingController: NSHostingController<AnyView>?
    private var sizeObserver: AnyCancellable?
    private var resetHandler: (() -> Void)?
    /// Shows the toast after the "Show menu after" delay.
    private let reveal = DelayedReveal()
    
    init(contentView: some View, resetHandler: @escaping () -> Void = {}) {
        self.resetHandler = resetHandler
        
        let window = CornerToastWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 50),
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )
        
        super.init(window: window)
        
        let hostingController = NSHostingController(rootView: AnyView(contentView))
        hostingController.view.setFrameSize(NSSize(width: 100, height: 50))
        self.hostingController = hostingController
        window.contentViewController = hostingController
        
        // Make the view size itself properly
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        if let contentView = window.contentView {
            NSLayoutConstraint.activate([
                hostingController.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                hostingController.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                hostingController.view.topAnchor.constraint(equalTo: contentView.topAnchor),
                hostingController.view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
            ])
        }
        
        // Position window after a brief delay to ensure proper sizing
        DispatchQueue.main.async {
            if let toastWindow = window as? CornerToastWindow {
                toastWindow.positionInCorner()
            }
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    /// Shows the corner toast window.
    /// Resets the view state, positions the window, and makes it visible. It takes keys at once;
    /// with `revealAfter` it appears only after that many seconds.
    @MainActor
    func show(revealAfter delay: TimeInterval = 0) {
        guard let window = window else { return }
        
        // Call reset handler to reset view state
        resetHandler?()
        
        // Reset window to initial size before showing
        window.setFrame(NSRect(x: 0, y: 0, width: 100, height: 50), display: false)
        
        // Reset window state: key at once, visible only after the delay.
        window.alphaValue = delay > 0 ? 0 : 1.0
        window.makeKeyAndOrderFront(nil)
        reveal.start(after: delay) { [weak window] in
            window?.alphaValue = 1.0
        }
        NSApp.activate(ignoringOtherApps: true)
        
        // Position immediately after reset
        DispatchQueue.main.async {
            if let toastWindow = window as? CornerToastWindow {
                toastWindow.positionInCorner()
            }
        }
    }
    
    /// Hides the corner toast window without closing it.
    /// The window remains in memory for quick re-display.
    @MainActor
    func hide() {
        reveal.cancel()
        window?.orderOut(nil)
        // Don't close the window, just hide it so it can be shown again
    }
}