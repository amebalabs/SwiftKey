import Combine
import Foundation
import os

class DependencyContainer {
    static let shared = DependencyContainer()

    // Logger for this class
    private let logger = AppLogger.core

    // Services
    let configManager: ConfigManager
    let settingsStore: SettingsStore
    let menuState: MenuState
    let sparkleUpdater: SparkleUpdater
    let deepLinkHandler: DeepLinkHandler
    let keyboardManager: KeyboardManager
    let snippetsStore: SnippetsStore

    private var cancellables = Set<AnyCancellable>()

    init(
        configManager: ConfigManager = ConfigManager.shared,
        settingsStore: SettingsStore? = nil,
        menuState: MenuState = MenuState(),
        sparkleUpdater: SparkleUpdater = SparkleUpdater.shared,
        deepLinkHandler: DeepLinkHandler = DeepLinkHandler.shared,
        keyboardManager: KeyboardManager = KeyboardManager.shared,
        snippetsStore: SnippetsStore = SnippetsStore()
    ) {
        // Create a new SettingsStore if one wasn't provided
        let settings = settingsStore ?? SettingsStore(sparkleUpdater: sparkleUpdater)
        self.configManager = configManager
        self.settingsStore = settings
        self.menuState = menuState
        self.sparkleUpdater = sparkleUpdater
        self.deepLinkHandler = deepLinkHandler
        self.keyboardManager = keyboardManager
        self.snippetsStore = snippetsStore

        // Inject dependencies into components in the correct order
        // First inject into services that don't depend on others
        sparkleUpdater.injectDependencies(self)
        settings.injectDependencies(self)

        // Then inject into services that depend on the above
        configManager.injectDependencies(self)
        menuState.injectDependencies(self)
        deepLinkHandler.injectDependencies(self)
        keyboardManager.injectDependencies(self)
        snippetsStore.injectDependencies(self)

        logger.notice("Initializing SwiftKey dependency container")

        setupComponentConnections()

        Task {
            await configManager.setupAfterDependenciesInjected()
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
