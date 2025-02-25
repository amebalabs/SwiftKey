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
}
