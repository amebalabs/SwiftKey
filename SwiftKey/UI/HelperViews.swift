import SwiftUI

struct ToggleView: View {
    let label: String
    let secondLabel: String
    @Binding var state: Bool
    let width: CGFloat

    var mainLabel: String {
        guard !label.isEmpty else { return "" }
        return "\(label):"
    }

    var body: some View {
        HStack {
            HStack {
                Spacer()
                Text(mainLabel)
            }.frame(width: width)
            Toggle("", isOn: $state)
            Text(secondLabel)
            Spacer()
        }
    }
}

struct BlinkingIndicator: View {
    @State private var opacity: Double = 1.0

    var body: some View {
        Circle()
            .frame(width: 8, height: 8)
            .foregroundColor(.white)
            .opacity(opacity)
            .onAppear {
                withAnimation(Animation.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    opacity = 0
                }
            }
    }
}

struct OptionKeyModifier: ViewModifier {
    @Binding var isOptionKeyPressed: Bool

    func body(content: Content) -> some View {
        content
            .onAppear {
                NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { event in
                    isOptionKeyPressed = event.modifierFlags.contains(.option)
                    return event
                }
            }
            .onDisappear {
                NSEvent.removeMonitor(self)
            }
    }
}

extension View {
    func detectOptionKey(isPressed: Binding<Bool>) -> some View {
        modifier(OptionKeyModifier(isOptionKeyPressed: isPressed))
    }
}
