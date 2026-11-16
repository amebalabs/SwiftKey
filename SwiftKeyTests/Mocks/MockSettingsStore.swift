import Foundation
import Combine
@testable import SwiftKey

final class MockSettingsStore: SettingsStoring {

    // MARK: - Configuration
    var configFilePath: String = ""

    var configFileResolvedURL: URL? {
        guard !configFilePath.isEmpty else { return nil }
        return URL(fileURLWithPath: (configFilePath as NSString).expandingTildeInPath)
    }

    var configFileResolvedPath: String? {
        configFileResolvedURL?.path
    }

    // MARK: - Overlay Settings
    var overlayStyle: SettingsStore.OverlayStyle = .panel
    var overlayScreenOption: SettingsStore.OverlayScreenOption = .primary
    var useHorizontalOverlayLayout: Bool = true
    var menuStateResetDelay: Double = 3.0

    // MARK: - Behavior
    var triggerKeyHoldMode: Bool = false
    var needsOnboarding: Bool = true

    // MARK: - Updates
    var automaticallyCheckForUpdates: Bool = true
    var automaticallyDownloadUpdates: Bool = false
    var enableBetaUpdates: Bool = false

    // MARK: - Computed
    var facelessMode: Bool {
        overlayStyle == .faceless
    }

    // MARK: - Change Notification
    private let settingsChangedSubject = PassthroughSubject<Void, Never>()

    var settingsChanged: AnyPublisher<Void, Never> {
        settingsChangedSubject.eraseToAnyPublisher()
    }

    // MARK: - Test Helpers

    func simulateSettingsChange() {
        settingsChangedSubject.send()
    }

    func reset() {
        configFilePath = ""
        overlayStyle = .panel
        overlayScreenOption = .primary
        useHorizontalOverlayLayout = true
        menuStateResetDelay = 3.0
        triggerKeyHoldMode = false
        needsOnboarding = true
        automaticallyCheckForUpdates = true
        automaticallyDownloadUpdates = false
        enableBetaUpdates = false
    }
}
