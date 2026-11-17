// Record any non-modifier key, alone or with modifiers.
import AppKit
import SwiftKeyCore
import SwiftUI

/// One recording of a hotkey: listens to keys in SwiftKey's windows until a valid key comes,
/// with every global hotkey paused through the gate.
@MainActor
@Observable
final class HotkeyRecording: HotkeyRecordingOwner {
    private(set) var isRecording = false
    private(set) var preview = ""
    private(set) var warning: String?
    @ObservationIgnored private let monitor = KeyMonitor()
    @ObservationIgnored private var gate: HotkeyRecordingGate?
    @ObservationIgnored private var resignObserver: NSObjectProtocol?
    @ObservationIgnored private var conflict: (Hotkey) -> String? = { _ in nil }
    @ObservationIgnored private var onFinish: (Hotkey) -> Void = { _ in }

    /// Starts listening. `conflict` returns a warning for a key that may not be used here;
    /// `onFinish` gets the recorded key.
    func start(gate: HotkeyRecordingGate, conflict: @escaping (Hotkey) -> String? = { _ in nil },
               onFinish: @escaping (Hotkey) -> Void) {
        // Starting again first stops this recording's monitor and observer.
        stopListening()
        self.gate = gate
        self.conflict = conflict
        self.onFinish = onFinish
        isRecording = true
        preview = ""
        warning = nil
        // Cancels any other recording and keeps the hotkeys off until this one ends.
        gate.begin(self)
        monitor.start { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
        // Leaving SwiftKey stops recording, so the hotkeys never stay switched off.
        resignObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancel() }
        }
    }

    func cancel() {
        guard isRecording else { return }
        isRecording = false
        preview = ""
        stopListening()
        gate?.end(self)
    }

    private func stopListening() {
        monitor.stop()
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        let modifiers = ModifierSet(event.modifierFlags).subtracting(.function)
        switch event.type {
        case .flagsChanged:
            // Modifiers may be held as part of a combination, but are never hotkeys alone.
            preview = modifiers.symbols
            return nil
        case .keyDown:
            let hotkey = Hotkey.combo(keyCode: event.keyCode, modifiers: modifiers)
            if KeyCodes.name(for: event.keyCode) == nil || !hotkey.isValid {
                warning = "A modifier alone cannot be a hotkey. Press any other key."
            } else if let problem = conflict(hotkey) {
                warning = problem
            } else {
                warning = nil
                cancel()
                onFinish(hotkey)
            }
            return nil
        default:
            return event
        }
    }
}

/// A field that shows a hotkey and records a new one when clicked.
struct HotkeyRecorderField: View {
    /// The hotkey as a `Hotkey` string; empty when none is set.
    @Binding var hotkey: String
    let gate: HotkeyRecordingGate
    var placeholder = "Click to record"
    /// A problem to show under the field, such as a failed registration.
    var problem: String?
    /// A warning for a recorded key that may not be used here.
    var conflict: (Hotkey) -> String? = { _ in nil }
    @State private var recording = HotkeyRecording()

    var body: some View {
        let isRecording = recording.isRecording
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    if isRecording {
                        recording.cancel()
                    } else {
                        recording.start(gate: gate, conflict: conflict) { hotkey = $0.string }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isRecording {
                            Circle().fill(Color.accentColor).frame(width: 7, height: 7)
                            Text(recording.preview.isEmpty ? "Press a key…" : recording.preview)
                                .foregroundStyle(recording.preview.isEmpty ? .secondary : .primary)
                        } else if let value = Hotkey(string: hotkey) {
                            Text(value.display)
                        } else {
                            Text(placeholder).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 10)
                    .frame(minWidth: 160)
                    .frame(height: 26)
                    .contentShape(Rectangle())
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(isRecording ? Color.accentColor : Color.primary.opacity(0.15),
                                      style: StrokeStyle(lineWidth: isRecording ? 1.5 : 1, dash: isRecording ? [4, 3] : [])))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Hotkey(string: hotkey).map { "Hotkey \($0.display). Click to change." } ?? "Record a hotkey")

                if !hotkey.isEmpty, !isRecording {
                    Button("Clear") { hotkey = "" }
                        .controlSize(.small)
                        .accessibilityLabel("Clear the hotkey")
                }
            }
            .onDisappear { recording.cancel() }

            if let warning = recording.warning {
                hint(warning)
            } else if let problem, !isRecording {
                hint(problem)
            }
        }
    }

    private func hint(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
    }
}
