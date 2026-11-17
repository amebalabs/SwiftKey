// State and logic of the launcha panel: name search over the menu items and the app index, the
// value of a calculation, a Spotlight file search only when nothing else matches, protected-folder
// consent and launch history.
// No AppKit windows here, and nothing is opened here: choosing a row returns a `LaunchaChoice`
// that the controller carries out, so the model can be tested without a panel or side effects.
import Foundation
import Observation
import SwiftKeyCore

/// One line in the launcha list.
struct LaunchaRow: Identifiable, Equatable {
    enum Kind: Equatable {
        /// An item of the menu. `candidateID` is the launch-history identity.
        case menu(candidateID: String, path: [String], kind: LaunchaMenuCandidate.Kind, itemID: String?)
        /// An indexed app. `candidateID` is the launch-history identity.
        case app(candidateID: String)
        case file
        /// The value of the query as a calculation. Return copies it.
        case calculation(value: String)
    }

    static let calculationID = "calculation"

    var id: String
    var kind: Kind
    var name: String
    /// The retained app bundle URL, the file URL, or the config file of a menu item.
    var url: URL
    /// Secondary text: the groups above a menu item, or the folder of a file with `~` for the
    /// home folder.
    var detail: String

    var isMenu: Bool {
        if case .menu = kind { return true }
        return false
    }

    var isApp: Bool {
        if case .app = kind { return true }
        return false
    }

    var isCalculation: Bool {
        if case .calculation = kind { return true }
        return false
    }
}

/// What choosing a row asks for. The controller carries it out after the panel closed.
enum LaunchaChoice: Equatable {
    /// Run a menu item the way its keys do in the menu. `candidateID` is counted when it runs.
    case runMenu(path: [String], candidateID: String)
    /// Open the app at this retained bundle URL, or bring it to the front.
    case openApp(URL, name: String, candidateID: String)
    /// Open a file or folder with its usual app.
    case openFile(URL, name: String)
    /// Show this file in Finder. Never counts as a launch.
    case reveal(URL)
    /// Copy the value of a calculation.
    case copy(String)
}

@MainActor
@Observable
final class LaunchaModel {
    struct Services {
        var index: LaunchaAppIndex
        var spotlight: LaunchaSpotlight
    }
    typealias ServiceFactory = @MainActor (ProtectedFolderPolicy) -> Services

    enum Message: Equatable {
        case info(String)
        case problem(String)

        var text: String {
            switch self {
            case .info(let text), .problem(let text): text
            }
        }
    }

    /// The text in the search field.
    var query = "" {
        didSet { if query != oldValue { queryChanged() } }
    }
    private(set) var rows: [LaunchaRow] = []
    private(set) var selection = 0
    private(set) var spotlight = LaunchaSpotlight.State()
    private(set) var indexIssues: [LaunchaServiceIssue] = []
    private(set) var isIndexing = false
    private(set) var hasIndex = false
    private(set) var isOpen = false
    private(set) var protectedFolders: ProtectedFolderPolicy
    /// The explanation of protected-folder access is shown.
    var isExplainingConsent = false
    private(set) var consentError: String?
    private(set) var historyIssue: String?
    /// Bumped on every open.
    private(set) var generation = 0

    /// Asks the owner to hide the panel. The owner then calls `close()`.
    @ObservationIgnored var onRequestClose: (() -> Void)?
    /// A query of digits and an operator shows its value first.
    var calculator = true {
        didSet { if calculator != oldValue, isOpen { recompute(keepSelection: true) } }
    }

    @ObservationIgnored private let makeServices: ServiceFactory
    @ObservationIgnored private var services: Services
    @ObservationIgnored let historyStore: LaunchaHistoryStore
    @ObservationIgnored private let consent: LaunchaConsentStore
    @ObservationIgnored private let home: URL
    @ObservationIgnored private let refreshInterval: Duration
    @ObservationIgnored private var apps: [IndexedLaunchaApp] = []
    @ObservationIgnored private var menuItems: [LaunchaMenuCandidate] = []
    @ObservationIgnored private var configFile: URL?
    @ObservationIgnored private var history = LaunchHistory()
    @ObservationIgnored private var spotlightQuery: String?
    @ObservationIgnored private var scanSerial = 0
    @ObservationIgnored private var appliedScan = 0
    @ObservationIgnored private var historySerial = 0
    @ObservationIgnored private var appliedHistory = 0
    @ObservationIgnored private var refreshLoop: Task<Void, Never>?

    init(historyStore: LaunchaHistoryStore, consent: LaunchaConsentStore,
         home: URL = FileManager.default.homeDirectoryForCurrentUser,
         refreshInterval: Duration = .seconds(15),
         makeServices: ServiceFactory? = nil) {
        self.historyStore = historyStore
        self.consent = consent
        self.home = home
        self.refreshInterval = refreshInterval
        let factory = makeServices ?? { policy in
            Services(index: LaunchaAppIndex(home: home, protectedFolders: policy),
                     spotlight: LaunchaSpotlight(home: home, protectedFolders: policy))
        }
        self.makeServices = factory
        protectedFolders = consent.policy
        consentError = consent.error
        services = factory(consent.policy)
        wireSpotlight()
    }

