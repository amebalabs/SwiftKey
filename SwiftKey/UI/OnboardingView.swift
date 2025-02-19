import KeyboardShortcuts
import SwiftUI

struct OnboardingView: View {
    let onFinish: () -> Void
    @State private var isDismissing = false

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

            KeyboardShortcuts.Recorder("Set your Hotkey", name: .toggleApp)
                .padding(.horizontal)

            Button(action: {
                withAnimation {
                    isDismissing = true
                }
                SettingsStore.shared.needsOnboarding = false
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
}
