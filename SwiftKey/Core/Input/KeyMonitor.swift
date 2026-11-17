// Key event plumbing for the hotkey recorders.
import AppKit
import SwiftKeyCore

extension ModifierSet {
    init(_ flags: NSEvent.ModifierFlags) {
        self = []
        if flags.contains(.control) { insert(.control) }
        if flags.contains(.option) { insert(.option) }
        if flags.contains(.shift) { insert(.shift) }
        if flags.contains(.command) { insert(.command) }
        if flags.contains(.function) { insert(.function) }
    }
}

/// Owns an NSEvent local monitor (keyDown + flagsChanged) for the lifetime of a recorder.
@MainActor
final class KeyMonitor {
    private var token: Any?

    func start(_ handler: @escaping (NSEvent) -> NSEvent?) {
        stop()
        token = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged], handler: handler)
    }

    func stop() {
        if let token { NSEvent.removeMonitor(token) }
        token = nil
    }
}
