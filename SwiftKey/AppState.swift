import SwiftUI

final class MenuState: ObservableObject, DependencyInjectable {
    // Removed shared singleton in favor of dependency injection

    @Published var rootMenu: [MenuItem] = []
    @Published var menuStack: [[MenuItem]] = []
    @Published var breadcrumbs: [String] = []
    @Published var currentKey: String?

    var configManager: ConfigManager?

    func injectDependencies(_ container: DependencyContainer) {
        self.configManager = container.configManager
    }

    func reset() {
        menuStack = []
        breadcrumbs = []
    }

    var currentMenu: [MenuItem] {
        menuStack.last ?? rootMenu
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