    // MARK: Session

    /// Scans the apps in the background before the first open, so the list is ready.
    func prewarm() {
        startScan(onOpen: true)
        loadHistory()
    }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        generation += 1
        isExplainingConsent = false
        query = ""
        selection = 0
        recompute(keepSelection: false)
        loadHistory()
        startScan(onOpen: true)
        let interval = refreshInterval
        let token = generation
        refreshLoop?.cancel()
        refreshLoop = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: interval) } catch { return }
                guard let self, self.isOpen, self.generation == token else { return }
                self.startScan(onOpen: false)
            }
        }
    }

    /// Ends the session: stops Spotlight and the refresh loop. Late results are ignored.
    func close() {
        guard isOpen else { return }
        isOpen = false
        generation += 1
        refreshLoop?.cancel()
        refreshLoop = nil
        stopSpotlight()
        isExplainingConsent = false
        query = ""
        rows = []
        selection = 0
    }

    /// The menu items to list and the config file they come from. Redraws an open list.
    func setMenu(_ candidates: [LaunchaMenuCandidate], configFile: URL?) {
        guard candidates != menuItems || configFile != self.configFile else { return }
        menuItems = candidates
        self.configFile = configFile
        if isOpen { recompute(keepSelection: true) }
    }

    // MARK: Selection and actions

    var selectedRow: LaunchaRow? { rows.indices.contains(selection) ? rows[selection] : nil }

    func moveSelection(by delta: Int) {
        guard !rows.isEmpty else { return }
        selection = min(max(selection + delta, 0), rows.count - 1)
    }

    func select(_ id: LaunchaRow.ID) {
        if let index = rows.firstIndex(where: { $0.id == id }) { selection = index }
    }

    /// Closes the panel and says what the selected row asks for: Return opens it, ⌘Return shows
    /// it in Finder (a menu item shows its config file). A calculation is copied either way.
    func activateSelection(reveal: Bool = false) -> LaunchaChoice? {
        guard isOpen, let row = selectedRow else { return nil }
        onRequestClose?()
        close()
        if case .calculation(let value) = row.kind { return .copy(value) }
        if reveal { return .reveal(row.url) }
        switch row.kind {
        case .menu(let candidateID, let path, _, _):
            return .runMenu(path: path, candidateID: candidateID)
        case .app(let candidateID):
            return .openApp(row.url, name: row.name, candidateID: candidateID)
        case .file:
            return .openFile(row.url, name: row.name)
        case .calculation:
            return nil
        }
    }

    /// Records a launch through the menu or launcha. Failed opens and reveals are not counted.
    func record(_ outcome: LaunchOutcome, id: String) async {
        guard outcome.counts else { return }
        historySerial += 1
        let serial = historySerial
        let snapshot = await historyStore.record(outcome, id: id)
        applyHistory(snapshot, serial: serial)
    }

    // MARK: Protected folders

    /// The user read the explanation and allowed Desktop, Documents and Downloads.
    func allowProtectedFolders() {
        setProtectedFolders(.allowed)
    }

    func revokeProtectedFolders() {
        setProtectedFolders(.needsConsent)
    }

    private func setProtectedFolders(_ policy: ProtectedFolderPolicy) {
        isExplainingConsent = false
        guard consent.set(policy) else {
            consentError = consent.error
            return
        }
        consentError = nil
        guard policy != protectedFolders else { return }
        protectedFolders = policy
        stopSpotlight()
        services.spotlight.onChange = nil
        services = makeServices(policy)
        wireSpotlight()
        if policy == .needsConsent {
            // Drop apps found in folders that are no longer allowed.
            let gate = LaunchaPathPolicy(home: home, protectedFolders: .needsConsent)
            apps.removeAll { gate.needsConsent($0.url) }
        }
        // Results of the old index must not land after this.
        appliedScan = scanSerial
        if isOpen { recompute(keepSelection: true) }
        startScan(onOpen: true)
    }

    // MARK: Messages

    /// Why the list is empty, or nil when it has rows.
    var statusMessage: Message? {
        guard rows.isEmpty else { return nil }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !hasIndex { return .info("Indexing apps…") }
        guard spotlightQuery != nil else {
            return .info(trimmed.isEmpty ? "No menu items or apps found." : "Nothing matches “\(trimmed)”.")
        }
        switch spotlight.status {
        case .idle, .searching: return .info("No menu items or apps match. Searching files…")
        case .results, .empty: return .info("Nothing matches “\(trimmed)”.")
        case .error(let message): return .problem("File search failed: \(message)")
        }
    }

    /// Set when a search skipped something other than protected folders.
    var incompleteMessage: String? {
        if spotlightQuery != nil, let issue = spotlight.issues.first(where: { $0.kind != .needsConsent }) {
            return issue.kind == .limit ? "Search incomplete: \(issue.message)"
                : "Search incomplete: some files could not be checked (\(issue.message))."
        }
        if let issue = indexIssues.first(where: { $0.kind != .needsConsent }) {
            return "App list may be incomplete: \(issue.message)"
        }
        return nil
    }

    /// Protected folders were skipped for this query. Never shown as a complete search.
    var showsConsentNotice: Bool {
        protectedFolders == .needsConsent && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: Private

    private func queryChanged() {
        guard isOpen else { return }
        isExplainingConsent = false
        recompute(keepSelection: false)
    }

    private func wireSpotlight() {
        services.spotlight.onChange = { [weak self] state in
            guard let self, self.isOpen, self.spotlightQuery != nil else { return }
            self.spotlight = state
            self.recompute(keepSelection: true)
        }
    }

    private func stopSpotlight() {
        spotlightQuery = nil
        services.spotlight.cancel()
        spotlight = LaunchaSpotlight.State()
    }

    /// Rebuilds the rows for the current query. Starts Spotlight only when a non-empty query
    /// matches no menu item or app, and cancels it as soon as one matches.
    private func recompute(keepSelection: Bool) {
        guard isOpen else { return }
        let previous = keepSelection ? selectedRow?.id : nil
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let appsByID = Dictionary(apps.map { ($0.candidate.id, $0) }, uniquingKeysWith: { first, _ in first })
        let menuByID = Dictionary(menuItems.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let config = configFile ?? home
        let candidates = menuItems.map(\.candidate) + apps.map(\.candidate)
        let matches = LaunchaSearch.results(for: trimmed, in: candidates, history: history, now: Date())
        let listed = matches.compactMap { match -> LaunchaRow? in
            if let item = menuByID[match.candidate.id] {
                return LaunchaRow(id: item.id,
                                  kind: .menu(candidateID: item.id, path: item.path, kind: item.kind, itemID: item.itemID),
                                  name: match.candidate.name, url: config,
                                  detail: item.breadcrumb.joined(separator: " › "))
            }
            guard let app = appsByID[match.candidate.id] else { return nil }
            return LaunchaRow(id: match.candidate.id, kind: .app(candidateID: match.candidate.id),
                              name: match.candidate.name, url: app.url, detail: "")
        }
        // A query without letters or digits lists everything, so it never reaches Spotlight
        // unless there is nothing to list.
        let wantsFiles = !trimmed.isEmpty && hasIndex && listed.isEmpty
        if wantsFiles {
            if spotlightQuery != trimmed {
                spotlightQuery = trimmed
                spotlight = LaunchaSpotlight.State()
                services.spotlight.search(trimmed)
            }
            rows = spotlight.files.map { file in
                LaunchaRow(id: "file:" + file.url.path, kind: .file, name: file.name, url: file.url,
                           detail: displayFolder(of: file.url))
            }
        } else {
            if spotlightQuery != nil { stopSpotlight() }
            rows = listed
        }
        // A calculation comes first, above everything that matches the same text.
        if calculator, let value = Calculator.evaluate(trimmed) {
            rows.insert(LaunchaRow(id: LaunchaRow.calculationID, kind: .calculation(value: value), name: value,
                                   url: URL(fileURLWithPath: "/"), detail: "Return copies the result"), at: 0)
        }
        if let previous, let index = rows.firstIndex(where: { $0.id == previous }) {
            selection = index
        } else {
            selection = 0
        }
    }

    private func displayFolder(of url: URL) -> String {
        let folder = url.deletingLastPathComponent().path
        let base = home.standardizedFileURL.path
        let real = LaunchaPathPolicy.realURL(home)?.path ?? base
        for prefix in [real, base] where folder == prefix || folder.hasPrefix(prefix + "/") {
            return "~" + folder.dropFirst(prefix.count)
        }
        return folder
    }

    private func startScan(onOpen: Bool) {
        scanSerial += 1
        let serial = scanSerial
        let index = services.index
        isIndexing = true
        Task { [weak self] in
            let snapshot = onOpen ? await index.refreshOnOpen() : await index.refreshIfNeeded()
            self?.applyScan(snapshot, serial: serial, index: index)
        }
    }

    /// Late or replaced scans never overwrite newer data; a closed session is not redrawn.
    private func applyScan(_ snapshot: LaunchaAppIndex.Snapshot, serial: Int, index: LaunchaAppIndex) {
        if serial == scanSerial { isIndexing = false }
        guard serial > appliedScan, index === services.index else { return }
        appliedScan = serial
        apps = snapshot.apps
        indexIssues = snapshot.issues
        hasIndex = true
        recompute(keepSelection: true)
    }

    private func loadHistory() {
        historySerial += 1
        let serial = historySerial
        let store = historyStore
        Task { [weak self] in
            let snapshot = await store.load()
            self?.applyHistory(snapshot, serial: serial)
        }
    }

    private func applyHistory(_ snapshot: LaunchaHistoryStore.Snapshot, serial: Int) {
        guard serial > appliedHistory else { return }
        appliedHistory = serial
        history = snapshot.history
        historyIssue = snapshot.issues.first.map { "Launch history: \($0.message)" }
        recompute(keepSelection: true)
    }
}
