// The Accessibility window: shown when a micro-app needs Accessibility and SwiftKey does not have
// it, or from Settings. It opens Privacy & Security › Accessibility and lets the person drag
// SwiftKey into its list, then closes by itself once macOS gives SwiftKey access.
import AppKit
import ApplicationServices
import SwiftUI

/// Whether SwiftKey may use Accessibility. Read again while the window is open.
@MainActor
@Observable
final class AccessibilityAccess {
    private(set) var isTrusted: Bool
    @ObservationIgnored private let check: () -> Bool

    init(check: @escaping () -> Bool = { AXIsProcessTrusted() }) {
        self.check = check
        isTrusted = check()
    }

    /// Reads the state again. `true` when access has just turned on.
    @discardableResult
    func refresh() -> Bool {
        let was = isTrusted
        isTrusted = check()
        return !was && isTrusted
    }
}

@MainActor
final class AccessibilityWindowController: NSObject, NSWindowDelegate {
    /// Privacy & Security › Accessibility of System Settings.
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
    /// How often the open window checks for access.
    static let pollInterval: TimeInterval = 1

    let access: AccessibilityAccess
    /// Called once each time access turns on while the window is open.
    var onGranted: (() -> Void)?

    private let appURL: URL
    private let openURL: (URL) -> Void
    /// `false` builds the window but never puts it on screen, for tests.
    private let presentsWindow: Bool
    private var window: NSWindow?
    private var timer: Timer?

    init(access: AccessibilityAccess? = nil, appURL: URL = Bundle.main.bundleURL,
         openURL: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) }, presentsWindow: Bool = true) {
        self.access = access ?? AccessibilityAccess()
        self.appURL = appURL
        self.openURL = openURL
        self.presentsWindow = presentsWindow
    }

    /// The window is on screen (or would be, in tests).
    private(set) var isOpen = false

    /// Shows the window, unless SwiftKey has access already.
    func show() {
        access.refresh()
        guard !access.isTrusted else { return }
        let window = self.window ?? makeWindow()
        isOpen = true
        startPolling()
        guard presentsWindow else { return }
        NSApp.activate()
        if !window.isVisible { window.center() }
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
        if !presentsWindow { windowWillClose(Notification(name: NSWindow.willCloseNotification)) }
    }

    /// Opens System Settings and moves the window to the left of the screen, so the list of apps
    /// stays free for the drop.
    func openSettings() {
        openURL(Self.settingsURL)
        guard presentsWindow, let window, let visible = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
        window.setFrameOrigin(NSPoint(x: visible.minX + 24, y: visible.midY - window.frame.height / 2))
    }

    /// One check of the open window: on access it says so, then closes.
    func poll() {
        guard access.refresh() else { return }
        stopPolling()
        onGranted?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.close() }
    }

    func windowWillClose(_ notification: Notification) {
        isOpen = false
        stopPolling()
    }

    private func startPolling() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    private func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: AccessibilityGuideView.width, height: 400),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Allow Accessibility"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        // Above System Settings, so the icon can be dragged into its list.
        window.level = .floating
        window.hidesOnDeactivate = false
        window.delegate = self
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        let view = AccessibilityGuideView(access: access, appURL: appURL,
                                          onOpenSettings: { [weak self] in self?.openSettings() })
        let hosting = NSHostingView(rootView: view)
        window.contentView = hosting
        window.setContentSize(hosting.fittingSize)
        self.window = window
        return window
    }
}

struct AccessibilityGuideView: View {
    static let width: CGFloat = 460

    let access: AccessibilityAccess
    let appURL: URL
    let onOpenSettings: () -> Void

    var body: some View {
        let granted = access.isTrusted
        VStack(alignment: .leading, spacing: 0) {
            Text("Let SwiftKey use Accessibility")
                .font(.title2.weight(.semibold))
            Text("A micro-app reads the selected text or the front window, or presses keys and pastes. macOS allows that only for the apps in Privacy & Security › Accessibility.")
                .font(.callout).foregroundStyle(.secondary).padding(.top, 6)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 14) {
                AppIconDragSource(url: appURL)
                    .frame(width: 64, height: 64)
                    .accessibilityLabel("SwiftKey app icon. Drag it into the Accessibility list.")
                VStack(alignment: .leading, spacing: 3) {
                    Text("SwiftKey").font(.headline)
                    Text("Drag this icon into the list of apps in Accessibility.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.right").font(.title3.weight(.semibold)).foregroundStyle(.tint)
                    .accessibilityHidden(true)
            }
            .padding(14)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.tint.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .padding(.top, 18)

            VStack(alignment: .leading, spacing: 8) {
                step(1, "Click Open Accessibility Settings.")
                step(2, "Drag the SwiftKey icon into the list of apps, or click + and choose SwiftKey.")
                step(3, "Turn on the switch next to SwiftKey.")
            }
            .padding(.top, 16)

            Divider().padding(.top, 18)
            HStack(spacing: 8) {
                if granted {
                    Label("Access is on", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Label("Waiting for access", systemImage: "hourglass")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !granted {
                    Button("Open Accessibility Settings", action: onOpenSettings)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .font(.callout)
            .frame(minHeight: 30)
            .padding(.top, 12)
        }
        .padding(24)
        .padding(.top, 12)
        .frame(width: Self.width)
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "\(number).circle.fill").foregroundStyle(.secondary).accessibilityHidden(true)
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The app icon as a drag source: dropping it into the Accessibility list of System Settings
/// adds SwiftKey there, as dragging the app from Finder does.
struct AppIconDragSource: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> AppIconDragView { AppIconDragView(url: url) }

    func updateNSView(_ view: AppIconDragView, context: Context) { view.url = url }
}

final class AppIconDragView: NSView, NSDraggingSource {
    var url: URL {
        didSet { if url != oldValue { icon = Self.icon(for: url); needsDisplay = true } }
    }
    private var icon: NSImage

    init(url: URL) {
        self.url = url
        icon = Self.icon(for: url)
        super.init(frame: .zero)
        toolTip = "Drag SwiftKey into the Accessibility list"
    }

    required init?(coder: NSCoder) { nil }

    private static func icon(for url: URL) -> NSImage {
        let image = NSWorkspace.shared.icon(forFile: url.path)
        image.size = NSSize(width: 128, height: 128)
        return image
    }

    /// The window moves by its background; a drag that starts on the icon drags the app instead.
    override var mouseDownCanMoveWindow: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        icon.draw(in: bounds)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {}

    override func mouseDragged(with event: NSEvent) {
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        item.setDraggingFrame(bounds, contents: icon)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : []
    }
}
