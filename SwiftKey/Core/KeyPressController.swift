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

class KeyPressController {
    var menuState: MenuState

    init(menuState: MenuState) {
        self.menuState = menuState
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
            let command = String(actionString.dropFirst("dynamic://".count))
            DispatchQueue.global(qos: .userInitiated).async {
                if let submenu = self.runDynamicMenu(command: command) {
                    DispatchQueue.main.async {
                        self.menuState.breadcrumbs.append(item.title)
                        self.menuState.menuStack.append(submenu)
                        completion(.submenuPushed(title: item.title))
                    }
                } else {
                    DispatchQueue.main.async {
                        completion(.error(key: item.key))
                    }
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
            if item.sticky == false, SettingsStore.shared.overlayStyle == .panel {
                completion(.none)
            } else {
                completion(.actionExecuted)
            }
            return
        }
        completion(.none)
    }

    private func runDynamicMenu(command: String) -> [MenuItem]? {
        do {
            let result = try runScript(to: command, args: [])
            let output = result.out
            let decoder = YAMLDecoder()
            let submenu = try decoder.decode([MenuItem].self, from: output)
            return submenu
        } catch {
            print("Dynamic menu error: \(error)")
            return nil
        }
    }
}
