import AppKit

class FacelessMenuController: DependencyInjectable {
    let rootMenu: [MenuItem]
    var resetDelay: TimeInterval
    var statusItem: NSStatusItem
    var localMonitor: Any?
    var sessionTimer: Timer?
    var animationTimer: Timer?
    var indicatorState: Bool = false
    var sessionActive: Bool = false
    // Dependencies - non-optional for consistent dependency handling
    var menuState: MenuState
    var settingsStore: SettingsStore
    var keyboardManager: KeyboardManager

    init(
        rootMenu: [MenuItem],
        statusItem: NSStatusItem,
        resetDelay: TimeInterval,
        menuState: MenuState,
        settingsStore: SettingsStore,
        keyboardManager: KeyboardManager
    ) {
        self.rootMenu = rootMenu
        self.statusItem = statusItem
        self.resetDelay = resetDelay
        self.menuState = menuState
        self.settingsStore = settingsStore
        self.keyboardManager = keyboardManager
        updateStatusItem()
    }
    
    // Convenience initializer that gets dependencies from AppDelegate
    convenience init(
        rootMenu: [MenuItem],
        statusItem: NSStatusItem,
        resetDelay: TimeInterval,
        menuState: MenuState
    ) {
        if let appDelegate = NSApp.delegate as? AppDelegate {
            self.init(
                rootMenu: rootMenu,
                statusItem: statusItem,
                resetDelay: resetDelay,
                menuState: menuState,
                settingsStore: appDelegate.settings,
                keyboardManager: appDelegate.keyboardManager
            )
        } else {
            // Fallback to create minimal dependencies
            self.init(
                rootMenu: rootMenu,
                statusItem: statusItem,
                resetDelay: resetDelay,
                menuState: menuState,
                settingsStore: SettingsStore(),
                keyboardManager: KeyboardManager()
            )
        }
    }

    func injectDependencies(_ container: DependencyContainer) {
        self.menuState = container.menuState
        self.settingsStore = container.settingsStore
        self.keyboardManager = container.keyboardManager
    }

    var currentMenu: [MenuItem] {
        menuState.visibleMenu
    }

    func updateStatusItem() {
        let imageConfig = NSImage.SymbolConfiguration(pointSize: 20, weight: .medium, scale: .small)
        if sessionActive {
            statusItem.button?.title = ""
            let imageName = indicatorState ? "circle.fill" : "circle"
            statusItem.button?.image = NSImage(systemSymbolName: imageName, accessibilityDescription: "Active session")?
                .withSymbolConfiguration(imageConfig)
        } else {
            statusItem.button?
                .image = NSImage(systemSymbolName: "k.circle", accessibilityDescription: "Active session")?
                .withSymbolConfiguration(imageConfig)
        }
    }

    func startAnimationTimer() {
        animationTimer?.invalidate()
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.toggleIndicator()
        }
    }

    func toggleIndicator() {
        indicatorState.toggle()
        updateStatusItem()
    }

    func blinkIndicator(success: Bool) async {
        animationTimer?.invalidate()
        animationTimer = nil

        if let button = statusItem.button {
            await MainActor.run {
                button.contentTintColor = success ? NSColor.systemGreen : NSColor.systemRed
            }

            try? await Task.sleep(nanoseconds: 300000000)

            await MainActor.run { [weak self] in
                button.contentTintColor = nil
                self?.startAnimationTimer()
            }
        }
    }

    func resetSessionTimer() {
        sessionTimer?.invalidate()
        sessionTimer = Timer.scheduledTimer(withTimeInterval: resetDelay, repeats: false) { [weak self] _ in
            self?.endSession()
        }
    }

    func startSession() {
        guard !sessionActive else { return }
        sessionActive = true
        NSApp.activate(ignoringOtherApps: true)
        startAnimationTimer()
        updateStatusItem()
        resetSessionTimer()

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self,
                  let key = englishCharactersForKeyEvent(event: event),
                  !key.isEmpty else { return event }

            // Spawn a Task to handle the key press asynchronously
            Task { [weak self] in
                guard let self = self else { return }

                let result = await keyboardManager.handleKey(key: key)

                switch result {
                case .escape:
                    self.endSession()
                case .help:
                    self.endSession()
                    AppDelegate.shared.presentOverlay()
                case .up:
                    break
                case .submenuPushed:
                    await self.blinkIndicator(success: true)
                    self.updateStatusItem()
                case .actionExecuted:
                    self.endSession()
                case .dynamicLoading:
                    break
                case .error:
                    await self.blinkIndicator(success: false)
                case .none:
                    break
                }
                self.resetSessionTimer()
            }

            return nil
        }
    }

    func endSession() {
        sessionActive = false
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        animationTimer?.invalidate()
        animationTimer = nil
        sessionTimer?.invalidate()
        sessionTimer = nil
        menuState.menuStack = []
        menuState.breadcrumbs = []
        updateStatusItem()
    }
}
