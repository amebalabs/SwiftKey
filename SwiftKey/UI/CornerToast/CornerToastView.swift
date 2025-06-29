import SwiftUI

class CornerToastState: ObservableObject {
    @Published var isExpanded: Bool = false
    @Published var autoExpandTimer: Timer?
    
    func reset() {
        isExpanded = false
        autoExpandTimer?.invalidate()
        autoExpandTimer = nil
        // Schedule auto-expand after reset
        scheduleAutoExpand()
    }
    
    func scheduleAutoExpand(after delay: TimeInterval = 0.8) {
        // Cancel any existing timer
        autoExpandTimer?.invalidate()
        
        // Schedule new timer
        autoExpandTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
            self.isExpanded = true
        }
    }
    
    func cancelAutoExpand() {
        autoExpandTimer?.invalidate()
        autoExpandTimer = nil
    }
}

struct CornerToastView: View {
    @ObservedObject var state: MenuState
    @ObservedObject var toastState: CornerToastState
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var keyboardManager: KeyboardManager
    @State private var windowSize: CGSize = .zero
    
    init(state: MenuState, toastState: CornerToastState) {
        self.state = state
        self.toastState = toastState
    }
    
    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            if toastState.isExpanded {
                expandedView
                    .transition(.identity)
            } else {
                collapsedView
                    .transition(.identity)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.85))
                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .fixedSize()
        .background(
            KeyHandlingView { key, modifiers in
                handleKeyPress(key, modifiers: modifiers)
            }
        )
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
            // Always ensure proper positioning when view appears
            DispatchQueue.main.async {
                ensureProperPosition()
            }
            // Schedule auto-expand for root state to show menu after delay
            if !toastState.isExpanded {
                toastState.scheduleAutoExpand()
            }
        }
        .onDisappear {
            // Clean up timer when view disappears
            toastState.cancelAutoExpand()
        }
        .onChange(of: toastState.isExpanded) { oldValue, newValue in
            // Force window to recalculate size when changing states
            if !newValue {
                // When collapsing, reset to small size first
                if let window = NSApp.keyWindow as? CornerToastWindow {
                    window.setFrame(NSRect(x: window.frame.origin.x, y: window.frame.origin.y, width: 150, height: 50), display: true)
                }
            }
            // Then reposition after size change
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                ensureProperPosition()
            }
        }
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        updateWindowSize(geometry.size)
                    }
                    .onChange(of: geometry.size) { oldValue, newValue in
                        updateWindowSize(newValue)
                    }
            }
        )
    }
    
    var collapsedView: some View {
        HStack(spacing: 8) {
            Image(systemName: "command.square.fill")
                .font(.system(size: 16))
                .foregroundColor(.white.opacity(0.8))
            
            if !state.breadcrumbs.isEmpty {
                Text(state.breadcrumbs.last ?? "SwiftKey")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)
            } else {
                Text("SwiftKey")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
            }
            
            Image(systemName: "chevron.left")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(minWidth: 120)
        .contentShape(Rectangle())
        .onTapGesture {
            toastState.isExpanded = true
        }
    }
    
    var expandedView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                if !state.breadcrumbs.isEmpty {
                    Text(state.breadcrumbs.joined(separator: " › "))
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                }
                
                Spacer()
                
                Button(action: {
                    toastState.isExpanded = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(PlainButtonStyle())
            }
            .frame(minWidth: 250)
            
            // Menu items
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(state.visibleMenu.enumerated()), id: \.element.id) { index, item in
                        menuItemView(for: item, index: index)
                    }
                }
            }
            .frame(maxHeight: getMaxMenuHeight())
            
            // Footer
            HStack(spacing: 4) {
                Text("Type to select")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.4))
                
                Text("•")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.3))
                
                Text("? for help")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.4))
                
                Text("•")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.3))
                
                Text("ESC to close")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(.top, 4)
        }
        .frame(minWidth: 280, maxWidth: 350, maxHeight: getMaxMenuHeight() + 100)
    }
    
    func menuItemView(for item: MenuItem, index: Int) -> some View {
        HStack(spacing: 8) {
            Text(item.key)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))
                .frame(width: 20, alignment: .center)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.1))
                )
            
            if item.icon != nil {
                // SF Symbol
                item.iconImage
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 16, height: 16)
            } else {
                // App icon or favicon
                item.iconImage
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 14, height: 14)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            
            Text(item.title)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(1)
            
            Spacer()
            
            if item.submenu != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.05))
        )
    }
    
    func updateWindowSize(_ size: CGSize) {
        windowSize = size
        if let window = NSApp.keyWindow as? CornerToastWindow {
            window.updateSizeAndPosition(for: size)
        }
    }
    
    func ensureProperPosition() {
        if let window = NSApp.keyWindow as? CornerToastWindow {
            window.positionInCorner()
        }
    }
    
    func handleKeyPress(_ key: String, modifiers: NSEvent.ModifierFlags?) {
        Task { @MainActor in
            // Check for help key first (?)
            if key == "?" {
                // Toggle expanded view when help is pressed
                toastState.isExpanded.toggle()
                // Don't show the full overlay for corner toast
                return
            }
            
            // Handle key immediately - no need to expand first
            let result = await keyboardManager.handleKey(key: key, modifierFlags: modifiers)
            
            // For successful actions that aren't navigation, we handled it cleanly without expanding
            switch result {
            case .escape:
                // Always dismiss the app completely on ESC
                NotificationCenter.default.post(name: .hideOverlay, object: nil)
                
            case .submenuPushed:
                // Don't auto-expand, just schedule it
                if !toastState.isExpanded {
                    toastState.scheduleAutoExpand()
                }
                
            case let .actionExecuted(sticky: sticky):
                if sticky {
                    // For sticky actions, keep the toast visible but don't expand
                    // User held Option to keep it open, but they want minimal UI
                    toastState.cancelAutoExpand()
                    // Don't hide the toast - stay open for more actions
                } else {
                    // For non-sticky actions, hide the toast completely
                    toastState.cancelAutoExpand()
                    NotificationCenter.default.post(name: .hideOverlay, object: nil)
                }
                
            case .up:
                // Schedule auto-expand when navigating
                if !toastState.isExpanded {
                    toastState.scheduleAutoExpand()
                }
                // Don't collapse or hide - user is still interacting
                
            case .error:
                // On error, immediately expand to show available options
                if !toastState.isExpanded {
                    toastState.isExpanded = true
                }
                toastState.cancelAutoExpand()
                
            case .dynamicLoading:
                // Schedule expansion for dynamic loading
                if !toastState.isExpanded {
                    toastState.scheduleAutoExpand()
                }
                
            case .help:
                // This shouldn't happen as we handle ? above, but just in case
                toastState.isExpanded = true
                
            case .none:
                // No action taken - likely an invalid key
                // Don't expand, just ignore
                break
                
            default:
                // For any other results, maintain current state
                break
            }
        }
    }
    
    func getMaxMenuHeight() -> CGFloat {
        // Get screen height and calculate max height for menu items
        guard let screen = NSScreen.main else { return 400 }
        let screenHeight = screen.visibleFrame.height
        // Use 70% of screen height for menu items, leaving room for header/footer
        return min(screenHeight * 0.7, 600)
    }
}
