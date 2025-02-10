import AppKit
import Carbon.HIToolbox
import Combine
import DynamicNotchKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, FacelessMenuDelegate {
    static var shared: AppDelegate!
    var settings = SettingsStore.shared

    var overlayWindow: NSWindow?
    var hudNotch: DynamicNotch<AnyView>?

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
        overlayWindow = OverlayWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        overlayWindow?.isOpaque = false
        overlayWindow?.backgroundColor = NSColor.clear
        overlayWindow?.center()
        overlayWindow?.level = .floating
        overlayWindow?.contentView = CustomHostingView(rootView: contentView)
        overlayWindow?.delegate = self
        overlayWindow?.orderOut(nil)

        if settings.facelessMode {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            if let button = statusItem?.button {
                button.action = #selector(statusItemClicked)
                button.target = self
            }
            if let statusItem = statusItem {
                let controller = FacelessMenuController(rootMenu: menuState.rootMenu, statusItem: statusItem, resetDelay: menuStateResetDelay)
                controller.delegate = self
                facelessMenuController = controller
            }
        }

        hotKeyRef = registerHotKey()

        defaultsObserver = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .sink { [weak self] _ in self?.applySettings() }

        NotificationCenter.default.addObserver(self, selector: #selector(hideWindow), name: .hideOverlay, object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(applicationDidResignActive(_:)),
                                               name: NSApplication.didResignActiveNotification,
                                               object: nil)
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
                let controller = FacelessMenuController(rootMenu: menuState.rootMenu, statusItem: statusItem, resetDelay: menuStateResetDelay)
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
            guard hudNotch == nil else { return }
            hudNotch = DynamicNotch<AnyView> { [unowned self] in
                AnyView(
                    MinimalHUDView(state: self.menuState)
                        .environmentObject(self.settings)
                )
            }
            hudNotch?.show(for: 0)
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
        if settings.overlayStyle == .hud {
            hudNotch?.hide(ignoreMouse: true)
            hudNotch = nil
        } else {
            overlayWindow?.orderOut(nil)
            lastHideTime = Date()
        }
    }

    func windowDidResignKey(_: Notification) {
        hideWindow()
    }

    @objc func applicationDidResignActive(_: Notification) {
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
