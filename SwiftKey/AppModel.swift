import AppKit
import SwiftUI
import Yams

// MARK: - ActionType

enum ActionType: String, CaseIterable, Codable {
    case launch
    case open
    case shell
    case shortcut
    case dynamic
    case submenu
    case unknown
    
    // Properties for UI display
    var label: String {
        switch self {
        case .launch: return "Application Path:"
        case .open: return "URL to Open:"
        case .shell: return "Shell Command:"
        case .shortcut: return "Shortcut Name:"
        case .dynamic: return "Dynamic Command:"
        case .submenu: return "Submenu Items:"
        case .unknown: return "Action Parameter:"
        }
    }
    
    var helpText: String {
        switch self {
        case .launch:
            return "Path to the application to launch. For system apps, use /System/Applications/AppName.app, for user apps use /Applications/AppName.app"
        case .open:
            return "URL to open in the default browser, e.g., https://example.com"
        case .shell:
            return "Shell command to execute. Use safe commands that don't need elevated privileges."
        case .shortcut:
            return "Name of the Shortcuts automation to run"
        case .dynamic:
            return "Shell command that returns YAML for dynamic menu generation"
        case .submenu:
            return "A collection of menu items that will appear in a submenu"
        case .unknown:
            return "Unknown action type"
        }
    }
    
    // Get prefix string for URL schemes
    var prefix: String {
        return "\(rawValue)://"
    }
    
    // Get array of types for picker
    static var selectableTypes: [ActionType] {
        // Filter out submenu and unknown for selectable types
        return ActionType.allCases.filter { $0 != .submenu && $0 != .unknown }
    }
    
    // Extract parameter from a full action string
    static func extractParameter(from action: String) -> String {
        if let range = action.range(of: "://") {
            return String(action[range.upperBound...])
        }
        return ""
    }
    
    // Create an action string with type and parameter
    static func createAction(type: ActionType, parameter: String) -> String {
        return "\(type.prefix)\(parameter)"
    }
}

// MARK: - MenuItem

struct MenuItem: Identifiable, Codable, Equatable {
    let id: UUID
    var key: String // e.g. "a", "B", "!", etc.
    var icon: String? // Default SF Symbol name
    var title: String // Descriptive title
    var action: String? // Raw action string from YAML
    var sticky: Bool? // Sticky actions don't close window after execution
    var notify: Bool? // Notify actions show a notification after execution
    var batch: Bool? // Batch runs all submenu items
    var hidden: Bool? // Hidden items aren't shown in UI but can be activated
    var submenu: [MenuItem]? // Optional nested submenu
    var hotkey: String? // Hotkey for the menu item
    
    // Helper to determine the action type
    var actionType: ActionType {
        // If it has a submenu, it's a submenu type
        if let submenu = submenu, !submenu.isEmpty {
            return .submenu
        }
        
        // Check the action prefix
        guard let action = action, !action.isEmpty else {
            // No action, might be a submenu or unknown
            return submenu != nil ? .submenu : .unknown
        }
        
        // Determine type from prefix
        for type in ActionType.allCases where type != .unknown && type != .submenu {
            if action.hasPrefix(type.prefix) {
                return type
            }
        }
        
        return .unknown
    }
    
    // Get the parameter part of the action (after the prefix)
    var actionParameter: String {
        guard let action = action, !action.isEmpty else { return "" }
        return ActionType.extractParameter(from: action)
    }
    
    // Update the action with new type and parameter
    mutating func updateAction(type: ActionType, parameter: String) {
        // Only set action if not a submenu type
        if type != .submenu {
            action = ActionType.createAction(type: type, parameter: parameter)
        } else {
            // For submenu type, ensure we have a submenu array
            if submenu == nil {
                submenu = []
            }
            // Clear action for submenu types
            action = nil
        }
    }
    
    // Convert item to a submenu type
    mutating func convertToSubmenu() {
        // Ensure we have a submenu array
        if submenu == nil {
            submenu = []
        }
        // Clear action as it's now a submenu
        action = nil
    }
    
    // Convert item to an action type with the specified action type
    mutating func convertToAction(type: ActionType = .launch) {
        // Only convert if it's not already a submenu type
        if type != .submenu {
            // Set a default empty action of the specified type
            action = ActionType.createAction(type: type, parameter: "")
            
            // Clear submenu if it's empty
            if submenu?.isEmpty ?? true {
                submenu = nil
            }
        }
    }

    // Define coding keys explicitly.
    enum CodingKeys: String, CodingKey {
        case id, key, icon, title, action, sticky, notify, batch, hidden, submenu, hotkey
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
        notify = try container.decodeIfPresent(Bool.self, forKey: .notify)
        batch = try container.decodeIfPresent(Bool.self, forKey: .batch)
        hidden = try container.decodeIfPresent(Bool.self, forKey: .hidden)
        submenu = try container.decodeIfPresent([MenuItem].self, forKey: .submenu)
        hotkey = try container.decodeIfPresent(String.self, forKey: .hotkey)
    }

    // Standard initializer for manual creation
    init(
        id: UUID = UUID(), key: String, icon: String? = nil, title: String, action: String? = nil,
        sticky: Bool? = nil, notify: Bool? = nil, batch: Bool? = nil, hidden: Bool? = nil, 
        submenu: [MenuItem]? = nil, hotkey: String? = nil
    ) {
        self.id = id
        self.key = key
        self.icon = icon
        self.title = title
        self.action = action
        self.sticky = sticky
        self.notify = notify
        self.batch = batch
        self.hidden = hidden
        self.submenu = submenu
        self.hotkey = hotkey
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(key, forKey: .key)
        try container.encode(icon, forKey: .icon)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(action, forKey: .action)
        try container.encodeIfPresent(sticky, forKey: .sticky)
        try container.encodeIfPresent(notify, forKey: .notify)
        try container.encodeIfPresent(batch, forKey: .batch)
        try container.encodeIfPresent(hidden, forKey: .hidden)
        try container.encodeIfPresent(submenu, forKey: .submenu)
        try container.encodeIfPresent(hotkey, forKey: .hotkey)
    }

