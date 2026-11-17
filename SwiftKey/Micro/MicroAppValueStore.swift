// The remembered values of the parameter panel: by micro-app id, the values of the last started run,
// as plain text. Kept apart from the micro-apps folder and the config file.
import Foundation
import SwiftKeyCore

@MainActor
final class MicroAppValueStore {
    let url: URL
    private(set) var remembered = MicroAppRememberedValues()

    /// `micro-values.json` in Application Support, or next to `SWIFTKEY_CONFIG` (see `AppPaths`).
    init(url: URL = AppPaths.current.url(for: "micro-values.json")) {
        self.url = url
        load()
    }

    /// Reads the file again. A missing or unreadable file gives no values.
    func load() {
        remembered = (try? Data(contentsOf: url)).map(MicroAppRememberedValues.decode) ?? MicroAppRememberedValues()
    }

    /// Saves the shown values of `app` when its run starts. `remember: false` keeps nothing (and
    /// drops what an earlier version of the file left). Throws when the file cannot be written.
    func remember(_ values: [String: String], for app: MicroApp) throws {
        let before = remembered
        remembered.remember(values, for: app)
        guard remembered != before else { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try remembered.encoded().write(to: url, options: .atomic)
    }
}
