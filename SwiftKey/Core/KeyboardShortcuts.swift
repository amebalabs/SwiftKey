import AppKit
import Combine
import os
import SwiftKeyCore
import Yams

// MARK: - KeyPressResult

/// Result of handling a keyboard press
enum KeyPressResult: Equatable {
    case escape
    case help
    case up
    case submenuPushed(title: String)
    case actionExecuted(sticky: Bool)
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
    /// Every action that runs code goes through it.
    private(set) var approvalGate: ApprovalGate!

    private let lastActionRepeatWindow: TimeInterval = 30
    
    // Default initialization for container creation
    init(approvalGate: ApprovalGate = ApprovalGate()) {
        // Default initialization - will be properly set in injectDependencies
        self.menuState = MenuState()
        self.settingsStore = SettingsStore()
        self.configManager = ConfigManager.create()
        self.dynamicMenuLoader = DynamicMenuLoader(approvalGate: approvalGate)
        self.approvalGate = approvalGate
    }

    func injectDependencies(_ container: DependencyContainer) {
        // Replace existing instances with the container ones
        self.menuState = container.menuState
        self.settingsStore = container.settingsStore
        self.configManager = container.configManager
        self.dynamicMenuLoader = container.dynamicMenuLoader
        self.approvalGate = container.approvalGate

        logger.debug("Dependencies injected successfully")
    }

    // MARK: - Key Handling

    /// Handles a key pressed in an open menu. The core `LeaderMachine` decides what the key does
    /// at the current level; this applies its effect to `menuState` and runs actions.
    func handleKey(
        key: String,
        modifierFlags: NSEvent.ModifierFlags? = nil
    ) async -> KeyPressResult {
        logger.debug("Key pressed: \(key, privacy: .public)")

        // Update UI state on main actor
        await MainActor.run {
            menuState.currentKey = key
            menuState.hint = nil
        }

        if key == "." {
            let result = await handleLastActionRepeat()
            if result != .none {
                return result
            }
        }

        // Keys that never reach the menu
        if key == "escape" {
            return .escape
        }
        if key == "?" {
            return .help
        }

        let event: LeaderEvent
        switch key {
        case "delete": event = .back
        case "cmd+up": event = .up
        default: event = .key(key, option: modifierFlags?.isOption == true)
        }
        let effect = await MainActor.run { () -> LeaderEffect in
            var machine = makeMachine()
            return machine.handle(event)
        }
        return await apply(effect, key: key)
    }

    /// A machine open at the levels `menuState` shows now.
    private func makeMachine() -> LeaderMachine {
        let overlayStyle = settingsStore.overlayStyle
        return LeaderMachine(
            items: MenuItemTree.build(menuState.rootMenu).items,
            openAt: menuState.keyPath,
            levels: menuState.menuStack.map { MenuItemTree.build($0).items },
            // Only the panel and the corner toast can stay open after an action.
            stickyAllowed: overlayStyle == .panel || overlayStyle == .cornerToast
        )
    }

    /// The config item a core node came from, in the current menu.
    private func menuItem(for node: Item) -> MenuItem? {
        menuState.currentMenu.first { $0.id.uuidString == node.id }
    }

