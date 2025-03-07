import Foundation
import os
import Yams

class DynamicMenuLoader {
    static let shared = DynamicMenuLoader()
    private let logger = AppLogger.utils

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
