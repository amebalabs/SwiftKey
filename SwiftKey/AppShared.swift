import Cocoa
import os
import SwiftUI

class AppShared: NSObject {
    // MARK: - Static Helpers

    static func showAbout() {
        NSApp.orderFrontStandardAboutPanel()
    }

    static var isDarkTheme: Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") != nil
    }

    static var isDarkStatusBar: Bool {
        let currentAppearance = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength).button?
            .effectiveAppearance
        return currentAppearance?.bestMatch(from: [.aqua, .darkAqua]) == .aqua
    }

    static var isReduceTransparencyEnabled: Bool {
        UserDefaults(suiteName: "com.apple.universalaccess.plist")?.bool(forKey: "reduceTransparency") ?? false
    }
}
