import Foundation
import Testing
@testable import SwiftKeyCore

@Suite struct LaunchaMenuCandidateTests {
    private let tree: [Item] = [
        Item(key: "d", label: "Developer", action: .group([
            Item(key: "g", label: "Git", action: .group([
                .shell("s", "Git Status", "git status"),
                .shell("p", "Git Pull", "git pull"),
            ]), id: "git"),
            .app("x", "Xcode", "/Applications/Xcode.app"),
        ]), id: "dev"),
        Item(key: "w", label: "Workflow", action: .group([
            .app("1", "Mail", "com.apple.mail"),
            .app("2", "Calendar", "com.apple.iCal"),
        ]), flags: .init(batch: true)),
        .dynamic("p", "Processes", "~/ps.sh"),
        .url("space", "", "https://example.com"),
        .shortcut("S", "Shortcut", "Morning"),
    ]

    @Test func everyItemDepthFirstWithPathsAndBreadcrumbs() {
        let candidates = LaunchaMenuCandidate.from(tree)
        #expect(candidates.map(\.path) == [["d"], ["d", "g"], ["d", "g", "s"], ["d", "g", "p"], ["d", "x"],
                                            ["w"], ["w", "1"], ["w", "2"], ["p"], ["space"], ["S"]])
        #expect(candidates.map(\.candidate.name) == ["Developer", "Git", "Git Status", "Git Pull", "Xcode",
                                                      "Workflow", "Mail", "Calendar", "Processes", "␣", "Shortcut"])
        let status = candidates[2]
        #expect(status.breadcrumb == ["Developer", "Git"])
        #expect(status.id == "menu:d g s")
        #expect(status.candidate.target == .menu(["d", "g", "s"]))
        #expect(candidates[1].itemID == "git")
    }

    @Test func kinds() {
        let kinds = Dictionary(uniqueKeysWithValues: LaunchaMenuCandidate.from(tree).map { ($0.id, $0.kind) })
        #expect(kinds["menu:d"] == .group)
        #expect(kinds["menu:d g s"] == .action)
        #expect(kinds["menu:w"] == .batch)
        #expect(kinds["menu:w 1"] == .action)
        #expect(kinds["menu:p"] == .dynamic)
        #expect(kinds["menu:S"] == .action)
    }

    @Test func hiddenItemsAndTheirChildrenAreLeftOut() {
        let items: [Item] = [
            Item(key: "h", label: "Hidden group", action: .group([.app("a", "Inside", "com.x")]), flags: .init(hidden: true)),
            Item(key: "s", label: "Secret", action: .shell("echo"), flags: .init(hidden: true)),
            .app("v", "Visible", "com.y"),
        ]
        #expect(LaunchaMenuCandidate.from(items).map(\.id) == ["menu:v"])
    }

    @Test func idsStayTheSameAcrossReloads() {
        let first = LaunchaMenuCandidate.from(tree).map(\.id)
        var renamed = tree
        renamed[0].label = "Dev tools"
        #expect(LaunchaMenuCandidate.from(renamed).map(\.id) == first)
    }

    @Test func duplicateKeysKeepTheFirstItem() {
        let items: [Item] = [.app("a", "First", "com.x"), .app("a", "Second", "com.y")]
        #expect(LaunchaMenuCandidate.from(items).map(\.candidate.name) == ["First"])
    }

    @Test func menuCandidatesAreSearchable() {
        let candidates = LaunchaMenuCandidate.from(tree).map(\.candidate)
        let names = LaunchaSearch.results(for: "gs", in: candidates, history: LaunchHistory(), now: Date()).map(\.candidate.name)
        #expect(names.first == "Git Status")
    }
}
