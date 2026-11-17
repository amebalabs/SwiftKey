import Foundation

struct LaunchaFileResult: Equatable, Sendable {
    var url: URL
    var name: String
}

/// Own one instance per panel. Cancel on close or whenever app matches take priority.
@MainActor
final class LaunchaSpotlight {
    struct State: Equatable, Sendable {
        enum Status: Equatable, Sendable { case idle, searching, results, empty, error(String) }
        var status: Status = .idle
        var files: [LaunchaFileResult] = []
        /// An empty result with needsConsent is NOT a complete home search.
        var issues: [LaunchaServiceIssue] = []
    }
    typealias Provider = @Sendable (String) async throws -> [URL]
    private(set) var state = State()
    var onChange: ((State) -> Void)?
    private let policy: LaunchaPathPolicy
    private let debounce: Duration
    private let timeout: Duration
    private let cap: Int
    private let provider: Provider?
    private var generation = UUID()
    private var work: Task<Void, Never>?
    private var deadline: Task<Void, Never>?
    private var query: NSMetadataQuery?
    private var observers: [NSObjectProtocol] = []

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
         protectedFolders: ProtectedFolderPolicy = .needsConsent,
         debounce: Duration = .milliseconds(200), timeout: Duration = .seconds(10),
         cap: Int = 50, provider: Provider? = nil) {
        policy = LaunchaPathPolicy(home: home, protectedFolders: protectedFolders)
        self.debounce = debounce
        self.timeout = timeout
        self.cap = max(1, cap)
        self.provider = provider
    }

    func cancel() {
        generation = UUID()
        stop()
        publish(State())
    }

    func search(_ text: String) {
        cancel()
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let token = generation
        let issues = policy.protectedFolders == .needsConsent ? policy.protectedURLs.map {
            LaunchaServiceIssue(kind: .needsConsent, url: $0, message: "Protected-folder search needs a user action.")
        } : []
        publish(State(status: .searching, issues: issues))
        work = Task { [weak self, debounce] in
            do { try await Task.sleep(for: debounce) } catch { return }
            guard let self, self.generation == token, !Task.isCancelled else { return }
            self.deadline = Task { [weak self, timeout] in
                do { try await Task.sleep(for: timeout) } catch { return }
                guard let self, self.generation == token else { return }
                self.fail("Spotlight search timed out.", token: token)
            }
            if let provider = self.provider {
                do {
                    let urls = try await provider(text)
                    guard !Task.isCancelled, self.generation == token else { return }
                    await self.complete(urls, token: token)
                } catch {
                    guard !Task.isCancelled else { return }
                    self.fail(error.localizedDescription, token: token, issue: .access(error, at: self.policy.home))
                }
            } else { self.startQuery(text, token: token) }
        }
    }

    private func startQuery(_ text: String, token: UUID) {
        let query = NSMetadataQuery()
        // Wildcards in the user's input are literal, not Spotlight pattern operators.
        query.predicate = NSPredicate(format: "%K CONTAINS[cd] %@", NSMetadataItemFSNameKey, text)
        query.searchScopes = [policy.home.path]
        query.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSNameKey, ascending: true)]
        self.query = query
        observers.append(NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering,
                                                                object: query, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token, let query = self.query else { return }
                query.disableUpdates()
                // Bound inspection too, not just the number displayed.
                if query.resultCount > 2000 {
                    self.state.issues.append(.init(kind: .limit, url: self.policy.home, message: "Spotlight inspection limit reached."))
                }
                let urls = (0..<min(query.resultCount, 2000)).compactMap { index -> URL? in
                    guard let item = query.result(at: index) as? NSMetadataItem,
                          let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { return nil }
                    return URL(fileURLWithPath: path)
                }
                self.stopQuery()
                self.work = Task { [weak self] in await self?.complete(urls, token: token) }
            }
        })
        if !query.start() { fail("Spotlight could not start the home search.", token: token) }
    }

    private func complete(_ urls: [URL], token: UUID) async {
        let policy = policy
        let cap = cap
        let filtered = Task.detached(priority: .userInitiated) { () -> ([LaunchaFileResult], [LaunchaServiceIssue]) in
            var files: [LaunchaFileResult] = []
            var issues: [LaunchaServiceIssue] = urls.count > 2000
                ? [.init(kind: .limit, url: policy.home, message: "Spotlight inspection limit reached.")]
                : []
            var seen: Set<String> = []
            for url in urls.prefix(2000) {
                guard !Task.isCancelled else { break }
                guard policy.lexicalSearchable(url) else { continue }
                guard let real = LaunchaPathPolicy.realURL(url) else {
                    issues.append(.access(NSError(domain: NSPOSIXErrorDomain, code: Int(errno)), at: url))
                    continue
                }
                guard policy.searchable(url) else { continue }
                guard seen.insert(real.path).inserted else { continue }
                do {
                    var excluded = false
                    // Finder-hidden directories and extensionless application packages also count.
                    for start in [url.standardizedFileURL, real] {
                        var ancestor = start
                        let root = start == real ? (LaunchaPathPolicy.realURL(policy.home) ?? policy.home) : policy.home.standardizedFileURL
                        while ancestor.path != root.path && ancestor.path != "/" {
                            if Task.isCancelled { return (files, issues) }
                            let values = try ancestor.resourceValues(forKeys: [.isHiddenKey, .isApplicationKey])
                            if values.isHidden == true || values.isApplication == true { excluded = true; break }
                            ancestor.deleteLastPathComponent()
                        }
                        if excluded { break }
                    }
                    guard !excluded else { continue }
                    let values = try real.resourceValues(forKeys: [.localizedNameKey])
                    files.append(.init(url: real, name: values.localizedName ?? real.lastPathComponent))
                    if files.count == cap { break }
                } catch { issues.append(.access(error, at: real)) }
            }
            return (files, issues)
        }
        let (files, issues) = await withTaskCancellationHandler {
            await filtered.value
        } onCancel: { filtered.cancel() }
        guard generation == token, !Task.isCancelled else { return }
        let previousIssues = state.issues
        stop()
        publish(State(status: files.isEmpty ? .empty : .results, files: files, issues: previousIssues + issues))
    }

    private func fail(_ message: String, token: UUID, issue: LaunchaServiceIssue? = nil) {
        guard generation == token else { return }
        let issues = state.issues + (issue.map { [$0] } ?? [])
        // Invalidate even a provider that ignores cancellation and returns later.
        generation = UUID()
        stop()
        publish(State(status: .error(message), issues: issues))
    }
    private func stopQuery() {
        query?.stop()
        query = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
    }
    private func stop() {
        work?.cancel(); work = nil
        deadline?.cancel(); deadline = nil
        stopQuery()
    }
    private func publish(_ state: State) { self.state = state; onChange?(state) }
    deinit {
        work?.cancel()
        deadline?.cancel()
        query?.stop()
        observers.forEach(NotificationCenter.default.removeObserver)
    }
}
