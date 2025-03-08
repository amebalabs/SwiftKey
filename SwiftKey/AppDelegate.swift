import AppKit
import Carbon.HIToolbox
import Combine
import KeyboardShortcuts
import os
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    // Static container for initializing new AppDelegate instances
    static var initialContainer: DependencyContainer?

    private let logger = AppLogger.app

    // Dependencies - now properly initialized in constructor
    private(set) var container: DependencyContainer
    private(set) var settings: SettingsStore
    private(set) var menuState: MenuState
    private(set) var configManager: ConfigManager
    private(set) var keyboardManager: KeyboardManager
    private(set) var deepLinkHandler: DeepLinkHandler
    private(set) var dynamicMenuLoader: DynamicMenuLoader

    override init() {
        logger.debug("AppDelegate init called")

        // Use the provided initial container if available, or create a new one
        let container = AppDelegate.initialContainer ?? DependencyContainer()
        self.container = container
        self.settings = container.settingsStore
        self.menuState = container.menuState
        self.configManager = container.configManager
        self.keyboardManager = container.keyboardManager
        self.deepLinkHandler = container.deepLinkHandler
        self.dynamicMenuLoader = container.dynamicMenuLoader

        super.init()

        // Reset the static container to avoid memory leaks
        AppDelegate.initialContainer = nil

        // Start loading the config immediately
        Task {
            logger.notice("Loading initial configuration in AppDelegate.init")
            await configManager.setupAfterDependenciesInjected()
        }
    }

    // Local state
    var overlayWindow: OverlayWindow?
    var notchContext: NotchContext?
    var lastHideTime: Date?
    var statusItem: NSStatusItem?
    var facelessMenuController: FacelessMenuController?
    var defaultsObserver: AnyCancellable?

    func applicationDidFinishLaunching(_: Notification) {
        logger.notice("SwiftKey application starting")

        let contentView = OverlayView(state: menuState)
            .environmentObject(settings)
            .environmentObject(keyboardManager)
        overlayWindow = OverlayWindow.makeWindow(view: contentView)
        overlayWindow?.delegate = self

        setupFacelessMenuController()

        _ = SparkleUpdater.shared

        KeyboardShortcuts.onKeyDown(for: .toggleApp) { [self] in
            Task {
                await toggleSession()
            }
        }

        KeyboardShortcuts.onKeyUp(for: .toggleApp) { [self] in
            if settings.triggerKeyHoldMode {
                Task {
                    await hideWindow()
                }
            }
        }

        if settings.needsOnboarding {
            Task {
                await showOnboardingWindow()
            }
        }

        defaultsObserver = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .sink { [weak self] _ in
                guard let self = self else { return }
                Task {
                    await self.applySettings()
                }
            }

        NotificationCenter.default.addObserver(forName: .hideOverlay, object: nil, queue: nil) { [weak self] _ in
            guard let self = self else { return }
            Task {
                await self.hideWindow()
            }
        }
        NotificationCenter.default
            .addObserver(forName: .presentOverlay, object: nil, queue: nil) { [weak self] _ in
                guard let self = self else { return }
                Task {
                    await self.presentOverlay()
                }
            }

        NotificationCenter.default
            .addObserver(forName: .presentGalleryWindow, object: nil, queue: nil) { [weak self] notification in
                guard let self = self else { return }

                // Extract the snippetId from the notification's userInfo
                if let snippetId = notification.userInfo?["snippetId"] as? String {
                    Task { @MainActor in
                        await self.showGalleryWindow(preselectedSnippetId: snippetId)
                    }
                }
            }
    }

    func applicationOpenUrls(_ application: NSApplication, open urls: [URL]) async {
        for url in urls {
            Task {
                await deepLinkHandler.handle(url: url)
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            Task {
                await applicationOpenUrls(application, open: [url])
            }
        }
    }

    @MainActor
    func applySettings() async {
        if overlayWindow?.isVisible == true || notchContext?.presented == true {
            logger.debug("Hiding overlay due to settings change")
            NotificationCenter.default.post(name: .hideOverlay, object: nil)
        }

        if settings.facelessMode {
            setupFacelessMenuController()
        } else {
            facelessMenuController?.endSession()
            facelessMenuController = nil
            if let item = statusItem {
                NSStatusBar.system.removeStatusItem(item)
                statusItem = nil
            }
        }
    }

    @objc func statusItemClicked() {
        Task {
            await configManager.refreshIfNeeded()

            await MainActor.run {
                if let controller = facelessMenuController {
                    if controller.sessionActive {
                        controller.endSession()
                    } else {
                        controller.startSession()
                    }
                }
            }
        }
    }

    @MainActor
    func toggleSession() async {
        await configManager.refreshIfNeeded()

        switch settings.overlayStyle {
        case .faceless:
            facelessMenuController?.endSession()
            facelessMenuController?.startSession()
        case .hud:
            if notchContext == nil {
                notchContext = NotchContext(
                    headerLeadingView: EmptyView(),
                    headerTrailingView: EmptyView(),
                    bodyView: AnyView(
                        MinimalHUDView(state: menuState)
                            .environmentObject(settings)
                            .environment(keyboardManager)
                    ),
                    animated: true,
                    settingsStore: settings
                )
            }
            if notchContext?.presented == true {
                notchContext?.close()
                return
            }
            notchContext?.open()
        case .panel:
            guard let window = overlayWindow else { return }
            if window.isVisible {
                window.orderOut(nil)
            } else {
                if settings.menuStateResetDelay == 0 {
                    menuState.reset()
                } else if let lastHide = lastHideTime,
                          Date().timeIntervalSince(lastHide) >= settings.menuStateResetDelay
                {
                    menuState.reset()
                }
                presentOverlay()
            }
        }
    }

    /// Hides any visible overlay windows
    @MainActor
    func hideWindow() async {
        // Skip hiding if menu is sticky
        guard menuState.isCurrentMenuSticky == false else { return }

        // Skip if no windows are visible (prevents unnecessary hide operations)
        let isVisible = overlayWindow?.isVisible == true || notchContext?.presented == true
        if !isVisible && settings.overlayStyle != .faceless {
            return
        }

        logger
            .debug(
                "hideWindow: hiding \(self.settings.overlayStyle.rawValue) overlay"
            )

        switch settings.overlayStyle {
        case .hud:
            overlayWindow?.orderOut(nil)
            menuState.reset()
            notchContext?.close()
        case .panel:
            overlayWindow?.orderOut(nil)
            lastHideTime = Date()
        case .faceless:
            overlayWindow?.orderOut(nil)
            facelessMenuController?.endSession()
        }
    }

    func windowDidResignKey(_: Notification) {
        Task {
            await hideWindow()
        }
    }

    @objc func applicationDidResignActive(_: Notification) {
        logger.debug("Application resigned active state")
        // Only hide windows if app is already initialized
        if overlayWindow != nil {
            Task {
                await hideWindow()
            }
        }
    }

    @MainActor
    func presentOverlay() {
        notchContext?.close()

        // Check if current menu consists of a single dynamic menu item
        if menuState.hasSingleDynamicMenuItem,
           let item = menuState.singleDynamicMenuItem
        {
            logger.debug("Detected single dynamic menu item: \(item.title, privacy: .public)")

            Task {
                // Don't show the UI yet - first load the dynamic menu
                if let submenu = await dynamicMenuLoader.loadDynamicMenu(for: item) {
                    // Update the menu state with the loaded submenu on the main actor
                    await MainActor.run {
                        self.menuState.breadcrumbs.append(item.title)
                        self.menuState.menuStack.append(submenu)

                        // Now that the menu is loaded, present the UI
                        self.showOverlayWindow()
                    }
                } else {
                    // Handle failure
                    await MainActor.run {
                        self.logger.error("Failed to load dynamic menu for: \(item.title, privacy: .public)")
                        self.showOverlayWindow()
                    }
                }
            }
            return
        }

        // Regular case - show the window directly
        showOverlayWindow()
        overlayWindow?.becomeKey()
    }

    /// Shows the overlay window positioned appropriately on screen
    @MainActor
    private func showOverlayWindow() {
        guard let window = overlayWindow, let screen = chosenScreen() else { return }
        let frame = window.frame
        let screenFrame = screen.visibleFrame

        let verticalAdjustment: CGFloat = 150
        let newOrigin = NSPoint(
            x: screenFrame.origin.x + (screenFrame.width - frame.width) / 2,
            y: screenFrame.origin.y + (screenFrame.height - frame.height) / 2 + verticalAdjustment
        )
        window.setFrameOrigin(newOrigin)
        window.makeKeyAndOrderFront(nil)
    }

    @MainActor
    func setupFacelessMenuController() {
        guard settings.facelessMode else { return }

        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            if let button = statusItem?.button {
                button.action = #selector(statusItemClicked)
                button.target = self
            }
        }

        let resetDelay = settings.menuStateResetDelay == 0 ? 2 : settings.menuStateResetDelay

        if facelessMenuController == nil, let statusItem = statusItem {
            facelessMenuController = FacelessMenuController(
                rootMenu: menuState.rootMenu,
                statusItem: statusItem,
                resetDelay: resetDelay
            )
        } else {
            facelessMenuController?.resetDelay = resetDelay
        }

        facelessMenuController?.injectDependencies(container)
    }

    private func chosenScreen() -> NSScreen? {
        let screens = NSScreen.screens
        switch settings.overlayScreenOption {
        case .primary:
            return screens.first
        case .mouse:
            let mouseLocation = NSEvent.mouseLocation
            return screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
        }
    }
}

extension AppDelegate {
    @MainActor
    func showOnboardingWindow() async {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                              styleMask: [.titled, .closable],
                              backing: .buffered,
                              defer: false)
        window.center()
        window.title = "Welcome to SwiftKey"
        let onboardingView = OnboardingView(onFinish: { [weak window, self] in
            window?.orderOut(nil)
            Task {
                await self.toggleSession()
            }
        })
        .environmentObject(settings)
        window.contentView = NSHostingView(rootView: onboardingView)
        window.makeKeyAndOrderFront(nil)
    }

    @MainActor
    func showGalleryWindow(preselectedSnippetId: String? = nil) async {
        if let existingWindow = NSApp.windows.first(where: { $0.title == "SwiftKey Snippets Gallery" }) {
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
        NSApp.activate(ignoringOtherApps: true)
    }
}
