import KeyboardShortcuts
import LaunchAtLogin
import SwiftUI

struct GeneralSettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @ObservedObject private var launchAtLogin = LaunchAtLogin.observable

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
        }
        .padding()
        .frame(width: 400)
    }
}

#Preview {
    GeneralSettingsView()
        .environmentObject(SettingsStore())
}
