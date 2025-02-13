import Foundation
import SwiftUI

enum KeyPressResult: Equatable {
    case escape
    case help
    case up
    case submenuPushed(title: String)
    case actionExecuted
    case error(key: String)
    case none
}

class KeyPressController {
    var menuState: MenuState

    init(menuState: MenuState) {
        self.menuState = menuState
    }

    func handleKey(_ key: String) -> KeyPressResult {
        let normalizedKey = key.lowercased()
        if normalizedKey == "escape" { return .escape }
        if normalizedKey == "cmd+up" {
            if !menuState.menuStack.isEmpty { menuState.menuStack.removeLast() }
            if !menuState.breadcrumbs.isEmpty { menuState.breadcrumbs.removeLast() }
            return .up
        }
        if normalizedKey == "?" { return .help }
        if let item = menuState.currentMenu.first(where: { $0.key.lowercased() == normalizedKey }) {
            if let submenu = item.submenu {
                menuState.breadcrumbs.append(item.title)
                menuState.menuStack.append(submenu)
                return .submenuPushed(title: item.title)
            } else if let action = item.actionClosure {
                action()
                return .actionExecuted
            }
        }
        return .error(key: key)
    }
}
