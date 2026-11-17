import AppKit
import SwiftKeyCore

struct IndexedLaunchaApp: Sendable {
    var candidate: LaunchaCandidate
    /// Always launch this URL, not a new bundle-ID lookup.
    var url: URL
}

/// App scans run on this actor. Call refreshOnOpen for every panel opening.
/// While open, call refreshIfNeeded periodically; it scans at most once per minute.
actor LaunchaAppIndex {
    struct Snapshot: Sendable {
        var apps: [IndexedLaunchaApp]
        var issues: [LaunchaServiceIssue]
    }
    private let roots: [URL]
    private let policy: LaunchaPathPolicy
    private var cached = Snapshot(apps: [], issues: [])
    private var lastRefresh: Date?

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
         protectedFolders: ProtectedFolderPolicy = .needsConsent, roots: [URL]? = nil) {
        self.roots = roots ?? [URL(fileURLWithPath: "/Applications"), URL(fileURLWithPath: "/System/Applications"),
                              home.appendingPathComponent("Applications"), home.appendingPathComponent("Desktop")]
        policy = LaunchaPathPolicy(home: home, protectedFolders: protectedFolders)
    }

    func refreshIfNeeded(now: Date = Date()) -> Snapshot {
        if let lastRefresh, now.timeIntervalSince(lastRefresh) < 60 { return cached }
        return refreshOnOpen()
    }

    func refreshOnOpen() -> Snapshot {
        let fm = FileManager.default
        var result = Snapshot(apps: [], issues: [])
        var visited: Set<String> = []
        var ids: Set<String> = []
        // Keep directory iterators, not recursive calls or complete child lists.
        enum Work {
            case visit(URL, isRoot: Bool)
            case children(FileManager.DirectoryEnumerator)
        }
        var work = roots.reversed().map { Work.visit($0, isRoot: true) }
        while !Task.isCancelled, let next = work.popLast() {
            let lexical: URL
            let isRoot: Bool
            switch next {
            case .visit(let url, let root):
                lexical = url
                isRoot = root
            case .children(let children):
                guard let child = children.nextObject() as? URL else { continue }
                work.append(.children(children))
                work.append(.visit(child, isRoot: false))
                continue
            }
            if policy.needsConsent(lexical) {
                result.issues.append(.init(kind: .needsConsent, url: lexical, message: "Folder access needs a user action."))
                continue
            }
            let url = LaunchaPathPolicy.realURL(lexical) ?? lexical.standardizedFileURL
            if policy.needsConsent(url) {
                result.issues.append(.init(kind: .needsConsent, url: url, message: "Folder access needs a user action."))
                continue
            }
            guard visited.insert(url.path).inserted else { continue }
            do {
                let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .localizedNameKey, .isHiddenKey])
                guard values.isDirectory == true, values.isHidden != true else { continue }
                if url.pathExtension.lowercased() == "app" {
                    let bundle = Bundle(url: url)
                    let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                        ?? values.localizedName.map { ($0 as NSString).deletingPathExtension }
                        ?? url.deletingPathExtension().lastPathComponent
                    let candidate: LaunchaCandidate
                    if let id = bundle?.bundleIdentifier, !id.isEmpty { candidate = .app(bundleID: id, name: name) }
                    else { candidate = LaunchaCandidate(id: "app-path:" + url.path, name: name, target: .url(url.absoluteString)) }
                    if ids.insert(candidate.id).inserted { result.apps.append(.init(candidate: candidate, url: url)) }
                    continue
                }
                guard values.isPackage != true, !Task.isCancelled else { continue }
                if let children = fm.enumerator(at: url, includingPropertiesForKeys: nil,
                                                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants],
                                                errorHandler: { failedURL, error in
                                                    result.issues.append(.access(error, at: failedURL))
                                                    return !Task.isCancelled
                                                }) {
                    work.append(.children(children))
                }
            } catch {
                // Optional roots may not exist yet. Other failures must reach the caller.
                let ns = error as NSError
                if !(isRoot && ns.domain == NSCocoaErrorDomain && ns.code == NSFileReadNoSuchFileError) {
                    result.issues.append(.access(error, at: url))
                }
            }
        }
        if !Task.isCancelled { cached = result; lastRefresh = Date() }
        return result
    }

    func search(_ query: String, history: LaunchHistory, now: Date = Date()) -> [LaunchaMatch] {
        LaunchaSearch.results(for: query, in: cached.apps.map(\.candidate), history: history, now: now)
    }
}

/// NSCache bounds icon memory. Loading runs on a private queue, not on the UI thread.
final class LaunchaIconCache: @unchecked Sendable {
    private let cache = NSCache<NSURL, NSImage>()
    private let queue = DispatchQueue(label: "com.ameba.SwiftKey.launcha-icons", qos: .userInitiated)
    init() { cache.countLimit = 256 }
    func icon(for url: URL) async -> NSImage {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                if let image = cache.object(forKey: url as NSURL) { continuation.resume(returning: image); return }
                let image = NSWorkspace.shared.icon(forFile: url.path)
                cache.setObject(image, forKey: url as NSURL)
                continuation.resume(returning: image)
            }
        }
    }
    func invalidate() { cache.removeAllObjects() }
}
