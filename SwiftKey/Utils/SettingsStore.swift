import SwiftUI

class SettingsStore: ObservableObject {
    public static let shared = SettingsStore()
    public enum OverlayStyle: String, CaseIterable {
        case panel = "Default"
        case hud = "Compact: HUD"
        case faceless = "Compact: Menu Bar"
    }

    public enum OverlayScreenOption: String, CaseIterable, Codable {
        case primary = "Primary Screen"
        case mouse = "Screen with Mouse"
    }

    @AppStorage("IsShowingMenuBar") public var isShowingMenuBar: Bool = true
    @AppStorage("ConfigFilePath") public var configFilePath: String = ""
    @AppStorage("MenuStateResetDelay") public var menuStateResetDelay: Double = 3.0
    @AppStorage("UseHorizontalOverlayLayout") public var useHorizontalOverlayLayout: Bool = true
    @AppStorage("OverlayStyle") public var overlayStyle: OverlayStyle = .panel
    @AppStorage("OverlayScreenOption") public var overlayScreenOption: OverlayScreenOption = .primary
    @AppStorage("NeedsOnboarding") public var needsOnboarding: Bool = true
    @AppStorage("AutomaticallyCheckForUpdates")
    public var automaticallyCheckForUpdates: Bool = true {
        didSet {
            SparkleUpdater.shared.automaticallyChecksForUpdates = automaticallyCheckForUpdates
        }
    }

    @AppStorage("AutomaticallyDownloadUpdates")
    public var automaticallyDownloadUpdates: Bool = false {
        didSet {
            SparkleUpdater.shared.automaticallyDownloadsUpdates = automaticallyDownloadUpdates
        }
    }

    @AppStorage("EnableBetaUpdates")
    public var enableBetaUpdates: Bool = false {
        didSet {
            SparkleUpdater.shared.configureFeedURLs()
        }
    }

    var facelessMode: Bool {
        overlayStyle == .faceless
    }

    var configFileResolvedURL: URL? {
        guard let path = configFilePath as NSString? else { return nil }
        return URL(fileURLWithPath: path.expandingTildeInPath).resolvingSymlinksInPath()
    }

    var configFileResolvedPath: String? {
        configFileResolvedURL?.path
    }
}
