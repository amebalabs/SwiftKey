import AppKit
import SwiftUI

struct OverlayView: View {
    @EnvironmentObject var settings: SettingsStore
    @ObservedObject var state: MenuState
    @State private var errorMessage: String = ""

    var currentMenu: [MenuItem] {
        state.menuStack.last ?? state.rootMenu
    }

    var body: some View {
        ZStack {
            Color.white.opacity(0.95)
                .cornerRadius(10)

            VStack(spacing: 20) {
                Text(state.breadcrumbText)
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.top, 10)

                ScrollView(.vertical) {
                    if settings.useHorizontalOverlayLayout {
                        LazyHGrid(rows: [GridItem(.adaptive(minimum: 44))], spacing: 8) {
                            menuItems
                        }
                        .padding(.horizontal)
                    } else {
                        LazyVStack(spacing: 8) {
                            menuItems
                        }
                    }
                }

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .foregroundColor(.red)
                }
            }
            .background(
                KeyHandlingView { key in
                    handleKey(key: key)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.clear)
            )
        }
        .frame(
            width: settings.useHorizontalOverlayLayout ? 500 : 300,
            height: settings.useHorizontalOverlayLayout ? 100 : 300
        )
        .padding()
        .onReceive(NotificationCenter.default.publisher(for: .resetMenuState)) { _ in
            state.reset()
        }
    }

    private var menuItems: some View {
        ForEach(currentMenu) { item in
            menuItemView(for: item)
        }
    }

    private func menuItemView(for item: MenuItem) -> some View {
        HStack {
            itemIcon(for: item)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline)
                Text(item.key)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 8)
        .frame(minWidth: settings.useHorizontalOverlayLayout ? 180 : nil)
        .background(Color.clear)
    }

    private func itemIcon(for item: MenuItem) -> some View {
        Group {
            if let actionString = item.action, actionString.hasPrefix("launch://") {
                let appName = String(actionString.dropFirst("launch://".count))
                if let icon = getAppIcon(appName: appName) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: item.systemImage)
                        .resizable()
                        .frame(width: 24, height: 24)
                }
            } else {
                Image(systemName: item.systemImage)
                    .resizable()
                    .frame(width: 24, height: 20)
            }
        }
    }

    private func handleKey(key: String) {
        if key == "escape" {
            NotificationCenter.default.post(name: .resetMenuState, object: nil)
            NotificationCenter.default.post(name: .hideOverlay, object: nil)
            return
        }
        if key == "cmd+up" {
            if !state.menuStack.isEmpty { state.menuStack.removeLast() }
            if !state.breadcrumbs.isEmpty { state.breadcrumbs.removeLast() }
            return
        }
        guard let pressedKey = key.first else { return }

        if let item = currentMenu.first(where: { $0.key == String(pressedKey) }) {
            if let submenu = item.submenu {
                state.breadcrumbs.append(item.title)
                state.menuStack.append(submenu)
            } else if let action = item.actionClosure {
                action()
                NotificationCenter.default.post(name: .hideOverlay, object: nil)
            }
        } else {
            errorMessage = "No action for key \(pressedKey)"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                errorMessage = ""
            }
        }
    }
}
