import Foundation

class ConfigMonitor {
    static let shared = ConfigMonitor()
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
            print("Error reading file attributes: \(error)")
        }
        return false
    }
}
