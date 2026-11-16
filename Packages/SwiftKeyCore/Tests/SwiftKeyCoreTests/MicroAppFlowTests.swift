import Foundation
import Testing
@testable import SwiftKeyCore

private func file(_ name: String? = nil, command: String = "echo hi", to: String = "[panel]") -> String {
    (name.map { "name: \($0)\n" } ?? "") + """
    format: ting.microapp/2
    description: Say hi.
    input: none
    command: \(command)
    output:
      to: \(to)
    """
}

private func app(to targets: [MicroApp.OutputTarget], style: MicroApp.OutputStyle = .markdown) -> MicroApp {
    MicroApp(id: "say-hi", name: "Say hi", description: "Say hi.", input: .none, command: "echo hi",
             output: .init(targets: targets, style: style))
}

@Suite struct MicroAppBindingTests {
    @Test func launchaSkipsMicroBindings() {
        #expect(LaunchaCandidate.from([.micro("j", "JSON", "format-json"), .url("g", "GitHub", "https://github.com")]).map(\.id)
                == ["url:https://github.com"])
    }

    @Test func leaderRunsAMicroBinding() {
        var machine = LeaderMachine(items: [.micro("j", "JSON", "format-json")])
        _ = machine.handle(.leader)
        #expect(machine.handle(.key("j")) == .run(.micro("j", "JSON", "format-json")))
        #expect(!machine.isOpen)
    }
}

@Suite struct MicroAppApprovalTests {
    @Test func hashIsSHA256OfTheContent() {
        #expect(MicroAppApprovals.hash(Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(MicroAppApprovals.hash(Data()) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    @Test func approvalIsByIdAndExactContent() {
        let text = file()
        let hash = MicroAppApprovals.hash(Data(text.utf8))
        var approvals = MicroAppApprovals()
        #expect(!approvals.isApproved(id: "say-hi", hash: hash))
        approvals.approve(id: "say-hi", hash: hash)
        #expect(approvals.isApproved(id: "say-hi", hash: hash))
        // Another id with the same content is not approved.
        #expect(!approvals.isApproved(id: "other", hash: hash))
        // Any edit, even a comment, asks again.
        #expect(!approvals.isApproved(id: "say-hi", hash: MicroAppApprovals.hash(Data((text + "\n# note").utf8))))
        // An empty hash is never approved and never stored.
        approvals.approve(id: "empty", hash: "")
        #expect(!approvals.isApproved(id: "empty", hash: ""))
        #expect(approvals.approvals["empty"] == nil)
    }

    @Test func codecRoundTripAndBadFiles() {
        var approvals = MicroAppApprovals()
        approvals.approve(id: "b", hash: String(repeating: "1", count: 64))
        approvals.approve(id: "a", hash: String(repeating: "2", count: 64))
        let data = approvals.encoded()
        #expect(MicroAppApprovals.decode(data) == approvals)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.hasSuffix("\n"))
        #expect(text.range(of: "\"a\"")!.lowerBound < text.range(of: "\"b\"")!.lowerBound)
        #expect(MicroAppApprovals.decode(Data("not json".utf8)) == MicroAppApprovals())
        #expect(MicroAppApprovals.decode(Data(#"{"version":99,"approvals":{"a":"x"}}"#.utf8)) == MicroAppApprovals())
    }
}

@Suite struct MicroAppStartTests {
    @Test func resolveAndNames() {
        let catalog = MicroAppCatalog.load([("say-hi.yaml", file("Say hi")), ("plain.yaml", file()), ("broken.yaml", "format: ting.microapp/2\n")])
        #expect(catalog.resolve("say-hi").isWorking)
        #expect(catalog.bindingName(label: "Hello", id: "say-hi") == "Hello")
        #expect(catalog.bindingName(label: "", id: "say-hi") == "Say hi")
        #expect(catalog.bindingName(label: "", id: "plain") == "plain")
        #expect(catalog.bindingName(label: "", id: "missing") == "missing")
        guard case .broken(let entry) = catalog.resolve("broken") else { Issue.record("expected broken"); return }
        #expect(entry.file == "broken.yaml")
        #expect(catalog.resolve("missing") == .missing)
        #expect(catalog.resolve("missing").problem(id: "missing", folder: "~/.config/ting/micro") == "Micro-app `missing` not found in ~/.config/ting/micro")
        let problem = catalog.resolve("broken").problem(id: "broken", folder: "x") ?? ""
        #expect(problem.hasPrefix("Micro-app broken.yaml, line "))
        #expect(catalog.resolve("say-hi").problem(id: "say-hi", folder: "x") == nil)
    }

