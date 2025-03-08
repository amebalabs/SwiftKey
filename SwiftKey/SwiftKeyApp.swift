import AppKit
import os
import SwiftUI

@main
struct SwiftKeyApp: App {
    private let logger = AppLogger.app
    
    // Use the NSApplicationDelegateAdaptor to create an AppDelegate instance
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate: AppDelegate
    
    // Create a computed property to access the container through the AppDelegate
    private var container: DependencyContainer {
        return appDelegate.container
    }
    
    init() {
        // Create the container and store it in the static property for AppDelegate to access
        let container = DependencyContainer()
        AppDelegate.initialContainer = container
        
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
