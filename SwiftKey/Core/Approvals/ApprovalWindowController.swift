import AppKit
import SwiftKeyCore
import SwiftUI

/// Shows the approval window and waits for the person's answer. The menu panels never become the
/// active app's main window, so this is a standalone window that takes focus and gives it back
/// to the app that had it.
@MainActor
final class ApprovalWindowController: NSObject, ApprovalPrompt, NSWindowDelegate {
    private var window: NSWindow?
    private var continuation: CheckedContinuation<Bool, Never>?
    private var previousApp: NSRunningApplication?

    /// Makes no window; the window opens on the main actor when there is something to ask.
    nonisolated override init() {
        super.init()
    }

    @MainActor
    func ask(_ pending: [PendingCode]) async -> Bool {
        // One question at a time: a second request while the window is open is declined.
        guard window == nil else { return false }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            show(pending)
        }
    }

    @MainActor
    private func show(_ pending: [PendingCode]) {
        let front = NSWorkspace.shared.frontmostApplication
        previousApp = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front

        let view = ApprovalView(pending: pending) { [weak self] approved in
            self?.finish(approved)
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 360),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = ApprovalView.windowTitle(pending)
        window.contentView = NSHostingView(rootView: view)
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.delegate = self
        window.center()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @MainActor
    private func finish(_ approved: Bool) {
        guard let continuation else { return }
        self.continuation = nil
        let window = self.window
        self.window = nil
        window?.delegate = nil
        window?.close()
        previousApp?.activate()
        previousApp = nil
        continuation.resume(returning: approved)
    }

    /// Closing the window is the same as Cancel.
    func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            finish(false)
        }
    }
}

/// The content of the approval window: what will run, from where, and the two answers.
struct ApprovalView: View {
    let pending: [PendingCode]
    let decide: (Bool) -> Void

    static func windowTitle(_ pending: [PendingCode]) -> String {
        if pending.count == 1, case .microApp = pending[0].subject { return "Run Micro-app?" }
        return pending.count == 1 ? "Run Command?" : "Run Commands?"
    }

    private var headline: String {
        if pending.count == 1, case .microApp = pending[0].subject {
            return "This micro-app is new or changed. SwiftKey runs it with your full rights only after you approve every line."
        }
        return pending.count == 1
            ? "SwiftKey runs this command only after you approve its exact text."
            : "SwiftKey runs these \(pending.count) commands only after you approve their exact text."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(headline)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(pending) { code in
                        PendingCodeView(code: code)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text("Approval is remembered until the text changes.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                // Return cancels, so a key typed for the menu can never approve by accident.
                Button("Cancel") { decide(false) }
                    .keyboardShortcut(.defaultAction)
                Button(pending.count == 1 ? "Approve and Run" : "Approve All and Run") { decide(true) }
                    .keyboardShortcut(.return, modifiers: .command)
                    .help("⌘↩")
            }
        }
        .padding(20)
        .frame(minWidth: 460, minHeight: 260)
        .onExitCommand { decide(false) }
    }
}

private struct PendingCodeView: View {
    let code: PendingCode

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(code.path.isEmpty ? code.title : code.path + " › " + code.title)
                .font(.subheadline.weight(.semibold))
            Text(kindLabel + " from " + code.origin)
                .font(.caption)
                .foregroundStyle(.secondary)
            if case .microApp(let app) = code.subject {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 3) {
                    ForEach(app.facts, id: \.self) { fact in
                        GridRow {
                            Text(fact.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(fact.value)
                                .font(.caption)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            Text(code.text)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
        }
        .accessibilityElement(children: .combine)
    }

    private var kindLabel: String {
        switch code.subject {
        case .command(let request):
            switch request.kind {
            case .shell: return "Shell command"
            case .dynamic: return "Dynamic menu command"
            }
        case .microApp: return "Micro-app"
        }
    }
}
