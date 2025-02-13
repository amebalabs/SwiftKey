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
        let keyController = KeyPressController(menuState: state)
        let result = keyController.handleKey(key)
        switch result {
        case .escape:
            NotificationCenter.default.post(name: .hideOverlay, object: nil)
        case .help:
            withAnimation(.easeInOut(duration: 0.1)) {
                showFullOverlay = true
            }
        case .up:
            break
        case .submenuPushed:
            lastKey = ""
        case .actionExecuted:
            showFullOverlay = false
            NotificationCenter.default.post(name: .hideOverlay, object: nil)
        case let .error(errorKey):
            withAnimation(.easeInOut(duration: 0.1)) {
                lastKey = errorKey
            }
            error = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation {
                    error = false
                }
            }
        case .none:
            break
        }
    }
}
