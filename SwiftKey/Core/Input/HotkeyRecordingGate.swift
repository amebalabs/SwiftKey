// One hotkey recording at a time. Global hotkeys stay off for the whole time a recording runs.
import Foundation

/// A view-side recorder that the gate can stop when another recording starts.
@MainActor
protocol HotkeyRecordingOwner: AnyObject {
    func cancel()
}

/// Gives recording to one owner at a time. A new owner cancels the previous one, and only
/// the current owner can end recording, so a late `end` from a cancelled owner never turns
/// the hotkeys back on while another recording still runs.
@MainActor
final class HotkeyRecordingGate {
    private(set) var isActive = false
    private weak var owner: HotkeyRecordingOwner?
    private let onChange: (Bool) -> Void

    /// `onChange` is called only when recording starts or stops as a whole.
    init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
    }

    func begin(_ newOwner: HotkeyRecordingOwner) {
        let previous = owner
        // Take ownership first: the previous owner's `end` from its `cancel` is then a no-op.
        owner = newOwner
        if let previous, previous !== newOwner { previous.cancel() }
        guard !isActive else { return }
        isActive = true
        onChange(true)
    }

    func end(_ endingOwner: HotkeyRecordingOwner) {
        // A recorder that was deallocated without `end` leaves `owner` nil: any `end` then stops.
        guard isActive, owner == nil || owner === endingOwner else { return }
        owner = nil
        isActive = false
        onChange(false)
    }
}
