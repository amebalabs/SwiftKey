import AppKit
import os
import SwiftUI

@main
struct SwiftKeyApp: App {
    private let logger = AppLogger.app

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate: AppDelegate

    var container: DependencyContainer {
        return appDelegate.container
    }

    init() {
        let container = DependencyContainer()
        AppDelegate.initialContainer = container

        logger.notice("SwiftKey starting with dependency container initialized")
    }

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(container.settingsStore)
                .environmentObject(container.menuState)
                .environmentObject(container.configManager)
                .environmentObject(container.sparkleUpdater)
                .onAppear {
                    // Show dock icon when settings window opens
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                }
                .onDisappear {
                    // Hide dock icon when settings window closes
                    NSApp.setActivationPolicy(.accessory)
                }
        }
    }
}
