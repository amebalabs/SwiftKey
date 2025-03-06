import AppKit
import Combine
import KeyboardShortcuts
import Yams

// MARK: - KeyboardShortcut Names

extension KeyboardShortcuts.Name {
    static let toggleApp = Self("toggleApp")
}

// MARK: - KeyboardManager

class KeyboardManager: DependencyInjectable, ObservableObject {
    // Singleton instance
    static let shared = KeyboardManager()

    // Dependencies
    var menuState: MenuState!
    var settingsStore: SettingsStore!
    var configManager: ConfigManager!

    // Event publishers
    let keyPressSubject = PassthroughSubject<KeyEvent, Never>()
    var keyPressPublisher: AnyPublisher<KeyEvent, Never> {
        keyPressSubject.eraseToAnyPublisher()
    }

    // Global key handlers map for menu hotkeys
    private var hotkeyHandlers: [String: KeyboardShortcuts.Name] = [:]

    // MARK: - Initialization

    init() {
        // Setup will happen after dependencies are injected
    }

    func injectDependencies(_ container: DependencyContainer) {
        self.menuState = container.menuState
        self.settingsStore = container.settingsStore
        self.configManager = container.configManager

        print("KeyboardManager: Dependencies injected successfully")
    }

    // MARK: - Key Handling

    func handleKey(
        key: String,
        modifierFlags: NSEvent.ModifierFlags? = nil,
        completion: @escaping (KeyPressResult) -> Void
    ) {
        print("KeyboardManager: Key pressed: \(key)")
        let normalizedKey = key
        menuState.currentKey = normalizedKey

        // Common navigation keys
        if normalizedKey == "escape" {
            completion(.escape)
            return
        }
        if normalizedKey == "cmd+up" {
            if !menuState.menuStack.isEmpty { menuState.menuStack.removeLast() }
            if !menuState.breadcrumbs.isEmpty { menuState.breadcrumbs.removeLast() }
            completion(.up)
            return
        }
        if normalizedKey == "?" {
            completion(.help)
            return
        }

        // Find matching menu item
        guard let item = menuState.currentMenu.first(where: { $0.key == normalizedKey }) else {
            completion(.error(key: key))
            return
        }

        // Handle dynamic menus
        if let actionString = item.action, actionString.hasPrefix("dynamic://") {
            completion(.dynamicLoading)
            loadDynamicMenu(for: item) { result in
                DispatchQueue.main.async {
                    completion(result)
                }
            }
            return
        }

        // Handle submenu navigation
        if let submenu = item.submenu {
            // Batch execution mode (Alt key or batch flag)
            if modifierFlags?.isOption == true || item.batch == true {
                executeBatchActions(in: submenu)
                completion(.actionExecuted)
                return
            }

            // Normal submenu navigation
            menuState.breadcrumbs.append(item.title)
            menuState.menuStack.append(submenu)
            completion(.submenuPushed(title: item.title))
            return
        }

        // Execute action
        if let action = item.actionClosure {
            DispatchQueue.global(qos: .userInitiated).async {
                action()
            }

            // Handle sticky flag for panel mode
            let overlayStyle = settingsStore?.overlayStyle ?? .panel
            if item.sticky == false, overlayStyle == .panel {
                completion(.none)
            } else {
                completion(.actionExecuted)
            }
            return
        }

        completion(.none)
    }

    // MARK: - Dynamic Menu Loading

    /// Loads a dynamic menu for the specified menu item
    /// - Parameters:
    ///   - item: The menu item containing a dynamic:// action
    ///   - completion: Completion handler called with the result
    func loadDynamicMenu(for item: MenuItem, completion: @escaping (KeyPressResult) -> Void) {
        guard item.action?.hasPrefix("dynamic://") == true else {
            completion(.error(key: item.key))
            return
        }

        completion(.dynamicLoading)

        DynamicMenuLoader.shared.loadDynamicMenu(for: item) { [weak self] submenu in
            guard let self = self, let submenu = submenu else {
                DispatchQueue.main.async {
                    completion(.error(key: item.key))
                }
                return
            }

            DispatchQueue.main.async {
                self.menuState.breadcrumbs.append(item.title)
                self.menuState.menuStack.append(submenu)
                completion(.submenuPushed(title: item.title))
            }
        }
    }

    // MARK: - Batch Actions

    private func executeBatchActions(in submenu: [MenuItem]) {
        DispatchQueue.global(qos: .userInitiated).async {
            for menu in submenu where menu.actionClosure != nil {
                guard menu.action?.hasPrefix("dynamic://") == false else { continue }
                menu.actionClosure!()
            }
        }
    }

    // MARK: - Hotkey Registration

    func registerMenuHotkeys(_ menu: [MenuItem]) {
        // Clear existing hotkeys if we're registering for the root menu
        if menu == menuState.rootMenu {
            hotkeyHandlers.removeAll()
        }

        for item in menu {
            if let hotkeyStr = item.hotkey, let shortcut = KeyboardShortcuts.Shortcut(hotkeyStr) {
                let name = KeyboardShortcuts.Name(item.id.uuidString)
                KeyboardShortcuts.setShortcut(shortcut, for: name)

                KeyboardShortcuts.onKeyDown(for: name) { [weak self] in
                    guard let self = self else { return }

                    if item.submenu != nil {
                        DispatchQueue.main.async {
                            self.navigateToMenuItem(item)
                        }
                    } else if let action = item.actionClosure {
                        DispatchQueue.global(qos: .userInitiated).async {
                            action()
                        }
                    }
                }

                hotkeyHandlers[item.id.uuidString] = name
            }

            // Recursively register hotkeys for submenus
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

            // Show overlay with the correct menu
            AppDelegate.shared.presentOverlay()
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

// MARK: - KeyEvent Data Structure

struct KeyEvent {
    let key: String
    let modifiers: NSEvent.ModifierFlags?

    init(key: String, modifiers: NSEvent.ModifierFlags? = nil) {
        self.key = key
        self.modifiers = modifiers
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
