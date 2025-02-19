import SwiftUI

final class MenuState: ObservableObject {
    public static let shared = MenuState()
    @Published var rootMenu: [MenuItem] = []
    @Published var menuStack: [[MenuItem]] = []
    @Published var breadcrumbs: [String] = []
    @Published var currentKey: String?

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
