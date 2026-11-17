import Foundation
import Testing
@testable import SwiftKeyCore

@Suite struct NameMatcherTests {
    @Test func qualities() {
        #expect(NameMatcher.match("safari", name: "Safari") == .exact)
        #expect(NameMatcher.match("SAF", name: "Safari") == .prefix)
        #expect(NameMatcher.match("visual studio code", name: "Visual Studio Code") == .exact)
        #expect(NameMatcher.match("visualstu", name: "Visual Studio Code") == .prefix)
        #expect(NameMatcher.match("code", name: "Visual Studio Code") == .wordStart)
        #expect(NameMatcher.match("studio co", name: "Visual Studio Code") == .wordStart)
        #expect(NameMatcher.match("vis co", name: "Visual Studio Code") == .wordStart)
        #expect(NameMatcher.match("vsc", name: "Visual Studio Code") == .initials)
        #expect(NameMatcher.match("vc", name: "Visual Studio Code") == .initials)
        #expect(NameMatcher.match("udi", name: "Visual Studio Code") == .substring)
        #expect(NameMatcher.match("xyz", name: "Visual Studio Code") == nil)
        #expect(NameMatcher.match("code vis", name: "Visual Studio Code") == nil)
    }
    @Test func caseAndDiacritics() {
        #expect(NameMatcher.match("cafe", name: "Café Racer") == .prefix)
        #expect(NameMatcher.match("CAFÉ", name: "cafe") == .exact)
        #expect(NameMatcher.match("zurich", name: "Zürich Maps") == .prefix)
        #expect(NameMatcher.match("елка", name: "Ёлка") == .exact)
        #expect(NameMatcher.match("телег", name: "Телеграм") == .prefix)
    }
    @Test func camelCaseAndPunctuationWords() {
        #expect(NameMatcher.match("time", name: "FaceTime") == .wordStart)
        #expect(NameMatcher.match("ft", name: "FaceTime") == .initials)
        #expect(NameMatcher.match("facetime", name: "FaceTime") == .exact)
        #expect(NameMatcher.match("term", name: "iTerm") == .wordStart)
        #expect(NameMatcher.match("js", name: "Node.js") == .wordStart)
        #expect(NameMatcher.match("node.js", name: "Node.js") == .exact)
        #expect(NameMatcher.match("1pass", name: "1Password 7") == .prefix)
        #expect(NameMatcher.match("7", name: "1Password 7") == .wordStart)
    }
    @Test func emptyQueries() {
        #expect(NameMatcher.match("", name: "Safari") == nil)
        #expect(NameMatcher.match("  -", name: "Safari") == nil)
        #expect(NameMatcher.match("a", name: "") == nil)
    }
    @Test func wrongLayout() {
        // Cyrillic letters typed on the keys of a Latin name.
        #expect(NameMatcher.match("ыфафкш", name: "Safari") == .exact)
        #expect(NameMatcher.match("ЕУКЬ", name: "Terminal") == .prefix)
        #expect(NameMatcher.match("ешьу", name: "Time Machine") == .prefix)
        // Ukrainian і on the S key.
        #expect(NameMatcher.match("іфа", name: "Safari") == .prefix)
        // Latin letters typed on the keys of a Cyrillic name.
        #expect(NameMatcher.match("ntktuhfv", name: "Телеграм") == .exact)
        #expect(NameMatcher.match("Ntktu", name: "Телеграм") == .prefix)
        // Ukrainian: S → і, ] → ї, ' → є.
        #expect(NameMatcher.match("rb]d", name: "Київ") == .exact)
        #expect(NameMatcher.match("scnjhsz", name: "Історія") == .exact)
        #expect(NameMatcher.match("'yjn", name: "Єнот") == .exact)
        // Russian ы on the S key.
        #expect(NameMatcher.match("ns", name: "Ты") == .exact)
        // Punctuation keys map to letters: , → б.
        #expect(NameMatcher.match(",fyr", name: "Банк") == .exact)
    }
    @Test func layoutVariants() {
        #expect(KeyboardLayoutSwap.variants(of: "Safari").first == "safari")
        #expect(KeyboardLayoutSwap.variants(of: "ыф") == ["ыф", "sa"])
        #expect(KeyboardLayoutSwap.variants(of: "sa") == ["sa", "ыф", "іф"])
        #expect(KeyboardLayoutSwap.variants(of: "ta") == ["ta", "еф"])
        #expect(KeyboardLayoutSwap.variants(of: "123") == ["123"])
    }
}