    /// Computed property that creates a closure to perform the specified action.
    var actionClosure: (() -> Void)? {
        guard let action = action else { return nil }
        
        switch actionType {
        case .launch:
            let appPath = actionParameter
            return {
                let expandedPath = (appPath as NSString).expandingTildeInPath
                let appURL = URL(fileURLWithPath: expandedPath)

                if FileManager.default.fileExists(atPath: appURL.path) {
                    NSWorkspace.shared.openApplication(
                        at: appURL, configuration: .init(), completionHandler: nil
                    )
                } else {
                    print("Application not found or invalid at path: \(appPath)")
                }
            }
            
        case .open:
            let urlString = actionParameter
            return {
                if let url = URL(string: urlString) {
                    NSWorkspace.shared.open(url)
                }
            }
            
        case .shortcut:
            let shortcutName = actionParameter
            return {
                ShortcutsManager.shared.runShortcut(shortcut: shortcutName)
            }
            
        case .shell:
            let command = actionParameter
            return {
                do {
                    let out = try runScript(to: command, env: [:])
                    
                    // Only show notification with output if it's not empty
                    let message = out.out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 
                                 "Command completed successfully" : out.out
                    notifyUser(title: "Finished running \(title)", message: message)
                } catch {
                    if let shellError = error as? ShellOutError {
                        let errorMessage = shellError.message.isEmpty ? 
                                          "Command failed with exit code \(shellError.terminationStatus)" : 
                                          shellError.message
                        notifyUser(title: "Error running \(title)", message: errorMessage)
                    } else {
                        // Handle other types of errors
                        notifyUser(title: "Error running \(title)", message: "Unknown error: \(error.localizedDescription)")
                    }
                }
            }
            
        default:
            return nil
        }
    }
}

extension MenuItem {
    // Static cache for storing already loaded images
    private static var imageCache = [String: Image]()
    private static var nsImageCache = [String: NSImage]()
    
    var iconImage: Image {
        // Generate a unique cache key based on the action or icon
        let cacheKey = generateIconCacheKey()
        
        // Return cached image if available
        if let cachedImage = Self.imageCache[cacheKey] {
            return cachedImage
        }
        
        // Otherwise generate the image
        let resultImage: Image
        
        if let icon, !icon.isEmpty {
            resultImage = Image(systemName: icon)
        } else if let action = action {
            if action.hasPrefix("launch://") {
                let appPath = String(action.dropFirst("launch://".count))
                if let nsImage = getCachedAppIcon(appPath: appPath) {
                    resultImage = Image(nsImage: nsImage)
                } else {
                    resultImage = Image(systemName: "questionmark")
                }
            } else if action.hasPrefix("open://") {
                let urlString = String(action.dropFirst("open://".count))
                let urlCacheKey = "url:\(urlString)"
                
                if let cachedNSImage = Self.nsImageCache[urlCacheKey] {
                    resultImage = Image(nsImage: cachedNSImage)
                } else if let url = URL(string: urlString),
                   let appURL = NSWorkspace.shared.urlForApplication(toOpen: url),
                   case let nsImage = NSWorkspace.shared.icon(forFile: appURL.path)
                {
                    Self.nsImageCache[urlCacheKey] = nsImage
                    resultImage = Image(nsImage: nsImage)
                } else {
                    resultImage = Image(systemName: "link")
                }
            } else if action.hasPrefix("shortcut://") {
                let shortcutsCacheKey = "shortcuts"
                
                if let cachedNSImage = Self.nsImageCache[shortcutsCacheKey] {
                    resultImage = Image(nsImage: cachedNSImage)
                } else if let appURL = NSWorkspace.shared.urlForApplication(
                    withBundleIdentifier: "com.apple.shortcuts"
                ),
                    case let nsImage = NSWorkspace.shared.icon(forFile: appURL.path)
                {
                    Self.nsImageCache[shortcutsCacheKey] = nsImage
                    resultImage = Image(nsImage: nsImage)
                } else {
                    resultImage = Image(systemName: "bolt.fill")
                }
            } else {
                resultImage = Image(systemName: "questionmark")
            }
        } else {
            resultImage = Image(systemName: "questionmark")
        }
        
        // Cache the result before returning
        Self.imageCache[cacheKey] = resultImage
        return resultImage
    }
    
    // Helper function to generate a unique cache key
    private func generateIconCacheKey() -> String {
        if let icon, !icon.isEmpty {
            return "sf:\(icon)"
        } else if let action = action {
            return "action:\(action)"
        } else {
            return "default"
        }
    }
    
    private func getCachedAppIcon(appPath: String) -> NSImage? {
        let cacheKey = "app:\(appPath)"
        
        if let cachedIcon = Self.nsImageCache[cacheKey] {
            return cachedIcon
        }
        
        if let loadedIcon = getAppIcon(appPath: appPath) {
            Self.nsImageCache[cacheKey] = loadedIcon
            return loadedIcon
        }
        
        return nil
    }
    
    static func clearImageCache() {
        imageCache.removeAll()
        nsImageCache.removeAll()
    }
}

