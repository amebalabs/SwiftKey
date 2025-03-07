import AppKit
import Foundation
import os
import SwiftUI

class DeepLinkHandler: DependencyInjectable {
    static let shared = DeepLinkHandler()

    private let logger = AppLogger.core

    // Dependencies
    var menuState: MenuState?

    func injectDependencies(_ container: DependencyContainer) {
        self.menuState = container.menuState
        logger.debug("Dependencies injected")
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

        guard let state = self.menuState else {
            logger.error("MenuState not properly injected")
            return
        }

        await MainActor.run {
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
                logger.error("Menu item not found for path \(pathKeys)")
                return
            }

            Task {
                if item.submenu == nil, let action = item.actionClosure {
                    Task { @MainActor in
                        action()
                    }
                } else {
                    if let appDelegate = AppDelegate.shared {
                        Task { @MainActor in
                            appDelegate.presentOverlay()
                            NSApp.activate(ignoringOtherApps: true)
                        }
                    }
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
            await AppDelegate.showGalleryWindow(preselectedSnippetId: snippetId)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
