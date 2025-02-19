import KeyboardShortcuts
import SwiftUI

struct GeneralSettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @ObservedObject private var launchAtLogin = LaunchAtLogin.observable
    @StateObject private var updater = SparkleUpdater.shared

    var body: some View {
        Form {
            LaunchAtLogin.Toggle()
            Picker("Overlay Style", selection: settings.$overlayStyle) {
                ForEach(SettingsStore.OverlayStyle.allCases, id: \.self) { style in
                    Text(style.rawValue).tag(style)
                }
            }

            if settings.overlayStyle == .panel {
                Toggle("Horizontal Layout", isOn: settings.$useHorizontalOverlayLayout)
            }

            Picker("Show SwiftKey on", selection: settings.$overlayScreenOption) {
                ForEach(SettingsStore.OverlayScreenOption.allCases, id: \.self) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            HStack {
                Text("Menu Reset Delay")
                Slider(value: settings.$menuStateResetDelay, in: 0 ... 10, step: 0.5)
                Text("\(settings.menuStateResetDelay, specifier: "%.1f")")
            }
            KeyboardShortcuts.Recorder("Hot key", name: .toggleApp)

            // Configuration file section.
            HStack {
                Text("Configuration file:")
                Button("Change...") {
                    AppShared.changeConfigFile()
                }
            }
            HStack(spacing: 8) {
                if let _ = UserDefaults.standard.data(forKey: "ConfigFileBookmark") {
                    if let url = AppShared.resolveConfigFileURL() {
                        Text(url.path)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }
                } else {
                    Text("No config file selected")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Button(action: {
                    AppShared.openConfigFile()
                }) {
                    Image(systemName: "doc.text")
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(BorderlessButtonStyle())
                .help("Reveal configuration file in Finder")
            }

            Divider()

            Section {
                Toggle("Automatically check for updates", isOn: $settings.automaticallyCheckForUpdates)
                Toggle("Receive beta updates", isOn: $settings.enableBetaUpdates)
                    .help("Beta versions might contain bugs and are not recommended for production use")
            }

            Section {
                HStack {
                    Button("Check for Updates Now") {
                        updater.checkForUpdates()
                    }
                    .disabled(!updater.canCheckForUpdates)

                    if !updater.canCheckForUpdates {
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
        .frame(width: 400)
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
    GeneralSettingsView().environmentObject(SettingsStore.shared)
}
