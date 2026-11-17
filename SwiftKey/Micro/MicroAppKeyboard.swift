// Sends key presses and pasted text to the app where a micro-app started, and copies its selection
// when Accessibility does not give it. Needs the Accessibility permission.
import AppKit
import Carbon
import CoreGraphics
import SwiftKeyCore

@MainActor
protocol MicroAppKeyboardSending: AnyObject {
    /// Sends `action` to `target`, which must still be the app in front.
    func send(_ action: MicroAppKeyboardAction, to target: MicroAppTarget?) async throws
}

@MainActor
final class MicroAppKeyboard: MicroAppKeyboardSending {
    /// The app reads the clipboard when it handles ⌘V; the old clipboard comes back after this.
    static let pasteSettle: TimeInterval = 0.4
    /// The longest wait for ⌘C to fill the clipboard.
    static let copyWait: TimeInterval = 0.5
    /// The pause between two key presses of a `keys` step.
    static let keyPause: TimeInterval = 0.03
    /// The pause after the last key press, so the app is ready for the next step (a new tab
    /// focuses its address bar, a dialog opens).
    static let keySettle: TimeInterval = 0.15

    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    func send(_ action: MicroAppKeyboardAction, to target: MicroAppTarget?) async throws {
        try await ready(target)
        switch action {
        case .keys(let keys):
            for (index, key) in keys.enumerated() {
                if index > 0 { try await Task.sleep(nanoseconds: UInt64(Self.keyPause * 1_000_000_000)) }
                post(key)
            }
            try await Task.sleep(nanoseconds: UInt64(Self.keySettle * 1_000_000_000))
        case .paste(let text, let keep):
            let saved = keep ? nil : MicroAppPasteboardSnapshot(pasteboard)
            pasteboard.clearContents()
            let item = NSPasteboardItem()
            item.setString(text, forType: .string)
            // Clipboard managers leave out text that SwiftKey puts back right away.
            if !keep { item.setData(Data(), forType: MicroAppPasteboardSnapshot.transient) }
            pasteboard.writeObjects([item])
            let ours = pasteboard.changeCount
            post(.combo(keyCode: KeyCodes.ansi["v"]!, modifiers: .command))
            guard let saved else { return }
            try? await Task.sleep(nanoseconds: UInt64(Self.pasteSettle * 1_000_000_000))
            // Something else copied in the meantime: that stays.
            if pasteboard.changeCount == ours { saved.restore(to: pasteboard) }
        }
    }

    /// The selected text of `target` by ⌘C, with the clipboard put back; `nil` when nothing was copied.
    func copySelection(from target: MicroAppTarget) async -> String? {
        guard (try? await ready(target)) != nil else { return nil }
        let saved = MicroAppPasteboardSnapshot(pasteboard)
        let before = pasteboard.changeCount
        post(.combo(keyCode: KeyCodes.ansi["c"]!, modifiers: .command))
        var text: String?
        let deadline = Date().addingTimeInterval(Self.copyWait)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
            guard pasteboard.changeCount != before else { continue }
            // The app clears the clipboard first, then writes it.
            try? await Task.sleep(nanoseconds: 30_000_000)
            text = pasteboard.string(forType: .string)
            break
        }
        if pasteboard.changeCount != before { saved.restore(to: pasteboard) }
        return text
    }

    /// Waits until `target` is in front with the keyboard: SwiftKey's panels are gone. Throws when it
    /// is not, when SwiftKey may not send keys or when a password field holds the keyboard.
    private func ready(_ target: MicroAppTarget?) async throws {
        guard let target, target.pid != ProcessInfo.processInfo.processIdentifier else {
            throw MicroAppInputError(message: "SwiftKey was in front when the micro-app started, so there is no app to send to.")
        }
        try MicroAppAccessibility.require()
        if IsSecureEventInputEnabled() {
            throw MicroAppInputError(message: "A password field holds the keyboard (secure input), so SwiftKey sent nothing.")
        }
        // The panel style never activates SwiftKey: once it is closed, the keyboard is back with the app.
        // The HUD, corner toast and menu-bar styles do, so the app is brought back to the front.
        if NSWorkspace.shared.frontmostApplication?.processIdentifier != target.pid {
            NSRunningApplication(processIdentifier: target.pid)?.activate()
        }
        let deadline = Date().addingTimeInterval(1)
        while Date() < deadline {
            if NSApp.keyWindow == nil, NSWorkspace.shared.frontmostApplication?.processIdentifier == target.pid { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.pid else {
            throw MicroAppInputError(message: "\(target.name) is no longer in front, so SwiftKey sent nothing to it.")
        }
    }

    /// Presses and releases one key with its modifiers. A letter, digit or sign is the key that
    /// types it in the ASCII-capable layout, so `cmd+s` is Save in Dvorak too.
    private func post(_ key: Hotkey) {
        guard case .combo(var keyCode, let modifiers) = key else { return }
        if let name = KeyCodes.name(for: keyCode), name.count == 1, let local = KeyTranslator.keyCode(forLatin: name) { keyCode = local }
        var flags = CGEventFlags()
        if modifiers.contains(.control) { flags.insert(.maskControl) }
        if modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if modifiers.contains(.shift) { flags.insert(.maskShift) }
        if modifiers.contains(.command) { flags.insert(.maskCommand) }
        let source = CGEventSource(stateID: .privateState)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down) else { continue }
            event.flags = flags
            event.post(tap: .cghidEventTap)
        }
    }
}

/// Every item of the clipboard with the data of each of its types, to put back later.
struct MicroAppPasteboardSnapshot {
    static let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    let items: [[(NSPasteboard.PasteboardType, Data)]]

    init(_ pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        let objects = items.map { entries -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in entries { item.setData(data, forType: type) }
            return item
        }
        // The old content is in the clipboard managers' history already.
        objects.first?.setData(Data(), forType: Self.transient)
        pasteboard.writeObjects(objects)
    }
}
