import SwiftUI

final class MenuState: ObservableObject {
    public static let shared = MenuState()
    @Published var rootMenu: [MenuItem] = []
    @Published var menuStack: [[MenuItem]] = []
    @Published var breadcrumbs: [String] = []

    func reset() {
        menuStack = []
        breadcrumbs = []
    }

    var currentMenu: [MenuItem] {
        menuStack.last ?? rootMenu
    }

    var breadcrumbText: String {
        breadcrumbs.isEmpty ? "Home" : "Home > " + breadcrumbs.joined(separator: " > ")
    }
}
