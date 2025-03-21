import AppKit
import SwiftUI

struct OverlayView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var keyboardManager: KeyboardManager
    @ObservedObject var state: MenuState
    @State private var errorMessage: String = ""
    @State private var altMode: Bool = false

    init(state: MenuState) {
        self.state = state
    }

    var currentMenu: [MenuItem] {
        state.visibleMenu
    }

    // MARK: - Screen-based size computations

    // Fixed constants for menu dimensions
    let verticalItemHeight: CGFloat = 64
    let verticalContentFixedWidth: CGFloat = 340
    let horizontalFixedHeight: CGFloat = 100
    let horizontalItemWidth: CGFloat = 180
    let horizontalItemSpacing: CGFloat = 8

    var screenSize: CGSize {
        NSScreen.main?.frame.size ?? CGSize(width: 800, height: 600)
    }

    var verticalMaxHeight: CGFloat {
        screenSize.height * 2 / 3
    }

    var verticalContentHeight: CGFloat {
        min(CGFloat(currentMenu.count) * verticalItemHeight, verticalMaxHeight)
    }

    // Calculate the appropriate height for vertical menus to avoid corner clipping
    func calculateVerticalHeight() -> CGFloat {
        if currentMenu.count > 5 {
            // For larger menus, reduce height to avoid corner clipping
            return verticalContentHeight - 20
        } else {
            // For smaller menus, calculate exact height needed
            let contentHeight = CGFloat(currentMenu.count) * verticalItemHeight + 20
            return contentHeight
        }
    }

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
            // Main background with rounded corners
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
                    // Create container for vertical content with insets to prevent clipping at corners
                    VStack {
                        // Use a smaller size for the scrollable area to avoid hitting the corners
                        ScrollView(.vertical, showsIndicators: false) {
                            LazyVStack(spacing: 8) {
                                ForEach(currentMenu) { item in
                                    VerticalMenuItemView(item: item, altMode: $altMode)
                                }
                            }
                            .padding(.vertical, 12)
                        }
                        // Make scrollable content slightly smaller to avoid corners
                        .padding(.top, currentMenu.count > 5 ? 8 : 0)
                        .padding(.bottom, currentMenu.count > 5 ? 8 : 0)
                    }
                    .padding(.horizontal, 16)
                    // Calculate the appropriate height based on menu size
                    .frame(
                        width: verticalContentFixedWidth,
                        height: calculateVerticalHeight(),
                        alignment: .top
                    )
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
        .onReceive(NotificationCenter.default.publisher(for: .hideOverlay)) { _ in
            altMode = false
        }
    }

    private func handleKey(key: String, modifierFlags: NSEvent.ModifierFlags?) {
        if key == "alt" {
            altMode = true
            return
        }
        if key == "alt+release" {
            altMode = false
            return
        }

        Task {
            await handleKey(key: key, modifierFlags: modifierFlags)
        }
    }

    private func handleKey(key: String, modifierFlags: NSEvent.ModifierFlags?) async {
        let result = await keyboardManager.handleKey(key: key, modifierFlags: modifierFlags)

        switch result {
        case .escape:
            await MainActor.run {
                NotificationCenter.default.post(name: .resetMenuState, object: nil)
                NotificationCenter.default.post(name: .hideOverlay, object: nil)
            }
        case .help:
            await MainActor.run {
                NotificationCenter.default.post(name: .resetMenuState, object: nil)
                NotificationCenter.default.post(name: .hideOverlay, object: nil)
            }
        case .up:
            break
        case .submenuPushed:
            errorMessage = ""
        case let .actionExecuted(sticky: sticky):
            guard sticky == false else { break }
            await MainActor.run {
                NotificationCenter.default.post(name: .hideOverlay, object: nil)
            }
        case .dynamicLoading:
            errorMessage = "Loading dynamic menu..."
        case let .error(errorKey):
            errorMessage = "No action for key \(errorKey)"

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1000000000) // 1 second
                errorMessage = ""
            }
        case .none:
            break
        }
    }
}

struct MenuItemIconView: View {
    let item: MenuItem
    let size: CGFloat
    @State private var refreshToggle = false

    var body: some View {
        Group {
            if item.isExternalURL && !item.isDefaultIcon {
                StyledFaviconView(image: item.iconImage, size: size)
            } else {
                item.iconImage
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .opacity(0.9)
            }
        }
        .id("\(item.id)_\(refreshToggle)")
        .onReceive(NotificationCenter.default.publisher(for: .menuIconUpdated)) { notification in
            if let id = notification.userInfo?["id"] as? UUID, id == item.id {
                refreshToggle.toggle()
            }
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs.item.id == rhs.item.id && lhs.size == rhs.size
    }
}

// Make MenuItemIconView conform to Equatable
extension MenuItemIconView: Equatable {}

struct VerticalMenuItemView: View {
    let item: MenuItem
    @Binding var altMode: Bool

    // Use id for stable identity
    private let id: UUID

    init(item: MenuItem, altMode: Binding<Bool>) {
        self.item = item
        self._altMode = altMode
        self.id = item.id
    }

    var body: some View {
        HStack(spacing: 16) {
            // Use dedicated component for icon
            MenuItemIconView(item: item, size: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)

                Text(item.key)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if item.submenu != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(altMode && item.submenu != nil ?
                    Color.red.opacity(0.2) :
                    Color.primary.opacity(0.05))
        )
        .contentShape(Rectangle())
        .id(id)
    }
}

struct HorizontalMenuItemView: View {
    let item: MenuItem
    @Binding var altMode: Bool

    private let id: UUID

    init(item: MenuItem, altMode: Binding<Bool>) {
        self.item = item
        self._altMode = altMode
        self.id = item.id
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                MenuItemIconView(item: item, size: 60)

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
                .lineLimit(1)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 4)
        }
        .frame(width: 180)
        .background(Color.clear)
        .id(id)
    }
}

#Preview {
    let settingsStore = SettingsStore()
    let menuState = MenuState()

    return OverlayView(state: menuState).environmentObject(settingsStore)
}
