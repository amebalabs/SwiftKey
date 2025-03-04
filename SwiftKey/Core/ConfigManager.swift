import AppKit
import Combine
import Foundation
import Yams

class ConfigManager: DependencyInjectable, ObservableObject {

    static let shared = ConfigManager()

    // Published properties for reactive updates
    @Published private(set) var menuItems: [MenuItem] = []
    @Published private(set) var lastError: Error?
    @Published private(set) var lastUpdateTime: Date?

    private var lastModificationDate: Date?

    // Dependencies
    var settingsStore: SettingsStore!

    func injectDependencies(_ container: DependencyContainer) {
        self.settingsStore = container.settingsStore
        print("ConfigManager: SettingsStore injected successfully")
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
        
        print("ConfigManager: Setting up after dependencies injected")
        
        // Load config and make sure it's processed
        DispatchQueue.main.async { [weak self] in
            self?.loadConfig()
            
            // If no config was loaded yet, try again with a delay
            // This helps with first launch scenarios
            if let self = self, self.menuItems.isEmpty {
                print("ConfigManager: Menu items empty after initial load, retrying...")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.loadConfig()
                }
            }
        }
    }

    // MARK: - Public Methods

    /// Loads the configuration from the YAML file
    func loadConfig() {
        print("ConfigManager: loadConfig() called")

        // Make sure dependencies are ready
        guard settingsStore != nil else {
            print("ConfigManager: SettingsStore not yet injected, delaying load")
            return
        }
        
        guard let configURL = resolveConfigFileURL() else {
            print("ConfigManager: Failed to resolve config file URL")
            self.lastError = ConfigError.fileNotFound
            return
        }

        print("ConfigManager: Loading config from \(configURL.path)")

        // Read the file content
        let yamlString: String
        do {
            yamlString = try String(contentsOf: configURL, encoding: .utf8)
            print("ConfigManager: Successfully read YAML file, length: \(yamlString.count) characters")
        } catch let error as NSError {
            if error.domain == NSCocoaErrorDomain {
                switch error.code {
                case NSFileReadNoSuchFileError:
                    print("ConfigManager: File not found at \(configURL.path)")
                    self.lastError = ConfigError.fileNotFound
                case NSFileReadNoPermissionError:
                    print("ConfigManager: Permission denied to read \(configURL.path)")
                    self.lastError = ConfigError.accessDenied
                default:
                    print("ConfigManager: Failed to read file: \(error.localizedDescription)")
                    self.lastError = ConfigError.readFailed(underlying: error)
                }
            } else {
                print("ConfigManager: Error loading config file: \(error.localizedDescription)")
                self.lastError = ConfigError.readFailed(underlying: error)
            }
            return
        }

        // Validate the YAML format before parsing
        if yamlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            print("ConfigManager: Config file is empty")
            self.lastError = ConfigError.emptyFile
            return
        }

        // Parse the YAML
        let decoder = YAMLDecoder()
        let config: [MenuItem]

        do {
            // First try to decode as a generic YAML to check structure
            if let yamlObject = try Yams.load(yaml: yamlString) {
                // Validate that the YAML is an array at the root level
                guard yamlObject is [Any] else {
                    print("ConfigManager: Invalid YAML format - root should be an array")
                    self.lastError = ConfigError.invalidYamlFormat(
                        message: "Root element must be an array of menu items",
                        line: 1,
                        column: 1
                    )
                    return
                }
            }
            
            // Now try to decode to the actual model
            config = try decoder.decode([MenuItem].self, from: yamlString)
            print("ConfigManager: Successfully decoded \(config.count) menu items")
        } catch let yamlError as YamlError {
            // Detailed handling for Yams parsing errors
            let lineInfo = extractLineInfo(from: yamlError)
            print("ConfigManager: YAML parsing error at \(lineInfo.line):\(lineInfo.column): \(yamlError.localizedDescription)")
            self.lastError = ConfigError.invalidYamlFormat(
                message: yamlError.localizedDescription,
                line: lineInfo.line,
                column: lineInfo.column
            )
            return
        } catch let decodingError as DecodingError {
            // Detailed handling for Swift Decodable errors
            print("ConfigManager: Decoding error: \(decodingError.localizedDescription)")
            
            switch decodingError {
            case let .keyNotFound(key, context):
                print("ConfigManager: Missing required key '\(key.stringValue)' in context: \(context.debugDescription)")
                self.lastError = ConfigError.missingRequiredField(
                    field: key.stringValue,
                    context: context.debugDescription
                )
            case let .typeMismatch(type, context):
                print("ConfigManager: Type mismatch for \(type) in context: \(context.debugDescription)")
                let fieldName = context.codingPath.last?.stringValue ?? "unknown"
                self.lastError = ConfigError.typeMismatch(
                    field: fieldName,
                    context: context.debugDescription
                )
            case let .valueNotFound(type, context):
                print("ConfigManager: Value not found for \(type) in context: \(context.debugDescription)")
                let fieldName = context.codingPath.last?.stringValue ?? "unknown"
                self.lastError = ConfigError.missingRequiredField(
                    field: fieldName,
                    context: context.debugDescription
                )
            case .dataCorrupted(let context):
                print("ConfigManager: Data corrupted in context: \(context.debugDescription)")
                self.lastError = ConfigError.invalidYamlFormat(
                    message: context.debugDescription,
                    line: 0,
                    column: 0
                )
            @unknown default:
                self.lastError = ConfigError.parsingFailed(underlying: decodingError)
            }
            return
        } catch let otherError {
            // Fallback for other errors
            print("ConfigManager: YAML parsing error: \(otherError.localizedDescription)")
            self.lastError = ConfigError.parsingFailed(underlying: otherError)
            return
        }

        // Validate the parsed config
        if config.isEmpty {
            print("ConfigManager: Config is empty, no menu items found")
            self.lastError = ConfigError.emptyConfiguration
            return
        }
        
        // Validate the menu items structure
        do {
            try validateMenuItems(config)
        } catch let validationError as ConfigError {
            print("ConfigManager: Menu item validation failed: \(validationError.localizedDescription)")
            self.lastError = validationError
            return
        } catch {
            print("ConfigManager: Unexpected validation error: \(error.localizedDescription)")
            self.lastError = ConfigError.unknown(underlying: error)
            return
        }

        // Successfully parsed, update the menu items
        DispatchQueue.main.async { [weak self] in
            print("ConfigManager: Updating menu items: \(config.count) items")
            self?.menuItems = config
            self?.lastError = nil
            self?.lastUpdateTime = Date()
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
                    print("ConfigManager: Initial config file mod date: \(modDate)")
                    return false
                }

                if let lastMod = lastModificationDate, modDate > lastMod {
                    print("ConfigManager: Config file changed - old: \(lastMod), new: \(modDate)")
                    lastModificationDate = modDate
                    return true
                }
            }
        } catch {
            print("Error reading file attributes: \(error)")
        }
        return false
    }

    @discardableResult func refreshIfNeeded() -> Bool {
        if hasConfigChanged() {
            loadConfig()
            return true
        }
        return false
    }

    /// Helper to resolve the config file URL using direct file path
    func resolveConfigFileURL() -> URL? {
        // Ensure we have a valid reference to settings store
        guard let settings = settingsStore else {
            print("Error: SettingsStore is not properly injected into ConfigManager")
            return nil
        }

        // Use the direct path
        if let url = settings.configFileResolvedURL {
            print("ConfigManager: Using direct path: \(url.path)")
            return url
        } else {
            print("ConfigManager: No configuration file path available")
            // Default to bundle location or create one in user Documents
            let defaultConfigPath = createDefaultConfigIfNeeded()
            print("ConfigManager: Using default config at: \(defaultConfigPath?.path ?? "none")")
            return defaultConfigPath
        }
    }

    private func createDefaultConfigIfNeeded() -> URL? {
        guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("ConfigManager: Could not access Documents directory")
            assert(true)
            return nil
        }

        let configURL = documentsDir.appendingPathComponent("menu.yaml")

        if FileManager.default.fileExists(atPath: configURL.path) {
            print("ConfigManager: Found existing config at \(configURL.path)")
            return configURL
        }
        
        // Get the default config from the app bundle
        guard let bundledConfigURL = Bundle.main.url(forResource: "menu", withExtension: "yaml") else {
            print("ConfigManager: Could not find bundled menu.yaml")
            assert(true)
            return nil
        }
        
        do {
            try FileManager.default.copyItem(at: bundledConfigURL, to: configURL)
            print("ConfigManager: Copied bundled config to \(configURL.path)")
            
            settingsStore.configFilePath = configURL.path
            return configURL
        } catch {
            print("ConfigManager: Failed to copy bundled config: \(error)")
        }
        assert(true)
        return nil
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
           let match = regex.firstMatch(in: errorDescription, range: NSRange(errorDescription.startIndex..., in: errorDescription)) {
            
            if let lineRange = Range(match.range(at: 1), in: errorDescription),
               let columnRange = Range(match.range(at: 2), in: errorDescription) {
                line = Int(errorDescription[lineRange]) ?? 0
                column = Int(errorDescription[columnRange]) ?? 0
            }
        }
        
        return (line, column)
    }
    
    /// Validates menu items recursively
    private func validateMenuItems(_ items: [MenuItem]) throws {
        for item in items {
            // Validate key format (should be a single character)
            if item.key.count != 1 {
                throw ConfigError.invalidYamlFormat(
                    message: "Key must be a single character, found '\(item.key)'",
                    line: 0,
                    column: 0
                )
            }
            
            // Validate title is not empty
            if item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ConfigError.invalidYamlFormat(
                    message: "Title cannot be empty for key '\(item.key)'",
                    line: 0,
                    column: 0
                )
            }
            
            // Validate that if there's no submenu, there must be an action
            if item.submenu == nil && item.action == nil {
                throw ConfigError.invalidYamlFormat(
                    message: "Menu item '\(item.title)' (key: \(item.key)) must have either a submenu or an action",
                    line: 0,
                    column: 0
                )
            }
            
            // Validate action format if present
            if let action = item.action {
                if !isValidActionFormat(action) {
                    throw ConfigError.invalidYamlFormat(
                        message: "Invalid action format: '\(action)' for key '\(item.key)'",
                        line: 0,
                        column: 0
                    )
                }
            }
            
            // Validate hotkey format if present
            if let hotkey = item.hotkey, !isValidHotkeyFormat(hotkey) {
                throw ConfigError.invalidYamlFormat(
                    message: "Invalid hotkey format: '\(hotkey)' for key '\(item.key)'",
                    line: 0,
                    column: 0
                )
            }
            
            // Recursively validate submenu if present
            if let submenu = item.submenu {
                try validateMenuItems(submenu)
            }
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
        for i in 0..<(components.count - 1) {
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
        }
    }
}
