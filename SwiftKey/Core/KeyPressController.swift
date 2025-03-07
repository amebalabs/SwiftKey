import Foundation
import os
import SwiftUI
import Yams

enum KeyPressResult: Equatable {
    case escape
    case help
    case up
    case submenuPushed(title: String)
    case actionExecuted
    case dynamicLoading
    case error(key: String)
    case none
}

class KeyPressController: DependencyInjectable {
    private let logger = AppLogger.keyboard

    var menuState: MenuState
    var settingsStore: SettingsStore?

    init(menuState: MenuState, settingsStore: SettingsStore? = nil) {
        self.menuState = menuState
        self.settingsStore = settingsStore
    }

    func injectDependencies(_ container: DependencyContainer) {
        self.settingsStore = container.settingsStore
    }

    func handleKey(_ key: String, modifierFlags: NSEvent.ModifierFlags? = nil) async -> KeyPressResult {
        logger.debug("Key pressed: \(key, privacy: .public)")
        let normalizedKey = key

        // Update UI state on main actor
        await MainActor.run {
            menuState.currentKey = normalizedKey
        }

        // Handle common navigation keys
        if normalizedKey == "escape" {
            return .escape
        }
        if normalizedKey == "cmd+up" {
            await MainActor.run {
                if !menuState.menuStack.isEmpty { menuState.menuStack.removeLast() }
                if !menuState.breadcrumbs.isEmpty { menuState.breadcrumbs.removeLast() }
            }
            return .up
        }
        if normalizedKey == "?" {
            return .help
        }

        // Find matching menu item
        let matchingItem = await MainActor.run {
            menuState.currentMenu.first(where: { $0.key == normalizedKey })
        }

        guard let item = matchingItem else {
            return .error(key: key)
        }

        // Handle dynamic menus
        if let actionString = item.action, actionString.hasPrefix("dynamic://") {
            if let submenu = await DynamicMenuLoader.shared.loadDynamicMenu(for: item) {
                await MainActor.run {
                    menuState.breadcrumbs.append(item.title)
                    menuState.menuStack.append(submenu)
                }
                return .submenuPushed(title: item.title)
            } else {
                return .error(key: item.key)
            }
        }

        // Handle submenu navigation
        if let submenu = item.submenu {
            if modifierFlags?.isOption == true || item.batch == true {
                Task(priority: .userInitiated) {
                    for menu in submenu where menu.actionClosure != nil {
                        guard menu.action?.hasPrefix("dynamic://") == false else { continue }
                        menu.actionClosure!()
                    }
                }
                return .actionExecuted
            }

            // Navigate to submenu
            await MainActor.run {
                menuState.breadcrumbs.append(item.title)
                menuState.menuStack.append(submenu)
            }
            return .submenuPushed(title: item.title)
        }

        if let action = item.actionClosure {
            Task(priority: .userInitiated) {
                action()
            }

            let overlayStyle = await MainActor.run { settingsStore?.overlayStyle ?? .panel }
            if item.sticky == false, overlayStyle == .panel {
                return .none
            } else {
                return .actionExecuted
            }
        }

        return .none
    }
}
