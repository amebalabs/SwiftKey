import AppKit
import Carbon.HIToolbox
import Combine
import os
import SwiftKeyCore
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
    var cornerToastController: CornerToastWindowController?
    var cornerToastState: CornerToastState?
    var lastHideTime: Date?
    var statusItem: NSStatusItem?
    var facelessMenuController: FacelessMenuController?
    var defaultsObserver: AnyCancellable?
    var hotkeySubscription: AnyCancellable?
    /// Shows the panel after the "Show menu after" delay.
    private let overlayReveal = DelayedReveal()
    // Gallery window management
    private static var activeGalleryWindow: NSWindow?

    var isOverlayVisible: Bool {
        [
            overlayWindow?.isVisible == true,
            notchContext?.presented == true,
            facelessMenuController?.sessionActive == true,
            cornerToastController?.window?.isVisible == true
        ].contains(true)
    }

    func applicationDidFinishLaunching(_: Notification) {
        logger.notice("SwiftKey application starting")

        let contentView = OverlayView(state: menuState)
            .environmentObject(settings)
            .environmentObject(keyboardManager)
        overlayWindow = OverlayWindow.makeWindow(view: contentView)
        overlayWindow?.delegate = self

        setupFacelessMenuController()

        _ = SparkleUpdater.shared

        setupHotkeys()

        if settings.needsOnboarding {
            Task {
                await showOnboardingWindow()
            }
        }

        defaultsObserver = settings.settingsChanged
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
                let snippetId = notification.userInfo?["snippetId"] as? String
                Task { @MainActor in
                    await self.showGalleryWindow(preselectedSnippetId: snippetId)
                }
            }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        logger.notice("Received URL open request with \(urls.count) URLs")

        for url in urls {
            logger.info("Processing URL: \(url.absoluteString)")

            // Start a task to handle the URL
            Task {
                await deepLinkHandler.handle(url: url)
            }
        }
    }

    /// Registers the main hotkey and the item hotkeys, and keeps them in step with settings and the menu.
    @MainActor
    private func setupHotkeys() {
        LegacyHotkeyMigration.migrate(AppPaths.defaults)
        let hotkeys = container.hotkeyCenter
        hotkeys.onMainPress = { [weak self] in
            Task { await self?.toggleSession() }
        }
        hotkeys.onMainRelease = { [weak self] in
            guard let self, settings.triggerKeyHoldMode else { return }
            Task { await self.hideWindow() }
        }
        hotkeys.onItemPress = { [weak self] id in
            guard let self, let item = menuState.rootMenu.findItem(with: id) else { return }
            keyboardManager.runItemHotkey(item)
        }
        hotkeys.setMain(settings.mainHotkeyValue)
        hotkeySubscription = menuState.$rootMenu
            .receive(on: RunLoop.main)
            .sink { menu in
                MainActor.assumeIsolated {
                    hotkeys.setItems(HotkeyCenter.itemHotkeys(in: menu))
                }
            }
    }

    @MainActor
    func applySettings() async {
        container.hotkeyCenter.setMain(settings.mainHotkeyValue)

        if isOverlayVisible {
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
        if isOverlayVisible {
            logger.debug("Overlay is visible, hiding it on repeated trigger")
            await hideWindow()
            return
        }

        await configManager.refreshIfNeeded()

        switch settings.overlayStyle {
        case .faceless:
            facelessMenuController?.startSession()

        case .hud:
            setupNotchContextIfNeeded()
            notchContext?.open(revealAfter: settings.showMenuDelay)

        case .panel:
            if settings.menuStateResetDelay == 0 {
                menuState.reset()
            } else if let lastHide = lastHideTime,
                      Date().timeIntervalSince(lastHide) >= settings.menuStateResetDelay
            {
                menuState.reset()
            }
            presentOverlay(revealAfter: settings.showMenuDelay)
            
        case .cornerToast:
            setupCornerToastIfNeeded()
            cornerToastController?.show(revealAfter: settings.showMenuDelay)
        }
    }

    @MainActor
    private func setupNotchContextIfNeeded() {
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
    }
    
    @MainActor
    private func setupCornerToastIfNeeded() {
        if cornerToastController == nil {
            // Create a shared toast state
            let toastState = CornerToastState()
            self.cornerToastState = toastState
            
            let toastView = CornerToastView(state: menuState, toastState: toastState)
                .environmentObject(settings)
                .environmentObject(keyboardManager)
            
            cornerToastController = CornerToastWindowController(
                contentView: toastView,
                resetHandler: { [weak toastState] in
                    toastState?.reset()
                }
            )
        }
    }

    @MainActor
    func hideWindow() async {
        if !isOverlayVisible {
            return
        }

        // Check if gallery window is visible - if so, don't hide the overlay
        if let galleryWindow = Self.activeGalleryWindow,
           galleryWindow.isVisible,
           NSApp.keyWindow === galleryWindow
        {
            // Only skip hiding when gallery window is showing and active
            logger.debug("hideWindow: skipping hide because gallery window is active")
            return
        }

        logger.debug("hideWindow: hiding \(self.settings.overlayStyle.rawValue) overlay")
        overlayReveal.cancel()

        // Perform style-specific cleanup
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
        case .cornerToast:
            overlayWindow?.orderOut(nil)
            cornerToastController?.hide()
            menuState.reset()
        }
        if NSApp.windows.isEmpty {
            NSApp.hide(nil)
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        // Check if we should suppress overlay hiding when snippets gallery is active
        if let window = notification.object as? NSWindow,
           window === overlayWindow,
           let galleryWindow = Self.activeGalleryWindow,
           galleryWindow.isVisible,
           NSApp.keyWindow === galleryWindow
        {
            // Don't hide the overlay if it's losing focus to the gallery window
            return
        }

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

    /// Shows the panel. With a delay the panel takes keys at once but appears only after
    /// `revealAfter` seconds, and never when it closes first.
    @MainActor
    func presentOverlay(revealAfter delay: TimeInterval = 0) {
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
                        self.menuState.push(key: SequenceKey.normalize(item.key) ?? item.key, title: item.title,
                                            items: submenu)

                        // Now that the menu is loaded, present the UI
                        self.showOverlayWindow(revealAfter: delay)
                    }
                } else {
                    // Handle failure
                    await MainActor.run {
                        self.logger.error("Failed to load dynamic menu for: \(item.title, privacy: .public)")
                        self.showOverlayWindow(revealAfter: delay)
                    }
                }
            }
            return
        }

        // Regular case - show the window directly
        showOverlayWindow(revealAfter: delay)
    }

    /// Shows the overlay window positioned appropriately on screen
    @MainActor
    private func showOverlayWindow(revealAfter delay: TimeInterval = 0) {
        guard let window = overlayWindow, let screen = chosenScreen() else { return }
        let frame = window.frame
        let screenFrame = screen.visibleFrame

        let verticalAdjustment: CGFloat = 150
        let newOrigin = NSPoint(
            x: screenFrame.origin.x + (screenFrame.width - frame.width) / 2,
            y: screenFrame.origin.y + (screenFrame.height - frame.height) / 2 + verticalAdjustment
        )
        window.setFrameOrigin(newOrigin)
        // Key at once, visible only after the delay: fast typing never shows the panel.
        window.alphaValue = delay > 0 ? 0 : 1
        window.makeKeyAndOrderFront(nil)
        overlayReveal.start(after: delay) { [weak window] in
            window?.alphaValue = 1
        }
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
        .environmentObject(container.hotkeyCenter)
        window.contentView = NSHostingView(rootView: onboardingView)
        window.makeKeyAndOrderFront(nil)
    }

    @MainActor
    func showGalleryWindow(preselectedSnippetId: String? = nil) async {
        if let existingWindow = Self.activeGalleryWindow, existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }

        Self.activeGalleryWindow = nil

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SwiftKey Snippets Gallery"
        window.center()
        window.delegate = self

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

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: nil
        ) { _ in
            if Self.activeGalleryWindow === window {
                Self.activeGalleryWindow = nil
            }
        }

        Self.activeGalleryWindow = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
