import Foundation
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
    var menuState: MenuState
    var settingsStore: SettingsStore?

    init(menuState: MenuState, settingsStore: SettingsStore? = nil) {
        self.menuState = menuState
        self.settingsStore = settingsStore
    }

    func injectDependencies(_ container: DependencyContainer) {
        self.settingsStore = container.settingsStore
    }

    func handleKeyAsync(
        _ key: String,
        modifierFlags: NSEvent.ModifierFlags? = nil,
        completion: @escaping (KeyPressResult) -> Void
    ) {
        print("Key pressed: \(key)")
        let normalizedKey = key
        menuState.currentKey = normalizedKey

        if normalizedKey == "escape" {
            completion(.escape)
            return
        }
        if normalizedKey == "cmd+up" {
            if !menuState.menuStack.isEmpty { menuState.menuStack.removeLast() }
            if !menuState.breadcrumbs.isEmpty { menuState.breadcrumbs.removeLast() }
            completion(.up)
            return
        }
        if normalizedKey == "?" {
            completion(.help)
            return
        }

        guard let item = menuState.currentMenu.first(where: { $0.key == normalizedKey }) else {
            completion(.error(key: key))
            return
        }

        if let actionString = item.action, actionString.hasPrefix("dynamic://") {
            completion(.dynamicLoading)

            DynamicMenuLoader.shared.loadDynamicMenu(for: item) { [weak self] submenu in
                guard let self = self, let submenu = submenu else {
                    DispatchQueue.main.async {
                        completion(.error(key: item.key))
                    }
                    return
                }

                DispatchQueue.main.async {
                    self.menuState.breadcrumbs.append(item.title)
                    self.menuState.menuStack.append(submenu)
                    completion(.submenuPushed(title: item.title))
                }
            }
            return
        }
        if let submenu = item.submenu {
            if modifierFlags?.isOption == true || item.batch == true {
                DispatchQueue.global(qos: .userInitiated).async {
                    for menu in submenu where menu.actionClosure != nil {
                        guard menu.action?.hasPrefix("dynamic://") == false else { continue }
                        menu.actionClosure!()
                    }
                }
                completion(.actionExecuted)
                return
            }
            menuState.breadcrumbs.append(item.title)
            menuState.menuStack.append(submenu)
            completion(.submenuPushed(title: item.title))
            return
        }
        if let action = item.actionClosure {
            DispatchQueue.global(qos: .userInitiated).async {
                action()
            }
            // sticky menus are only for full panel mode for now
            let overlayStyle = settingsStore?.overlayStyle ?? .panel
            if item.sticky == false, overlayStyle == .panel {
                completion(.none)
            } else {
                completion(.actionExecuted)
            }
            return
        }
        completion(.none)
    }

    // Removed runDynamicMenu method, now using DynamicMenuLoader instead
}
