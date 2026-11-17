import SwiftKeyCore
import SwiftUI

struct GeneralSettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject private var hotkeys: HotkeyCenter
    @ObservedObject private var launchAtLogin = LaunchAtLogin.observable
    @EnvironmentObject private var sparkleUpdater: SparkleUpdater
    @Environment(AccessibilityAccess.self) private var accessibility
    @State private var promptCopied = false

    var body: some View {
        Form {
            LaunchAtLogin.Toggle()
            Picker("Overlay Style", selection: $settings.overlayStyle) {
                ForEach(SettingsStore.OverlayStyle.allCases, id: \.self) { style in
                    Text(style.rawValue).tag(style)
                }
            }

            if settings.overlayStyle == .panel {
                Toggle("Horizontal Layout", isOn: $settings.useHorizontalOverlayLayout)
            }

            Picker("Show SwiftKey on", selection: $settings.overlayScreenOption) {
                ForEach(SettingsStore.OverlayScreenOption.allCases, id: \.self) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            Divider()
            HStack {
                Text("Menu Reset Delay")
                Slider(value: $settings.menuStateResetDelay, in: 0 ... 10, step: 0.5)
                Text("\(settings.menuStateResetDelay, specifier: "%.1f")")
            }
            LabeledContent("Hot key") {
                HotkeyRecorderField(hotkey: $settings.mainHotkey, gate: hotkeys.recordingGate,
                                    placeholder: "Not set", problem: mainHotkeyProblem)
            }
            Toggle("Trigger hold mode", isOn: $settings.triggerKeyHoldMode)
            HStack {
                Text("Show menu after")
                Slider(value: $settings.showMenuDelay, in: SettingsStore.showMenuDelayRange, step: 0.05)
                Text("\(settings.showMenuDelay, specifier: "%.2f") s")
            }
            .help("Keys typed faster than this work without the menu ever showing. 0 shows it at once.")
            Divider()

            Section {
                LabeledContent("Accessibility") {
                    HStack(spacing: 8) {
                        if accessibility.isTrusted {
                            Label("On", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Label("Off", systemImage: "exclamationmark.circle")
                                .foregroundStyle(.secondary)
                            Button("Allow…") {
                                NotificationCenter.default.post(name: .showAccessibilityHelp, object: nil)
                            }
                        }
                    }
                }
                .help("Micro-apps need Accessibility to read the selected text or the front window, and to press keys or paste.")
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                accessibility.refresh()
            }
            .onAppear { accessibility.refresh() }

            Section {
                LabeledContent("Coding agent") {
                    HStack(spacing: 8) {
                        Button("Copy Prompt for Agent") { copyAgentPrompt() }
                        if promptCopied {
                            Text(AgentPrompt.toast)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .transition(.opacity)
                        }
                    }
                }
                .help("Copies a ready text that tells a coding agent such as Claude Code how to change your menu and write micro-apps. Add your task at its end.")
            }

            Section {
                Toggle("Automatically check for updates", isOn: $settings.automaticallyCheckForUpdates)
                Toggle("Receive beta updates", isOn: $settings.enableBetaUpdates)
                    .help("Beta versions might contain bugs and are not recommended for production use")
            }

            Section {
                HStack {
                    Button("Check for Updates Now") {
                        sparkleUpdater.checkForUpdates()
                    }
                    .disabled(!sparkleUpdater.canCheckForUpdates)

                    if !sparkleUpdater.canCheckForUpdates {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.leading, 4)
                    }
                }
                Text("Last checked: \(lastUpdateCheck)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                Text("Current Version: \(currentVersion)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(width: 420)
    }

    /// Copies the agent prompt for the config file in use and shows a short confirmation.
    private func copyAgentPrompt() {
        guard let config = AppPaths.current.configOverride ?? settings.configFileResolvedURL else { return }
        AgentPromptSource.copy(AgentPromptSource.text(configURL: config), to: .general)
        withAnimation { promptCopied = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            withAnimation { promptCopied = false }
        }
    }

    private var mainHotkeyProblem: String? {
        if case .failed(let reason) = hotkeys.mainStatus { return reason }
        return nil
    }

    private var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }

    private var lastUpdateCheck: String {
        let date = UserDefaults.standard.object(forKey: "SULastCheckTime") as? Date ?? Date()
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

#Preview {
    GeneralSettingsView()
        .environmentObject(SettingsStore())
        .environmentObject(HotkeyCenter())
        .environment(AccessibilityAccess())
}
