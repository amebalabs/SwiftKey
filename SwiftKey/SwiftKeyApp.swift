import AppKit
import SwiftUI

@main
struct OverlayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(SettingsStore.shared)
        }
    }
}
