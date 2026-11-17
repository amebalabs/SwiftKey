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

    /// Approves dynamic commands before they run. Without it no command runs.
    private var approvalGate: ApprovalGate?

    init(approvalGate: ApprovalGate? = nil) {
        self.approvalGate = approvalGate
    }

    func injectDependencies(_ container: DependencyContainer) {
        approvalGate = container.approvalGate
    }

    /// Runs the item's `dynamic://` command once it is approved and returns the menu it prints.
    /// The returned items are marked as generated: they run without another approval.
    func loadDynamicMenu(for menuItem: MenuItem, path: [String] = []) async -> [MenuItem]? {
        guard let actionString = menuItem.action, actionString.hasPrefix("dynamic://") else {
            return nil
        }
        guard let approvalGate else {
            logger.error("Dynamic menu not loaded: no approval gate")
            return nil
        }
        guard await approvalGate.authorize([menuItem], path: path) else { return nil }

        let command = String(actionString.dropFirst("dynamic://".count))

        do {
            let result = try await runScript(to: command, args: [])
            let output = result.out
            let decoder = YAMLDecoder()
            return try decoder.decode([MenuItem].self, from: output).map { $0.markedGenerated() }
        } catch {
            logger.error("Dynamic menu error: \(error.localizedDescription)")
            return nil
        }
    }
}
