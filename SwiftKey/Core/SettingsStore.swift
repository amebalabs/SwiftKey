import SwiftUI
import Combine

class SettingsStore: ObservableObject, DependencyInjectable, SettingsStoring {
    // Publisher for settings changes
    private let settingsChangedSubject = PassthroughSubject<Void, Never>()
    var settingsChanged: AnyPublisher<Void, Never> {
        settingsChangedSubject.eraseToAnyPublisher()
    }
    // Dependencies
    private var sparkleUpdater: SparkleUpdater?

    init(sparkleUpdater: SparkleUpdater? = nil) {
        self.sparkleUpdater = sparkleUpdater
    }

    func injectDependencies(_ container: DependencyContainer) {
        self.sparkleUpdater = container.sparkleUpdater
    }

    /// Returns the injected updater if available, otherwise the shared instance
    private var activeUpdater: SparkleUpdater {
        sparkleUpdater ?? SparkleUpdater.shared
    }

    enum OverlayStyle: String, CaseIterable {
        case panel = "Default"
        case hud = "Compact: HUD"
        case faceless = "Compact: Menu Bar"
        case cornerToast = "Compact: Corner Toast"
    }

    enum OverlayScreenOption: String, CaseIterable, Codable {
        case primary = "Primary Screen"
        case mouse = "Screen with Mouse"
    }

    @AppStorage("ConfigFilePath", store: AppPaths.defaults) var configFilePath: String = "" {
        didSet { settingsChangedSubject.send() }
    }
    @AppStorage("MenuStateResetDelay", store: AppPaths.defaults) var menuStateResetDelay: Double = 3.0 {
        didSet { settingsChangedSubject.send() }
    }
    @AppStorage("UseHorizontalOverlayLayout", store: AppPaths.defaults) var useHorizontalOverlayLayout: Bool = true {
        didSet { settingsChangedSubject.send() }
    }
    @AppStorage("OverlayStyle", store: AppPaths.defaults) var overlayStyle: OverlayStyle = .panel {
        didSet { settingsChangedSubject.send() }
    }
    @AppStorage("OverlayScreenOption", store: AppPaths.defaults) var overlayScreenOption: OverlayScreenOption = .primary {
        didSet { settingsChangedSubject.send() }
    }
    @AppStorage("TriggerKeyHoldMode", store: AppPaths.defaults) var triggerKeyHoldMode: Bool = false {
        didSet { settingsChangedSubject.send() }
    }
    @AppStorage("NeedsOnboarding", store: AppPaths.defaults) var needsOnboarding: Bool = true {
        didSet { settingsChangedSubject.send() }
    }
    @AppStorage("AutomaticallyCheckForUpdates", store: AppPaths.defaults)
    public var automaticallyCheckForUpdates: Bool = true {
        didSet {
            activeUpdater.automaticallyChecksForUpdates = automaticallyCheckForUpdates
            settingsChangedSubject.send()
        }
    }

    @AppStorage("AutomaticallyDownloadUpdates", store: AppPaths.defaults)
    public var automaticallyDownloadUpdates: Bool = false {
        didSet {
            activeUpdater.automaticallyDownloadsUpdates = automaticallyDownloadUpdates
            settingsChangedSubject.send()
        }
    }

    @AppStorage("EnableBetaUpdates", store: AppPaths.defaults)
    public var enableBetaUpdates: Bool = false {
        didSet {
            activeUpdater.configureFeedURLs()
            settingsChangedSubject.send()
        }
    }

    var facelessMode: Bool {
        overlayStyle == .faceless
    }

    var configFileResolvedURL: URL? {
        guard let path = configFilePath as NSString?, path != "" else {
            return nil
        }
        return URL(fileURLWithPath: path.expandingTildeInPath).resolvingSymlinksInPath()
    }

    var configFileResolvedPath: String? {
        configFileResolvedURL?.path
    }
}
