import KeyboardShortcuts
import SwiftUI

struct GeneralSettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @ObservedObject private var launchAtLogin = LaunchAtLogin.observable
    // Get services from AppDelegate's container
    @StateObject private var updater: SparkleUpdater
    @ObservedObject private var configManager: ConfigManager
    
    init() {
        // Get services from AppDelegate's container
        if let appDelegate = NSApp.delegate as? AppDelegate {
            // Use _updater for StateObject initialization
            _updater = StateObject(wrappedValue: appDelegate.container.sparkleUpdater)
            self.configManager = appDelegate.container.configManager
        } else {
            // Fallback to create new instances if needed
            _updater = StateObject(wrappedValue: SparkleUpdater.shared)
            self.configManager = ConfigManager.create()
        }
    }

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
            // Configuration file section.
            HStack {
                Text("Configuration file:")
                Button("Change...") {
                    configManager.changeConfigFile()
                }
            }
            HStack(spacing: 8) {
                if !settings.configFilePath.isEmpty {
                    if let url = configManager.resolveConfigFileURL() {
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
                    configManager.openConfigFile()
                }) {
                    Image(systemName: "doc.text")
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(BorderlessButtonStyle())
                .help("Reveal configuration file in Finder")
            }

            // Show configuration error if present
            if let error = configManager.lastError {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Configuration Error")
                        .font(.headline)
                        .foregroundColor(.red)

                    Text(error.localizedDescription)
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)

                    if let configError = error as? ConfigError,
                       case let .invalidYamlFormat(_, line, column) = configError,
                       line > 0
                    {
                        Text("Line \(line), Column \(column)")
                            .font(.system(size: 11))
                            .foregroundColor(.red)
                    }

                    HStack {
                        Button("Reload Configuration") {
                            Task {
                                await configManager.loadConfig()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        Button("Edit File") {
                            configManager.openConfigFile()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.top, 5)
                }
                .padding(10)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
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
