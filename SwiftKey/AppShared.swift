import Cocoa
import os
import SwiftUI

class AppShared: NSObject {
    public static func changeConfigFile() {
        let dialog = NSOpenPanel()
        dialog.message = "Choose your configuration file"
        dialog.showsHiddenFiles = false
        dialog.canChooseDirectories = false
        dialog.canChooseFiles = true
        dialog.allowsMultipleSelection = false

        guard dialog.runModal() == .OK, let url = dialog.url else { return }
        SettingsStore.shared.configFilePath = url.path
        // Create a security-scoped bookmark.
        do {
            let bookmarkData = try url.bookmarkData(options: .withSecurityScope,
                                                    includingResourceValuesForKeys: nil,
                                                    relativeTo: nil)
            SettingsStore.shared.configFileBookmark = bookmarkData
        } catch {
            print("Error creating bookmark: \(error)")
        }
        reloadConfig()
    }

    public static func openConfigFile() {
        guard let url = resolveConfigFileURL() else { return }
        // Reveal the file in Finder by selecting it.
        NSWorkspace.shared.selectFile(url.path,
                                      inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
    }

    /// Helper to resolve the saved security-scoped bookmark.
    public static func resolveConfigFileURL() -> URL? {
        guard let bookmarkData = SettingsStore.shared.configFileBookmark else {
            return SettingsStore.shared.configFileResolvedURL
        }

        var isStale = false
        do {
            let url = try URL(resolvingBookmarkData: bookmarkData,
                              options: .withSecurityScope,
                              relativeTo: nil,
                              bookmarkDataIsStale: &isStale)
            if isStale {
                print("Bookmark is stale, please re-select the configuration file.")
            }
            guard url.startAccessingSecurityScopedResource() else {
                print("Couldn't access the resource via the security-scoped bookmark.")
                return nil
            }
            return url
        } catch {
            print("Error resolving bookmark: \(error)")
            return nil
        }
    }

    public static func reloadConfig() {
        DispatchQueue.main.async {
            MenuState.shared.rootMenu = loadMenuConfig() ?? []
        }
    }

    public static func showAbout() {
        NSApp.orderFrontStandardAboutPanel()
    }

    public static var isDarkTheme: Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") != nil
    }

    public static var isDarkStatusBar: Bool {
        let currentAppearance = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength).button?
            .effectiveAppearance
        return currentAppearance?.bestMatch(from: [.aqua, .darkAqua]) == .aqua
    }

    public static var isReduceTransparencyEnabled: Bool {
        UserDefaults(suiteName: "com.apple.universalaccess.plist")?.bool(forKey: "reduceTransparency") ?? false
    }
}
