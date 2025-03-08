import AppKit
import Foundation
import os
import SwiftUI

/// Handles deep links to the app
class DeepLinkHandler: DependencyInjectable {
    static func create() -> DeepLinkHandler {
        return DeepLinkHandler()
    }

    private let logger = AppLogger.core

    private(set) var menuState: MenuState

    init() {
        self.menuState = MenuState()
    }

    func injectDependencies(_ container: DependencyContainer) {
        self.menuState = container.menuState
        logger.debug("DeepLinkHandler: Dependencies injected")
    }

    func handle(url: URL) async {
        guard url.scheme?.lowercased() == "swiftkey" else { return }

        // Handle snippet import URLs (format: swiftkey://snippets/author/name)
        if url.host?.lowercased() == "snippets" {
            handleSnippetImport(url: url)
            return
        }

        // Handle regular menu opening URLs
        guard url.host?.lowercased() == "open" else { return }
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        guard let pathQuery = queryItems?.first(where: { $0.name == "path" })?.value,
              !pathQuery.isEmpty
        else {
            logger.error("No path specified in URL \(url)")
            return
        }
        let pathKeys = pathQuery.components(separatedBy: ",")

        await MainActor.run {
            menuState.reset()
            var currentMenu = menuState.rootMenu
            var lastFound: MenuItem?
            for key in pathKeys {
                if let found = currentMenu.first(where: { $0.key == key }) {
                    lastFound = found
                    if let submenu = found.submenu {
                        menuState.breadcrumbs.append(found.title)
                        menuState.menuStack.append(submenu)
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
                logger.error("Menu item not found for path \(pathKeys)")
                return
            }

            Task {
                if item.submenu == nil, let action = item.actionClosure {
                    Task { @MainActor in
                        action()
                    }
                } else {
                    NotificationCenter.default.post(name: .presentOverlay, object: nil)
                }
            }
        }
    }

    private func handleSnippetImport(url: URL) {
        let snippetId = url.path.trimmingCharacters(in: .init(charactersIn: "/"))

        guard !snippetId.isEmpty else {
            logger.error("Invalid snippet ID in URL \(url)")
            return
        }

        logger.info("Opening snippet gallery for snippet ID: \(snippetId, privacy: .public)")

        Task { @MainActor in
            NotificationCenter.default
                .post(
                    name: .presentGalleryWindow,
                    object: nil,
                    userInfo: ["snippetId": snippetId]
                )
        }
    }
}
