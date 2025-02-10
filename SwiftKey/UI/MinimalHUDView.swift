import SwiftUI

struct MinimalHUDView: View {
    @ObservedObject var state: MenuState
    @EnvironmentObject var settings: SettingsStore

    @State private var lastKey: String = ""
    @State private var error: Bool = false
    @State private var showFullOverlay: Bool = false

    var body: some View {
        VStack {
            if showFullOverlay {
                OverlayView(state: state)
                    .environmentObject(settings)
                    .transition(.opacity)
            } else {
                VStack(spacing: 8) {
                    if !state.breadcrumbs.isEmpty {
                        Text(state.breadcrumbs.joined(separator: " > "))
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    HStack(spacing: 4) {
                        Spacer()
                        Text(lastKey)
                            .font(.largeTitle)
                            .foregroundColor(error ? .red : .white)
                            .transition(.scale)
                        Spacer()
                        BlinkingIndicator()
                    }
                }
                .padding(8)
                .background(Color.black.opacity(0.7))
                .cornerRadius(8)
                .shadow(radius: 4)
                .frame(width: 200)
            }
        }
        .background(
            KeyHandlingView { key in
                handleKeyPress(key)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.clear)
        )
    }

    func handleKeyPress(_ key: String) {
        // Dismiss on escape.
        if key == "escape" {
            NotificationCenter.default.post(name: .hideOverlay, object: nil)
            return
        }
        // On "?" show the full overlay.
        if key == "?" {
            withAnimation(.easeInOut(duration: 0.1)) {
                showFullOverlay = true
            }
            return
        }
        guard let pressedChar = key.first else { return }
        // Look up the pressed key in the current menu.
        if let item = state.currentMenu.first(where: { $0.key.caseInsensitiveCompare(String(pressedChar)) == .orderedSame }) {
            if let submenu = item.submenu {
                lastKey = key
                withAnimation(.easeInOut(duration: 0.2)) {
                    state.breadcrumbs.append(item.title)
                    state.menuStack.append(submenu)
                    lastKey = ""
                }
            } else if let action = item.actionClosure {
                lastKey = key
                showFullOverlay = false
                NotificationCenter.default.post(name: .hideOverlay, object: nil)
                action()
            }
        } else {
            // Key not registered: indicate error.
            withAnimation(.easeInOut(duration: 0.1)) {
                lastKey = key
            }
            error = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation {
                    error = false
                }
            }
        }
    }
}
