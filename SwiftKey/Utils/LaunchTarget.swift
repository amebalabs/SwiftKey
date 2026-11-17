import AppKit

/// What a `launch://` action names: an app path (`/Applications/Safari.app`, `~/Applications/X.app`)
/// or a bundle identifier (`com.apple.Safari`).
enum LaunchTarget: Equatable {
    /// An expanded file path.
    case path(String)
    case bundleID(String)

    /// A target with a `/` or ending in `.app` is a path; anything else is a bundle identifier.
    init(_ raw: String) {
        if raw.contains("/") || raw.hasSuffix(".app") {
            self = .path((raw as NSString).expandingTildeInPath)
        } else {
            self = .bundleID(raw)
        }
    }

    /// The app bundle, or nil when the path does not exist or no app has the bundle identifier.
    func resolve(workspace: NSWorkspace = .shared) -> URL? {
        switch self {
        case .path(let path):
            return FileManager.default.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil
        case .bundleID(let bundleID):
            return workspace.urlForApplication(withBundleIdentifier: bundleID)
        }
    }

    /// Opens the app; an app that is already running comes to the front.
    @MainActor
    func open(workspace: NSWorkspace = .shared) {
        guard let url = resolve(workspace: workspace) else {
            AppLogger.app.error("Application not found: \(String(describing: self), privacy: .public)")
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        workspace.openApplication(at: url, configuration: configuration) { _, error in
            if let error {
                AppLogger.app.error("Could not open \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
