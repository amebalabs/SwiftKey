import KeyboardShortcuts
import LaunchAtLogin
import SwiftUI

struct GeneralSettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @ObservedObject private var launchAtLogin = LaunchAtLogin.observable
    @StateObject private var updater = SparkleUpdater.shared
    
    let width: CGFloat = 90

    var body: some View {
        Form {
            LaunchAtLogin.Toggle()
            Picker("Overlay Style", selection: settings.$overlayStyle) {
                ForEach(SettingsStore.OverlayStyle.allCases, id: \.self) { style in
                    Text(style.rawValue).tag(style)
                }
            }

            if settings.overlayStyle == .panel {
                Toggle(
                    "Horizontal Layout",
                    isOn: settings.$useHorizontalOverlayLayout
                )
            }

            HStack {
                Text("Menu Reset Delay")
                Slider(value: settings.$menuStateResetDelay, in: 0 ... 10, step: 0.5)
                Text("\(settings.menuStateResetDelay, specifier: "%.1f")")
            }
            KeyboardShortcuts.Recorder("Hot key", name: .toggleApp)

            HStack {
                Text("Configuration folder:")
                Button("Change...") {
                    AppShared.changeConfigFolder()
                }
            }
            Text(settings.configDirectoryPath)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .textSelection(.enabled)

            Divider()
            
            Section() {
                Toggle("Automatically check for updates",
                           isOn: $settings.automaticallyCheckForUpdates)
                Toggle("Receive beta updates",
                       isOn: $settings.enableBetaUpdates)
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
        Bundle.main
            .object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? "Unknown"
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
}
