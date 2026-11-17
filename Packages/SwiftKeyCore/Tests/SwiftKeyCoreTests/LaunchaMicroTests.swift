import Foundation
import Testing
@testable import SwiftKeyCore

private func file(id: String? = nil, name: String? = nil, hidden: Bool = false, description: String = "Say hi.",
                  command: Bool = true) -> String {
    var text = "format: ting.microapp/2\n"
    if let id { text += "id: \(id)\n" }
    if let name { text += "name: \(name)\n" }
    if hidden { text += "hidden: true\n" }
    text += "description: \(description)\ninput: none\n"
    if command { text += "command: echo hi\n" }
    text += "output:\n  to: [panel]\n"
    return text
}

private let now = Date(timeIntervalSince1970: 1_000_000)

private func search(_ query: String, _ candidates: [LaunchaCandidate]) -> [String] {
    LaunchaSearch.results(for: query, in: candidates, history: LaunchHistory(), now: now).map(\.candidate.id)
}

@Suite struct LaunchaMicroTests {
    @Test func everyLoadedMicroAppIsACandidateWithOrWithoutABinding() {
        let catalog = MicroAppCatalog.load([
            ("format-json.yaml", file(name: "Format JSON", description: "Pretty-print JSON.")),
            ("count.yaml", file()),
        ])
        let candidates = catalog.launchaCandidates(bindings: [])
        #expect(candidates.map(\.start) == [.id("count"), .id("format-json")])
        #expect(candidates.map(\.candidate.id) == ["micro:count", "micro:format-json"])
        #expect(candidates.map(\.candidate.target) == [.micro("count"), .micro("format-json")])
        #expect(candidates.allSatisfy { $0.isWorking })
        #expect(candidates.last?.file == "format-json.yaml")
        #expect(candidates.last?.description == "Pretty-print JSON.")
    }

    @Test func nameIsTheBindingLabelThenNameThenId() {
        let catalog = MicroAppCatalog.load([
            ("labelled.yaml", file(name: "Own Name")),
            ("named.yaml", file(name: "Format JSON")),
            ("plain.yaml", file()),
            ("bound-no-label.yaml", file()),
        ])
        let items = [
            Item(key: "m", label: "", action: .group([
                Item(key: "l", label: "Bound Label", action: .micro("labelled")),
                Item(key: "b", label: "", action: .micro("bound-no-label")),
            ])),
            Item(key: "x", label: "Later Label", action: .micro("labelled")),
        ]
        let names = Dictionary(uniqueKeysWithValues: catalog.launchaCandidates(bindings: items).map { ($0.file, $0.candidate.name) })
        #expect(names["labelled.yaml"] == "Bound Label", "the first labelled binding, depth-first")
        #expect(names["named.yaml"] == "Format JSON")
        #expect(names["plain.yaml"] == "plain")
        #expect(names["bound-no-label.yaml"] == "bound-no-label", "an empty label falls back to the id")
        // Without bindings the `name` key is shown.
        let unbound = catalog.launchaCandidates(bindings: []).first { $0.file == "labelled.yaml" }
        #expect(unbound?.candidate.name == "Own Name")
    }

    @Test func hiddenMicroAppIsLeftOutButStillStartsByItsBinding() {
        let catalog = MicroAppCatalog.load([
            ("secret.yaml", file(hidden: true)),
            ("shown.yaml", file()),
        ])
        let items = [Item(key: "s", label: "Secret", action: .micro("secret"))]
        #expect(catalog.launchaCandidates(bindings: items).map(\.file) == ["shown.yaml"])
        #expect(catalog.resolve("secret").isWorking, "a hidden micro-app still resolves for its binding")
        let step = MicroAppStartStep.first(id: "secret", catalog: catalog, approvals: MicroAppApprovals(), folder: "micro")
        guard case .approve(let app, _) = step else { Issue.record("expected the approval step"); return }
        #expect(app.id == "secret")
    }

    @Test func hiddenButInvalidFileIsLeftOut() {
        let catalog = MicroAppCatalog.load([
            ("secret-broken.yaml", file(hidden: true, command: false)),
            ("shown.yaml", file()),
        ])
        #expect(catalog.entries.first?.isBroken == true, "the missing `command` breaks the file")
        #expect(catalog.entries.first?.isHidden == true)
        #expect(catalog.launchaCandidates(bindings: []).map(\.file) == ["shown.yaml"])
        // An invalid `hidden` value cannot hide the file.
        let invalid = MicroAppCatalog.load([("odd.yaml", file(command: false).replacingOccurrences(of: "input: none", with: "hidden: yes\ninput: none"))])
        #expect(invalid.launchaCandidates(bindings: []).map(\.file) == ["odd.yaml"])
    }

    @Test func brokenFileIsListedAsNotWorkingAndStartsWithItsOwnErrors() {
        let catalog = MicroAppCatalog.load([
            ("broken.yaml", "format: ting.microapp/2\ndescription: x\n"),
            ("good.yaml", file()),
        ])
        let candidates = catalog.launchaCandidates(bindings: [Item(key: "b", label: "Broken One", action: .micro("broken"))])
        #expect(candidates.map(\.file) == ["broken.yaml", "good.yaml"])
        let broken = candidates[0]
        #expect(!broken.isWorking)
        #expect(broken.candidate.id == "micro-file:broken.yaml")
        #expect(broken.start == .file("broken.yaml"))
        #expect(broken.candidate.name == "Broken One")
        #expect(broken.problem?.hasPrefix("line ") == true)
        let step = MicroAppStartStep.first(file: "broken.yaml", catalog: catalog, approvals: MicroAppApprovals(), folder: "micro")
        guard case .error(let message) = step else { Issue.record("expected an error"); return }
        #expect(message.contains("broken.yaml"))
    }

