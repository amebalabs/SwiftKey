import Foundation
import os
import SwiftKeyCore

/// A micro-app waiting for approval: its whole text and what it reads, needs and sends.
struct PendingMicroApp: Equatable {
    var id: String
    /// The combined hash of the file and the libraries it uses.
    var hash: String
    /// The micro-app's file as the person sees it, such as `~/.config/swiftkey/micro/x.yaml`.
    var file: String
    /// The command of a `command` file or the whole text of a `steps` file, then every library it uses.
    var text: String
    /// Short facts for the approval window, such as ("tools", "dig, whois").
    var facts: [Fact]

    struct Fact: Equatable, Hashable {
        var label: String
        var value: String
    }

    init(app: MicroApp, hash: String, file: String) {
        id = app.id
        self.hash = hash
        self.file = file
        text = app.approvalText
        var facts = [Fact(label: "file", value: file)]
        if !app.requiredTools.isEmpty { facts.append(Fact(label: "tools", value: app.requiredTools.joined(separator: ", "))) }
        if !app.requiredContext.isEmpty {
            facts.append(Fact(label: "reads", value: app.requiredContext.map(\.summary).joined(separator: ", ")))
        }
        if app.sendsInput { facts.append(Fact(label: "sends", value: "key presses and text to the app in front")) }
        self.facts = facts
    }
}

/// One piece of code waiting for approval, with what the approval window shows about it.
struct PendingCode: Equatable, Identifiable {
    enum Subject: Equatable {
        /// A `shell://` or `dynamic://` command.
        case command(CodeRequest)
        /// A micro-app file with its libraries.
        case microApp(PendingMicroApp)
    }

    var subject: Subject
    /// The menu item's title, or the micro-app's name.
    var title: String
    /// The menu path to the item, such as "Developer › Git".
    var path: String
    /// Where the code came from, in words.
    var origin: String

    init(request: CodeRequest, title: String, path: String, origin: String) {
        self.init(subject: .command(request), title: title, path: path, origin: origin)
    }

    init(subject: Subject, title: String, path: String, origin: String) {
        self.subject = subject
        self.title = title
        self.path = path
        self.origin = origin
    }

    /// The command of a `shell://` or `dynamic://` item; nil for a micro-app.
    var request: CodeRequest? {
        if case .command(let request) = subject { return request }
        return nil
    }

    /// The exact text the person approves.
    var text: String {
        switch subject {
        case .command(let request): request.content
        case .microApp(let app): app.text
        }
    }

    var id: String {
        switch subject {
        case .command(let request): request.kind.rawValue + ":" + request.hash
        case .microApp(let app): "micro:" + app.id + ":" + app.hash
        }
    }
}

/// Starts micro-apps. The flow asks `ApprovalGate.authorizeMicroApp` before anything runs.
@MainActor
protocol MicroAppRunning: AnyObject {
    /// Starts the micro-app `id` and returns when its flow has ended.
    func run(id: String, path: [String]) async -> MicroAppOutcome
    /// Starts the micro-app file `file` of the folder, as launcha starts a broken file, and
    /// returns when its flow has ended.
    func run(file: String) async -> MicroAppOutcome
}

/// How a micro-app start ended.
enum MicroAppOutcome: Equatable {
    /// It never ran: missing or broken, not approved, or closed before it ran.
    case notRun
    /// It ran and finished; `succeeded` is false when a step failed, timed out or was stopped.
    case ran(succeeded: Bool)

    var succeeded: Bool { self == .ran(succeeded: true) }
}

/// Asks the person to approve commands.
protocol ApprovalPrompt {
    /// True when the person approved every command in `pending`.
    @MainActor func ask(_ pending: [PendingCode]) async -> Bool
}

/// The one way SwiftKey runs code from the config. A `shell://` or `dynamic://` command runs only
/// after the person approved its exact text, and a micro-app only after the person approved its
/// file and libraries; every key press, item hotkey, batch, deep link, launcha start and dynamic
/// menu goes through here.
final class ApprovalGate: ObservableObject {
    /// Where code came from when nothing else is known: everything typed in SwiftKey's editor is
    /// approved on save, so code that still needs approval was written outside the editor.
    static let outsideOrigin = "your config file, written outside SwiftKey's editor"

    let store: ApprovalStore
    private let prompt: ApprovalPrompt
    /// Starts micro-apps; set once the micro-app flow exists.
    @MainActor weak var microApps: MicroAppRunning?
    private let logger = AppLogger.core

    init(store: ApprovalStore = ApprovalStore(), prompt: ApprovalPrompt = ApprovalWindowController()) {
        self.store = store
        self.prompt = prompt
    }

    /// The code the items run. A batch group runs its children; items made by an approved
    /// `dynamic://` script run without another approval: the script that made them could run the
    /// same code itself, so asking again would protect nothing.
    static func requests(for items: [MenuItem]) -> [(item: MenuItem, request: CodeRequest)] {
        items.flatMap { item -> [(item: MenuItem, request: CodeRequest)] in
            if item.isGenerated { return [] }
            if item.batch == true, let children = item.submenu { return requests(for: children) }
            guard let action = item.action, let request = CodeRequest(action: action) else { return [] }
            return [(item, request)]
        }
    }

