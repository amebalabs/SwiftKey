import SwiftUI

struct MinimalHUDView: View {
    @ObservedObject var state: MenuState
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var keyboardManager: KeyboardManager
    @State private var lastKey: String = ""
    @State private var error: Bool = false

    init(state: MenuState) {
        self.state = state
    }

    var body: some View {
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
        .background(
            KeyHandlingView { key, _ in
                handleKeyPress(key)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.clear)
        )
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func handleKeyPress(_ key: String) {
        Task {
            await processKeyPress(key)
        }
    }

    func processKeyPress(_ key: String) async {
        let result = await keyboardManager.handleKey(key: key)

        switch result {
        case .escape:
            NotificationCenter.default.post(name: .hideOverlay, object: nil)
        case .help:
            NotificationCenter.default.post(name: .presentOverlay, object: nil)
        case .up:
            break
        case .submenuPushed:
            lastKey = ""
        case let .actionExecuted(sticky: sticky):
            guard sticky == false else { break }
            NotificationCenter.default.post(name: .hideOverlay, object: nil)
        case .dynamicLoading:
            lastKey = "Loading..."
        case let .error(errorKey):
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.1)) { lastKey = errorKey }
                error = true
            }

            await MainActor.run {
                withAnimation { error = false }
            }
        case .none:
            break
        }
    }
}
