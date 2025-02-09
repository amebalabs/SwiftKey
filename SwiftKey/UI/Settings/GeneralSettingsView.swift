import SwiftUI
import LaunchAtLogin
import KeyboardShortcuts

struct GeneralSettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @ObservedObject private var launchAtLogin = LaunchAtLogin.observable
    
    let width: CGFloat = 90
    
    var body: some View {
        Form {
            LaunchAtLogin.Toggle()
            Toggle("Faceless Mode", isOn: settings.$facelessMode)
            Toggle(
                "Horizontal Layout",
                isOn: settings.$useHorizontalOverlayLayout
            )
            HStack {
                Text("Menu Reset Delay")
                Slider(value: settings.$menuStateResetDelay, in: 0...10, step: 0.5)
                Text("\(settings.menuStateResetDelay, specifier: "%.1f")")
            }
            KeyboardShortcuts.Recorder("Hot key", name: .toggleApp)
            Section {
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
            }
        }
        .padding()
        .frame(width: 400)
    }
}

#Preview {
    GeneralSettingsView()
        .environmentObject(SettingsStore())
}
