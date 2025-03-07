import AppKit
import os
import SwiftUI

@main
struct SwiftKeyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    private let container = DependencyContainer.shared
    private let logger = AppLogger.app

    init() {
        logger.notice("SwiftKey starting with dependency container initialized")
    }

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(container.settingsStore)
                .environmentObject(container.menuState)
        }
    }
}