    @Test func duplicateIdResolvesToTheFirstFile() {
        let catalog = MicroAppCatalog.load([("b.yaml", "id: a\n" + file()), ("a.yaml", file())])
        guard case .working(_, let entry) = catalog.resolve("a") else { Issue.record("expected working"); return }
        #expect(entry.file == "a.yaml")
    }

    @Test func approvalBeforeTheFirstRunOnly() {
        let text = file("Say hi")
        var catalog = MicroAppCatalog.load([("say-hi.yaml", text)])
        var approvals = MicroAppApprovals()
        guard case .approve(let app, let hash) = MicroAppStartStep.first(id: "say-hi", catalog: catalog, approvals: approvals, folder: "f")
        else { Issue.record("expected approval"); return }
        #expect(hash == MicroAppApprovals.hash(Data(text.utf8)))
        approvals.approve(id: app.id, hash: hash)
        #expect(MicroAppStartStep.first(id: "say-hi", catalog: catalog, approvals: approvals, folder: "f") == .run(app))
        // An edit of the file asks again.
        catalog = MicroAppCatalog.load([("say-hi.yaml", text + "\n")])
        guard case .approve = MicroAppStartStep.first(id: "say-hi", catalog: catalog, approvals: approvals, folder: "f")
        else { Issue.record("expected approval after an edit"); return }
    }

    @Test func missingAndBrokenStartNothing() {
        let catalog = MicroAppCatalog.load([("broken.yaml", "format: ting.microapp/2\n")])
        guard case .error(let missing) = MicroAppStartStep.first(id: "nope", catalog: catalog, approvals: .init(), folder: "f"),
              case .error(let broken) = MicroAppStartStep.first(id: "broken", catalog: catalog, approvals: .init(), folder: "f")
        else { Issue.record("expected errors"); return }
        #expect(missing.contains("not found"))
        #expect(broken.contains("broken.yaml"))
    }
}

@Suite struct MicroAppResultPlanTests {
    private let ok = MicroAppRunOutput(stdout: "result")

    @Test func panelOnly() {
        let plan = MicroAppResultPlan.make(app: app(to: [.panel], style: .code), result: .success(ok))
        #expect(plan == MicroAppResultPlan(show: .panel(MicroAppPanelContent(title: "Say hi", text: "result", style: .code, isError: false))))
    }

    @Test func clipboardOnlyCopiesWithToast() {
        let plan = MicroAppResultPlan.make(app: app(to: [.clipboard]), result: .success(ok))
        #expect(plan == MicroAppResultPlan(clipboard: "result", show: .toast("Copied")))
    }

    @Test func bothCopiesAndShowsTheCopiedNote() {
        let plan = MicroAppResultPlan.make(app: app(to: [.clipboard, .panel]), result: .success(ok))
        #expect(plan.clipboard == "result")
        guard case .panel(let content) = plan.show else { Issue.record("expected panel"); return }
        #expect(content.notes == ["Copied"])
        #expect(!content.isError)
    }

    @Test func emptyOutputLeavesTheClipboard() {
        let empty = MicroAppRunResult.success(MicroAppRunOutput(stdout: ""))
        #expect(MicroAppResultPlan.make(app: app(to: [.clipboard]), result: empty) == MicroAppResultPlan(show: .toast("No output")))
        let both = MicroAppResultPlan.make(app: app(to: [.clipboard, .panel]), result: empty)
        #expect(both.clipboard == nil)
        guard case .panel(let content) = both.show else { Issue.record("expected panel"); return }
        #expect(content.notes == ["No output"])
    }