@Suite struct LaunchHistoryTests {
    private let day: TimeInterval = 24 * 60 * 60
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func onlySuccessCounts() {
        var h = LaunchHistory()
        let r1 = h.record(.failed, id: "a", at: t0)
        #expect(!r1)
        let r2 = h.record(.revealed, id: "a", at: t0)
        #expect(!r2)
        #expect(h.entries.isEmpty)
        #expect(h.lastLaunch(id: "a") == nil)
        let r3 = h.record(.opened, id: "a", at: t0)
        #expect(r3)
        let r4 = h.record(.activated, id: "a", at: t0 + 1)
        #expect(r4)
        #expect(h.recentCount(id: "a", now: t0 + 2) == 2)
        #expect(h.lastLaunch(id: "a") == t0 + 1)
        #expect(h.recentCount(id: "missing", now: t0) == 0)
    }
    @Test func sevenDayBoundary() {
        var h = LaunchHistory()
        h.record(.opened, id: "a", at: t0)
        let edge = t0 + 7 * day
        #expect(h.recentCount(id: "a", now: edge - 1) == 1)
        #expect(h.recentCount(id: "a", now: edge) == 1)
        #expect(h.recentCount(id: "a", now: edge + 0.001) == 0)
        #expect(h.recentCount(id: "a", now: edge + day) == 0)
    }
    @Test func pruningKeepsLastLaunch() {
        var h = LaunchHistory()
        h.record(.opened, id: "a", at: t0)
        h.record(.opened, id: "a", at: t0 + day)
        h.record(.opened, id: "b", at: t0 + 7 * day + 1)
        #expect(h.entries["a"]?.events == [t0 + day])
        h.prune(now: t0 + 30 * day)
        #expect(h.entries["a"]?.events == [])
        #expect(h.lastLaunch(id: "a") == t0 + day)
        #expect(h.recentCount(id: "a", now: t0 + 30 * day) == 0)
    }
    @Test func outOfOrderEventsKeepLatestLaunch() {
        var h = LaunchHistory()
        h.record(.opened, id: "a", at: t0 + 10)
        h.record(.opened, id: "a", at: t0)
        #expect(h.entries["a"]?.events == [t0, t0 + 10])
        #expect(h.lastLaunch(id: "a") == t0 + 10)
    }
    @Test func bounds() {
        var h = LaunchHistory()
        for i in 0..<(LaunchHistory.maxEventsPerEntry + 20) {
            h.record(.opened, id: "a", at: t0 + Double(i))
        }
        #expect(h.entries["a"]?.events.count == LaunchHistory.maxEventsPerEntry)
        #expect(h.entries["a"]?.events.first == t0 + 20)
        for i in 0..<LaunchHistory.maxEntries {
            h.record(.opened, id: "id\(i)", at: t0 + 1000 + Double(i))
        }
        #expect(h.entries.count == LaunchHistory.maxEntries)
        #expect(h.entries["a"] == nil)
        #expect(h.entries["id0"] != nil)
    }
    @Test func forgetAndCodable() throws {
        var h = LaunchHistory()
        h.record(.opened, id: "app:com.apple.safari", at: t0)
        h.record(.activated, id: "url:https://github.com", at: t0 + 0.5)
        let data = h.encoded()
        #expect(try LaunchHistory.decode(data) == h)
        #expect(String(decoding: data, as: UTF8.self).hasSuffix("\n"))
        h.forget(id: "app:com.apple.safari")
        #expect(h.lastLaunch(id: "app:com.apple.safari") == nil)
        #expect(throws: DecodingError.self) { try LaunchHistory.decode(Data("[]".utf8)) }
    }
}

@Suite struct LaunchaSearchTests {
    private let day: TimeInterval = 24 * 60 * 60
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let safari = LaunchaCandidate.app(bundleID: "com.apple.Safari", name: "Safari")
    private let slack = LaunchaCandidate.app(bundleID: "com.tinyspeck.slackmacgap", name: "Slack")
    private let messages = LaunchaCandidate.app(bundleID: "com.apple.MobileSMS", name: "Messages")
    private let github = LaunchaCandidate.url("https://github.com", name: "GitHub")

