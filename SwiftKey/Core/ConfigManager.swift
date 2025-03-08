import AppKit
import Combine
import Foundation
import os
import Yams

/// Manages loading, parsing, and updating configuration files
class ConfigManager: DependencyInjectable, ObservableObject {
    private let logger = AppLogger.config

    /// Factory method to create a new ConfigManager instance
    static func create() -> ConfigManager {
        return ConfigManager()
    }

    // Published properties for reactive updates
    @Published private(set) var menuItems: [MenuItem] = []
    @Published private(set) var lastError: Error?

    private var lastModificationDate: Date?

    // Dependencies - using non-optional since this is a required dependency
    private(set) var settingsStore: SettingsStore

    // Default initializer for container creation
    init() {
        // Default empty initialization, proper values will be set by injectDependencies
        self.settingsStore = SettingsStore()
    }

    func injectDependencies(_ container: DependencyContainer) {
        self.settingsStore = container.settingsStore
        logger.debug("SettingsStore injected successfully")
    }

    // Private subject to control when menu items are published
    private let menuItemsSubject = CurrentValueSubject<[MenuItem], Never>([])

    // Publishers - using the subject to avoid initial empty array publish
    var menuItemsPublisher: AnyPublisher<[MenuItem], Never> {
        menuItemsSubject.eraseToAnyPublisher()
    }

    var errorPublisher: AnyPublisher<Error?, Never> {
        $lastError.eraseToAnyPublisher()
    }

    // This will be called after dependencies are injected
    private var didSetupDependencies = false

