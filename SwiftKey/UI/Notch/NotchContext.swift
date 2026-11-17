import Cocoa
import Foundation
import SwiftUI

class NotchContext {
    let screen: NSScreen
    let headerLeadingView: AnyView
    let headerTrailingView: AnyView
    let bodyView: AnyView
    let animated: Bool
    private var viewModel: NotchViewModel?

    var settingsStore: SettingsStore?

    /// Shows the HUD after the "Show menu after" delay.
    private let reveal = DelayedReveal()

    /// Open, or waiting to appear: either way the HUD takes keys and must be closed.
    var presented: Bool {
        viewModel?.status == .opened || reveal.isPending
    }

    init(screen: NSScreen, headerLeadingView: AnyView, headerTrailingView: AnyView, bodyView: AnyView, animated: Bool) {
        self.screen = screen
        self.headerLeadingView = headerLeadingView
        self.headerTrailingView = headerTrailingView
        self.bodyView = bodyView
        self.animated = animated
    }

    convenience init?(
        headerLeadingView: some View,
        headerTrailingView: some View,
        bodyView: some View,
        animated: Bool = true,
        settingsStore: SettingsStore? = nil
    ) {
        let screens = NSScreen.screens
        var chosenScreen: NSScreen?

        let screenOption: SettingsStore.OverlayScreenOption

        if let settings = settingsStore {
            screenOption = settings.overlayScreenOption
        } else {
            screenOption = .primary
        }

        switch screenOption {
        case .primary:
            chosenScreen = screens.first
        case .mouse:
            let mouseLocation = NSEvent.mouseLocation
            chosenScreen = screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
        }
        guard let screen = chosenScreen ?? NSScreen.buildin else { return nil }
        self.init(
            screen: screen,
            headerLeadingView: AnyView(headerLeadingView),
            headerTrailingView: AnyView(headerTrailingView),
            bodyView: AnyView(bodyView),
            animated: animated
        )

        self.settingsStore = settingsStore
    }

    /// Opens the HUD. It takes keys at once; with `revealAfter` it stays invisible, and its open
    /// animation waits, until that many seconds have passed.
    @MainActor
    func open(forInterval interval: TimeInterval = 0, revealAfter delay: TimeInterval = 0) {
        let window = NotchWindowController(screen: screen)
        window.window?.setFrameOrigin(.zero)
        viewModel = NotchViewModel(
            screen: screen,
            headerLeadingView: headerLeadingView,
            headerTrailingView: headerTrailingView,
            bodyView: bodyView,
            animated: animated
        )
        guard let viewModel = viewModel else { return }
        let view = NotchView(vm: viewModel)
        let viewController = NotchViewController(view)
        window.contentViewController = viewController
        let shadowInset: CGFloat = 50
        let topRect = CGRect(
            x: screen.frame.origin.x,
            y: screen.frame.origin.y + screen.frame.height - viewModel.notchOpenedSize.height - shadowInset,
            width: screen.frame.width,
            height: viewModel.notchOpenedSize.height + shadowInset
        )
        window.window?.setFrameOrigin(topRect.origin)
        window.window?.setContentSize(topRect.size)
        window.window?.alphaValue = delay > 0 ? 0 : 1
        window.window?.orderFront(nil)
        window.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // The HUD body takes keys from the start, so keys typed before the reveal are not lost; it
        // is drawn, with the open animation, at the reveal, which `close()` cancels.
        viewModel.open(revealed: false)
        reveal.start(after: max(delay, 0.1)) { [weak window] in
            window?.window?.alphaValue = 1
            viewModel.reveal()
        }
        viewModel.referencedWindow = window
        guard interval > 0 else { return }
        viewModel.scheduleClose(after: interval)
    }

    @MainActor
    func close() {
        reveal.cancel()
        guard let vm = viewModel else { return }
        // Closed at once, so a press right after counts as opening the HUD again, not hiding it.
        vm.close()
        Task {
            await vm.destroy()
        }
    }
}