    @Test func failureIsAConsolePanelWithNothingCopied() {
        let output = MicroAppRunOutput(stdout: "partial\n", stderr: "bad input\n")
        let plan = MicroAppResultPlan.make(app: app(to: [.clipboard, .panel]), result: .failure(exitCode: 5, output))
        #expect(plan.clipboard == nil)
        #expect(plan.show == .panel(MicroAppPanelContent(title: "Say hi", text: "bad input\n\npartial", style: .console,
                                                         isError: true, notes: ["exit 5"])))
    }

    @Test func timeoutShowsStoppedNoteWithPartialOutput() {
        let plan = MicroAppResultPlan.make(app: app(to: [.clipboard]), result: .timeout(MicroAppRunOutput(stdout: "half")))
        #expect(plan.clipboard == nil)
        guard case .panel(let content) = plan.show else { Issue.record("expected panel"); return }
        #expect(content.isError && content.style == .console)
        #expect(content.notes == ["stopped after 60 s"])
        #expect(content.text == "half")
    }

    @Test func cutNote() {
        let cut = MicroAppRunOutput(stdout: "a lot", stdoutCut: true)
        guard case .panel(let content) = MicroAppResultPlan.make(app: app(to: [.clipboard, .panel]), result: .success(cut)).show
        else { Issue.record("expected panel"); return }
        #expect(content.notes == ["Copied", "output cut at 1 MB"])
        #expect(MicroAppResultPlan.make(app: app(to: [.clipboard]), result: .success(cut)).show == .toast("Copied, output cut at 1 MB"))
        #expect(MicroAppResultPlan.cutNote(limit: 16) == "output cut at 16 bytes")
    }

    @Test func clipboardOnlyToastShowsTheCutMarkWhenOnlyStderrWasCut() {
        let output = MicroAppRunOutput(stdout: "result", stderr: "noise", stderrCut: true)
        let plan = MicroAppResultPlan.make(app: app(to: [.clipboard]), result: .success(output))
        #expect(plan == MicroAppResultPlan(clipboard: "result", show: .toast("Copied, output cut at 1 MB")))
        let both = MicroAppRunOutput(stdout: "result", stderr: "noise", stdoutCut: true, stderrCut: true)
        #expect(MicroAppResultPlan.make(app: app(to: [.clipboard]), result: .success(both))
            == MicroAppResultPlan(clipboard: "result", show: .toast("Copied, output cut at 1 MB")))
        let small = MicroAppResultPlan.make(app: app(to: [.clipboard]), result: .success(output), outputLimit: 16)
        #expect(small.show == .toast("Copied, output cut at 16 bytes"))
    }

    @Test func clipboardOnlyEmptyOutputIsExactlyNoOutput() {
        for stderrCut in [false, true] {
            let output = MicroAppRunOutput(stdout: "", stderr: "noise", stderrCut: stderrCut)
            let plan = MicroAppResultPlan.make(app: app(to: [.clipboard]), result: .success(output))
            #expect(plan.clipboard == nil)
            #expect(plan == MicroAppResultPlan(show: .toast("No output")))
        }
    }

    @Test func cancelledShowsNothingAndCopiesNothing() {
        #expect(MicroAppResultPlan.make(app: app(to: [.clipboard]), result: .cancelled(ok)) == MicroAppResultPlan(show: .nothing))
    }

    @Test func errorsUseAToastWhenTheyFitTwoLines() {
        #expect(MicroAppResultPlan.make(app: app(to: [.panel]), result: .toolNotFound("jq")).show == .toast("Say hi: tool not found: jq"))
        let long = String(repeating: "x", count: 300)
        let plan = MicroAppResultPlan.error(title: "id", message: long)
        #expect(plan.clipboard == nil)
        #expect(plan.show == .panel(MicroAppPanelContent(title: "id", text: long, style: .console, isError: true)))
        #expect(!MicroAppResultPlan.fitsToast("a\nb\nc"))
    }
}
