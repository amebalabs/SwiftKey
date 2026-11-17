import Foundation

/// A UI must explain possible macOS prompts before supplying `.allowed`.
enum ProtectedFolderPolicy: Sendable { case needsConsent, allowed }

struct LaunchaServiceIssue: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case needsConsent, denied, io, limit }
    var kind: Kind
    var url: URL
    var message: String

    static func access(_ error: Error, at url: URL) -> Self {
        let ns = error as NSError
        let denied = (ns.domain == NSCocoaErrorDomain && [NSFileReadNoPermissionError, NSFileWriteNoPermissionError].contains(ns.code))
            || (ns.domain == NSPOSIXErrorDomain && [Int(EACCES), Int(EPERM)].contains(ns.code))
        return Self(kind: denied ? .denied : .io, url: url, message: error.localizedDescription)
    }
}

struct LaunchaPathPolicy: Sendable {
    var home: URL
    var protectedFolders: ProtectedFolderPolicy = .needsConsent

    var protectedURLs: [URL] { ["Desktop", "Documents", "Downloads"].map { home.appendingPathComponent($0) } }
    func contains(_ url: URL, in root: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let base = root.standardizedFileURL.path
        return path == base || path.hasPrefix(base + "/")
    }
    private func firstHomeComponent(_ url: URL, home: URL) -> String? {
        guard contains(url, in: home) else { return nil }
        return url.standardizedFileURL.pathComponents.dropFirst(home.standardizedFileURL.pathComponents.count).first?.lowercased()
    }
    func needsConsent(_ url: URL) -> Bool {
        guard protectedFolders == .needsConsent else { return false }
        return [home, Self.realURL(home) ?? home].contains {
            ["desktop", "documents", "downloads"].contains(firstHomeComponent(url, home: $0) ?? "")
        }
    }
    /// Foundation may leave intermediate symlinks unresolved when a leaf is missing.
    /// realpath fails closed instead. Never use this before the lexical policy check.
    static func realURL(_ url: URL) -> URL? {
        guard let path = realpath(url.path, nil) else { return nil }
        defer { free(path) }
        return URL(fileURLWithPath: String(cString: path))
    }
    private func valid(_ path: URL, home: URL) -> Bool {
        contains(path, in: home) && firstHomeComponent(path, home: home) != "library"
            && !path.pathComponents.contains { $0.hasPrefix(".") || $0.lowercased().hasSuffix(".app") }
            && !needsConsent(path)
    }
    func lexicalSearchable(_ url: URL) -> Bool {
        guard !url.pathComponents.contains(where: { $0.hasPrefix(".") || $0.lowercased().hasSuffix(".app") }) else { return false }
        return valid(url.standardizedFileURL, home: home.standardizedFileURL)
    }
    /// Check lexical paths before touching the filesystem, then check resolved paths too.
    func searchable(_ url: URL) -> Bool {
        guard lexicalSearchable(url) else { return false }
        guard let resolved = Self.realURL(url), let realHome = Self.realURL(home) else { return false }
        return valid(resolved, home: realHome)
    }
}
