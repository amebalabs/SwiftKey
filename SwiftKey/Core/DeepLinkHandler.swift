import AppKit
import Foundation
import SwiftUI

class DeepLinkHandler: DependencyInjectable {
    static let shared = DeepLinkHandler()

    // Dependencies
    var menuState: MenuState?

    func injectDependencies(_ container: DependencyContainer) {
        self.menuState = container.menuState
    }

    func handle(url: URL) {
        guard url.scheme?.lowercased() == "swiftkey" else { return }
        guard url.host?.lowercased() == "open" else { return }
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        guard let pathQuery = queryItems?.first(where: { $0.name == "path" })?.value,
              !pathQuery.isEmpty
        else {
            print("DeepLinkHandler: No path specified in URL \(url)")
            return
        }
        let pathKeys = pathQuery.components(separatedBy: ",")

        guard let state = self.menuState else {
            print("DeepLinkHandler: MenuState not properly injected")
            return
        }

        state.reset()
        var currentMenu = state.rootMenu
        var lastFound: MenuItem?
        for key in pathKeys {
            if let found = currentMenu.first(where: { $0.key == key }) {
                lastFound = found
                if let submenu = found.submenu {
                    state.breadcrumbs.append(found.title)
                    state.menuStack.append(submenu)
                    currentMenu = submenu
                } else {
                    break
                }
            } else {
                lastFound = nil
                break
            }
        }
        guard let item = lastFound else {
            print("DeepLinkHandler: Menu item not found for path \(pathKeys)")
            return
        }
        if item.submenu == nil, let action = item.actionClosure {
            DispatchQueue.main.async {
                action()
            }
        } else {
            // Open the overlay UI with the submenu open.
            if let appDelegate = AppDelegate.shared {
                DispatchQueue.main.async {
                    // Use presentOverlay method to handle any single dynamic menu items
                    appDelegate.presentOverlay()
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
        }
    }
}
