import AppKit
import Carbon.HIToolbox
import Combine
import KeyboardShortcuts
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static var shared: AppDelegate!
    var settings = SettingsStore.shared

    var overlayWindow: OverlayWindow?
    var notchContext: NotchContext?

    var hotKeyRef: EventHotKeyRef?

    var lastHideTime: Date?

    var statusItem: NSStatusItem?
    var facelessMenuController: FacelessMenuController?

    var menuState = MenuState.shared

    var defaultsObserver: AnyCancellable?
    var hotkeyHandlers: [String: KeyboardShortcuts.Name] = [:]

    private var sparkle: SparkleUpdater?

    func applicationDidFinishLaunching(_: Notification) {
        AppDelegate.shared = self
        sparkle = SparkleUpdater.shared

        setupDefaultConfigFile()

        menuState.rootMenu = loadMenuConfig() ?? []
        registerMenuHotkeys(menuState.rootMenu)
        menuState.reset()

        let contentView = OverlayView(state: menuState).environmentObject(SettingsStore.shared)
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
                    resetDelay: settings.menuStateResetDelay == 0
                        ? 2 : settings
                        .menuStateResetDelay // TODO: in fact we should have another setting, but for now we'll just use 2 seconds
                )
            } else {
                facelessMenuController?.resetDelay = settings.menuStateResetDelay
            }
        }

        hotKeyRef = registerHotKey()
        KeyboardShortcuts.onKeyDown(for: .toggleApp) { [self] in
            toggleSession()
        }

        if settings.needsOnboarding {
            showOnboardingWindow()
        }

        defaultsObserver = NotificationCenter.default.publisher(
            for: UserDefaults.didChangeNotification
        )
        .sink { [weak self] _ in self?.applySettings() }

        NotificationCenter.default.addObserver(
            self, selector: #selector(hideWindow), name: .hideOverlay, object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidResignActive(_:)),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            DeepLinkHandler.shared.handle(url: url)
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
                    resetDelay: settings.menuStateResetDelay
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
        if let controller = facelessMenuController {
            if controller.sessionActive {
                controller.endSession()
            } else {
                controller.startSession()
            }
        }
    }

    func toggleSession() {
        if let configURL = SettingsStore.shared.configFileResolvedURL {
            if ConfigMonitor.shared.hasConfigChanged(at: configURL) {
                if let updatedMenu = loadMenuConfig() {
                    menuState.rootMenu = updatedMenu
                    registerMenuHotkeys(menuState.rootMenu)
                    print("Configuration file changed; reloaded config.")
                }
            }
        }

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
                            .environmentObject(SettingsStore.shared)
                    ),
                    animated: true
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
                window.center()
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    @objc func hideWindow() {
        guard menuState.isCurrentMenuSticky == false else { return }
        print("hideWindow triggered")
        if settings.overlayStyle == .hud {
            menuState.reset()
            notchContext?.close()
        } else {
            overlayWindow?.orderOut(nil)
            lastHideTime = Date()
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
        guard let window = overlayWindow else { return }
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(window.contentView)
    }
}

// MARK: - Hotkeys

extension AppDelegate {
    private func registerMenuHotkeys(_ menu: [MenuItem]) {
        if menu == menuState.rootMenu {
            hotkeyHandlers.removeAll()
        }
        for item in menu {
            if let hotkeyStr = item.hotkey,
               let shortcut = KeyboardShortcuts.Shortcut(hotkeyStr)
            {
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
            } //TODO: this is a place where we could do optional automagic hotkeys

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

            if let submenu = item.submenu,
               let path = findPathToMenuItem(target, in: submenu, currentPath: currentPath + [item])
            {
                return path
            }
        }

        return nil
    }
}

// MARK: - First Launch experience

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
                    } catch {
                        print("Error copying default config from bundle: \(error)")
                    }
                } else {
                    let defaultContent = "# Default menu configuration\n"
                    do {
                        try defaultContent.write(
                            to: configFileURL, atomically: true, encoding: .utf8
                        )
                    } catch {
                        print("Error writing default config file: \(error)")
                    }
                }
            }

            settings.configFilePath = configFileURL.path
            print("Default config file set to: \(configFileURL.path)")
        }
    }

    func showOnboardingWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Welcome to SwiftKey"
        let onboardingView = OnboardingView(onFinish: { [weak window, self] in
            window?.orderOut(nil)
            self.toggleSession()
        })
        window.contentView = NSHostingView(rootView: onboardingView)
        window.makeKeyAndOrderFront(nil)
    }
}
