import AppKit
import Combine
import Foundation
import Yams

class ConfigManager: DependencyInjectable {

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
        loadConfig()
    }

    // MARK: - Public Methods

    /// Loads the configuration from the YAML file
    func loadConfig() {
        print("ConfigManager: loadConfig() called")

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
            config = try decoder.decode([MenuItem].self, from: yamlString)
            print("ConfigManager: Successfully decoded \(config.count) menu items")
        } catch let yamlError {
            // Process YAML parsing errors with more detail
            print("ConfigManager: YAML parsing error: \(yamlError.localizedDescription)")
            self.lastError = ConfigError.parsingFailed(underlying: yamlError)
            return
        }

        // Validate the parsed config
        if config.isEmpty {
            print("ConfigManager: Config is empty, no menu items found")
            self.lastError = ConfigError.emptyConfiguration
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

        // Create a security-scoped bookmark
        do {
            let bookmarkData = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            settingsStore.configFileBookmark = bookmarkData
        } catch {
            print("Error creating bookmark: \(error)")
            self.lastError = error
        }

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

    /// Helper to resolve the saved security-scoped bookmark
    func resolveConfigFileURL() -> URL? {
        // Ensure we have a valid reference to settings store
        guard let settings = settingsStore else {
            print("Error: SettingsStore is not properly injected into ConfigManager")
            return nil
        }

        // Check if we have a bookmark
        if let bookmarkData = settings.configFileBookmark {
            var isStale = false
            do {
                let url = try URL(
                    resolvingBookmarkData: bookmarkData,
                    options: .withSecurityScope,
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )

                if isStale {
                    print("Bookmark is stale, please re-select the configuration file.")
                }

                guard url.startAccessingSecurityScopedResource() else {
                    print("Couldn't access the resource via the security-scoped bookmark.")
                    return nil
                }

                print("ConfigManager: Resolved bookmark to URL: \(url.path)")
                return url
            } catch {
                print("Error resolving bookmark: \(error)")
                return settings.configFileResolvedURL
            }
        } else {
            // No bookmark, use the direct path
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
    }

    private func createDefaultConfigIfNeeded() -> URL? {
        guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("ConfigManager: Could not access Documents directory")
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
            return createFallbackConfig(at: configURL)
        }
        
        do {
            try FileManager.default.copyItem(at: bundledConfigURL, to: configURL)
            print("ConfigManager: Copied bundled config to \(configURL.path)")
            
            settingsStore.configFilePath = configURL.path
            
            return configURL
        } catch {
            print("ConfigManager: Failed to copy bundled config: \(error)")
            return createFallbackConfig(at: configURL)
        }
    }
    
    /// Creates a minimal fallback config if the bundled config can't be used
    private func createFallbackConfig(at url: URL) -> URL? {
        let fallbackConfig = """
        # Minimal SwiftKey configuration
        
        - key: "c"
          title: "Launch Calculator"
          action: "launch:///System/Applications/Calculator.app"
          
        - key: "n"
          title: "Launch Notes"
          action: "launch:///System/Applications/Notes.app"
          
        - key: "s"
          title: "Settings"
          submenu:
            - key: "1"
              title: "Open SwiftKey Settings"
              action: "shell://open -a SwiftKey --args --preferences"
            - key: "2" 
              title: "Open System Settings"
              action: "launch:///System/Applications/System Settings.app"
        """
        
        do {
            try fallbackConfig.write(to: url, atomically: true, encoding: .utf8)
            print("ConfigManager: Created fallback config at \(url.path)")
            
            settingsStore.configFilePath = url.path
            
            return url
        } catch {
            print("ConfigManager: Failed to create fallback config: \(error)")
            return nil
        }
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
        case let .unknown(error):
            return "Unknown error processing configuration: \(error.localizedDescription)"
        }
    }
}
