import Foundation
import Combine

/// Protocol for user settings storage
protocol SettingsStoring: AnyObject {
    // MARK: - Configuration
    var configFilePath: String { get set }
    var configFileResolvedURL: URL? { get }
    var configFileResolvedPath: String? { get }

    // MARK: - Overlay Settings
    var overlayStyle: SettingsStore.OverlayStyle { get set }
    var overlayScreenOption: SettingsStore.OverlayScreenOption { get set }
    var useHorizontalOverlayLayout: Bool { get set }
    var menuStateResetDelay: Double { get set }

    // MARK: - Behavior
    var triggerKeyHoldMode: Bool { get set }
    var needsOnboarding: Bool { get set }

    // MARK: - Updates
    var automaticallyCheckForUpdates: Bool { get set }
    var automaticallyDownloadUpdates: Bool { get set }
    var enableBetaUpdates: Bool { get set }

    // MARK: - Computed
    var facelessMode: Bool { get }

    // MARK: - Change Notification
    var settingsChanged: AnyPublisher<Void, Never> { get }
}
