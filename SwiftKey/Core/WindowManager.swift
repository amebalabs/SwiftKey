import AppKit
import SwiftUI

/// Manages all application windows (overlay, settings, gallery, onboarding)
@MainActor
final class WindowManager: ObservableObject {

    // MARK: - Window References

    private(set) var overlayWindow: OverlayWindow?
    private var settingsWindow: NSWindow?
    private var galleryWindow: NSWindow?
    private var onboardingWindow: NSWindow?

    // MARK: - State

    @Published private(set) var lastHideTime: Date?
    private weak var windowDelegate: NSWindowDelegate?

    // MARK: - Dependencies

    private let container: DependencyContainer

    init(container: DependencyContainer, windowDelegate: NSWindowDelegate? = nil) {
        self.container = container
        self.windowDelegate = windowDelegate
    }

    // MARK: - Overlay Window

    func createOverlayWindow() {
        guard overlayWindow == nil else { return }

        let contentView = OverlayView(state: container.menuState)
            .environmentObject(container.settingsStore)
            .environmentObject(container.keyboardManager)

        overlayWindow = OverlayWindow.makeWindow(view: contentView)
        overlayWindow?.delegate = windowDelegate
    }

    func showOverlay(on screen: NSScreen? = nil) {
        guard let window = overlayWindow else { return }
        let targetScreen = screen ?? NSScreen.main
        guard let screenFrame = targetScreen?.visibleFrame else { return }

        let frame = window.frame
        let verticalAdjustment: CGFloat = 150

        let newOrigin = NSPoint(
            x: screenFrame.origin.x + (screenFrame.width - frame.width) / 2,
            y: screenFrame.origin.y + (screenFrame.height - frame.height) / 2 + verticalAdjustment
        )

        window.setFrameOrigin(newOrigin)
        window.makeKeyAndOrderFront(nil)
    }

    func hideOverlay() {
        overlayWindow?.orderOut(nil)
        lastHideTime = Date()
    }

    var isOverlayVisible: Bool {
        overlayWindow?.isVisible == true
    }

    // MARK: - Settings Window

    func showSettings() {
        if let existingWindow = settingsWindow, existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        let contentView = SettingsView()
            .environmentObject(container.settingsStore)
            .environmentObject(container.configManager)

        window.contentView = NSHostingView(rootView: contentView)
        window.title = "Settings"
        window.center()
        window.makeKeyAndOrderFront(nil)

        settingsWindow = window
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Gallery Window

    func showGallery(preselectedSnippetId: String? = nil) {
        if let existingWindow = galleryWindow, existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "SwiftKey Snippets Gallery"
        window.center()
        window.delegate = windowDelegate

        let viewModel = SnippetsGalleryViewModel(
            snippetsStore: container.snippetsStore,
            preselectedSnippetId: preselectedSnippetId
        )

        let hostingController = NSHostingController(
            rootView: SnippetsGalleryView(viewModel: viewModel)
                .environmentObject(container.configManager)
                .environmentObject(container.settingsStore)
        )

        window.contentViewController = hostingController
        window.makeKeyAndOrderFront(nil)

        galleryWindow = window
        NSApp.activate(ignoringOtherApps: true)
    }

    var isGalleryVisible: Bool {
        galleryWindow?.isVisible == true
    }

    var isGalleryKeyWindow: Bool {
        galleryWindow != nil && NSApp.keyWindow === galleryWindow
    }

    // MARK: - Onboarding Window

    func showOnboarding(onFinish: @escaping () -> Void) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        window.center()
        window.title = "Welcome to SwiftKey"

        let onboardingView = OnboardingView(onFinish: { [weak window] in
            window?.orderOut(nil)
            onFinish()
        })
        .environmentObject(container.settingsStore)
        .environmentObject(container.hotkeyCenter)

        window.contentView = NSHostingView(rootView: onboardingView)
        window.makeKeyAndOrderFront(nil)

        onboardingWindow = window
    }

    // MARK: - Utility

    func chosenScreen(for option: SettingsStore.OverlayScreenOption) -> NSScreen? {
        let screens = NSScreen.screens
        switch option {
        case .primary:
            return screens.first
        case .mouse:
            let mouseLocation = NSEvent.mouseLocation
            return screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
        }
    }

    func hideAllWindows() {
        overlayWindow?.orderOut(nil)
        settingsWindow?.orderOut(nil)
        galleryWindow?.orderOut(nil)
        onboardingWindow?.orderOut(nil)
    }
}
