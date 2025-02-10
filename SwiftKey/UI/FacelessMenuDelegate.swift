import AppKit

protocol FacelessMenuDelegate: AnyObject {
    func facelessMenuControllerDidRequestOverlayCheatsheet(_ controller: FacelessMenuController)
}

class FacelessMenuController {
    let rootMenu: [MenuItem]
    var menuStack: [[MenuItem]] = []
    var breadcrumbs: [String] = []
    var resetDelay: TimeInterval
    var statusItem: NSStatusItem
    var localMonitor: Any?
    var sessionTimer: Timer?

    var animationTimer: Timer?
    var indicatorState: Bool = false
    var sessionActive: Bool = false

    weak var delegate: FacelessMenuDelegate?

    init(rootMenu: [MenuItem], statusItem: NSStatusItem, resetDelay: TimeInterval) {
        self.rootMenu = rootMenu
        self.statusItem = statusItem
        self.resetDelay = resetDelay
        updateStatusItem()
    }

    var currentMenu: [MenuItem] {
        menuStack.last ?? rootMenu
    }

    func updateStatusItem() {
        let imageConfig = NSImage.SymbolConfiguration(
            pointSize: 20,
            weight: .medium,
            scale: .small
        )
        if sessionActive {
            statusItem.button?.title = ""
            let imageName = indicatorState ? "circle.fill" : "circle"
            statusItem.button?.image = NSImage(systemSymbolName: imageName, accessibilityDescription: "Active session")?.withSymbolConfiguration(imageConfig)
        } else {
            statusItem.button?.image = NSImage(
                systemSymbolName: "k.circle",
                accessibilityDescription: "Active session"
            )?
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
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            return self?.handleKeyEvent(event: event)
        }
        startAnimationTimer()
        updateStatusItem()
        resetSessionTimer()
        NSApp.activate(ignoringOtherApps: true)
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
        menuStack = []
        breadcrumbs = []
        updateStatusItem()
    }

    func handleKeyEvent(event: NSEvent) -> NSEvent? {
        if event.keyCode == 53 { // Escape
            endSession()
            return nil
        }
        if event.keyCode == 126, event.modifierFlags.contains(.command) {
            if !menuStack.isEmpty { menuStack.removeLast() }
            if !breadcrumbs.isEmpty { breadcrumbs.removeLast() }
            updateStatusItem()
            resetSessionTimer()
            return nil
        }
        guard let key = englishCharactersForKeyEvent(event: event), !key.isEmpty else { return nil }
        if key == "?" {
            delegate?.facelessMenuControllerDidRequestOverlayCheatsheet(self)
            return nil
        }
        processKey(keyString: key)
        resetSessionTimer()
        return nil
    }

    func processKey(keyString: String) {
        guard let pressedKey = keyString.first else { return }
        if let action = currentMenu.first(where: { $0.key.caseInsensitiveCompare(String(pressedKey)) == .orderedSame }) {
            blinkIndicator(success: true)
            if let submenu = action.submenu {
                breadcrumbs.append(action.title)
                menuStack.append(submenu)
                updateStatusItem()
            } else if let act = action.actionClosure {
                act()
                endSession()
            }
        } else {
            blinkIndicator(success: false)
            NSSound.beep()
        }
    }
}
