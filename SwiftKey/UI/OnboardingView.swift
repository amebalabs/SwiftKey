import SwiftUI

struct OnboardingView: View {
    let onFinish: () -> Void
    @State private var isDismissing = false
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject private var hotkeys: HotkeyCenter

    var body: some View {
        VStack(spacing: 20) {
            Image("mac_512")
                .resizable()
                .renderingMode(.original)
                .frame(width: 90, height: 90, alignment: .leading)

            Text("Welcome to SwiftKey!")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text(
                "SwiftKey is your quick access tool for launching apps, shortcuts, and more. Customize your hotkey below and start navigating efficiently!"
            )
            .multilineTextAlignment(.center)
            .padding(.horizontal)

            VStack(alignment: .leading, spacing: 6) {
                HotkeyRecorderField(hotkey: $settings.mainHotkey, gate: hotkeys.recordingGate,
                                    placeholder: "Click to record your hotkey")
                Text("Any key works: Home, F13, or a combination such as ⌥⇧⌘K. A modifier alone cannot be a hotkey.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            Button(action: {
                withAnimation {
                    isDismissing = true
                }
                settings.needsOnboarding = false
                onFinish()
            }) {
                Text("Get Started")
                    .frame(minWidth: 100)
            }
            .buttonStyle(PrimaryButtonStyle())
            .focusable(false)
        }
        .padding()
        .frame(width: 500, height: 400)
        .opacity(isDismissing ? 0 : 1)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding()
            .background(Color.accentColor.opacity(configuration.isPressed ? 0.7 : 1.0))
            .foregroundColor(.white)
            .cornerRadius(8)
    }
}

#Preview {
    OnboardingView(onFinish: {})
        .environmentObject(SettingsStore())
        .environmentObject(HotkeyCenter())
}
