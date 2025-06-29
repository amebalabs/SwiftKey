import SwiftUI

// MARK: - Toast Menu Item View

/// A view component that renders a single menu item in the corner toast.
/// Displays the keyboard shortcut, icon, title, and submenu indicator.
struct ToastMenuItemView: View {
    let item: MenuItem
    let index: Int
    
    var body: some View {
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
}

// MARK: - Toast Header View

/// The header component of the expanded toast view.
/// Shows the navigation breadcrumbs and a close button.
struct ToastHeaderView: View {
    let breadcrumbs: [String]
    let onClose: () -> Void
    
    var body: some View {
        HStack {
            if !breadcrumbs.isEmpty {
                Text(breadcrumbs.joined(separator: " › "))
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
            }
            
            Spacer()
            
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.5))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .frame(minWidth: 250)
    }
}

// MARK: - Toast Footer View

/// The footer component of the expanded toast view.
/// Displays helpful hints about keyboard navigation.
struct ToastFooterView: View {
    var body: some View {
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
}

// MARK: - Corner Toast State

/// Observable state object for the corner toast UI.
/// Manages the expanded/collapsed state and auto-expansion timing.
@MainActor
class CornerToastState: ObservableObject {
    @Published var isExpanded: Bool = false
    private var autoExpandTask: Task<Void, Never>?
    
    func reset() {
        isExpanded = false
        cancelAutoExpand()
        // Schedule auto-expand after reset
        scheduleAutoExpand()
    }
    
    func scheduleAutoExpand(after delay: TimeInterval = 0.8) {
        // Cancel any existing task
        cancelAutoExpand()
        
        // Schedule new task
        autoExpandTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
                await MainActor.run { [weak self] in
                    self?.isExpanded = true
                }
            } catch {
                // Task was cancelled, which is fine
            }
        }
    }
    
    func cancelAutoExpand() {
        autoExpandTask?.cancel()
        autoExpandTask = nil
    }
}

/// The main view for the corner toast overlay.
/// Provides a minimal, non-intrusive interface that can be expanded to show the full menu.
/// Handles keyboard input and manages transitions between collapsed and expanded states.
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
            // Workaround for SwiftUI/AppKit integration challenges:
            // When transitioning between collapsed/expanded states, SwiftUI's dynamic layout
            // doesn't always communicate size changes to AppKit windows properly.
            // We manually set a small frame when collapsing to ensure smooth animation
            // and prevent layout glitches. The delay allows SwiftUI to complete its
            // layout pass before we reposition the window.
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
            
            Text(state.breadcrumbs.last ?? "SwiftKey")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(1)
            
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
            ToastHeaderView(
                breadcrumbs: state.breadcrumbs,
                onClose: { toastState.isExpanded = false }
            )
            
            // Menu items
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(state.visibleMenu.enumerated()), id: \.element.id) { index, item in
                        ToastMenuItemView(item: item, index: index)
                    }
                }
            }
            .frame(maxHeight: getMaxMenuHeight())
            
            // Footer
            ToastFooterView()
        }
        .frame(minWidth: 280, maxWidth: 350)
    }
    
    // MARK: - Helper Methods
    
    func updateWindowSize(_ size: CGSize) {
        windowSize = size
        if let window = NSApp.keyWindow as? CornerToastWindow {
            window.updateSizeAndPosition(for: size)
        }
    }
    
    func ensureProperPosition() {
        if let window = NSApp.keyWindow as? CornerToastWindow {
            window.ensureFitsOnScreen()
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
        // Get the window and its screen to calculate available space
        guard let window = NSApp.keyWindow as? CornerToastWindow,
              let screen = window.screen ?? NSScreen.main else { return 400 }
        
        let screenFrame = screen.visibleFrame
        let windowY = window.frame.origin.y
        let padding: CGFloat = 20
        
        // Calculate available height from window position to top of screen
        // Subtract padding and space for header/footer (approximately 100pt)
        let availableHeight = screenFrame.maxY - windowY - padding - 100
        
        // Return the smaller of available height or a reasonable maximum
        return min(max(availableHeight, 200), 600)
    }
}
