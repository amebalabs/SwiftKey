import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI


class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, FacelessMenuDelegate {
    static var shared: AppDelegate!
    
    var overlayWindow: NSWindow?
    var hotKeyRef: EventHotKeyRef?
    
    var facelessModeEnabled: Bool {
        UserDefaults.standard.bool(forKey: "facelessMode")
    }
    var menuStateResetDelay: TimeInterval {
        let delay = UserDefaults.standard.double(forKey: "menuStateResetDelay")
        return delay == 0 ? 3 : delay
    }
    
    var lastHideTime: Date?
    
    var statusItem: NSStatusItem?
    var facelessMenuController: FacelessMenuController?
    
    var menuState = MenuState.shared
    
    var defaultsObserver: AnyCancellable?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
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
            defer: false)
        overlayWindow?.isOpaque = false
        overlayWindow?.backgroundColor = NSColor.clear
        overlayWindow?.center()
        overlayWindow?.level = .floating
        overlayWindow?.contentView = CustomHostingView(rootView: contentView)
        overlayWindow?.delegate = self
        overlayWindow?.orderOut(nil)
        
        if facelessModeEnabled {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            if let button = statusItem?.button {
                button.title = "Menu"
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
    }
    
    func applySettings() {
        if self.facelessModeEnabled {
            if self.statusItem == nil {
                self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                if let button = self.statusItem?.button {
                    button.title = "Menu"
                    button.action = #selector(statusItemClicked)
                    button.target = self
                }
            }
            if self.facelessMenuController == nil, let statusItem = self.statusItem {
                let controller = FacelessMenuController(rootMenu: menuState.rootMenu, statusItem: statusItem, resetDelay: menuStateResetDelay)
                controller.delegate = self
                facelessMenuController = controller
            } else {
                facelessMenuController?.resetDelay = self.menuStateResetDelay
            }
        } else {
            facelessMenuController?.endSession()
            facelessMenuController = nil
            if let item = self.statusItem {
                NSStatusBar.system.removeStatusItem(item)
                self.statusItem = nil
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
        if facelessModeEnabled {
            facelessMenuController?.startSession()
        } else {
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
        overlayWindow?.orderOut(nil)
        lastHideTime = Date()
    }
    
    func windowDidResignKey(_ notification: Notification) {
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
