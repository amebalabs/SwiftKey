// Global hotkeys: the main key, the optional launcha key and the per-item hotkeys of the config.
// Each is any non-modifier key, alone or with modifiers. Registered with Carbon
// `RegisterEventHotKey`, which needs no Accessibility or Input Monitoring permission. Carbon
// reports both press and release.
import AppKit
import Carbon
import os
import SwiftKeyCore

@MainActor
final class HotkeyService {
    /// The hotkeys SwiftKey registers.
    enum Slot: Hashable, Sendable {
        case main
        case launcha
        /// The `hotkey:` of a menu item, by the item's id.
        case item(UUID)

        var role: String {
            switch self {
            case .main: "open SwiftKey"
            case .launcha: "open launcha"
            case .item: "be an item hotkey"
            }
        }

        var name: String {
            switch self {
            case .main: "the SwiftKey hotkey"
            case .launcha: "launcha"
            case .item: "another menu item"
            }
        }
    }

    enum Status: Equatable {
        /// No hotkey, paused, or recording a new hotkey.
        case inactive
        case active
        /// Registration failed; the text says why.
        case failed(String)
    }

    /// A registered hotkey was pressed.
    var onPress: ((Slot) -> Void)?
    /// A registered hotkey was released.
    var onRelease: ((Slot) -> Void)?
    var onStatusChange: ((Slot, Status) -> Void)?

    private var registrations: [Slot: Registration] = [:]
    private var statuses: [Slot: Status] = [:]
    private var handlerRef: EventHandlerRef?
    private var nextItemID: UInt32 = HotkeyService.firstItemID
    /// While paused (a hotkey is being recorded) nothing is registered; `resume` registers again.
    private(set) var isPaused = false

    private struct Registration {
        var hotkey: Hotkey
        var id: UInt32
        var ref: EventHotKeyRef?
    }

    private let logger = AppLogger.keyboard

    /// The C callback cannot capture context; it reaches the single service through this.
    private static weak var shared: HotkeyService?
    private static let signature = OSType(0x5357_4B59) // 'SWKY'
    private static let firstItemID: UInt32 = 100

    init() {
        HotkeyService.shared = self
    }

    func status(_ slot: Slot) -> Status { statuses[slot] ?? .inactive }

    func hotkey(_ slot: Slot) -> Hotkey? { registrations[slot]?.hotkey }

    /// Every slot with a hotkey, registered or not.
    var slots: [Slot] { Array(registrations.keys) }

    /// Activates `hotkey` in `slot`, replacing the previous one. nil turns the slot off.
    /// A slot that goes off while its key is down reports a release, so callers never keep
    /// a stale "held" state.
    func activate(_ hotkey: Hotkey?, for slot: Slot) {
        if let hotkey, hotkey == registrations[slot]?.hotkey, status(slot) == .active { return }
        deactivate(slot)
        guard let hotkey else { return }
        registrations[slot] = Registration(hotkey: hotkey, id: id(for: slot), ref: nil)
        guard !isPaused else { return }
        register(slot)
    }

    /// Turns off every item slot whose id is not in `keep`.
    func deactivateItems(except keep: Set<UUID>) {
        for slot in registrations.keys {
            if case .item(let id) = slot, !keep.contains(id) { deactivate(slot) }
        }
    }

    /// Unregisters every hotkey but remembers them, for recording a new hotkey.
    func pause() {
        guard !isPaused else { return }
        isPaused = true
        for slot in registrations.keys { unregister(slot) }
    }

    /// Registers the remembered hotkeys again after `pause`: the main key first, then launcha,
    /// then items, so a duplicate fails in the same slot as before.
    func resume() {
        guard isPaused else { return }
        isPaused = false
        for slot in registrations.keys.sorted(by: { Self.priority($0) < Self.priority($1) }) { register(slot) }
    }

    private static func priority(_ slot: Slot) -> Int {
        switch slot {
        case .main: 0
        case .launcha: 1
        case .item: 2
        }
    }

    private func id(for slot: Slot) -> UInt32 {
        switch slot {
        case .main: return 1
        case .launcha: return 2
        case .item:
            if let existing = registrations[slot]?.id { return existing }
            defer { nextItemID += 1 }
            return nextItemID
        }
    }

    private func deactivate(_ slot: Slot) {
        unregister(slot)
        registrations[slot] = nil
        setStatus(.inactive, for: slot)
    }

    private func unregister(_ slot: Slot) {
        guard let ref = registrations[slot]?.ref else {
            if isPaused { setStatus(.inactive, for: slot) }
            return
        }
        UnregisterEventHotKey(ref)
        registrations[slot]?.ref = nil
        setStatus(.inactive, for: slot)
        // Carbon sends no release for a hotkey that is gone.
        onRelease?(slot)
    }

    private func register(_ slot: Slot) {
        guard let registration = registrations[slot] else { return }
        let hotkey = registration.hotkey
        guard hotkey.isValid, case .combo(let keyCode, let modifiers) = hotkey else {
            setStatus(.failed("\(hotkey.display) cannot \(slot.role). Choose a key that is not a modifier."), for: slot)
            return
        }
        if let other = registrations.first(where: { $0.key != slot && $0.value.hotkey == hotkey && $0.value.ref != nil })?.key {
            setStatus(.failed("\(hotkey.display) is already used for \(other.name)."), for: slot)
            return
        }
        installCarbonHandler()
        var carbonModifiers: UInt32 = 0
        if modifiers.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
        if modifiers.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }
        if modifiers.contains(.option) { carbonModifiers |= UInt32(optionKey) }
        if modifiers.contains(.control) { carbonModifiers |= UInt32(controlKey) }
        let hotKeyID = EventHotKeyID(signature: HotkeyService.signature, id: registration.id)
        var ref: EventHotKeyRef?
        let result = RegisterEventHotKey(UInt32(keyCode), carbonModifiers, hotKeyID, GetApplicationEventTarget(),
                                         OptionBits(kEventHotKeyExclusive), &ref)
        if result == noErr, let ref {
            registrations[slot]?.ref = ref
            setStatus(.active, for: slot)
        } else if result == OSStatus(eventHotKeyExistsErr) {
            setStatus(.failed("\(hotkey.display) is already used by another app."), for: slot)
        } else {
            setStatus(.failed("Cannot register \(hotkey.display) (error \(result))."), for: slot)
        }
    }

    private func setStatus(_ status: Status, for slot: Slot) {
        guard statuses[slot] != status else { return }
        statuses[slot] = status
        logger.info("Hotkey \(String(describing: slot), privacy: .public) \(self.registrations[slot]?.hotkey.string ?? "none", privacy: .public): \(String(describing: status), privacy: .public)")
        onStatusChange?(slot, status)
    }

    private func slot(forID id: UInt32) -> Slot? {
        registrations.first { $0.value.id == id && $0.value.ref != nil }?.key
    }

    private func installCarbonHandler() {
        guard handlerRef == nil else { return }
        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            guard let event else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr, id.signature == HotkeyService.signature else { return OSStatus(eventNotHandledErr) }
            let kind = GetEventKind(event)
            let hotKeyID = id.id
            MainActor.assumeIsolated {
                guard let service = HotkeyService.shared, let slot = service.slot(forID: hotKeyID) else { return }
                if kind == UInt32(kEventHotKeyPressed) {
                    service.logger.debug("Hotkey \(String(describing: slot), privacy: .public) pressed")
                    service.onPress?(slot)
                } else if kind == UInt32(kEventHotKeyReleased) {
                    service.onRelease?(slot)
                }
            }
            return noErr
        }, specs.count, &specs, nil, &handlerRef)
    }
}
