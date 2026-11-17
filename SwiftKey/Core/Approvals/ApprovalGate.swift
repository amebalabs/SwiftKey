import Foundation
import os
import SwiftKeyCore

/// One command waiting for approval, with what the approval window shows about it.
struct PendingCode: Equatable, Identifiable {
    var request: CodeRequest
    /// The menu item's title.
    var title: String
    /// The menu path to the item, such as "Developer › Git".
    var path: String
    /// Where the command came from, in words.
    var origin: String

    var id: String { request.kind.rawValue + ":" + request.hash }
}

/// Asks the person to approve commands.
protocol ApprovalPrompt {
    /// True when the person approved every command in `pending`.
    @MainActor func ask(_ pending: [PendingCode]) async -> Bool
}

/// The one way SwiftKey runs code from the config. A `shell://` or `dynamic://` command runs only
/// after the person approved its exact text; every key press, item hotkey, batch, deep link,
/// launcha start and dynamic menu goes through here.
final class ApprovalGate: ObservableObject {
    /// Where code came from when nothing else is known: everything typed in SwiftKey's editor is
    /// approved on save, so code that still needs approval was written outside the editor.
    static let outsideOrigin = "your config file, written outside SwiftKey's editor"

    let store: ApprovalStore
    private let prompt: ApprovalPrompt
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
            try store.approve(pending.map(\.request))
        } catch {
            logger.error("Cannot save approvals to \(self.store.url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            notifyUser(title: "Approval not saved",
                       message: "SwiftKey will ask again next time: \(error.localizedDescription)")
        }
        return true
    }

    /// Runs an item's action once its code is approved.
    @MainActor
    func run(_ item: MenuItem, path: [String]) async {
        guard let action = item.actionClosure, await authorize([item], path: path) else { return }
        action()
    }

    /// Runs every action of a batch once all their code is approved, with one approval for all.
    @MainActor
    func runBatch(_ items: [MenuItem], path: [String]) async {
        guard await authorize(items, path: path) else { return }
        for item in items {
            item.actionClosure?()
        }
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
