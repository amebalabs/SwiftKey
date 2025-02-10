import Cocoa
import os
import SwiftUI

class AppShared: NSObject {
    public static func openConfigFolder(path: String? = nil) {
        NSWorkspace.shared
            .selectFile(
                path,
                inFileViewerRootedAtPath: SettingsStore.shared.configDirectoryResolvedPath ?? ""
            )
    }

    public static func changeConfigFolder() {
        let dialog = NSOpenPanel()
        dialog.message = "Choose a folder to store your plugins"
        dialog.showsHiddenFiles = false
        dialog.canChooseDirectories = true
        dialog.canChooseFiles = false
        dialog.canCreateDirectories = true
        dialog.allowsMultipleSelection = false

        guard dialog.runModal() == .OK,
              let url = dialog.url
        else { return }

        var restrictedPaths =
            [FileManager.SearchPathDirectory.allApplicationsDirectory, .documentDirectory, .downloadsDirectory, .desktopDirectory, .libraryDirectory, .developerDirectory, .userDirectory, .musicDirectory, .moviesDirectory,
             .picturesDirectory]
            .map { FileManager.default.urls(for: $0, in: .allDomainsMask) }
            .flatMap { $0 }

        restrictedPaths.append(FileManager.default.homeDirectoryForCurrentUser)

        if restrictedPaths.contains(url) {
            let alert = NSAlert()
            alert.messageText = "Folder not allowed"
            alert.informativeText = "\(url.path)"
            alert.addButton(withTitle: "OK")
            let modalResult = alert.runModal()

            switch modalResult {
            case .alertFirstButtonReturn:
                AppShared.changeConfigFolder()
            default:
                break
            }
            return
        }

        SettingsStore.shared.configDirectoryPath = url.path
    }

    public static func showAbout() {
        NSApp.orderFrontStandardAboutPanel()
    }

    public static var isDarkTheme: Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") != nil
    }

    public static var isDarkStatusBar: Bool {
        let currentAppearance = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength).button?.effectiveAppearance
        return currentAppearance?.bestMatch(from: [.aqua, .darkAqua]) == .aqua
    }

    public static var isReduceTransparencyEnabled: Bool {
        UserDefaults(suiteName: "com.apple.universalaccess.plist")?.bool(forKey: "reduceTransparency") ?? false
    }
}
