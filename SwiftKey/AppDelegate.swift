import AppKit
import Carbon.HIToolbox
import Combine
import KeyboardShortcuts
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, DependencyInjectable {
    static var shared: AppDelegate!

    // Dependencies (will be injected)
    var container: DependencyContainer!
    var settings: SettingsStore!
    var menuState: MenuState!
    var configManager: ConfigManager!
    var deepLinkHandler: DeepLinkHandler!

    // Local state
    var overlayWindow: OverlayWindow?
    var notchContext: NotchContext?
    var hotKeyRef: EventHotKeyRef?
    var lastHideTime: Date?
    var statusItem: NSStatusItem?
    var facelessMenuController: FacelessMenuController?
    var defaultsObserver: AnyCancellable?
    var hotkeyHandlers: [String: KeyboardShortcuts.Name] = [:]
    private var sparkle: SparkleUpdater?

    func injectDependencies(_ container: DependencyContainer) {
        self.container = container
        self.settings = container.settingsStore
        self.menuState = container.menuState
        self.configManager = container.configManager
        self.deepLinkHandler = container.deepLinkHandler
    }

    func applicationDidFinishLaunching(_: Notification) {
        AppDelegate.shared = self
        sparkle = SparkleUpdater.shared

        // Set up dependency container
        let container = DependencyContainer.shared
        injectDependencies(container)

        setupDefaultConfigFile()

        // Register hotkeys based on initial menu state
        registerMenuHotkeys(menuState.rootMenu)
        menuState.reset()

        let contentView = OverlayView(state: menuState).environmentObject(settings)
        overlayWindow = OverlayWindow.makeWindow(view: contentView)
        overlayWindow?.delegate = self

        if settings.facelessMode {
            if statusItem == nil {
                statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                if let button = statusItem?.button {
                    button.action = #selector(statusItemClicked)
                    button.target = self
                }
            }
            if facelessMenuController == nil, let statusItem = statusItem {
                facelessMenuController = FacelessMenuController(
                    rootMenu: menuState.rootMenu,
                    statusItem: statusItem,
                    resetDelay: settings.menuStateResetDelay == 0 ? 2 : settings.menuStateResetDelay,
                    menuState: menuState,
                    settingsStore: settings
                )
            } else {
                facelessMenuController?.resetDelay = settings.menuStateResetDelay
            }
        }

        hotKeyRef = registerHotKey()
        KeyboardShortcuts.onKeyDown(for: .toggleApp) { [self] in
            toggleSession()
        }
        KeyboardShortcuts.onKeyUp(for: .toggleApp) { [self] in
            if settings.triggerKeyHoldMode {
                hideWindow()
            }
        }

        if settings.needsOnboarding {
            showOnboardingWindow()
        }

        defaultsObserver = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .sink { [weak self] _ in self?.applySettings() }

        NotificationCenter.default.addObserver(self, selector: #selector(hideWindow), name: .hideOverlay, object: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidResignActive(_:)),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            deepLinkHandler.handle(url: url)
        }
    }

    func applySettings() {
        NotificationCenter.default.post(name: .hideOverlay, object: nil)
        if settings.facelessMode {
            if statusItem == nil {
                statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                if let button = statusItem?.button {
                    button.action = #selector(statusItemClicked)
                    button.target = self
                }
            }
            if facelessMenuController == nil, let statusItem = statusItem {
                let controller = FacelessMenuController(
                    rootMenu: menuState.rootMenu,
                    statusItem: statusItem,
                    resetDelay: settings.menuStateResetDelay, menuState: menuState
                )
                facelessMenuController = controller
            } else {
                facelessMenuController?.resetDelay = settings.menuStateResetDelay
            }
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
        configManager.refreshIfNeeded()

        if let controller = facelessMenuController {
            if controller.sessionActive {
                controller.endSession()
            } else {
                controller.startSession()
            }
        }
    }

    func toggleSession() {
        configManager.refreshIfNeeded()

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
                        MinimalHUDView(state: self.menuState)
                            .environmentObject(settings)
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

    @objc func hideWindow() {
        guard menuState.isCurrentMenuSticky == false else { return }
        print("hideWindow triggered")
        switch settings.overlayStyle {
        case .hud:
            menuState.reset()
            notchContext?.close()
        case .panel:
            overlayWindow?.orderOut(nil)
            lastHideTime = Date()
        case .faceless:
            facelessMenuController?.endSession()
        }
    }

    func windowDidResignKey(_: Notification) {
        hideWindow()
    }

    @objc func applicationDidResignActive(_: Notification) {
        print("Resign active")
        hideWindow()
    }

    func presentOverlay() {
        notchContext?.close()
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
    private func registerMenuHotkeys(_ menu: [MenuItem]) {
        if menu == menuState.rootMenu {
            hotkeyHandlers.removeAll()
        }
        for item in menu {
            if let hotkeyStr = item.hotkey, let shortcut = KeyboardShortcuts.Shortcut(hotkeyStr) {
                let name = KeyboardShortcuts.Name(item.id.uuidString)
                KeyboardShortcuts.setShortcut(shortcut, for: name)
                KeyboardShortcuts.onKeyDown(for: name) { [weak self] in
                    guard let self = self else { return }
                    if item.submenu != nil {
                        DispatchQueue.main.async {
                            self.navigateToMenuItem(item)
                        }
                    } else if let action = item.actionClosure {
                        DispatchQueue.global(qos: .userInitiated).async {
                            action()
                        }
                    }
                }
                hotkeyHandlers[item.id.uuidString] = name
            }
            if let submenu = item.submenu {
                registerMenuHotkeys(submenu)
            }
        }
    }

    private func navigateToMenuItem(_ item: MenuItem) {
        menuState.reset()
        if let path = findPathToMenuItem(item, in: menuState.rootMenu) {
            for (index, menuItem) in path.enumerated() {
                if index < path.count {
                    menuState.breadcrumbs.append(menuItem.title)
                    if let submenu = menuItem.submenu {
                        menuState.menuStack.append(submenu)
                    }
                }
            }
            overlayWindow?.orderOut(nil)
            overlayWindow?.center()
            overlayWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func findPathToMenuItem(
        _ target: MenuItem,
        in menu: [MenuItem],
        currentPath: [MenuItem] = []
    ) -> [MenuItem]? {
        for item in menu {
            if item.id == target.id {
                return currentPath + [item]
            }
            if let submenu = item.submenu, let path = findPathToMenuItem(
                target,
                in: submenu,
                currentPath: currentPath + [item]
            ) {
                return path
            }
        }
        return nil
    }
}

extension AppDelegate {
    func setupDefaultConfigFile() {
        guard settings.configFilePath.isEmpty else { return }

        let fileManager = FileManager.default
        if let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            let configFileURL = documentsURL.appendingPathComponent("menu.yaml")

            if !fileManager.fileExists(atPath: configFileURL.path) {
                if let bundleConfigURL = Bundle.main.url(forResource: "menu", withExtension: "yaml") {
                    do {
                        try fileManager.copyItem(at: bundleConfigURL, to: configFileURL)
                        print("Copied default config from bundle")
                    } catch {
                        print("Error copying default config from bundle: \(error)")
                    }
                } else {
                    let defaultContent = "# Default menu configuration\n"
                    do {
                        try defaultContent.write(to: configFileURL, atomically: true, encoding: .utf8)
                        print("Created empty default config file")
                    } catch {
                        print("Error writing default config file: \(error)")
                    }
                }
            }

            settings.configFilePath = configFileURL.path
            settings.configFileBookmark = try? configFileURL.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )

            print("Default config file set to: \(configFileURL.path)")
        }
    }

    func showOnboardingWindow() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                              styleMask: [.titled, .closable],
                              backing: .buffered,
                              defer: false)
        window.center()
        window.title = "Welcome to SwiftKey"
        let onboardingView = OnboardingView(onFinish: { [weak window, self] in
            window?.orderOut(nil)
            self.toggleSession()
        })
        .environmentObject(settings)
        window.contentView = NSHostingView(rootView: onboardingView)
        window.makeKeyAndOrderFront(nil)
    }
}
