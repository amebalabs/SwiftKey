import Foundation
import os

class ConfigMonitor {
    private let logger = AppLogger.config
    private var lastModificationDate: Date?

    func hasConfigChanged(at url: URL) -> Bool {
        let fileManager = FileManager.default
        do {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            if let modDate = attributes[.modificationDate] as? Date {
                if let lastMod = lastModificationDate {
                    if modDate > lastMod {
                        lastModificationDate = modDate
                        return true
                    } else {
                        return false
                    }
                } else {
                    lastModificationDate = modDate
                    return false
                }
            }
        } catch {
            logger.error("Error reading file attributes: \(error.localizedDescription)")
        }
        return false
    }
}
