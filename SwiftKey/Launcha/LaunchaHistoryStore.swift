import Foundation
import SwiftKeyCore

/// All disk IO and mutations run on this actor, never the main actor.
actor LaunchaHistoryStore {
    struct Snapshot: Sendable {
        var history: LaunchHistory
        var issues: [LaunchaServiceIssue]
        var preservedOriginal: URL?
    }
    let url: URL
    private var snapshot: Snapshot?
    private var mayWrite = true

    /// `launcha-history.json` in Application Support, or next to `SWIFTKEY_CONFIG`.
    init(url: URL = AppPaths.current.url(for: "launcha-history.json")) { self.url = url }

    func load() -> Snapshot {
        if let snapshot { return snapshot }
        var result = Snapshot(history: LaunchHistory(), issues: [], preservedOriginal: nil)
        do {
            let data = try Data(contentsOf: url)
            do { result.history = try LaunchHistory.decode(data) }
            catch {
                result.issues.append(.access(error, at: url))
                let backup = url.appendingPathExtension("corrupt-" + UUID().uuidString)
                do {
                    try FileManager.default.copyItem(at: url, to: backup)
                    result.preservedOriginal = backup
                } catch {
                    mayWrite = false
                    result.issues.append(.access(error, at: url))
                }
            }
        } catch {
            let ns = error as NSError
            if ns.domain != NSCocoaErrorDomain || ns.code != NSFileReadNoSuchFileError {
                result.issues.append(.access(error, at: url))
                mayWrite = false
            }
        }
        snapshot = result
        return result
    }

    /// Only successful opens/activations count. No system observation or launch wiring.
    @discardableResult
    func record(_ outcome: LaunchOutcome, id: String, at time: Date = Date()) -> Snapshot {
        var result = load()
        guard result.history.record(outcome, id: id, at: time) else { return result }
        if mayWrite {
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try result.history.encoded().write(to: url, options: .atomic)
            } catch { result.issues.append(.access(error, at: url)) }
        }
        snapshot = result
        return result
    }
}
