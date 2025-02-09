import AppKit
import Yams

import AppKit
import Yams

// Unified model for both configuration and runtime usage.
struct MenuItem: Identifiable, Decodable {
    let id: UUID = UUID()
    var key: String           // e.g. "a", "B", "!", etc.
    var systemImage: String   // Default SF Symbol name
    var title: String         // Descriptive title
    var action: String?       // Raw action string from YAML
    var submenu: [MenuItem]?  // Optional nested submenu
    
    /// Computed property to return a closure based on the raw action string.
    var actionClosure: (() -> Void)? {
        guard let action = action else { return nil }
        if action.hasPrefix("launch://") {
            let appName = String(action.dropFirst("launch://".count))
            return {
                NSWorkspace.shared.launchApplication(appName)
            }
        } else if action.hasPrefix("open://") {
            let urlString = String(action.dropFirst("open://".count))
            return {
                if let url = URL(string: urlString) {
                    NSWorkspace.shared.open(url)
                }
            }
        } else if action.hasPrefix("print://") {
            let message = String(action.dropFirst("print://".count))
            return {
                print(message)
            }
        } else if action.hasPrefix("shortcut://") {
            let shortcutName = String(action.dropFirst("shortcut://".count))
            return {
                let process = Process()
                process.launchPath = "/usr/bin/shortcuts"
                process.arguments = ["run", shortcutName]
                process.launch()
            }
        } else if action.hasPrefix("shell://") {
            let command = String(action.dropFirst("shell://".count))
            return {
                let process = Process()
                process.launchPath = "/bin/bash"
                process.arguments = ["-c", command]
                process.launch()
            }
        }
        return nil
    }
}

/// Top-level container for YAML decoding.
struct MenuConfig: Decodable {
    let menu: [MenuItem]
}

func loadMenuConfig() -> [MenuItem]? {
    let configURL: URL?
    if let customPath = SettingsStore.shared.configDirectoryResolvedPath {
        // Look for the config in the custom folder.
        configURL = URL(fileURLWithPath: customPath).appendingPathComponent("menu.yaml")
    } else {
        // Fallback to bundled resource.
        configURL = Bundle.main.url(forResource: "menu", withExtension: "yaml")
    }
    
    guard let url = configURL, FileManager.default.fileExists(atPath: url.path) else {
        print("menu.yaml not found.")
        return nil
    }
    
    do {
        let yamlString = try String(contentsOf: url, encoding: .utf8)
        let decoder = YAMLDecoder()
        let config = try decoder.decode(MenuConfig.self, from: yamlString)
        return config.menu
    } catch {
        print("Error loading YAML config: \(error)")
        return nil
    }
}
