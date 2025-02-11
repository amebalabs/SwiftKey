import Cocoa

private let notchHeight: CGFloat = 200

class NotchWindowController: NSWindowController {
    public var persistUntilExplicitDismiss: Bool = false

    init(screen: NSScreen) {
        let window = NotchWindow(
            contentRect: screen.frame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError() }

    public func dismissNotch() {
        close()
    }
}
