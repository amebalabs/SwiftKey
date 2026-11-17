import Foundation
import os
import SwiftKeyCore

/// The approved commands on disk: `approvals.json` in Application Support (or next to
/// `SWIFTKEY_CONFIG`). Kept apart from the config file, so a copied config, a snippet or an
/// outside edit never approves anything.
@MainActor
final class ApprovalStore {
    let url: URL
    private(set) var approvals = Approvals()
    private let logger = AppLogger.core

    /// Only stores its values, so any code can make a store; everything after runs on the main actor.
    nonisolated init(url: URL = AppPaths.current.url(for: "approvals.json")) {
        self.url = url
        self.approvals = Self.read(url)
    }

    /// Reads the file again. A missing or unreadable file approves nothing.
    func load() {
        approvals = Self.read(url)
    }

    private nonisolated static func read(_ url: URL) -> Approvals {
        (try? Data(contentsOf: url)).map(Approvals.decode) ?? Approvals()
    }

    func pending(_ requests: [CodeRequest]) -> [CodeRequest] {
        approvals.pending(requests)
    }

    func origin(of request: CodeRequest) -> String? {
        approvals.origin(of: request)
    }

    /// Approves the requests and saves. Throws when the file cannot be written; the approval then
    /// holds for this run only.
    func approve(_ requests: [CodeRequest]) throws {
        guard !requests.isEmpty else { return }
        requests.forEach { approvals.approve($0) }
        try save()
    }

    /// True when the micro-app `id` was approved with exactly this content hash.
    func isMicroApproved(id: String, hash: String) -> Bool {
        approvals.micro.isApproved(id: id, hash: hash)
    }

    /// Approves the micro-app `id` with this content hash and saves. Throws when the file cannot
    /// be written; the approval then holds for this run only.
    func approveMicro(id: String, hash: String) throws {
        approvals.micro.approve(id: id, hash: hash)
        try save()
    }

    /// Records where code came from, such as an imported snippet, and saves.
    func recordOrigin(_ origin: String, for requests: [CodeRequest]) throws {
        guard !requests.isEmpty else { return }
        requests.forEach { approvals.recordOrigin(origin, for: $0) }
        try save()
    }

    private func save() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try approvals.encoded().write(to: url, options: .atomic)
        logger.debug("Saved approvals to \(self.url.path, privacy: .public)")
    }
}
