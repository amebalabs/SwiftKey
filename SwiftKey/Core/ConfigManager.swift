import AppKit
import Combine
import Foundation
import os
import Yams

class ConfigManager: DependencyInjectable, ObservableObject {
    static let shared = ConfigManager()

    // Logger for this class
    private let logger = AppLogger.config

    // Published properties for reactive updates
    @Published private(set) var menuItems: [MenuItem] = []
    @Published private(set) var lastError: Error?
    @Published private(set) var lastUpdateTime: Date?

    private var lastModificationDate: Date?

    // Dependencies
    var settingsStore: SettingsStore!

    func injectDependencies(_ container: DependencyContainer) {
        self.settingsStore = container.settingsStore
        logger.debug("SettingsStore injected successfully")
    }

    // Publishers
    var menuItemsPublisher: AnyPublisher<[MenuItem], Never> {
        $menuItems.eraseToAnyPublisher()
    }

    var errorPublisher: AnyPublisher<Error?, Never> {
        $lastError.eraseToAnyPublisher()
    }

    init() {
        // Initialization without loading config
        // Config will be loaded after dependencies are injected
    }

    // This will be called after dependencies are injected
    private var didSetupDependencies = false
    func setupAfterDependenciesInjected() {
        guard !didSetupDependencies else { return }
        didSetupDependencies = true

        logger.info("Setting up after dependencies injected")

        // Load config and make sure it's processed
        DispatchQueue.main.async { [weak self] in
            _ = self?.loadConfig()

            // If no config was loaded yet, try again with a delay
            // This helps with first launch scenarios
            if let self = self, self.menuItems.isEmpty {
                logger.notice("Menu items empty after initial load, retrying...")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    _ = self.loadConfig()
                }
            }
        }
    }

    // MARK: - Public Methods

    /// Loads the configuration from the YAML file
    /// - Returns: A Result indicating success or failure with detailed error information
    @discardableResult
    func loadConfig() -> Result<[MenuItem], ConfigError> {
        logger.debug("loadConfig() called")

        // Make sure dependencies are ready
        guard settingsStore != nil else {
            logger.error("SettingsStore not yet injected, delaying load")
            self.lastError = ConfigError.dependencyNotReady
            return .failure(.dependencyNotReady)
        }

        guard let configURL = resolveConfigFileURL() else {
            logger.error("Failed to resolve config file URL")
            self.lastError = ConfigError.fileNotFound
            return .failure(.fileNotFound)
        }

        logger.info("Loading config from \(configURL.path, privacy: .public)")

        // Read the file content
        let fileReadResult = readConfigFile(from: configURL)
        switch fileReadResult {
        case let .failure(error):
            self.lastError = error
            return .failure(error)
        case let .success(yamlString):
            logger.debug("Successfully read YAML file, length: \(yamlString.count) characters")

            // Validate the YAML format before parsing
            if yamlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                logger.error("Config file is empty")
                self.lastError = ConfigError.emptyFile
                return .failure(.emptyFile)
            }

            // Parse the YAML
            let parseResult = parseYAML(yamlString)
            switch parseResult {
            case let .failure(error):
                self.lastError = error
                return .failure(error)
            case let .success(config):
                // Validate the parsed config
                if config.isEmpty {
                    logger.error("Config is empty, no menu items found")
                    self.lastError = ConfigError.emptyConfiguration
                    return .failure(.emptyConfiguration)
                }

                // Validate the menu items structure
                let validationResult = validateMenuItemsResult(config)
                switch validationResult {
                case let .failure(error):
                    self.lastError = error
                    return .failure(error)
                case .success:
                    // Successfully parsed, update the menu items
                    DispatchQueue.main.async { [weak self] in
                        self?.logger.info("Updating menu items: \(config.count) items")
                        self?.menuItems = config
                        self?.lastError = nil
                        self?.lastUpdateTime = Date()
                    }
                    return .success(config)
                }
            }
        }
    }

    /// Read configuration file from the specified URL
    private func readConfigFile(from url: URL) -> Result<String, ConfigError> {
        do {
            let yamlString = try String(contentsOf: url, encoding: .utf8)
            return .success(yamlString)
        } catch let error as NSError {
            if error.domain == NSCocoaErrorDomain {
                switch error.code {
                case NSFileReadNoSuchFileError:
                    logger.error("File not found at \(url.path, privacy: .public)")
                    return .failure(.fileNotFound)
                case NSFileReadNoPermissionError:
                    logger.error("Permission denied to read \(url.path, privacy: .public)")
                    return .failure(.accessDenied)
                default:
                    logger.error("Failed to read file: \(error.localizedDescription)")
                    return .failure(.readFailed(underlying: error))
                }
            } else {
                logger.error("Error loading config file: \(error.localizedDescription)")
                return .failure(.readFailed(underlying: error))
            }
        }
    }

    /// Parse YAML string into menu items
    private func parseYAML(_ yamlString: String) -> Result<[MenuItem], ConfigError> {
        let decoder = YAMLDecoder()

        do {
            // First try to decode as a generic YAML to check structure
            if let yamlObject = try Yams.load(yaml: yamlString) {
                // Validate that the YAML is an array at the root level
                guard yamlObject is [Any] else {
                    logger.error("Invalid YAML format - root should be an array")
                    return .failure(ConfigError.invalidYamlFormat(
                        message: "Root element must be an array of menu items",
                        line: 1,
                        column: 1
                    ))
                }
            }

            // Now try to decode to the actual model
            let config = try decoder.decode([MenuItem].self, from: yamlString)
            logger.debug("Successfully decoded \(config.count) menu items")
            return .success(config)
        } catch let yamlError as YamlError {
            // Detailed handling for Yams parsing errors
            let lineInfo = extractLineInfo(from: yamlError)
            logger.error("YAML parsing error at \(lineInfo.line):\(lineInfo.column): \(yamlError.localizedDescription)")
            return .failure(ConfigError.invalidYamlFormat(
                message: yamlError.localizedDescription,
                line: lineInfo.line,
                column: lineInfo.column
            ))
        } catch let decodingError as DecodingError {
            // Detailed handling for Swift Decodable errors
            logger.error("Decoding error: \(decodingError.localizedDescription)")

            switch decodingError {
            case let .keyNotFound(key, context):
                logger.error("Missing required key '\(key.stringValue)' in context: \(context.debugDescription)")
                return .failure(ConfigError.missingRequiredField(
                    field: key.stringValue,
                    context: context.debugDescription
                ))
            case let .typeMismatch(type, context):
                logger.error("Type mismatch for \(type) in context: \(context.debugDescription)")
                let fieldName = context.codingPath.last?.stringValue ?? "unknown"
                return .failure(ConfigError.typeMismatch(
                    field: fieldName,
                    context: context.debugDescription
                ))
            case let .valueNotFound(type, context):
                logger.error("Value not found for \(type) in context: \(context.debugDescription)")
                let fieldName = context.codingPath.last?.stringValue ?? "unknown"
                return .failure(ConfigError.missingRequiredField(
                    field: fieldName,
                    context: context.debugDescription
                ))
            case let .dataCorrupted(context):
                logger.error("Data corrupted in context: \(context.debugDescription)")
                return .failure(ConfigError.invalidYamlFormat(
                    message: context.debugDescription,
                    line: 0,
                    column: 0
                ))
            @unknown default:
                return .failure(ConfigError.parsingFailed(underlying: decodingError))
            }
        } catch let otherError {
            // Fallback for other errors
            logger.error("YAML parsing error: \(otherError.localizedDescription)")
            return .failure(ConfigError.parsingFailed(underlying: otherError))
        }
    }

    /// Changes the configuration file to a new location
    func changeConfigFile() {
        let dialog = NSOpenPanel()
        dialog.message = "Choose your configuration file"
        dialog.showsHiddenFiles = false
        dialog.canChooseDirectories = false
        dialog.canChooseFiles = true
        dialog.allowsMultipleSelection = false

        guard dialog.runModal() == .OK, let url = dialog.url else { return }
        settingsStore.configFilePath = url.path
        loadConfig()
    }

    /// Opens the current configuration file in Finder
    func openConfigFile() {
        guard let url = resolveConfigFileURL() else { return }

        // Reveal the file in Finder by selecting it
        NSWorkspace.shared.selectFile(
            url.path,
            inFileViewerRootedAtPath: url.deletingLastPathComponent().path
        )
    }

    /// Imports and merges menu items from a snippet into the current configuration
    func importSnippet(menuItems: [MenuItem], strategy: MergeStrategy) -> Result<Void, ConfigError> {
        // Validation
        do {
            try validateMenuItems(menuItems)
        } catch let validationError as ConfigError {
            logger.error("Snippet validation failed: \(validationError.localizedDescription)")
            self.lastError = validationError
            return .failure(validationError)
        } catch {
            logger.error("Unexpected validation error: \(error.localizedDescription)")
            self.lastError = ConfigError.unknown(underlying: error)
            return .failure(ConfigError.unknown(underlying: error))
        }

        // Get current config
        var currentConfig = self.menuItems

        // Apply merge strategy
        switch strategy {
        case .append:
            currentConfig.append(contentsOf: menuItems)
        case .prepend:
            currentConfig = menuItems + currentConfig
        case .replace:
            currentConfig = menuItems
        case .smart:
            currentConfig = smartMergeMenuItems(currentConfig, with: menuItems)
        }

        // Save back to file
        return saveMenuItems(currentConfig)
    }

    /// Saves the menu items to the current config file
    func saveMenuItems(_ items: [MenuItem]) -> Result<Void, ConfigError> {
        guard let url = resolveConfigFileURL() else {
            return .failure(ConfigError.fileNotFound)
        }

        do {
            // Create a YAML encoder with a custom encoding function that strips out IDs
            let yamlString = try createCleanYaml(from: items)

            try yamlString.write(to: url, atomically: true, encoding: .utf8)
            logger.info("Successfully saved \(items.count) menu items to \(url.path, privacy: .public)")

            // Update the menu items
            DispatchQueue.main.async { [weak self] in
                self?.menuItems = items
                self?.lastError = nil
                self?.lastUpdateTime = Date()
            }

            return .success(())
        } catch {
            logger.error("Failed to save config: \(error.localizedDescription)")
            self.lastError = ConfigError.readFailed(underlying: error)
            return .failure(ConfigError.readFailed(underlying: error))
        }
    }

    /// Creates YAML using the standard encoder
    /// The MenuItem.encode(to:) method already handles skipping the ID
    private func createCleanYaml(from items: [MenuItem]) -> String {
        let encoder = YAMLEncoder()
        do {
            return try encoder.encode(items)
        } catch {
            logger.error("Error creating YAML: \(error.localizedDescription)")
            return ""
        }
    }

    /// Performs a smart merge of two menu item arrays
    func smartMergeMenuItems(_ base: [MenuItem], with new: [MenuItem]) -> [MenuItem] {
        var result = base

        for newItem in new {
            // Check if an item with the same key and title already exists
            if let existingIndex = result.firstIndex(where: { $0.key == newItem.key && $0.title == newItem.title }) {
                // If same key+title, replace the item completely
                result[existingIndex] = newItem
            } else if let existingKeyIndex = result.firstIndex(where: { $0.key == newItem.key }) {
                // If only same key, add as a new item (avoids key conflicts)
                let uniqueItem = makeKeyUnique(newItem, existingItems: result)
                result.append(uniqueItem)
            } else {
                // Completely new item
                result.append(newItem)
            }
        }

        return result
    }

    /// Makes a menu item's key unique by appending a number if needed
    private func makeKeyUnique(_ item: MenuItem, existingItems: [MenuItem]) -> MenuItem {
        var uniqueItem = item
        var counter = 1
        var newKey = item.key

        // Keep incrementing until we find a unique key
        while existingItems.contains(where: { $0.key == newKey }) {
            counter += 1
            // Use the next available character if possible
            if item.key.count == 1, let ascii = item.key.first?.asciiValue, ascii + UInt8(counter) <= 122 {
                newKey = String(Character(UnicodeScalar(ascii + UInt8(counter))))
            } else {
                // Otherwise just append a number
                newKey = "\(item.key)\(counter)"
            }
        }

        uniqueItem.key = newKey
        return uniqueItem
    }

    // MARK: - Private Methods

    /// Checks if the configuration file has changed since the last check
    func hasConfigChanged() -> Bool {
        guard let url = resolveConfigFileURL() else { return false }

        let fileManager = FileManager.default
        do {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            if let modDate = attributes[.modificationDate] as? Date {
                if lastModificationDate == nil {
                    lastModificationDate = modDate
                    logger.debug("Initial config file mod date: \(modDate)")
                    return false
                }

                if let lastMod = lastModificationDate, modDate > lastMod {
                    logger.notice("Config file changed - old: \(lastMod), new: \(modDate)")
                    lastModificationDate = modDate
                    return true
                }
            }
        } catch {
            logger.error("Error reading file attributes: \(error.localizedDescription)")
        }
        return false
    }

    @discardableResult func refreshIfNeeded() -> Bool {
        if hasConfigChanged() {
            _ = loadConfig()
            return true
        }
        return false
    }

    /// Helper to resolve the config file URL using direct file path
    func resolveConfigFileURL() -> URL? {
        // Ensure we have a valid reference to settings store
        guard let settings = settingsStore else {
            logger.error("SettingsStore is not properly injected into ConfigManager")
            return nil
        }

        // Use the direct path
        if let url = settings.configFileResolvedURL {
            logger.debug("Using direct path: \(url.path, privacy: .public)")
            return url
        } else {
            logger.notice("No configuration file path available, creating default")
            // Default to bundle location or create one in user Documents
            let defaultConfigPath = createDefaultConfigIfNeeded()
            logger.debug("Using default config at: \(defaultConfigPath?.path ?? "none", privacy: .public)")
            return defaultConfigPath
        }
    }

    private func createDefaultConfigIfNeeded() -> URL? {
        guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            logger.fault("Could not access Documents directory")
            assertionFailure("Could not access Documents directory")
            return nil
        }

        let configURL = documentsDir.appendingPathComponent("menu.yaml")

        if FileManager.default.fileExists(atPath: configURL.path) {
            logger.debug("Found existing config at \(configURL.path, privacy: .public)")
            return configURL
        }

        // Get the default config from the app bundle
        guard let bundledConfigURL = Bundle.main.url(forResource: "menu", withExtension: "yaml") else {
            logger.fault("Could not find bundled menu.yaml")
            assertionFailure("Could not find bundled menu.yaml")
            return nil
        }

        do {
            try FileManager.default.copyItem(at: bundledConfigURL, to: configURL)
            logger.info("Copied bundled config to \(configURL.path, privacy: .public)")

            settingsStore.configFilePath = configURL.path
            return configURL
        } catch {
            logger.error("Failed to copy bundled config: \(error.localizedDescription)")
            // This is a serious error but don't crash in production
            assertionFailure("Failed to copy bundled config: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - YAML Validation Helpers

    /// Extracts line and column information from a YAML error
    private func extractLineInfo(from error: YamlError) -> (line: Int, column: Int) {
        // Default values
        var line = 0
        var column = 0

        // Try to extract line/column info from error description
        let errorDescription = error.localizedDescription

        // Look for line:column pattern in the error description
        let lineColumnPattern = #"line (\d+), column (\d+)"#
        if let regex = try? NSRegularExpression(pattern: lineColumnPattern),
           let match = regex.firstMatch(
               in: errorDescription,
               range: NSRange(errorDescription.startIndex..., in: errorDescription)
           )
        {
            if let lineRange = Range(match.range(at: 1), in: errorDescription),
               let columnRange = Range(match.range(at: 2), in: errorDescription)
            {
                line = Int(errorDescription[lineRange]) ?? 0
                column = Int(errorDescription[columnRange]) ?? 0
            }
        }

        return (line, column)
    }

    /// Validates menu items recursively using Result
    private func validateMenuItemsResult(_ items: [MenuItem]) -> Result<Void, ConfigError> {
        for item in items {
            // Validate key format (should be a single character)
            if item.key.count != 1 {
                logger.error("Invalid key format: \(item.key)")
                return .failure(ConfigError.invalidYamlFormat(
                    message: "Key must be a single character, found '\(item.key)'",
                    line: 0,
                    column: 0
                ))
            }

            // Validate title is not empty
            if item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                logger.error("Empty title for key: \(item.key)")
                return .failure(ConfigError.invalidYamlFormat(
                    message: "Title cannot be empty for key '\(item.key)'",
                    line: 0,
                    column: 0
                ))
            }

            // Validate that if there's no submenu, there must be an action
            if item.submenu == nil && item.action == nil {
                logger.error("Menu item missing both submenu and action: \(item.title)")
                return .failure(ConfigError.invalidYamlFormat(
                    message: "Menu item '\(item.title)' (key: \(item.key)) must have either a submenu or an action",
                    line: 0,
                    column: 0
                ))
            }

            // Validate action format if present
            if let action = item.action {
                if !isValidActionFormat(action) {
                    logger.error("Invalid action format: \(action)")
                    return .failure(ConfigError.invalidYamlFormat(
                        message: "Invalid action format: '\(action)' for key '\(item.key)'",
                        line: 0,
                        column: 0
                    ))
                }
            }

            // Validate hotkey format if present
            if let hotkey = item.hotkey, !isValidHotkeyFormat(hotkey) {
                logger.error("Invalid hotkey format: \(hotkey)")
                return .failure(ConfigError.invalidYamlFormat(
                    message: "Invalid hotkey format: '\(hotkey)' for key '\(item.key)'",
                    line: 0,
                    column: 0
                ))
            }

            // Recursively validate submenu if present
            if let submenu = item.submenu {
                let result = validateMenuItemsResult(submenu)
                if case let .failure(error) = result {
                    return .failure(error)
                }
            }
        }

        return .success(())
    }

    /// Legacy method that uses throws for backward compatibility
    private func validateMenuItems(_ items: [MenuItem]) throws {
        let result = validateMenuItemsResult(items)
        switch result {
        case .success:
            return
        case let .failure(error):
            throw error
        }
    }

    /// Validates the action string format
    private func isValidActionFormat(_ action: String) -> Bool {
        if action.hasPrefix("shell://") {
            switch validateShellCommand(action) {
            case .success:
                return true
            case .failure:
                return false
            }
        }

        let validPrefixes = ["launch://", "open://", "shortcut://", "dynamic://"]
        return validPrefixes.contains { action.hasPrefix($0) }
    }

    /// Validates shell commands for security and proper format
    private func validateShellCommand(_ command: String) -> Result<Void, ConfigError> {
        // Strip the "shell://" prefix
        let shellCmd = String(command.dropFirst("shell://".count)).trimmingCharacters(in: .whitespacesAndNewlines)

        // Check for empty commands
        if shellCmd.isEmpty {
            return .failure(ConfigError.invalidShellCommand(
                message: "Shell command cannot be empty",
                command: command
            ))
        }

        // Check for blacklisted commands
        let blacklistedPrefixes = ["rm -rf /", "sudo ", "> /", ">> /", "mkfs", "dd if=", ":(){ :|:& };:"]
        for prefix in blacklistedPrefixes {
            if shellCmd.hasPrefix(prefix) || shellCmd.contains(" " + prefix) {
                return .failure(ConfigError.invalidShellCommand(
                    message: "Shell command contains potentially dangerous operation",
                    command: command
                ))
            }
        }

        // Check command length to prevent very long commands
        if shellCmd.count > 1000 {
            return .failure(ConfigError.invalidShellCommand(
                message: "Shell command exceeds maximum allowed length (1000 characters)",
                command: command
            ))
        }

        // Check for proper quoting
        let quoteCount = shellCmd.filter { $0 == "\"" || $0 == "'" }.count
        if quoteCount % 2 != 0 {
            return .failure(ConfigError.invalidShellCommand(
                message: "Shell command has unbalanced quotes",
                command: command
            ))
        }

        return .success(())
    }

    /// Validates the hotkey format
    private func isValidHotkeyFormat(_ hotkey: String) -> Bool {
        // Simple validation for now - can be made more sophisticated
        let components = hotkey.components(separatedBy: "+")

        // Hotkey must have at least one component
        guard !components.isEmpty else { return false }

        // Check for valid modifiers
        let validModifiers = ["cmd", "ctrl", "alt", "shift"]
        // At least all but the last component should be valid modifiers
        for i in 0 ..< (components.count - 1) {
            if !validModifiers.contains(components[i].lowercased()) {
                return false
            }
        }

        return true
    }
}

