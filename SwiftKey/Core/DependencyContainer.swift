import Combine
import Foundation

class DependencyContainer {
    static let shared = DependencyContainer()
    
    // Services
    let configManager: ConfigManager
    let settingsStore: SettingsStore
    let menuState: MenuState
    let sparkleUpdater: SparkleUpdater
    let deepLinkHandler: DeepLinkHandler
    let keyboardManager: KeyboardManager
    
    private var cancellables = Set<AnyCancellable>()
    
    init(
        configManager: ConfigManager = ConfigManager.shared,
        settingsStore: SettingsStore? = nil,
        menuState: MenuState = MenuState(),
        sparkleUpdater: SparkleUpdater = SparkleUpdater.shared,
        deepLinkHandler: DeepLinkHandler = DeepLinkHandler.shared,
        keyboardManager: KeyboardManager = KeyboardManager.shared
    ) {
        // Create a new SettingsStore if one wasn't provided
        let settings = settingsStore ?? SettingsStore(sparkleUpdater: sparkleUpdater)
        self.configManager = configManager
        self.settingsStore = settings
        self.menuState = menuState
        self.sparkleUpdater = sparkleUpdater
        self.deepLinkHandler = deepLinkHandler
        self.keyboardManager = keyboardManager

        // Inject dependencies into components in the correct order
        // First inject into services that don't depend on others
        sparkleUpdater.injectDependencies(self)
        settings.injectDependencies(self)

        // Then inject into services that depend on the above
        configManager.injectDependencies(self)
        menuState.injectDependencies(self)
        deepLinkHandler.injectDependencies(self)
        keyboardManager.injectDependencies(self)

        // Set up services that need post-injection initialization
        configManager.setupAfterDependenciesInjected()

        // Set up initial connections between components
        setupComponentConnections()
    }

    /// Connect components via publishers/subscribers
    private func setupComponentConnections() {
        // Connect ConfigManager to MenuState
        configManager.menuItemsPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] items in
                guard let self = self else { return }
                self.menuState.rootMenu = items
                print("DependencyContainer: Updated menu items: \(items.count) items")
                
                // Re-register keyboard shortcuts whenever menu items are updated
                self.keyboardManager.registerMenuHotkeys(items)
                print("DependencyContainer: Re-registered keyboard shortcuts for menu items")
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
                        print("Config error: \(configError.localizedDescription)")
                    }
                }
            }
            .store(in: &cancellables)
    }
}

protocol DependencyInjectable {
    func injectDependencies(_ container: DependencyContainer)
}