    /// Setup after dependencies are injected using async/await
    /// Performs one-time initialization after dependencies are injected
    func setupAfterDependenciesInjected() async {
        guard !didSetupDependencies else {
            return // Silent return - avoid unnecessary logging
        }

        didSetupDependencies = true

        let result = await loadConfig()

        if case let .success(items) = result {
            if items.isEmpty {
                logger.notice("Initial config load: No menu items found")
            } else {
                logger.info("Initial config load completed with \(items.count) items")
            }
        } else if case let .failure(error) = result {
            logger.error("Initial config load failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Public Methods

    @discardableResult
    func loadConfig() async -> Result<[MenuItem], ConfigError> {
        logger.debug("loadConfig() called - will attempt to load menu configuration")

        guard let configURL = resolveConfigFileURL() else {
            logger.error("Failed to resolve config file URL")
            await MainActor.run {
                self.lastError = ConfigError.fileNotFound
            }
            return .failure(.fileNotFound)
        }

        logger.info("Loading config from \(configURL.path, privacy: .public)")

        // Use Task to read the file asynchronously
        let fileReadResult = await Task {
            readConfigFile(from: configURL)
        }.value

        switch fileReadResult {
        case let .failure(error):
            await MainActor.run {
                self.lastError = error
            }
            return .failure(error)

        case let .success(yamlString):
            logger.debug("Successfully read YAML file, length: \(yamlString.count) characters")

            // Validate the YAML format before parsing
            if yamlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                logger.error("Config file is empty")
                await MainActor.run {
                    self.lastError = ConfigError.emptyFile
                }
                return .failure(.emptyFile)
            }

            let parseResult = await Task {
                parseYAML(yamlString)
            }.value

            switch parseResult {
            case let .failure(error):
                await MainActor.run {
                    self.lastError = error
                }
                return .failure(error)

            case let .success(config):
                // Validate the parsed config
                if config.isEmpty {
                    logger.error("Config is empty, no menu items found")
                    await MainActor.run {
                        self.lastError = ConfigError.emptyConfiguration
                    }
                    return .failure(.emptyConfiguration)
                }

                // Validate the menu items structure
                let validationResult = validateMenuItems(config)
                switch validationResult {
                case let .failure(error):
                    await MainActor.run {
                        self.lastError = error
                    }
                    return .failure(error)

                case .success:
                    // Successfully parsed, update the menu items on the main actor
                    await MainActor.run {
                        logger.info("Config load successful, publishing \(config.count) menu items")
                        // Debug each menu item to verify their actions
                        for item in config {
                            logger.debug("Menu item: '\(item.title)' with key '\(item.key)'")
                            if let action = item.action {
                                logger.debug(" - Action: '\(action)'")
                                if item.actionClosure == nil {
                                    logger.error(" - No action closure generated for action: '\(action)'")
                                } else {
                                    logger.debug(" - Action closure successfully generated")
                                }
                            } else if let submenu = item.submenu {
                                logger.debug(" - Has submenu with \(submenu.count) items")
                            }
                        }

                        menuItems = config // Update the @Published property
                        menuItemsSubject.send(config) // Explicitly send to subject
                        lastError = nil
                    }
                    return .success(config)
                }
            }
        }
    }

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
        Task {
            await loadConfig()
        }
    }

    func openConfigFile() {
        guard let url = resolveConfigFileURL() else { return }
        NSWorkspace.shared.selectFile(
            url.path,
            inFileViewerRootedAtPath: url.deletingLastPathComponent().path
        )
    }

    func importSnippet(menuItems: [MenuItem], strategy: MergeStrategy) async throws {
        let validationResult = await Task {
            validateMenuItems(menuItems)
        }.value

        switch validationResult {
        case let .failure(validationError):
            logger.error("Snippet validation failed: \(validationError.localizedDescription)")
            await MainActor.run {
                self.lastError = validationError
            }
            throw validationError
        case .success:
            break
        }

        var currentConfig = menuItems

        // Apply merge strategy (can be done off main thread)
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
        let result = await saveMenuItems(currentConfig)
        switch result {
        case .success:
            return
        case let .failure(error):
            throw error
        }
    }

    func saveMenuItems(_ items: [MenuItem]) async -> Result<Void, ConfigError> {
        guard let url = resolveConfigFileURL() else {
            return .failure(ConfigError.fileNotFound)
        }

        let yamlResult = await Task {
            createCleanYaml(from: items)
        }.value

        // Check for YAML generation errors
        switch yamlResult {
        case let .failure(error):
            await MainActor.run {
                self.lastError = error
            }
            return .failure(error)

        case let .success(yamlString):
            do {
                // Write to file
                try yamlString.write(to: url, atomically: true, encoding: .utf8)
                logger.info("Successfully saved \(items.count) menu items to \(url.path, privacy: .public)")

                // Update the menu items on the main actor
                await MainActor.run {
                    menuItems = items
                    menuItemsSubject.send(items)
                    lastError = nil
                }

                return .success(())
            } catch {
                logger.error("Failed to save config: \(error.localizedDescription)")

                let wrappedError = ConfigError.readFailed(underlying: error)
                await MainActor.run {
                    self.lastError = wrappedError
                }

                return .failure(wrappedError)
            }
        }
    }

    /// Creates YAML using the standard encoder
    /// The MenuItem.encode(to:) method already handles skipping the ID
    /// - Returns: A Result with the YAML string or an error
    private func createCleanYaml(from items: [MenuItem]) -> Result<String, ConfigError> {
        let encoder = YAMLEncoder()
        do {
            let yamlString = try encoder.encode(items)
            return .success(yamlString)
        } catch {
            logger.error("Error creating YAML: \(error.localizedDescription)")
            return .failure(ConfigError.parsingFailed(underlying: error))
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
            } else if result.contains(where: { $0.key == newItem.key }) {
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

    @discardableResult
    func refreshIfNeeded() async -> Bool {
        if await checkConfigChanged() {
            await loadConfig()
            return true
        }
        return false
    }

    private func checkConfigChanged() async -> Bool {
        return await Task {
            hasConfigChanged()
        }.value
    }

    func resolveConfigFileURL() -> URL? {
        // Use the direct path
        if let url = settingsStore.configFileResolvedURL {
            logger.debug("Using direct path: \(url.path, privacy: .public)")
            return url
        } else {
            logger.notice("No configuration file path available, creating default config file")
            // Default to bundle location or create one in user Documents
            let defaultConfigPath = createDefaultConfigIfNeeded()

            if let path = defaultConfigPath?.path {
                logger.notice("Created default config at: \(path, privacy: .public)")
            } else {
                logger.error("Failed to create default config file")
            }

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
    private func validateMenuItems(_ items: [MenuItem]) -> Result<Void, ConfigError> {
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
                let result = validateMenuItems(submenu)
                if case let .failure(error) = result {
                    return .failure(error)
                }
            }
        }

        return .success(())
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
