import Combine
import Foundation
import os

/// Central container for all application dependencies
/// This class manages the lifecycle and dependencies of all major services in the app
class DependencyContainer {
    // No more singleton - each instance is a complete container of all application services

    // Logger for this class
    private let logger = AppLogger.core

    // Services - all non-optional since they're fully managed by the container
    let configManager: ConfigManager
    let settingsStore: SettingsStore
    let menuState: MenuState
    let sparkleUpdater: SparkleUpdater
    let deepLinkHandler: DeepLinkHandler
    let keyboardManager: KeyboardManager
    let snippetsStore: SnippetsStore
    let dynamicMenuLoader: DynamicMenuLoader
    let shortcutsManager: ShortcutsManager

    // Track active subscriptions
    private var cancellables = Set<AnyCancellable>()

    init(
        // Use factory methods instead of singletons for better testability
        configManager: ConfigManager? = nil,
        settingsStore: SettingsStore? = nil,
        menuState: MenuState? = nil,
        sparkleUpdater: SparkleUpdater? = nil,
        deepLinkHandler: DeepLinkHandler? = nil,
        keyboardManager: KeyboardManager? = nil,
        snippetsStore: SnippetsStore? = nil,
        dynamicMenuLoader: DynamicMenuLoader? = nil,
        shortcutsManager: ShortcutsManager? = nil
    ) {
        self.sparkleUpdater = sparkleUpdater ?? SparkleUpdater.shared
        
        // Now create other components using factory methods or constructors
        self.settingsStore = settingsStore ?? SettingsStore(sparkleUpdater: self.sparkleUpdater)
        self.configManager = configManager ?? ConfigManager.create()
        self.menuState = menuState ?? MenuState()
        self.deepLinkHandler = deepLinkHandler ?? DeepLinkHandler.create()
        self.keyboardManager = keyboardManager ?? KeyboardManager.create()
        self.snippetsStore = snippetsStore ?? SnippetsStore()
        self.dynamicMenuLoader = dynamicMenuLoader ?? DynamicMenuLoader.create()
        self.shortcutsManager = shortcutsManager ?? ShortcutsManager.create()

        // Inject dependencies into components in the correct order
        // First inject into services that don't depend on others
        self.sparkleUpdater.injectDependencies(self)
        self.settingsStore.injectDependencies(self)

        // Then inject into services that depend on the above
        self.configManager.injectDependencies(self)
        self.menuState.injectDependencies(self)
        self.deepLinkHandler.injectDependencies(self)
        self.keyboardManager.injectDependencies(self)
        self.snippetsStore.injectDependencies(self)
        self.dynamicMenuLoader.injectDependencies(self)
        self.shortcutsManager.injectDependencies(self)

        logger.notice("Initializing SwiftKey dependency container")

        setupComponentConnections()

        Task {
            await configManager?.setupAfterDependenciesInjected()
        }
    }

    /// Connect components via publishers/subscribers
    private func setupComponentConnections() {
        // Connect ConfigManager to MenuState
        configManager.menuItemsPublisher
            .receive(on: RunLoop.main)
            .filter { !$0.isEmpty } // Skip empty arrays completely
            .sink { [weak self] items in
                guard let self = self else { return }

                self.logger.debug("Menu publisher received update: \(items.count) items")
                self.menuState.rootMenu = items
                self.menuState.reset()
                self.keyboardManager.registerMenuHotkeys(items)
                self.logger.debug("Re-registered keyboard shortcuts with \(items.count) menu items")
            }
            .store(in: &cancellables)

        // Connect errors to a notification system
        configManager.errorPublisher
            .receive(on: RunLoop.main)
            .compactMap { $0 }
            .sink { error in
                if let configError = error as? ConfigError {
                    switch configError {
                    case .fileNotFound, .accessDenied:
                        notifyUser(title: "Configuration Error", message: configError.localizedDescription)
                    default:
                        self.logger.error("Config error: \(configError.localizedDescription)")
                    }
                }
            }
            .store(in: &cancellables)
    }
}

protocol DependencyInjectable {
    func injectDependencies(_ container: DependencyContainer)
}
