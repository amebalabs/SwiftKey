import AppKit
import Combine
import KeyboardShortcuts
import os
import Yams

// MARK: - KeyboardShortcut Names

extension KeyboardShortcuts.Name {
    static let toggleApp = Self("toggleApp")
}

// MARK: - KeyPressResult

/// Result of handling a keyboard press
enum KeyPressResult: Equatable {
    case escape
    case help
    case up
    case submenuPushed(title: String)
    case actionExecuted
    case dynamicLoading
    case error(key: String)
    case none
}

// MARK: - KeyboardManager

/// Manages keyboard shortcuts and key event handling
@Observable
class KeyboardManager: DependencyInjectable, ObservableObject {
    /// Factory method to create a new KeyboardManager instance
    static func create() -> KeyboardManager {
        return KeyboardManager()
    }

    private let logger = AppLogger.keyboard

    // Dependencies using proper initialization
    private(set) var menuState: MenuState!
    private(set) var settingsStore: SettingsStore!
    private(set) var configManager: ConfigManager!
    private(set) var dynamicMenuLoader: DynamicMenuLoader!

    // Global key handlers map for menu hotkeys
    private var hotkeyHandlers: [String: KeyboardShortcuts.Name] = [:]

    // Default initialization for container creation
    init() {
        // Default initialization - will be properly set in injectDependencies
        self.menuState = MenuState()
        self.settingsStore = SettingsStore()
        self.configManager = ConfigManager.create()
        self.dynamicMenuLoader = DynamicMenuLoader.create()
    }

    func injectDependencies(_ container: DependencyContainer) {
        // Replace existing instances with the container ones
        self.menuState = container.menuState
        self.settingsStore = container.settingsStore
        self.configManager = container.configManager
        self.dynamicMenuLoader = container.dynamicMenuLoader

        logger.debug("Dependencies injected successfully")
    }

    // MARK: - Key Handling

    func handleKey(
        key: String,
        modifierFlags: NSEvent.ModifierFlags? = nil
    ) async -> KeyPressResult {
        logger.debug("Key pressed: \(key, privacy: .public)")
        let normalizedKey = key

        // Update UI state on main actor
        await MainActor.run {
            menuState.currentKey = normalizedKey
        }

        // Common navigation keys
        if normalizedKey == "escape" {
            return .escape
        }
        if normalizedKey == "cmd+up" {
            await MainActor.run {
                if !menuState.menuStack.isEmpty { menuState.menuStack.removeLast() }
                if !menuState.breadcrumbs.isEmpty { menuState.breadcrumbs.removeLast() }
            }
            return .up
        }
        if normalizedKey == "?" {
            return .help
        }

        // Find matching menu item
        let matchingItem = menuState.currentMenu.first(where: { $0.key == normalizedKey })

        guard let item = matchingItem else {
            return .error(key: key)
        }

        // Handle dynamic menus
        if let actionString = item.action, actionString.hasPrefix("dynamic://") {
            let result = await loadDynamicMenu(for: item)
            return result
        }

        // Handle submenu navigation
        if let submenu = item.submenu {
            // Batch execution mode (Alt key or batch flag)
            if modifierFlags?.isOption == true || item.batch == true {
                await executeBatchActions(in: submenu)
                return .actionExecuted
            }

            // Normal submenu navigation
            await MainActor.run {
                menuState.breadcrumbs.append(item.title)
                menuState.menuStack.append(submenu)
            }
            return .submenuPushed(title: item.title)
        }

        // Execute action
        if let action = item.actionClosure {
            Task(priority: .userInitiated) {
                action()
            }

            // Handle sticky flag for panel mode
            let overlayStyle = settingsStore.overlayStyle
            if item.sticky == false, overlayStyle == .panel {
                return .none
            } else {
                return .actionExecuted
            }
        }

        return .none
    }

    // MARK: - Dynamic Menu Loading

    func loadDynamicMenu(for item: MenuItem) async -> KeyPressResult {
        guard item.action?.hasPrefix("dynamic://") == true else {
            return .error(key: item.key)
        }

        // Use the injected instance rather than the shared singleton
        if let submenu = await dynamicMenuLoader.loadDynamicMenu(for: item) {
            // Update UI state on the main actor
            await MainActor.run {
                menuState.breadcrumbs.append(item.title)
                menuState.menuStack.append(submenu)
            }
            return .submenuPushed(title: item.title)
        } else {
            return .error(key: item.key)
        }
    }

    // MARK: - Batch Actions

    private func executeBatchActions(in submenu: [MenuItem]) async {
        Task(priority: .userInitiated) {
            for menu in submenu where menu.actionClosure != nil {
                guard menu.action?.hasPrefix("dynamic://") == false else { continue }
                menu.actionClosure!()
            }
        }
    }

    // MARK: - Hotkey Registration