    @Test func brokenFileWithTheIdOfAWorkingMicroAppIsStillListed() {
        let catalog = MicroAppCatalog.load([
            ("good.yaml", file(name: "Good")),
            ("other.yaml", file(id: "good")),
        ])
        #expect(catalog.entries.first { $0.file == "other.yaml" }?.isBroken == true)
        let binding = Item(key: "g", label: "Good Label", action: .micro("good"))
        let candidates = catalog.launchaCandidates(bindings: [binding])
        #expect(candidates.map(\.candidate.id) == ["micro:good", "micro-file:other.yaml"])
        #expect(candidates.map(\.isWorking) == [true, false])
        #expect(candidates.map(\.candidate.name) == ["Good Label", "good"], "the binding label belongs to the working file")
        // A start of the broken one shows other.yaml's errors, not the working good.yaml.
        let step = MicroAppStartStep.first(file: "other.yaml", catalog: catalog, approvals: MicroAppApprovals(), folder: "micro")
        guard case .error(let message) = step else { Issue.record("expected an error"); return }
        #expect(message.contains("other.yaml"))
    }

    @Test func twoBrokenFilesWithTheSameIdAreBothListed() {
        let catalog = MicroAppCatalog.load([
            ("first.yaml", "id: same\nformat: ting.microapp/2\n"),
            ("second.yaml", "id: same\nformat: ting.microapp/2\ndescription: x\n"),
        ])
        let candidates = catalog.launchaCandidates(bindings: [])
        #expect(candidates.map(\.candidate.id) == ["micro-file:first.yaml", "micro-file:second.yaml"])
        #expect(Set(candidates.map(\.candidate.id)).count == 2)
        for name in ["first.yaml", "second.yaml"] {
            let step = MicroAppStartStep.first(file: name, catalog: catalog, approvals: MicroAppApprovals(), folder: "micro")
            guard case .error(let message) = step else { Issue.record("expected an error"); continue }
            #expect(message.contains(name), "each start shows its own file's errors")
        }
    }

    @Test func duplicateIdFileIsListedSeparately() {
        let app = MicroApp(id: "same", name: "Same", description: "Say hi.", input: .none, command: "echo hi",
                           output: .init(targets: [.panel]))
        let catalog = MicroAppCatalog.build([("a.yaml", .success(app)), ("b.yaml", .success(app))])
        let candidates = catalog.launchaCandidates(bindings: [])
        #expect(candidates.map(\.candidate.id) == ["micro:same", "micro-file:b.yaml"])
        #expect(candidates.map(\.isWorking) == [true, false])
        #expect(candidates[1].candidate.name == "Same", "the duplicate keeps its own name")
        #expect(candidates[1].problem?.contains("duplicate id") == true)
    }

    @Test func namedButInvalidFileIsShownAndSearchedByItsName() {
        let catalog = MicroAppCatalog.load([("format-json.yaml", file(name: "Format JSON", command: false))])
        let candidates = catalog.launchaCandidates(bindings: [])
        #expect(candidates.count == 1)
        #expect(candidates.first?.isWorking == false)
        #expect(candidates.first?.candidate.name == "Format JSON")
        let all = candidates.map(\.candidate)
        #expect(search("fj", all) == ["micro-file:format-json.yaml"], "initials of the name")
        #expect(search("format js", all) == ["micro-file:format-json.yaml"])
        // A binding label still wins over the name of a broken file.
        let labelled = catalog.launchaCandidates(bindings: [Item(key: "j", label: "JSON!", action: .micro("format-json"))])
        #expect(labelled.first?.candidate.name == "JSON!")
    }

    @Test func microAppsMatchByNameInSearch() {
        let catalog = MicroAppCatalog.load([
            ("format-json.yaml", file(name: "Format JSON")),
            ("count.yaml", file(name: "Count words and characters")),
        ])
        let apps = [LaunchaCandidate.app(bundleID: "com.apple.Safari", name: "Safari")]
        let candidates = catalog.launchaCandidates(bindings: []).map(\.candidate) + apps
        #expect(search("json", candidates) == ["micro:format-json"])
        #expect(search("fj", candidates) == ["micro:format-json"])
        #expect(search("cwac", candidates) == ["micro:count"])
        #expect(search("saf", candidates) == ["app:com.apple.safari"])
        #expect(search("", candidates).count == 3)
    }

    @Test func microCandidateIdentity() {
        let candidate = LaunchaCandidate.micro(id: "dns-lookup", name: "DNS lookup")
        #expect(candidate.id == "micro:dns-lookup")
        #expect(candidate.target == .micro("dns-lookup"))
        #expect(LaunchaCandidate.brokenMicroFile("dns.yaml", name: "dns").id == "micro-file:dns.yaml")
    }
}
