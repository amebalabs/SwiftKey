import KeyboardShortcuts
import SwiftUI

struct GeneralSettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @ObservedObject private var launchAtLogin = LaunchAtLogin.observable
    @StateObject private var updater = SparkleUpdater.shared
    @ObservedObject private var configManager = ConfigManager.shared

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
            Divider()
            HStack {
                Text("Menu Reset Delay")
                Slider(value: settings.$menuStateResetDelay, in: 0 ... 10, step: 0.5)
                Text("\(settings.menuStateResetDelay, specifier: "%.1f")")
            }
            KeyboardShortcuts.Recorder("Hot key", name: .toggleApp)
            Toggle("Trigger hold mode", isOn: settings.$triggerKeyHoldMode)
            Divider()
            
            // Configuration file section - simplified
            HStack {
                Text("Menu Configuration:")
                Spacer()
                Button("Open Menu Editor") {
                    // Notify parent to switch to Menu Editor tab
                    NotificationCenter.default.post(name: .switchToMenuEditor, object: nil)
                }
            }
            
            if let error = configManager.lastError {
                Text("Configuration Error: \(error.localizedDescription)")
                    .font(.system(size: 12))
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 5)
            } else if configManager.menuItems.isEmpty {
                Text("No menu items loaded. Please check your configuration file.")
                    .font(.system(size: 12))
                    .foregroundColor(.orange)
                    .padding(.vertical, 5)
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
    GeneralSettingsView().environmentObject(SettingsStore())
}
