import SwiftUI

class SettingsStore: ObservableObject, DependencyInjectable {
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
    }

    enum OverlayScreenOption: String, CaseIterable, Codable {
        case primary = "Primary Screen"
        case mouse = "Screen with Mouse"
    }

    @AppStorage("ConfigFilePath") var configFilePath: String = ""
    @AppStorage("MenuStateResetDelay") var menuStateResetDelay: Double = 3.0
    @AppStorage("UseHorizontalOverlayLayout") var useHorizontalOverlayLayout: Bool = true
    @AppStorage("OverlayStyle") var overlayStyle: OverlayStyle = .panel
    @AppStorage("OverlayScreenOption") var overlayScreenOption: OverlayScreenOption = .primary
    @AppStorage("TriggerKeyHoldMode") var triggerKeyHoldMode: Bool = false
    @AppStorage("NeedsOnboarding") var needsOnboarding: Bool = true
    @AppStorage("AutomaticallyCheckForUpdates")
    public var automaticallyCheckForUpdates: Bool = true {
        didSet {
            // Use injected sparkleUpdater if available, otherwise fall back to singleton
            if let updater = sparkleUpdater {
                updater.automaticallyChecksForUpdates = automaticallyCheckForUpdates
            } else {
                SparkleUpdater.shared.automaticallyChecksForUpdates = automaticallyCheckForUpdates
            }
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