// MARK: - Error Types

enum ConfigError: Error {
    case fileNotFound
    case accessDenied
    case readFailed(underlying: Error)
    case emptyFile
    case emptyConfiguration
    case invalidYamlFormat(message: String, line: Int, column: Int)
    case missingRequiredField(field: String, context: String)
    case typeMismatch(field: String, context: String)
    case parsingFailed(underlying: Error)
    case invalidShellCommand(message: String, command: String)
    case unknown(underlying: Error)
    case dependencyNotReady
}

extension ConfigError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "Configuration file not found."
        case .accessDenied:
            return "Access to the configuration file was denied."
        case let .readFailed(error):
            return "Failed to read the configuration file: \(error.localizedDescription)"
        case .emptyFile:
            return "Configuration file is empty."
        case .emptyConfiguration:
            return "Configuration does not contain any menu items."
        case let .invalidYamlFormat(message, line, column):
            return "Invalid YAML format at line \(line), column \(column): \(message)"
        case let .missingRequiredField(field, _):
            return "Required field '\(field)' is missing in the configuration."
        case let .typeMismatch(field, _):
            return "Type mismatch for field '\(field)' in the configuration."
        case let .parsingFailed(error):
            return "Failed to parse the configuration: \(error.localizedDescription)"
        case let .invalidShellCommand(message, command):
            return "Invalid shell command: \(message) in '\(command)'"
        case let .unknown(error):
            return "Unknown error processing configuration: \(error.localizedDescription)"
        case .dependencyNotReady:
            return "Configuration manager dependencies are not ready."
        }
    }
}
