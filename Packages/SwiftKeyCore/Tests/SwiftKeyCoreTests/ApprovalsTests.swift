import Foundation
import Testing
@testable import SwiftKeyCore

@Suite struct ApprovalsTests {
    private let list = CodeRequest(kind: .shell, content: "ls ~")
    private let menu = CodeRequest(kind: .dynamic, content: "~/bin/menu.sh")

    @Test func requestsFromActions() {
        #expect(CodeRequest(action: "shell://ls ~") == list)
        #expect(CodeRequest(action: "dynamic://~/bin/menu.sh") == menu)
        #expect(CodeRequest(action: "shell://") == CodeRequest(kind: .shell, content: ""))
        for action in ["launch:///Applications/Safari.app", "open://https://example.com", "shortcut://Focus",
                       "micro://format-json", "ls ~", ""] {
            #expect(CodeRequest(action: action) == nil, "\(action)")
        }
    }

    @Test func hashIsTheExactContent() {
        #expect(list.hash.count == 64)
        #expect(list.hash == CodeRequest(kind: .dynamic, content: "ls ~").hash)
        #expect(list.hash != CodeRequest(kind: .shell, content: "ls ~ ").hash)
        #expect(list.hash != CodeRequest(kind: .shell, content: "ls  ~").hash)
    }

    @Test func nothingIsApprovedByDefault() {
        let approvals = Approvals()
        #expect(!approvals.isApproved(list))
        #expect(approvals.pending([list, menu]) == [list, menu])
    }

    @Test func approvalIsPerKindAndExactText() {
        var approvals = Approvals()
        approvals.approve(list)
        #expect(approvals.isApproved(list))
        #expect(!approvals.isApproved(CodeRequest(kind: .dynamic, content: "ls ~")))
        #expect(!approvals.isApproved(CodeRequest(kind: .shell, content: "ls ~/")))
        approvals.approve(list)
        #expect(approvals.commands["shell"]?.count == 1)
    }

    @Test func pendingIsUniqueAndKeepsOrder() {
        var approvals = Approvals()
        let other = CodeRequest(kind: .shell, content: "date")
        approvals.approve(menu)
        #expect(approvals.pending([other, list, menu, other, list]) == [other, list])
        #expect(approvals.pending([]).isEmpty)
    }

    @Test func originsAreRecordedByContent() {
        var approvals = Approvals()
        approvals.recordOrigin("snippet “Dev tools”", for: list)
        #expect(approvals.origin(of: list) == "snippet “Dev tools”")
        #expect(approvals.origin(of: CodeRequest(kind: .dynamic, content: "ls ~")) == "snippet “Dev tools”")
        #expect(approvals.origin(of: menu) == nil)
        #expect(!approvals.isApproved(list), "an origin never approves")
    }

    @Test func roundTripAndStableEncoding() {
        var approvals = Approvals()
        approvals.approve(list)
        approvals.approve(menu)
        approvals.recordOrigin("snippet “X”", for: menu)
        approvals.micro.approve(id: "format-json", hash: String(repeating: "a", count: 64))
        let data = approvals.encoded()
        #expect(Approvals.decode(data) == approvals)
        #expect(Approvals.decode(data).encoded() == data)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.hasSuffix("\n"))
        #expect(text.contains("\"format-json\""))
        #expect(!text.contains("ls ~"), "only hashes are stored")
    }

    @Test(arguments: ["", "{", "[]", "not json", #"{"version": 99, "commands": {"shell": ["x"]}}"#,
                      #"{"commands": {"shell": "x"}}"#])
    func unreadableStoreApprovesNothing(_ text: String) {
        #expect(Approvals.decode(Data(text.utf8)) == Approvals())
    }

    @Test func runsCodeOnlyForCodeActions() {
        #expect(Item.Action.shell("ls").runsCode)
        #expect(Item.Action.dynamic("x").runsCode)
        #expect(Item.Action.micro("x").runsCode)
        #expect(!Item.Action.app("com.apple.Safari").runsCode)
        #expect(!Item.Action.url("https://example.com").runsCode)
        #expect(!Item.Action.shortcut("Focus").runsCode)
        #expect(!Item.Action.group([]).runsCode)
    }
}
