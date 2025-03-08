import Foundation
import os
import Yams

/// Responsible for loading dynamic menus by executing shell scripts
class DynamicMenuLoader: DependencyInjectable {
    // Keep singleton for backward compatibility during transition to DI
    static let shared = DynamicMenuLoader()
    
    private let logger = AppLogger.utils
    
    /// Factory method for creating a DynamicMenuLoader instance
    static func create() -> DynamicMenuLoader {
        return DynamicMenuLoader()
    }

    // DynamicMenuLoader has no dependencies but implements the protocol
    // for consistency with the rest of the codebase
    func injectDependencies(_ container: DependencyContainer) {
        // Nothing to inject
    }

    func loadDynamicMenu(for menuItem: MenuItem) async -> [MenuItem]? {
        guard let actionString = menuItem.action, actionString.hasPrefix("dynamic://") else {
            return nil
        }

        let command = String(actionString.dropFirst("dynamic://".count))

        do {
            let result = try await runScript(to: command, args: [])
            let output = result.out
            let decoder = YAMLDecoder()
            return try decoder.decode([MenuItem].self, from: output)
        } catch {
            logger.error("Dynamic menu error: \(error.localizedDescription)")
            return nil
        }
    }
}