    private func names(_ query: String, _ candidates: [LaunchaCandidate], _ history: LaunchHistory) -> [String] {
        LaunchaSearch.results(for: query, in: candidates, history: history, now: now).map(\.candidate.name)
    }

    @Test func identities() {
        #expect(safari.id == "app:com.apple.safari")
        #expect(LaunchaCandidate.app(bundleID: "COM.APPLE.SAFARI", name: "x").id == safari.id)
        #expect(github.id == "url:https://github.com")
        #expect(safari.target == .app("com.apple.Safari"))
        #expect(LaunchaCandidate.menu(path: ["d", "g", "s"], name: "Git Status").id == "menu:d g s")
        #expect(LaunchaCandidate.menu(path: ["d"], name: "x").target == .menu(["d"]))
    }
    @Test func usageBeatsMatchQuality() {
        var h = LaunchHistory()
        // Messages matches "s" only as a substring, but it is used more.
        h.record(.opened, id: messages.id, at: now - 3 * day)
        h.record(.opened, id: messages.id, at: now - 2 * day)
        h.record(.opened, id: safari.id, at: now - day)
        #expect(names("s", [safari, slack, messages], h) == ["Messages", "Safari", "Slack"])
        let top = LaunchaSearch.results(for: "s", in: [safari, slack, messages], history: h, now: now)[0]
        #expect(top.recentCount == 2)
        #expect(top.quality == .substring)
        #expect(top.lastLaunch == now - 2 * day)
    }
    @Test func equalCountsUseLatestLaunch() {
        var h = LaunchHistory()
        h.record(.opened, id: safari.id, at: now - 2 * day)
        h.record(.opened, id: slack.id, at: now - day)
        #expect(names("s", [safari, slack], h) == ["Slack", "Safari"])
        h.record(.activated, id: safari.id, at: now - 60)
        h.record(.opened, id: slack.id, at: now - 120)
        #expect(names("s", [safari, slack], h) == ["Safari", "Slack"])
    }
    @Test func lastLaunchOutsideWindowStillOrdersZeroCounts() {
        var h = LaunchHistory()
        h.record(.opened, id: slack.id, at: now - 10 * day)
        h.record(.opened, id: messages.id, at: now - 20 * day)
        h.prune(now: now)
        // All have 0 launches in 7 days; launched before beats never; later beats earlier.
        #expect(names("s", [safari, messages, slack], h) == ["Slack", "Messages", "Safari"])
    }
    @Test func sevenDayBoundaryInRanking() {
        var h = LaunchHistory()
        h.record(.opened, id: safari.id, at: now - 7 * day)
        h.record(.opened, id: slack.id, at: now - 7 * day - 1)
        h.record(.opened, id: slack.id, at: now - 7 * day - 2)
        let results = LaunchaSearch.results(for: "s", in: [slack, safari], history: h, now: now)
        #expect(results.map(\.candidate.name) == ["Safari", "Slack"])
        #expect(results.map(\.recentCount) == [1, 0])
    }
    @Test func failedAndRevealDoNotChangeOrder() {
        var h = LaunchHistory()
        h.record(.opened, id: safari.id, at: now - day)
        for _ in 0..<5 {
            h.record(.failed, id: slack.id, at: now - 10)
            h.record(.revealed, id: slack.id, at: now - 5)
        }
        #expect(names("s", [slack, safari], h) == ["Safari", "Slack"])
    }
    @Test func noHistoryUsesQualityThenName() {
        let h = LaunchHistory()
        let studio = LaunchaCandidate.app(bundleID: "com.microsoft.VSCode", name: "Visual Studio Code")
        let code = LaunchaCandidate.app(bundleID: "com.example.code", name: "Code")
        let xcode = LaunchaCandidate.app(bundleID: "com.apple.dt.Xcode", name: "Xcode")
        let codeRunner = LaunchaCandidate.app(bundleID: "com.example.runner", name: "CodeRunner")
        #expect(names("code", [xcode, studio, codeRunner, code], h) == ["Code", "CodeRunner", "Visual Studio Code", "Xcode"])
        #expect(names("b", [LaunchaCandidate.url("https://b.example", name: "beta"), .url("https://a.example", name: "Abby"),
                            .url("https://c.example", name: "Bravo")], h) == ["beta", "Bravo", "Abby"])
    }
    @Test func emptyQueryListsAllAndDuplicatesCollapse() {
        var h = LaunchHistory()
        h.record(.opened, id: github.id, at: now - day)
        let all = LaunchaSearch.results(for: " ", in: [safari, github, safari, slack], history: h, now: now)
        #expect(all.map(\.candidate.name) == ["GitHub", "Safari", "Slack"])
        #expect(all.allSatisfy { $0.quality == nil })
    }
    @Test func wrongLayoutQuery() {
        #expect(names("ыф", [safari, slack, github], LaunchHistory()) == ["Safari"])
    }
}

