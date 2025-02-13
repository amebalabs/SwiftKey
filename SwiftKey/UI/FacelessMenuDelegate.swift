import AppKit

class FacelessMenuController {
    let rootMenu: [MenuItem]
    var resetDelay: TimeInterval
    var statusItem: NSStatusItem
    var localMonitor: Any?
    var sessionTimer: Timer?
    var animationTimer: Timer?
    var indicatorState: Bool = false
    var sessionActive: Bool = false
    var keyPressController: KeyPressController

    init(rootMenu: [MenuItem], statusItem: NSStatusItem, resetDelay: TimeInterval) {
        self.rootMenu = rootMenu
        self.statusItem = statusItem
        self.resetDelay = resetDelay
        self.keyPressController = KeyPressController(menuState: MenuState.shared)
        updateStatusItem()
    }

    var currentMenu: [MenuItem] {
        MenuState.shared.menuStack.last ?? rootMenu
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

    func blinkIndicator(success: Bool) {
        animationTimer?.invalidate()
        animationTimer = nil
        if let button = statusItem.button {
            button.contentTintColor = success ? NSColor.systemGreen : NSColor.systemRed
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
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
            self.keyPressController.handleKeyAsync(key) { result in
                switch result {
                case .escape:
                    self.endSession()
                case .help:
                    self.endSession()
                    AppDelegate.shared.presentOverlay()
                case .up:
                    break
                case .submenuPushed:
                    self.blinkIndicator(success: true)
                    self.updateStatusItem()
                case .actionExecuted:
                    self.endSession()
                case .dynamicLoading:
                    break
                case .error:
                    self.blinkIndicator(success: false)
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
        MenuState.shared.menuStack = []
        MenuState.shared.breadcrumbs = []
        updateStatusItem()
    }
}
