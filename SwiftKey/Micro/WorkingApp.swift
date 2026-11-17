import AppKit

/// The app the person works in: the last app other than SwiftKey that became active. The HUD,
/// corner toast and menu-bar styles activate SwiftKey to take keys, so the front app alone would
/// be SwiftKey itself there.
@MainActor
final class WorkingApp {
    static let shared = WorkingApp()

    private(set) var last: NSRunningApplication?
    private var observer: NSObjectProtocol?
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    private init() {}

    /// Starts following app activations. Call once at launch.
    func start() {
        guard observer == nil else { return }
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != ownPID { last = front }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.activated(app) }
        }
    }

    private func activated(_ app: NSRunningApplication?) {
        guard let app, app.processIdentifier != ownPID else { return }
        last = app
    }

    /// The front app when it is not SwiftKey, else the last app the person worked in.
    var current: NSRunningApplication? {
        Self.choose(front: NSWorkspace.shared.frontmostApplication, last: last, ownPID: ownPID)
    }

    nonisolated static func choose(front: NSRunningApplication?, last: NSRunningApplication?, ownPID: pid_t) -> NSRunningApplication? {
        if let front, front.processIdentifier != ownPID { return front }
        guard let last, last.processIdentifier != ownPID, !last.isTerminated else { return nil }
        return last
    }
}