@Suite struct LeaderDoubleTapTests {
    @Test func doubleTapAtRoot() {
        var tap = LeaderDoubleTap()
        var m = LeaderMachine(items: [.app("s", "Safari", "com.apple.Safari")])
        let r5 = tap.press(at: 10, machine: m)
        #expect(r5 == .single)
        let r6 = m.handle(.leader)
        #expect(r6 == .open)
        tap.release()
        let r7 = tap.press(at: 10.25, machine: m)
        #expect(r7 == .double)
        m.reset()
        tap.release()
        // A third quick press is a new first press.
        let r8 = tap.press(at: 10.4, machine: m)
        #expect(r8 == .single)
    }
    @Test func windowBoundary() {
        for (delay, expected) in [(0.3, LeaderPress.double), (0.31, .single), (-0.1, .single)] {
            var tap = LeaderDoubleTap(window: 0.3)
            let r9 = tap.press(at: 0, menuOpen: false, menuOpenAtRoot: false)
            #expect(r9 == .single)
            tap.release()
            let r10 = tap.press(at: delay, menuOpen: true, menuOpenAtRoot: true)
            #expect(r10 == expected)
        }
        var tap = LeaderDoubleTap(LaunchaSettings())
        #expect(tap.window == 0.3)
        #expect(tap.isEnabled)
        tap.window = 0.6
        _ = tap.press(at: 0, menuOpen: false, menuOpenAtRoot: false)
        tap.release()
        let r11 = tap.press(at: 0.5, menuOpen: true, menuOpenAtRoot: true)
        #expect(r11 == .double)
    }
    @Test func heldKeyAndRepeatsNeverCountTwice() {
        var tap = LeaderDoubleTap()
        let r12 = tap.press(at: 0, menuOpen: false, menuOpenAtRoot: false)
        #expect(r12 == .single)
        #expect(tap.isHeld)
        // Auto-repeat while held.
        let r13 = tap.press(at: 0.05, menuOpen: true, menuOpenAtRoot: true)
        #expect(r13 == .ignored)
        let r14 = tap.press(at: 0.1, menuOpen: true, menuOpenAtRoot: true)
        #expect(r14 == .ignored)
        tap.release()
        #expect(!tap.isHeld)
        let r15 = tap.press(at: 0.2, menuOpen: true, menuOpenAtRoot: true)
        #expect(r15 == .double)
        // Holding the second press does not make another double tap.
        let r16 = tap.press(at: 0.25, menuOpen: true, menuOpenAtRoot: true)
        #expect(r16 == .ignored)
    }
    @Test func heldRepeatAfterDoubleTapIsIgnoredWithMenuClosed() {
        // The double tap closed the menu and opened launcha. A repeat of the held leader
        // comes with the menu closed and must stay ignored, so launcha stays open.
        var tap = LeaderDoubleTap()
        #expect(tap.press(at: 0, menuOpen: false, menuOpenAtRoot: false) == .single)
        tap.release()
        #expect(tap.press(at: 0.2, menuOpen: true, menuOpenAtRoot: true) == .double)
        #expect(tap.press(at: 0.25, menuOpen: false, menuOpenAtRoot: false) == .ignored)
        #expect(tap.press(at: 0.3, menuOpen: false, menuOpenAtRoot: false) == .ignored)
        tap.release()
        #expect(tap.press(at: 1, menuOpen: false, menuOpenAtRoot: false) == .single)
    }
    @Test func lostReleaseRecoversAfterStaleHold() {
        var tap = LeaderDoubleTap()
        #expect(tap.press(at: 0, menuOpen: false, menuOpenAtRoot: false) == .single)
        // Repeats keep the hold alive, even for a long time.
        for step in 1...40 {
            #expect(tap.press(at: Double(step) * 0.1, menuOpen: true, menuOpenAtRoot: true) == .ignored)
        }
        // No release and no press for longer than staleHold: the release was lost.
        let late = 4 + LeaderDoubleTap.staleHold + 0.1
        #expect(tap.press(at: late, menuOpen: false, menuOpenAtRoot: false) == .single)
        #expect(tap.isHeld)
        tap.release()
        #expect(tap.press(at: late + 0.1, menuOpen: true, menuOpenAtRoot: true) == .double)
    }
    @Test func sequenceInputCancels() {
        var tap = LeaderDoubleTap()
        var m = LeaderMachine(items: [.group("w", "Web", [.url("g", "GitHub", "https://github.com")]), .app("x", "X", "com.example.X")])
        let r17 = tap.press(at: 0, machine: m)
        #expect(r17 == .single)
        _ = m.handle(.leader)
        tap.release()
        // The key acts at once; the double tap does not delay it.
        let r18 = m.handle(.key("w"))
        #expect(r18 == .show(path: ["w"]))
        tap.sequenceInput()
        let r19 = tap.press(at: 0.1, machine: m)
        #expect(r19 == .single)
        let r20 = m.handle(.leader)
        #expect(r20 == .close)
        tap.release()

        // Back to the top level with ⌫ is still input in between.
        let r21 = tap.press(at: 1, machine: m)
        #expect(r21 == .single)
        _ = m.handle(.leader)
        tap.release()
        _ = m.handle(.key("w"))
        tap.sequenceInput()
        _ = m.handle(.back)
        tap.sequenceInput()
        let r22 = tap.press(at: 1.1, machine: m)
        #expect(r22 == .single)
    }
    @Test func notAtRootOrMenuClosed() {
        var tap = LeaderDoubleTap()
        _ = tap.press(at: 0, menuOpen: false, menuOpenAtRoot: false)
        tap.release()
        let r23 = tap.press(at: 0.1, menuOpen: true, menuOpenAtRoot: false)
        #expect(r23 == .single)
        tap.release()

        // The menu closed before the second press (for example it lost focus).
        _ = tap.press(at: 1, menuOpen: false, menuOpenAtRoot: false)
        tap.release()
        let r24 = tap.press(at: 1.1, menuOpen: false, menuOpenAtRoot: false)
        #expect(r24 == .single)
        tap.release()

        // The first press closed an open menu: the next press only reopens it.
        tap.reset()
        let r25 = tap.press(at: 2, menuOpen: true, menuOpenAtRoot: true)
        #expect(r25 == .single)
        tap.release()
        let r26 = tap.press(at: 2.1, menuOpen: false, menuOpenAtRoot: false)
        #expect(r26 == .single)
        tap.release()
        let r27 = tap.press(at: 2.2, menuOpen: true, menuOpenAtRoot: true)
        #expect(r27 == .double)
    }
    @Test func resetAndDisabled() {
        var tap = LeaderDoubleTap()
        _ = tap.press(at: 0, menuOpen: false, menuOpenAtRoot: false)
        tap.release()
        tap.reset()
        let r28 = tap.press(at: 0.1, menuOpen: true, menuOpenAtRoot: true)
        #expect(r28 == .single)

        var off = LeaderDoubleTap(isEnabled: false)
        let r29 = off.press(at: 0, menuOpen: false, menuOpenAtRoot: false)
        #expect(r29 == .single)
        off.release()
        let r30 = off.press(at: 0.1, menuOpen: true, menuOpenAtRoot: true)
        #expect(r30 == .single)
        let r31 = off.press(at: 0.15, menuOpen: false, menuOpenAtRoot: false)
        #expect(r31 == .ignored)
        var settings = LaunchaSettings()
        settings.doubleTap = false
        #expect(!LeaderDoubleTap(settings).isEnabled)
    }
}
