import SwiftUI

/// A view that displays a favicon within a styled background
struct StyledFaviconView: View {
    let image: Image
    let size: CGFloat
    
    var body: some View {
        ZStack {
            // Background oval shape
            RoundedRectangle(cornerRadius: size / 4)
                .fill(Color(.windowBackgroundColor).opacity(0.7))
                .frame(width: size, height: size)
                .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)
            
            // Favicon image
            image
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size * 0.75, height: size * 0.75)
        }
    }
}

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
