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
                    Text(lastKey)
                        .font(.largeTitle)
                        .foregroundColor(error ? .red : .white)
                        .transition(.scale)
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
                // For group keys: animate key press and reveal breadcrumbs.
                withAnimation(.easeInOut(duration: 0.1)) {
                    lastKey = key
                }
                withAnimation(.easeInOut(duration: 0.1)) {
                    state.breadcrumbs.append(item.title)
                    state.menuStack.append(submenu)
                }
            } else if let action = item.actionClosure {
                // For actions: animate the key press, trigger the action, and dismiss quickly.
                withAnimation(.easeInOut(duration: 0.05)) {
                    lastKey = key
                }
                action()
                withAnimation(.easeInOut(duration: 0.05)) {
                }
                NotificationCenter.default.post(name: .hideOverlay, object: nil)
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
