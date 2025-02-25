import Cocoa
import Foundation
import SwiftUI

class NotchContext: DependencyInjectable {
    let screen: NSScreen
    let headerLeadingView: AnyView
    let headerTrailingView: AnyView
    let bodyView: AnyView
    let animated: Bool
    private var viewModel: NotchViewModel?

    // Dependencies
    var settingsStore: SettingsStore?

    var presented: Bool {
        viewModel?.status == .opened
    }

    func injectDependencies(_ container: DependencyContainer) {
        self.settingsStore = container.settingsStore
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

    func open(forInterval interval: TimeInterval = 0) {
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
        window.window?.orderFront(nil)
        window.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            window.window?.makeFirstResponder(window.window?.contentView)
            viewModel.open()
        }
        viewModel.referencedWindow = window
        guard interval > 0 else { return }
        viewModel.scheduleClose(after: interval)
    }

    func close() {
        viewModel?.destroy()
    }
}
