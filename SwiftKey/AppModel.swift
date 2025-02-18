// Unified model for both configuration and runtime usage.
import AppKit
import SwiftUI
import Yams

// MARK: - MenuItem
struct MenuItem: Identifiable, Codable {
    let id: UUID
    var key: String  // e.g. "a", "B", "!", etc.
    var icon: String?  // Default SF Symbol name
    var title: String  // Descriptive title
    var action: String?  // Raw action string from YAML
    var sticky: Bool?  // Sticky actions don't close window after execution
    var batch: Bool?  // Batch runs all submenu items
    var submenu: [MenuItem]?  // Optional nested submenu

    // Define coding keys explicitly.
    enum CodingKeys: String, CodingKey {
        case id, key, icon, title, action, sticky, batch, submenu
    }

    // Custom initializer that ignores any incoming 'id' from the YAML
    // and always creates a new one. This silences the warning.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Always generate a new UUID (or you could choose to decode if needed)
        id = UUID()
        key = try container.decode(String.self, forKey: .key)
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
        title = try container.decode(String.self, forKey: .title)
        action = try container.decodeIfPresent(String.self, forKey: .action)
        sticky = try container.decodeIfPresent(Bool.self, forKey: .sticky)
        batch = try container.decodeIfPresent(Bool.self, forKey: .batch)
        submenu = try container.decodeIfPresent([MenuItem].self, forKey: .submenu)
    }

    // Standard initializer for manual creation
    init(
        id: UUID = UUID(), key: String, icon: String? = nil, title: String, action: String? = nil,
        sticky: Bool? = nil, batch: Bool? = nil, submenu: [MenuItem]? = nil
    ) {
        self.id = id
        self.key = key
        self.icon = icon
        self.title = title
        self.action = action
        self.sticky = sticky
        self.batch = batch
        self.submenu = submenu
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(key, forKey: .key)
        try container.encode(icon, forKey: .icon)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(action, forKey: .action)
        try container.encodeIfPresent(sticky, forKey: .sticky)
        try container.encodeIfPresent(batch, forKey: .batch)
        try container.encodeIfPresent(submenu, forKey: .submenu)
    }

    /// Computed property that creates a closure to perform the specified action.
    var actionClosure: (() -> Void)? {
        guard let action = action else { return nil }
        if action.hasPrefix("launch://") {
            let appPath = String(action.dropFirst("launch://".count))
            return {
                let expandedPath = (appPath as NSString).expandingTildeInPath
                let appURL = URL(fileURLWithPath: expandedPath)

                if FileManager.default.fileExists(atPath: appURL.path) {
                    NSWorkspace.shared.openApplication(
                        at: appURL, configuration: .init(), completionHandler: nil)
                } else {
                    print("Application not found or invalid at path: \(appPath)")
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
    var iconImage: Image {
        if let icon, !icon.isEmpty {
            return Image(systemName: icon)
        } else if let action = action {
            if action.hasPrefix("launch://") {
                let appPath = String(action.dropFirst("launch://".count))
                if let nsImage = getAppIcon(appPath: appPath) {
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
                if let appURL = NSWorkspace.shared.urlForApplication(
                    withBundleIdentifier: "com.apple.shortcuts"),
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
    guard let configURL = AppShared.resolveConfigFileURL() else {
        print("Configuration file URL not available.")
        return nil
    }

    do {
        let yamlString = try String(contentsOf: configURL, encoding: .utf8)
        let decoder = YAMLDecoder()
        let config = try decoder.decode([MenuItem].self, from: yamlString)
        return config
    } catch {
        print("Error loading YAML config: \(error)")
        return nil
    }
}
