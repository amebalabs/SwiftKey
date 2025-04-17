import SwiftUI

final class MenuState: ObservableObject {
    @Published var rootMenu: [MenuItem] = []
    @Published var menuStack: [[MenuItem]] = []
    @Published var breadcrumbs: [String] = []
    @Published var currentKey: String?
    @Published var lastExecutedAction: (() -> Void)? = nil
    @Published var lastActionTime: Date? = nil

    func reset() {
        menuStack = []
        breadcrumbs = []
    }

    // Returns the current menu (raw, including hidden items)
    var currentMenu: [MenuItem] {
        menuStack.last ?? rootMenu
    }

    // Returns menu items that should be visible in the UI
    var visibleMenu: [MenuItem] {
        let menu = currentMenu

        // Special case: if there's only one item in the menu and it's hidden,
        // we should still show it in overlay mode
        if menu.count == 1 && menu[0].hidden == true && !breadcrumbs.isEmpty {
            return menu
        }

        // Normal case: filter out hidden items
        return menu.filter { $0.hidden != true }
    }

    var isCurrentMenuSticky: Bool {
        guard let lastKey = currentKey else { return false }
        return currentMenu.first(where: { $0.key == lastKey })?.sticky ?? false
    }

    var breadcrumbText: String {
        breadcrumbs.isEmpty ? "Home" : "Home > " + breadcrumbs.joined(separator: " > ")
    }

    /// Checks if the current menu consists of a single dynamic menu item
    var hasSingleDynamicMenuItem: Bool {
        let menu = currentMenu
        return menu.count == 1 &&
            menu[0].action?.hasPrefix("dynamic://") == true &&
            menu[0].submenu == nil
    }

    /// Returns the single dynamic menu item if it exists
    var singleDynamicMenuItem: MenuItem? {
        guard hasSingleDynamicMenuItem else { return nil }
        return currentMenu.first
    }
}
