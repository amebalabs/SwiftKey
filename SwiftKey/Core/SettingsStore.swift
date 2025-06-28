import SwiftUI
import Combine

class SettingsStore: ObservableObject, DependencyInjectable {
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

    enum OverlayStyle: String, CaseIterable {
        case panel = "Default"
        case hud = "Compact: HUD"
        case faceless = "Compact: Menu Bar"
        case cornerToast = "Minimal: Corner Toast"
    }

    enum OverlayScreenOption: String, CaseIterable, Codable {
        case primary = "Primary Screen"
        case mouse = "Screen with Mouse"
    }

    @AppStorage("ConfigFilePath") var configFilePath: String = "" {
        didSet { settingsChangedSubject.send() }
    }
    @AppStorage("MenuStateResetDelay") var menuStateResetDelay: Double = 3.0 {
        didSet { settingsChangedSubject.send() }
    }
    @AppStorage("UseHorizontalOverlayLayout") var useHorizontalOverlayLayout: Bool = true {
        didSet { settingsChangedSubject.send() }
    }
    @AppStorage("OverlayStyle") var overlayStyle: OverlayStyle = .panel {
        didSet { settingsChangedSubject.send() }
    }
    @AppStorage("OverlayScreenOption") var overlayScreenOption: OverlayScreenOption = .primary {
        didSet { settingsChangedSubject.send() }
    }
    @AppStorage("TriggerKeyHoldMode") var triggerKeyHoldMode: Bool = false {
        didSet { settingsChangedSubject.send() }
    }
    @AppStorage("NeedsOnboarding") var needsOnboarding: Bool = true {
        didSet { settingsChangedSubject.send() }
    }
    @AppStorage("AutomaticallyCheckForUpdates")
    public var automaticallyCheckForUpdates: Bool = true {
        didSet {
            // Use injected sparkleUpdater if available, otherwise fall back to singleton
            if let updater = sparkleUpdater {
                updater.automaticallyChecksForUpdates = automaticallyCheckForUpdates
            } else {
                SparkleUpdater.shared.automaticallyChecksForUpdates = automaticallyCheckForUpdates
            }
            settingsChangedSubject.send()
        }
    }

    @AppStorage("AutomaticallyDownloadUpdates")
    public var automaticallyDownloadUpdates: Bool = false {
        didSet {
            if let updater = sparkleUpdater {
                updater.automaticallyDownloadsUpdates = automaticallyDownloadUpdates
            } else {
                SparkleUpdater.shared.automaticallyDownloadsUpdates = automaticallyDownloadUpdates
            }
            settingsChangedSubject.send()
        }
    }

    @AppStorage("EnableBetaUpdates")
    public var enableBetaUpdates: Bool = false {
        didSet {
            if let updater = sparkleUpdater {
                updater.configureFeedURLs()
            } else {
                SparkleUpdater.shared.configureFeedURLs()
            }
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
