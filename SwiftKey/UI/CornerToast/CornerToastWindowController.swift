import Cocoa
import SwiftUI
import Combine

class CornerToastWindowController: NSWindowController {
    private var hostingController: NSHostingController<AnyView>?
    private var sizeObserver: AnyCancellable?
    private var resetHandler: (() -> Void)?
    
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
    
    func show() {
        guard let window = window else { return }
        
        // Call reset handler to reset view state
        resetHandler?()
        
        // Reset window to initial size before showing
        window.setFrame(NSRect(x: 0, y: 0, width: 100, height: 50), display: false)
        
        // Reset window state
        window.alphaValue = 1.0
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        // Position immediately after reset
        DispatchQueue.main.async {
            if let toastWindow = window as? CornerToastWindow {
                toastWindow.positionInCorner()
            }
        }
    }
    
    func hide() {
        window?.orderOut(nil)
        // Don't close the window, just hide it so it can be shown again
    }
}