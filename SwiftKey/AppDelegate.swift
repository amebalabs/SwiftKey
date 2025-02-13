import AppKit
import Carbon.HIToolbox
import Combine
import DynamicNotchKit
import KeyboardShortcuts
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, FacelessMenuDelegate {
    static var shared: AppDelegate!
    var settings = SettingsStore.shared

    var overlayWindow: OverlayWindow?
    var notchHUD: DynamicNotch<AnyView>?
    var notchContext: NotchContext?

    var hotKeyRef: EventHotKeyRef?

    var menuStateResetDelay: TimeInterval {
        let delay = UserDefaults.standard.double(forKey: "menuStateResetDelay")
        return delay == 0 ? 3 : delay
    }

    var lastHideTime: Date?

    var statusItem: NSStatusItem?
    var facelessMenuController: FacelessMenuController?

    var menuState = MenuState.shared

    var defaultsObserver: AnyCancellable?

    func applicationDidFinishLaunching(_: Notification) {
        AppDelegate.shared = self

        if let customPath = SettingsStore.shared.configDirectoryResolvedPath {
            let configURL = URL(fileURLWithPath: customPath).appendingPathComponent("menu.yaml")
            _ = ConfigWatcher(url: configURL) { [weak self] in
                guard let self = self else { return }
                if let updatedMenu = loadMenuConfig() {
                    self.menuState.rootMenu = updatedMenu
                    print("Menu config reloaded!")
                }
            }
        }

        menuState.rootMenu = loadMenuConfig() ?? []
        menuState.reset()

        let contentView = OverlayView(state: menuState).environmentObject(SettingsStore.shared)
        overlayWindow = OverlayWindow.makeWindow(view: contentView)
        overlayWindow?.delegate = self

        if settings.facelessMode {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            if let button = statusItem?.button {
                button.action = #selector(statusItemClicked)
                button.target = self
            }
            if let statusItem = statusItem {
                let controller = FacelessMenuController(
                    rootMenu: menuState.rootMenu,
                    statusItem: statusItem,
                    resetDelay: menuStateResetDelay
                )
                controller.delegate = self
                facelessMenuController = controller
            }
        }

//        hotKeyRef = registerHotKey()
        KeyboardShortcuts.onKeyDown(for: .toggleApp) { [self] in
            toggleSession()
        }

        defaultsObserver = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .sink { [weak self] _ in self?.applySettings() }

        NotificationCenter.default.addObserver(self, selector: #selector(hideWindow), name: .hideOverlay, object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(applicationDidResignActive(_:)),
                                               name: NSApplication.didResignActiveNotification,
                                               object: nil)
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
                    resetDelay: menuStateResetDelay
                )
                controller.delegate = self
                facelessMenuController = controller
            } else {
                facelessMenuController?.resetDelay = menuStateResetDelay
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
        switch settings.overlayStyle {
        case .faceless:
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
//                if notchHUD == nil {
//                    notchHUD = DynamicNotch<AnyView> {
//                        AnyView(
//                            MinimalHUDView(state: self.menuState)
//                                .environmentObject(SettingsStore.shared)
//                        )
//                    }
//                }

            notchHUD?.show(for: 0)
            notchContext?.open()
            NSApp.activate(ignoringOtherApps: true)
        case .panel:
            guard let window = overlayWindow else { return }
            if window.isVisible {
                window.orderOut(nil)
            } else {
                if menuStateResetDelay == 0 {
                    NotificationCenter.default.post(name: .resetMenuState, object: nil)
                } else if let lastHide = lastHideTime, Date().timeIntervalSince(lastHide) >= menuStateResetDelay {
                    NotificationCenter.default.post(name: .resetMenuState, object: nil)
                }
                window.center()
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    @objc func hideWindow() {
        print("hideWindow triggered")
        if settings.overlayStyle == .hud {
            notchHUD?.hide()
            menuState.reset()
            notchContext?.close()
        } else {
            overlayWindow?.orderOut(nil)
            lastHideTime = Date()
        }
    }

    func windowDidResignKey(_: Notification) {
//        hideWindow()
    }

    @objc func applicationDidResignActive(_: Notification) {
        print("Resign active")
        hideWindow()
    }

    // MARK: - FacelessMenuDelegate

    func facelessMenuControllerDidRequestOverlayCheatsheet(_ controller: FacelessMenuController) {
        menuState.menuStack = controller.menuStack
        menuState.breadcrumbs = controller.breadcrumbs
        controller.endSession()
        overlayWindow?.center()
        overlayWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // Slight delay to ensure the overlay's content becomes first responder.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.overlayWindow?.makeFirstResponder(self.overlayWindow?.contentView)
        }
    }
}
