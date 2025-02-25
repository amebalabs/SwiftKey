import AppKit
import SwiftUI

@main
struct SwiftKeyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    private let container = DependencyContainer.shared

    init() {
        print("SwiftKey starting with dependency container initialized")
    }

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(container.settingsStore)
                .environmentObject(container.menuState)
        }
    }
}