    /// The commands of `items` that still need approval, each once.
    func pendingCode(for items: [MenuItem], path: [String]) -> [PendingCode] {
        let found = Self.requests(for: items)
        let pending = store.pending(found.map(\.request))
        return pending.compactMap { request in
            guard let item = found.first(where: { $0.request == request })?.item else { return nil }
            return PendingCode(request: request, title: item.title, path: path.joined(separator: " › "),
                               origin: store.origin(of: request) ?? Self.outsideOrigin)
        }
    }

    /// True when the items may run: their code was approved before, or the person approves it now.
    @MainActor
    func authorize(_ items: [MenuItem], path: [String]) async -> Bool {
        let pending = pendingCode(for: items, path: path)
        guard !pending.isEmpty else { return true }
        guard await prompt.ask(pending) else {
            logger.info("Command approval declined for \(pending.count) command(s)")
            return false
        }
        do {
            try store.approve(pending.compactMap(\.request))
        } catch {
            logger.error("Cannot save approvals to \(self.store.url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            notifyUser(title: "Approval not saved",
                       message: "SwiftKey will ask again next time: \(error.localizedDescription)")
        }
        return true
    }

    /// True when the micro-app may run: this exact file and its libraries were approved before,
    /// or the person approves them now.
    @MainActor
    func authorizeMicroApp(_ app: MicroApp, hash: String, file: String, path: [String]) async -> Bool {
        guard !store.isMicroApproved(id: app.id, hash: hash) else { return true }
        let pending = PendingCode(subject: .microApp(PendingMicroApp(app: app, hash: hash, file: file)),
                                  title: app.shownName, path: path.joined(separator: " › "),
                                  origin: "the micro-app file \(file)")
        guard await prompt.ask([pending]) else {
            logger.info("Micro-app approval declined for \(app.id, privacy: .public)")
            return false
        }
        do {
            try store.approveMicro(id: app.id, hash: hash)
        } catch {
            logger.error("Cannot save approvals to \(self.store.url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            notifyUser(title: "Approval not saved",
                       message: "SwiftKey will ask again next time: \(error.localizedDescription)")
        }
        return true
    }

    /// Runs an item's action once its code is approved. A micro-app runs through its flow, which
    /// asks for its own approval. True when the action ran: false when it was declined, a
    /// micro-app could not start, or a micro-app's run failed.
    @discardableResult
    @MainActor
    func run(_ item: MenuItem, path: [String]) async -> Bool {
        if let id = item.microAppID {
            return await runMicroApp(id: id, item: item, path: path)
        }
        guard let action = item.actionClosure, await authorize([item], path: path) else { return false }
        action()
        return true
    }

    /// Runs every action of a batch once all their commands are approved, with one approval for
    /// all of them. Micro-apps run after that, one after another, each with its own flow.
    @discardableResult
    @MainActor
    func runBatch(_ items: [MenuItem], path: [String]) async -> Bool {
        guard await authorize(items, path: path) else { return false }
        var ran = false
        for item in items {
            if let id = item.microAppID {
                if await runMicroApp(id: id, item: item, path: path) { ran = true }
            } else if let action = item.actionClosure {
                action()
                ran = true
            }
        }
        return ran
    }

    @MainActor
    private func runMicroApp(id: String, item: MenuItem, path: [String]) async -> Bool {
        guard let microApps else {
            logger.error("Micro-app \(id, privacy: .public) not started: micro-apps are not ready")
            return false
        }
        let outcome = await microApps.run(id: id, path: path)
        if item.notify == true, case .ran(let succeeded) = outcome {
            notifyUser(title: item.title, message: succeeded ? "Micro-app finished" : "Micro-app failed")
        }
        return outcome.succeeded
    }

    /// Approves commands the person typed in SwiftKey's editor, once the config was saved.
    func approveTyped(_ actions: [String]) throws {
        try store.approve(actions.compactMap(CodeRequest.init(action:)))
    }

    /// Records that the commands of `items` came with the snippet `name`. They still need approval.
    func recordSnippet(named name: String, items: [MenuItem]) throws {
        try store.recordOrigin("snippet “\(name)”", for: Self.allRequests(in: items))
    }

    /// Records that the commands of `items` came from the imported file `name`. They still need approval.
    func recordImportedFile(named name: String, items: [MenuItem]) throws {
        try store.recordOrigin("imported file “\(name)”", for: Self.allRequests(in: items))
    }

    /// Every command in `items` and their submenus.
    static func allRequests(in items: [MenuItem]) -> [CodeRequest] {
        items.flatMap { item -> [CodeRequest] in
            (item.action.flatMap(CodeRequest.init(action:)).map { [$0] } ?? []) + allRequests(in: item.submenu ?? [])
        }
    }
}
