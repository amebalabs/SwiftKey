import Foundation

/// Manages configuration file backups
final class ConfigBackup {

    private let backupDirectory: URL
    private let maxBackups: Int
    private let fileManager: FileManager

    init(backupDirectory: URL, maxBackups: Int = 10, fileManager: FileManager = .default) {
        self.backupDirectory = backupDirectory
        self.maxBackups = maxBackups
        self.fileManager = fileManager
    }

    /// Creates a backup of the file at the given URL
    /// - Parameters:
    ///   - sourceURL: The file to backup
    /// - Returns: The URL of the created backup, or nil if source doesn't exist
    func createBackup(of sourceURL: URL) throws -> URL? {
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            return nil
        }

        try ensureBackupDirectoryExists()

        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let originalName = sourceURL.deletingPathExtension().lastPathComponent
        let ext = sourceURL.pathExtension
        let backupName = "\(originalName)_\(timestamp).\(ext)"
        let backupURL = backupDirectory.appendingPathComponent(backupName)

        try fileManager.copyItem(at: sourceURL, to: backupURL)
        try pruneOldBackups(for: originalName)

        return backupURL
    }

    /// Creates a backup from content string
    /// - Parameters:
    ///   - content: The content to backup
    ///   - originalName: The original file name (without extension)
    /// - Returns: The URL of the created backup
    func createBackup(content: String, originalName: String) throws -> URL {
        try ensureBackupDirectoryExists()

        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backupName = "\(originalName)_\(timestamp).yaml"
        let backupURL = backupDirectory.appendingPathComponent(backupName)

        try content.write(to: backupURL, atomically: true, encoding: .utf8)
        try pruneOldBackups(for: originalName)

        return backupURL
    }

    /// Lists available backups for a configuration file
    func listBackups(for originalName: String) throws -> [URL] {
        guard fileManager.fileExists(atPath: backupDirectory.path) else {
            return []
        }

        let contents = try fileManager.contentsOfDirectory(
            at: backupDirectory,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        )

        return contents
            .filter { $0.lastPathComponent.hasPrefix(originalName) }
            .sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return date1 > date2
            }
    }

    /// Restores a backup to the original location
    func restoreBackup(_ backupURL: URL, to destinationURL: URL) throws {
        // Create backup of current file before restoring
        if fileManager.fileExists(atPath: destinationURL.path) {
            _ = try? createBackup(of: destinationURL)
        }

        let content = try String(contentsOf: backupURL, encoding: .utf8)
        try content.write(to: destinationURL, atomically: true, encoding: .utf8)
    }

    /// Deletes a specific backup
    func deleteBackup(_ backupURL: URL) throws {
        guard backupURL.path.hasPrefix(backupDirectory.path) else {
            return
        }
        try fileManager.removeItem(at: backupURL)
    }

    /// Deletes all backups for a given original name
    func deleteAllBackups(for originalName: String) throws {
        let backups = try listBackups(for: originalName)
        for backup in backups {
            try fileManager.removeItem(at: backup)
        }
    }

    // MARK: - Private Methods

    private func ensureBackupDirectoryExists() throws {
        if !fileManager.fileExists(atPath: backupDirectory.path) {
            try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        }
    }

    private func pruneOldBackups(for originalName: String) throws {
        let backups = try listBackups(for: originalName)

        if backups.count > maxBackups {
            let toDelete = backups.suffix(from: maxBackups)
            for url in toDelete {
                try? fileManager.removeItem(at: url)
            }
        }
    }
}
