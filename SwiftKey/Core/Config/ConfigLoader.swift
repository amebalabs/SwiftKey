import Foundation

/// Handles file system operations for configuration files
final class ConfigLoader {

    private let fileManager: FileManager
    private let configURL: URL

    init(configURL: URL, fileManager: FileManager = .default) {
        self.configURL = configURL
        self.fileManager = fileManager
    }

    /// The URL of the configuration file
    var url: URL { configURL }

    /// Checks if the configuration file exists
    var fileExists: Bool {
        fileManager.fileExists(atPath: configURL.path)
    }

    /// Loads raw configuration content from disk
    func loadContent() throws -> String {
        guard fileExists else {
            throw ConfigError.fileNotFound
        }

        do {
            return try String(contentsOf: configURL, encoding: .utf8)
        } catch let error as NSError {
            if error.domain == NSCocoaErrorDomain {
                switch error.code {
                case NSFileReadNoSuchFileError:
                    throw ConfigError.fileNotFound
                case NSFileReadNoPermissionError:
                    throw ConfigError.accessDenied
                default:
                    throw ConfigError.readFailed(underlying: error)
                }
            }
            throw ConfigError.readFailed(underlying: error)
        }
    }

    /// Saves configuration content to disk
    func saveContent(_ content: String) throws {
        do {
            try content.write(to: configURL, atomically: true, encoding: .utf8)
        } catch {
            throw ConfigError.readFailed(underlying: error)
        }
    }

    /// Returns the last modification date of the config file
    func lastModificationDate() throws -> Date? {
        guard fileExists else { return nil }

        let attributes = try fileManager.attributesOfItem(atPath: configURL.path)
        return attributes[.modificationDate] as? Date
    }

    /// Creates the parent directory if it doesn't exist
    func ensureParentDirectoryExists() throws {
        let parentDirectory = configURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentDirectory.path) {
            try fileManager.createDirectory(at: parentDirectory, withIntermediateDirectories: true)
        }
    }
}
