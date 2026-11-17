import SwiftKeyCore
import SwiftUI

/// Settings of launcha, the search panel for menu items, apps and files.
struct LaunchaSettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var hotkeys: HotkeyCenter
    @Environment(LaunchaModel.self) private var launcha

    var body: some View {
        Form {
            Section {
                LabeledContent("Hot key") {
                    HotkeyRecorderField(hotkey: $settings.launchaHotkey, gate: hotkeys.recordingGate,
                                        placeholder: "Not set", problem: hotkeyProblem,
                                        conflict: conflict)
                }
                Toggle("Open with a double press of the main hot key", isOn: $settings.launchaDoubleTap)
                    .disabled(settings.triggerKeyHoldMode)
                    .help(settings.triggerKeyHoldMode
                          ? "Not available in hold mode, where the main hot key is held down."
                          : "Press the main hot key twice quickly to open launcha instead of the menu.")
                if settings.launchaDoubleTap && !settings.triggerKeyHoldMode {
                    HStack {
                        Text("Double press within")
                        Slider(value: $settings.launchaDoubleTapWindow, in: LaunchaSettings.doubleTapWindowRange, step: 0.05)
                        Text("\(settings.launchaDoubleTapWindow, specifier: "%.2f") s")
                    }
                }
            } footer: {
                Text("launcha also opens with swiftkey://launcha.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Calculate in launcha", isOn: $settings.launchaCalculator)
                    .help("A query such as 2*(3+4) shows its value first; Return copies it.")
            }

            Section {
                Toggle("Search Desktop, Documents and Downloads", isOn: protectedFolders)
                    .help("macOS may ask you to allow SwiftKey to access each folder.")
                if let error = launcha.consentError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } footer: {
                Text("Without this, launcha finds apps and files in your home folder outside these folders.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(width: 420)
    }

    private var protectedFolders: Binding<Bool> {
        Binding(get: { launcha.protectedFolders == .allowed },
                set: { allowed in
                    if allowed { launcha.allowProtectedFolders() } else { launcha.revokeProtectedFolders() }
                })
    }

    private var hotkeyProblem: String? {
        if case .failed(let reason) = hotkeys.launchaStatus { return reason }
        return nil
    }

    private func conflict(_ hotkey: Hotkey) -> String? {
        hotkey == settings.mainHotkeyValue ? "\(hotkey.display) is already the main hot key." : nil
    }
}
