import AppKit
import SwiftUI
import Yams

// Unified model for both configuration and runtime usage.
import AppKit
import SwiftUI
import Yams

// MARK: - MenuItem
struct MenuItem: Identifiable, Codable {
    let id: UUID
    var key: String // e.g. "a", "B", "!", etc.
    var systemImage: String // Default SF Symbol name
    var title: String // Descriptive title
    var action: String? // Raw action string from YAML
    var sticky: Bool? // Sticky actions don't close window after execution
    var submenu: [MenuItem]? // Optional nested submenu
    
    // Define coding keys explicitly.
    enum CodingKeys: String, CodingKey {
        case id, key, systemImage, title, action, sticky, submenu
    }
    
    // Custom initializer that ignores any incoming 'id' from the YAML
    // and always creates a new one. This silences the warning.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Always generate a new UUID (or you could choose to decode if needed)
        id = UUID()
        key = try container.decode(String.self, forKey: .key)
        systemImage = try container.decode(String.self, forKey: .systemImage)
        title = try container.decode(String.self, forKey: .title)
        action = try container.decodeIfPresent(String.self, forKey: .action)
        sticky = try container.decodeIfPresent(Bool.self, forKey: .sticky)
        submenu = try container.decodeIfPresent([MenuItem].self, forKey: .submenu)
    }
    
    // Standard initializer for manual creation
    init(id: UUID = UUID(), key: String, systemImage: String, title: String, action: String? = nil, sticky: Bool? = nil, submenu: [MenuItem]? = nil) {
        self.id = id
        self.key = key
        self.systemImage = systemImage
        self.title = title
        self.action = action
        self.sticky = sticky
        self.submenu = submenu
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(key, forKey: .key)
        try container.encode(systemImage, forKey: .systemImage)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(action, forKey: .action)
        try container.encodeIfPresent(sticky, forKey: .sticky)
        try container.encodeIfPresent(submenu, forKey: .submenu)
    }
    
    /// Computed property that creates a closure to perform the specified action.
    var actionClosure: (() -> Void)? {
        guard let action = action else { return nil }
        if action.hasPrefix("launch://") {
            let bundleID = String(action.dropFirst("launch://".count))
            return {
                if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                    NSWorkspace.shared.openApplication(at: appURL, configuration: .init(), completionHandler: nil)
                } else {
                    print("Application with bundle identifier \(bundleID) not found.")
                }
            }
        }
        if action.hasPrefix("open://") {
            let urlString = String(action.dropFirst("open://".count))
            return {
                if let url = URL(string: urlString) {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        if action.hasPrefix("print://") {
            let message = String(action.dropFirst("print://".count))
            return {
                print(message)
            }
        }
        if action.hasPrefix("shortcut://") {
            let shortcutName = String(action.dropFirst("shortcut://".count))
            return {
                ShortcutsManager.shared.runShortcut(shortcut: shortcutName)
            }
        }
        if action.hasPrefix("shell://") {
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

extension MenuItem {
    var icon: Image {
        if !systemImage.isEmpty {
            return Image(systemName: systemImage)
        } else if let action = action {
            if action.hasPrefix("launch://") {
                let appName = String(action.dropFirst("launch://".count))
                if let nsImage = getAppIcon(appName: appName) {
                    return Image(nsImage: nsImage)
                } else {
                    return Image(systemName: "questionmark")
                }
            } else if action.hasPrefix("open://") {
                let urlString = String(action.dropFirst("open://".count))
                if let url = URL(string: urlString),
                   let appURL = NSWorkspace.shared.urlForApplication(toOpen: url),
                   case let nsImage = NSWorkspace.shared.icon(forFile: appURL.path)
                {
                    return Image(nsImage: nsImage)
                } else {
                    return Image(systemName: "link")
                }
            } else if action.hasPrefix("shortcut://") {
                if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.shortcuts"),
                   case let nsImage = NSWorkspace.shared.icon(forFile: appURL.path)
                {
                    return Image(nsImage: nsImage)
                } else {
                    return Image(systemName: "bolt.fill")
                }
            } else {
                return Image(systemName: "questionmark")
            }
        } else {
            return Image(systemName: "questionmark")
        }
    }
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
        let config = try decoder.decode([MenuItem].self, from: yamlString)
        return config
    } catch {
        print("Error loading YAML config: \(error)")
        return nil
    }
}
