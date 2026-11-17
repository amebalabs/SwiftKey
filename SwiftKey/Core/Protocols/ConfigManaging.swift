import Foundation
import Combine

/// Protocol for configuration management
protocol ConfigManaging: AnyObject {
    /// Current menu items
    var menuItems: [MenuItem] { get }

    /// Current configuration error, if any
    var configError: ConfigError? { get }

    /// Current validation issues
    var validationIssues: [ValidationIssue] { get }

    /// Publisher for menu items changes
    var menuItemsPublisher: AnyPublisher<[MenuItem], Never> { get }

    /// Loads configuration from the configured source
    func loadConfiguration() async -> Result<[MenuItem], ConfigError>

    /// Reloads configuration from disk
    func reloadConfiguration() async

    /// Validates the given menu items
    func validateMenuItems(_ items: [MenuItem]) -> [ValidationIssue]

    /// Saves configuration
    func saveConfiguration(_ items: [MenuItem]) async throws

    /// Returns the URL of the current configuration file
    var configFileURL: URL? { get }
}

/// Protocol for configuration file watching
protocol ConfigWatching: AnyObject {
    /// Starts watching the configuration file for changes
    func startWatching()

    /// Stops watching the configuration file
    func stopWatching()

    /// Publisher that emits when the configuration file changes
    var fileChangedPublisher: AnyPublisher<Void, Never> { get }
}