    private func apply(_ effect: LeaderEffect, key: String) async -> KeyPressResult {
        switch effect {
        case .show(let path):
            return await MainActor.run { () -> KeyPressResult in
                if path.count < menuState.keyPath.count {
                    menuState.pop()
                    return .up
                }
                guard let group = menuState.currentMenu.first(where: { SequenceKey.normalize($0.key) == path.last }) else {
                    return .error(key: key)
                }
                menuState.push(key: path.last ?? key, title: group.title, items: group.submenu ?? [])
                return .submenuPushed(title: group.title)
            }
        case .close:
            return .escape
        case .none:
            // ⌘↑ at the top level stays where it is.
            return key == "cmd+up" ? .up : .none
        case .reject(let rejected, _):
            return .error(key: rejected)
        case .run(let node), .runAndStay(let node):
            guard let item = await MainActor.run(body: { menuItem(for: node) }), item.actionClosure != nil else {
                return .none
            }
            let path = await MainActor.run { menuState.breadcrumbs }
            // The menu closes at once; an action whose code needs approval asks after that.
            let run = { [approvalGate] in
                Task { @MainActor in
                    await approvalGate?.run(item, path: path)
                }
            }
            _ = run()
            await MainActor.run {
                menuState.lastExecutedAction = { _ = run() }
                menuState.lastActionTime = Date()
            }
            if case .runAndStay = effect {
                return .actionExecuted(sticky: true)
            }
            return .actionExecuted(sticky: false)
        case .runBatch(let groupNode, let actions):
            if let group = await MainActor.run(body: { menuItem(for: groupNode) }) {
                let ids = Set(actions.compactMap(\.id))
                let path = await MainActor.run { menuState.breadcrumbs + [group.title] }
                await executeBatchActions(in: (group.submenu ?? []).filter { ids.contains($0.id.uuidString) }, path: path)
            }
            return .actionExecuted(sticky: false)
        case .loadDynamic(let node):
            guard let item = await MainActor.run(body: { menuItem(for: node) }) else { return .error(key: key) }
            return await loadDynamicMenu(for: item, key: node.key)
        case .open:
            return .none
        }
    }

    // MARK: - Dynamic Menu Loading

    func loadDynamicMenu(for item: MenuItem, key: String) async -> KeyPressResult {
        guard item.action?.hasPrefix("dynamic://") == true else {
            return .error(key: item.key)
        }

        // Use the injected instance rather than the shared singleton
        let path = await MainActor.run { menuState.breadcrumbs }
        if let submenu = await dynamicMenuLoader.loadDynamicMenu(for: item, path: path) {
            // Update the UI state on the main actor
            await MainActor.run {
                menuState.push(key: key, title: item.title, items: submenu)
            }
            return .submenuPushed(title: item.title)
        } else {
            return .error(key: item.key)
        }
    }

    // MARK: - Batch Actions

    /// Runs the actions of a batch, with one approval for all the code they run.
    private func executeBatchActions(in submenu: [MenuItem], path: [String]) async {
        Task { @MainActor [approvalGate] in
            await approvalGate?.runBatch(submenu, path: path)
        }
    }

    // MARK: - Item Hotkeys

    /// A global item hotkey fired: an action runs at once, a group opens the menu there.
    @MainActor
    func runItemHotkey(_ item: MenuItem) {
        guard let path = findPathToMenuItem(item, in: menuState.rootMenu) else { return }
        let keys = path.compactMap { SequenceKey.normalize($0.key) }
        guard keys.count == path.count else { return }
        var machine = LeaderMachine(items: MenuItemTree.build(menuState.rootMenu).items)
        switch machine.open(at: keys) {
        case .show:
            menuState.reset()
            for (key, menuItem) in zip(keys, path) {
                menuState.push(key: key, title: menuItem.title, items: menuItem.submenu ?? [])
            }
            NotificationCenter.default.post(name: .presentOverlay, object: nil)
        case .run:
            // Hotkeys cannot see the Option key, so they always use the default sticky behaviour.
            let titles = path.dropLast().map(\.title)
            Task { @MainActor [approvalGate] in
                await approvalGate?.run(item, path: Array(titles))
            }
        default:
            break
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

    // MARK: - Last Action Repeat
    private func handleLastActionRepeat() async -> KeyPressResult {
        guard let lastAction = menuState.lastExecutedAction,
              let lastActionTime = menuState.lastActionTime,
              Date().timeIntervalSince(lastActionTime) <= lastActionRepeatWindow
        else {
            return .none
        }

        logger.debug("Repeating last action")

        Task(priority: .userInitiated) {
            lastAction()
            await MainActor.run {
                menuState.lastActionTime = Date()
            }
        }
        return .actionExecuted(sticky: false)
    }
}
