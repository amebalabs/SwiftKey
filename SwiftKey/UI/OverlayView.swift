import AppKit
import SwiftUI

struct OverlayView: View {
    @EnvironmentObject var settings: SettingsStore
    @ObservedObject var state: MenuState
    @State private var errorMessage: String = ""
    
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
            VisualEffectView()
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .opacity(0.9)
            
            VStack(spacing: 20) {
                Text(state.breadcrumbText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 10)
                
                if settings.useHorizontalOverlayLayout {
                    HStack {
                        Spacer()
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHGrid(
                                rows: [GridItem(.flexible())],
                                spacing: horizontalItemSpacing
                            ) {
                                ForEach(currentMenu) { item in
                                    HorizontalMenuItemView(item: item)
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
                                menuItemView(for: item)
                            }
                        }
                        .padding(.bottom, 0)
                    }
                    .frame(width: 300, height: verticalContentHeight, alignment: .top)
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
            .padding()
        }
        // Set overall frame based on the current layout.
        .frame(
            width: settings.useHorizontalOverlayLayout ? horizontalContentWidth : 300,
            height: settings.useHorizontalOverlayLayout ? horizontalFixedHeight : verticalContentHeight
        )
        // Center the overlay in its container.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding()
        .onReceive(NotificationCenter.default.publisher(for: .resetMenuState)) { _ in
            state.reset()
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
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                }
            } else {
                Image(systemName: item.systemImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
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

struct HorizontalMenuItemView: View {
    let item: MenuItem
    
    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let actionString = item.action, actionString.hasPrefix("launch://") {
                        let appName = String(actionString.dropFirst("launch://".count))
                        if let icon = getAppIcon(appName: appName) {
                            Image(nsImage: icon)
                                .resizable()
                                .scaledToFit()
                        } else {
                            Image(systemName: item.systemImage)
                                .resizable()
                                .scaledToFit()
                        }
                    } else {
                        Image(systemName: item.systemImage)
                            .resizable()
                            .scaledToFit()
                    }
                }
                .frame(width: 60, height: 60)
                .opacity(0.7)
                
                Text(item.key)
                    .font(.caption)
                    .padding(6)
                    .background(Color.black.opacity(0.7))
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

// VisualEffectView for a semi-transparent glass effect.
struct VisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

#Preview {
    OverlayView(state: MenuState.shared).environmentObject(SettingsStore.shared)
}
