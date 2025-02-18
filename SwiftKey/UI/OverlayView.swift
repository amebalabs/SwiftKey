import AppKit
import SwiftUI

struct OverlayView: View {
    @EnvironmentObject var settings: SettingsStore
    @ObservedObject var state: MenuState
    @State private var errorMessage: String = ""
    @State private var altMode: Bool = false

    var currentMenu: [MenuItem] {
        state.menuStack.last ?? state.rootMenu
    }

    // MARK: - Screen-based size computations

    var screenSize: CGSize {
        NSScreen.main?.frame.size ?? CGSize(width: 800, height: 600)
    }

    // Vertical mode: maximum allowed height is 2/3 of screen height.
    var verticalMaxHeight: CGFloat {
        screenSize.height * 2 / 3
    }

    // Fixed height per vertical menu item.
    var verticalItemHeight: CGFloat { 50 }
    // Actual vertical height: total item height capped at verticalMaxHeight.
    var verticalContentHeight: CGFloat {
        min(CGFloat(currentMenu.count) * verticalItemHeight, verticalMaxHeight)
    }

    var verticalContentFixedWidth: CGFloat { 300 }

    // Horizontal mode: fixed height; width computed dynamically.
    var horizontalFixedHeight: CGFloat { 100 }
    var horizontalItemWidth: CGFloat { 180 }
    var horizontalItemSpacing: CGFloat { 8 }
    var horizontalMaxWidth: CGFloat {
        screenSize.width * 4 / 5
    }

    var horizontalContentWidth: CGFloat {
        let totalWidth = (CGFloat(currentMenu.count) * horizontalItemWidth) +
            (CGFloat(max(currentMenu.count - 1, 0)) * horizontalItemSpacing) +
            20
        return min(totalWidth, horizontalMaxWidth)
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.thinMaterial)
                .shadow(radius: 10)
                .clipShape(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                )
                .opacity(0.9)

            VStack(spacing: 10) {
                Spacer()
                if settings.useHorizontalOverlayLayout {
                    HStack {
                        Spacer()
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHGrid(
                                rows: [GridItem(.flexible())],
                                spacing: horizontalItemSpacing
                            ) {
                                ForEach(currentMenu) { item in
                                    HorizontalMenuItemView(item: item, altMode: $altMode)
                                }
                            }
                            .padding(.horizontal)
                        }
                        .frame(width: horizontalContentWidth, height: horizontalFixedHeight)
                        Spacer()
                    }
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 8) {
                            ForEach(currentMenu) { item in
                                VerticalMenuItemView(item: item, altMode: $altMode)
                            }
                        }
                        .padding(.bottom, 0)
                    }
                    .padding()
                    .frame(width: verticalContentFixedWidth, height: verticalContentHeight, alignment: .top)
                }
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .padding(.bottom, 8)
                } else {
                    Text(state.breadcrumbText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 8)
                }
            }
        }
        .background(
            KeyHandlingView { key, modifierFlags in
                handleKey(key: key, modifierFlags: modifierFlags)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.clear)
        )
        .detectOptionKey(isPressed: $altMode)
        // Set overall frame based on the current layout.
        .frame(
            width: settings.useHorizontalOverlayLayout ? horizontalContentWidth : verticalContentFixedWidth,
            height: settings.useHorizontalOverlayLayout ? horizontalFixedHeight : verticalContentHeight
        )
        // Center the overlay in its container.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding()
        .onReceive(NotificationCenter.default.publisher(for: .resetMenuState)) { _ in
            state.reset()
        }
    }

    private func handleKey(key: String, modifierFlags: NSEvent.ModifierFlags?) {
        let keyController = KeyPressController(menuState: state)
        keyController.handleKeyAsync(key, modifierFlags: modifierFlags) { result in
            switch result {
            case .escape:
                NotificationCenter.default.post(name: .resetMenuState, object: nil)
                NotificationCenter.default.post(name: .hideOverlay, object: nil)
            case .help:
                NotificationCenter.default.post(name: .resetMenuState, object: nil)
                NotificationCenter.default.post(name: .hideOverlay, object: nil)
            case .up:
                break
            case .submenuPushed:
                self.errorMessage = ""
            case .actionExecuted:
                NotificationCenter.default.post(name: .hideOverlay, object: nil)
            case .dynamicLoading:
                self.errorMessage = "Loading dynamic menu..."
            case let .error(errorKey):
                self.errorMessage = "No action for key \(errorKey)"
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.errorMessage = ""
                }
            case .none:
                break
            }
        }
    }
}

struct VerticalMenuItemView: View {
    let item: MenuItem
    @Binding var altMode: Bool

    var body: some View {
        HStack {
            item.iconImage

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
        .background(altMode && item.submenu != nil ? Color.red.opacity(0.7) : Color.clear)
    }
}

struct HorizontalMenuItemView: View {
    let item: MenuItem
    @Binding var altMode: Bool

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                item.iconImage
                    .resizable()
                    .scaledToFit()
                    .frame(width: 60, height: 60)
                    .opacity(0.9)

                Text(item.key)
                    .font(.caption)
                    .padding(6)
                    .background(altMode && item.submenu != nil ? Color.red.opacity(0.7) : Color.black.opacity(0.7))
                    .foregroundColor(.white)
                    .cornerRadius(4)
                    .padding(-10)
            }
            Text(item.title)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 4)
        }
        .frame(width: 180)
        .background(Color.clear)
    }
}

#Preview {
    OverlayView(state: MenuState.shared).environmentObject(SettingsStore.shared)
}
