import AppKit
import Foundation
import os
import SwiftKeyCore
import SwiftUI

/// Handles deep links to the app
class DeepLinkHandler: DependencyInjectable {
    static func create() -> DeepLinkHandler {
        return DeepLinkHandler()
    }

    private let logger = AppLogger.core

    private(set) var menuState: MenuState
    private var approvalGate: ApprovalGate?
    private let notificationCenter: NotificationCenter

    init(notificationCenter: NotificationCenter = .default) {
        self.menuState = MenuState()
        self.notificationCenter = notificationCenter
    }

    func injectDependencies(_ container: DependencyContainer) {
        self.menuState = container.menuState
        self.approvalGate = container.approvalGate
        logger.debug("DeepLinkHandler: Dependencies injected")
    }

    func handle(url: URL) async {
        guard url.scheme?.lowercased() == "swiftkey" else { return }

        // Handle snippet import URLs (format: swiftkey://snippets/author/name)
        if url.host?.lowercased() == "snippets" {
            handleSnippetImport(url: url)
            return
        }

        // swiftkey://launcha opens the search panel
        if url.host?.lowercased() == "launcha" {
            await MainActor.run { notificationCenter.post(name: .openLauncha, object: nil) }
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

        let outcome = await MainActor.run { Self.resolve(pathKeys, in: menuState.rootMenu) }
        switch outcome {
        case .notFound:
            logger.error("Menu item not found for path \(pathKeys)")
        case let .navigate(groups, hint):
            await MainActor.run {
                menuState.reset()
                for group in groups {
                    menuState.push(key: SequenceKey.normalize(group.key) ?? group.key, title: group.title,
                                   items: group.submenu ?? [])
                }
                menuState.hint = hint
                // A link only shows the menu: a lone `dynamic://` item waits for its key like any other command.
                notificationCenter.post(name: .presentOverlay, object: nil,
                                        userInfo: [PresentOverlayKey.loadsDynamicMenu: false])
            }
        case let .run(item, path):
            await MainActor.run { menuState.reset() }
            await approvalGate?.run(item, path: path)
        }
    }

    /// What a deep link does.
    enum Outcome: Equatable {
        /// Open the menu inside these groups, with an optional hint in place of the breadcrumbs.
        case navigate(groups: [MenuItem], hint: String?)
        /// Run the item's action; `path` holds the titles of its groups.
        case run(MenuItem, path: [String])
        case notFound
    }

    /// Follows the keys from the top of the menu. A group opens the menu there. An action that
    /// only opens something (`launch://`, `open://`, `shortcut://`) runs. An action that runs code
    /// from the config (`shell://`, `dynamic://`, `micro://`) only opens the menu at its group:
    /// any web page or app can open a link, so running code always needs a key press.
    static func resolve(_ keys: [String], in root: [MenuItem]) -> Outcome {
        var current = root
        var groups: [MenuItem] = []
        for key in keys {
            guard let found = current.first(where: { $0.key == key }) else { return .notFound }
            if let submenu = found.submenu {
                groups.append(found)
                current = submenu
                continue
            }
            let action = found.action.flatMap(MenuItemTree.action(for:))
            if action?.runsCode == true {
                return .navigate(groups: groups, hint: "Press \(found.key) to run \(found.title)")
            }
            return .run(found, path: groups.map(\.title))
        }
        return groups.isEmpty ? .notFound : .navigate(groups: groups, hint: nil)
    }

    private func handleSnippetImport(url: URL) {
        let snippetId = url.path.trimmingCharacters(in: .init(charactersIn: "/"))

        // If path is empty, show the gallery without a preselected snippet
        if snippetId.isEmpty {
            logger.info("Opening snippet gallery without preselection")
            Task { @MainActor in
                NotificationCenter.default.post(name: .presentGalleryWindow, object: nil)
            }
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
