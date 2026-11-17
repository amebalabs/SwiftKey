import Combine
import Foundation
import SwiftKeyCore

/// Connects the global hotkeys to the app: the main key from settings, the `hotkey:` of menu
/// items from the config, and the recorders that pause every hotkey while a new one is recorded.
final class HotkeyCenter: ObservableObject {
    /// The state of the main hotkey, for Settings.
    @Published private(set) var mainStatus: HotkeyService.Status = .inactive
    /// Item hotkeys that could not be registered, by item id, with the reason.
    @Published private(set) var itemProblems: [UUID: String] = [:]

    /// The main hotkey went down.
    var onMainPress: (() -> Void)?
    /// The main hotkey went up.
    var onMainRelease: (() -> Void)?
    /// The hotkey of the item with this id went down.
    var onItemPress: ((UUID) -> Void)?

    @MainActor private lazy var service: HotkeyService = {
        let service = HotkeyService()
        service.onPress = { [weak self] slot in
            switch slot {
            case .main: self?.onMainPress?()
            case .item(let id): self?.onItemPress?(id)
            case .launcha: break
            }
        }
        service.onRelease = { [weak self] slot in
            if slot == .main { self?.onMainRelease?() }
        }
        service.onStatusChange = { [weak self] slot, status in
            self?.statusChanged(slot, status)
        }
        return service
    }()

    /// One recording at a time; every hotkey is off while it runs.
    @MainActor private(set) lazy var recordingGate = HotkeyRecordingGate { [weak self] recording in
        guard let self else { return }
        if recording { service.pause() } else { service.resume() }
    }

    /// Registers `hotkey` as the main key; nil turns it off.
    @MainActor
    func setMain(_ hotkey: Hotkey?) {
        service.activate(hotkey, for: .main)
    }

    /// Registers the hotkeys of menu items, by item id, and turns off those of items that are gone.
    @MainActor
    func setItems(_ hotkeys: [UUID: Hotkey]) {
        service.deactivateItems(except: Set(hotkeys.keys))
        itemProblems = itemProblems.filter { hotkeys[$0.key] != nil }
        for (id, hotkey) in hotkeys {
            service.activate(hotkey, for: .item(id))
        }
    }

    /// The `hotkey:` strings of `menu` and its submenus that parse, by item id.
    static func itemHotkeys(in menu: [MenuItem]) -> [UUID: Hotkey] {
        var result: [UUID: Hotkey] = [:]
        for item in menu {
            if let text = item.hotkey, let hotkey = Hotkey(string: text) { result[item.id] = hotkey }
            if let submenu = item.submenu { result.merge(itemHotkeys(in: submenu)) { first, _ in first } }
        }
        return result
    }

    @MainActor
    private func statusChanged(_ slot: HotkeyService.Slot, _ status: HotkeyService.Status) {
        switch slot {
        case .main:
            mainStatus = status
        case .item(let id):
            if case .failed(let reason) = status { itemProblems[id] = reason } else { itemProblems[id] = nil }
        case .launcha:
            break
        }
    }
}