    /// Register hotkeys for navigation
    func registerMenuHotkeys(_ menu: [MenuItem]) {
        let isRootMenu = menu == menuState.rootMenu
        if isRootMenu {
            hotkeyHandlers.removeAll()
        }

        for item in menu {
            if let hotkeyStr = item.hotkey, let shortcut = KeyboardShortcuts.Shortcut(hotkeyStr) {
                let name = KeyboardShortcuts.Name(item.id.uuidString)
                KeyboardShortcuts.setShortcut(shortcut, for: name)

                KeyboardShortcuts.onKeyDown(for: name) { [weak self] in
                    guard let self = self else { return }

                    if item.submenu != nil {
                        Task { @MainActor in
                            self.navigateToMenuItem(item)
                        }
                    } else if let action = item.actionClosure {
                        Task(priority: .userInitiated) {
                            action()
                        }
                    }
                }

                hotkeyHandlers[item.id.uuidString] = name
            }

            if let submenu = item.submenu {
                registerMenuHotkeys(submenu)
            }
        }
    }

    private func navigateToMenuItem(_ item: MenuItem) {
        menuState.reset()

        if let path = findPathToMenuItem(item, in: menuState.rootMenu) {
            for (index, menuItem) in path.enumerated() {
                if index < path.count {
                    menuState.breadcrumbs.append(menuItem.title)
                    if let submenu = menuItem.submenu {
                        menuState.menuStack.append(submenu)
                    }
                }
            }

            NotificationCenter.default.post(name: .presentOverlay, object: nil)
        }
    }

    private func findPathToMenuItem(
        _ target: MenuItem,
        in menu: [MenuItem],
        currentPath: [MenuItem] = []
    ) -> [MenuItem]? {
        for item in menu {
            if item.id == target.id {
                return currentPath + [item]
            }

            if let submenu = item.submenu,
               let path = findPathToMenuItem(
                   target,
                   in: submenu,
                   currentPath: currentPath + [item]
               )
            {
                return path
            }
        }
        return nil
    }
}

// MARK: - KeyboardShortcuts Extension

extension KeyboardShortcuts.Shortcut {
    init?(_ string: String) {
        let components = string.lowercased().split(separator: "+").map(String.init)
        guard let keyStr = components.last else { return nil }

        var modifiers: NSEvent.ModifierFlags = []

        for modifier in components.dropLast() {
            switch modifier {
            case "cmd", "command", "⌘":
                modifiers.insert(.command)
            case "ctrl", "control", "⌃":
                modifiers.insert(.control)
            case "alt", "option", "⌥":
                modifiers.insert(.option)
            case "shift", "⇧":
                modifiers.insert(.shift)
            default:
                continue
            }
        }

        // Convert key string to KeyboardShortcuts.Key
        let key: KeyboardShortcuts.Key
        switch keyStr {
        case "a": key = .a
        case "b": key = .b
        case "c": key = .c
        case "d": key = .d
        case "e": key = .e
        case "f": key = .f
        case "g": key = .g
        case "h": key = .h
        case "i": key = .i
        case "j": key = .j
        case "k": key = .k
        case "l": key = .l
        case "m": key = .m
        case "n": key = .n
        case "o": key = .o
        case "p": key = .p
        case "q": key = .q
        case "r": key = .r
        case "s": key = .s
        case "t": key = .t
        case "u": key = .u
        case "v": key = .v
        case "w": key = .w
        case "x": key = .x
        case "y": key = .y
        case "z": key = .z
        case "0": key = .zero
        case "1": key = .one
        case "2": key = .two
        case "3": key = .three
        case "4": key = .four
        case "5": key = .five
        case "6": key = .six
        case "7": key = .seven
        case "8": key = .eight
        case "9": key = .nine
        case "space": key = .space
        case "return", "enter": key = .return
        case "tab": key = .tab
        case "esc", "escape": key = .escape
        case "left": key = .leftArrow
        case "right": key = .rightArrow
        case "up": key = .upArrow
        case "down": key = .downArrow
        case "backspace", "delete": key = .delete
        case "f1": key = .f1
        case "f2": key = .f2
        case "f3": key = .f3
        case "f4": key = .f4
        case "f5": key = .f5
        case "f6": key = .f6
        case "f7": key = .f7
        case "f8": key = .f8
        case "f9": key = .f9
        case "f10": key = .f10
        case "f11": key = .f11
        case "f12": key = .f12
        case "[": key = .leftBracket
        case "]": key = .rightBracket
        case "\\": key = .backslash
        case ";": key = .semicolon
        case "'", "\"": key = .quote
        case ",": key = .comma
        case ".": key = .period
        case "/": key = .slash
        case "-": key = .minus
        case "=": key = .equal
        case "`": key = .backtick
        default: return nil
        }

        self.init(key, modifiers: modifiers)
    }
}
