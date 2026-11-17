import Testing
@testable import SwiftKeyCore

@Suite struct LeaderMachineTests {
    private var safari: Item { .app("s", "Safari", "com.apple.Safari") }
    private var fixture: [Item] { [.group("w", "Work", [.group("d", "Daily", [safari])]), .url("g", "GitHub", "https://github.com")] }

    @Test func closedEventsAndOpen() {
        var m = LeaderMachine(items: fixture)
        #expect(!m.isOpen)
        #expect(m.path.isEmpty)
        #expect(m.currentItems == fixture)
        for event: LeaderEvent in [.key("w"), .back, .escape] {
            #expect(m.handle(event) == .none)
            #expect(!m.isOpen)
        }
        #expect(m.handle(.leader) == .open)
        #expect(m.isOpen)
        #expect(m.path.isEmpty)
        #expect(m.currentItems == fixture)
    }
    @Test func userFlowLeaderWDS() {
        var m = LeaderMachine(items: fixture)
        #expect(m.handle(.leader) == .open)
        #expect(m.handle(.key("w")) == .show(path: ["w"]))
        #expect(m.path == ["w"])
        #expect(m.currentItems == [.group("d", "Daily", [safari])])
        #expect(m.handle(.key("d")) == .show(path: ["w", "d"]))
        #expect(m.currentItems == [safari])
        #expect(m.handle(.key("s")) == .run(safari))
        #expect(!m.isOpen)
        #expect(m.handle(.key("s")) == .none)
        #expect(m.handle(.leader) == .open)
        #expect(m.path.isEmpty)
        #expect(m.currentItems == fixture)
    }
    @Test func backAtDepthAndTop() {
        var m = LeaderMachine(items: fixture)
        _ = m.handle(.leader)
        _ = m.handle(.key("w"))
        _ = m.handle(.key("d"))
        #expect(m.handle(.back) == .show(path: ["w"]))
        #expect(m.path == ["w"])
        #expect(m.currentItems == [.group("d", "Daily", [safari])])
        #expect(m.handle(.back) == .show(path: []))
        #expect(m.currentItems == fixture)
        #expect(m.handle(.back) == .close)
        #expect(!m.isOpen)
    }
    @Test(arguments: [LeaderEvent.leader, .escape]) func closeFromNestedGroup(_ event: LeaderEvent) {
        var m = LeaderMachine(items: fixture)
        _ = m.handle(.leader)
        _ = m.handle(.key("w"))
        #expect(m.handle(event) == .close)
        #expect(!m.isOpen)
        #expect(m.handle(.leader) == .open)
        #expect(m.path.isEmpty)
    }
    @Test(arguments: UnknownKeyBehavior.allCases) func unknownKeys(_ behavior: UnknownKeyBehavior) {
        var m = LeaderMachine(items: fixture, unknownKey: behavior)
        _ = m.handle(.leader)
        _ = m.handle(.key("w"))
        #expect(m.handle(.key("x")) == .reject(key: "x", closed: behavior == .close))
        #expect(m.isOpen == (behavior == .shake))
        if behavior == .shake {
            #expect(m.path == ["w"])
            #expect(m.currentItems == [.group("d", "Daily", [safari])])
            #expect(m.handle(.key("d")) == .show(path: ["w", "d"]))
        } else { #expect(m.handle(.key("d")) == .none) }
    }
    @Test func resetAndURLAction() {
        var m = LeaderMachine(items: fixture)
        _ = m.handle(.leader)
        _ = m.handle(.key("w"))
        m.reset()
        #expect(!m.isOpen)
        #expect(m.handle(.back) == .none)
        m.reset()
        #expect(m.handle(.leader) == .open)
        #expect(m.path.isEmpty)
        #expect(m.handle(.key("g")) == .run(.url("g", "GitHub", "https://github.com")))
        #expect(!m.isOpen)
    }
    @Test func replacingItemsKeepsPathUntilNextEvent() {
        var m = LeaderMachine(items: fixture)
        _ = m.handle(.leader)
        _ = m.handle(.key("w"))
        m.items = [.app("x", "New", "com.example.New")]
        #expect(m.path == ["w"])
        #expect(m.isOpen)
        #expect(m.handle(.key("x")) == .run(.app("x", "New", "com.example.New")))
        #expect(!m.isOpen)
    }
    @Test func replacingItemsAtExistingPath() {
        var m = LeaderMachine(items: fixture)
        _ = m.handle(.leader)
        _ = m.handle(.key("w"))
        m.items = [.group("w", "Changed", [safari])]
        #expect(m.path == ["w"])
        #expect(m.currentItems == [safari])
        #expect(m.handle(.key("s")) == .run(safari))
    }
}

@Suite struct LeaderMachineEffectTests {
    private var mail: Item { .app("m", "Mail", "com.apple.mail") }
    private var notes: Item { .app("n", "Notes", "com.apple.Notes") }
    private var volume: Item { Item(key: "v", label: "Volume", action: .shell("vol +"), flags: .init(sticky: true)) }
    private var processes: Item { .dynamic("p", "Processes", "ps.sh") }
    private var startDay: Item {
        .group("s", "Start", [mail, .group("x", "Nested", [notes]), processes, notes])
    }
    private var batchDay: Item {
        Item(key: "b", label: "Batch", action: .group([mail, notes]), flags: .init(batch: true))
    }
    private var fixture: [Item] { [startDay, batchDay, volume, processes, mail] }

    private func opened(_ items: [Item]? = nil, stickyAllowed: Bool = true) -> LeaderMachine {
        var m = LeaderMachine(items: items ?? fixture, stickyAllowed: stickyAllowed)
        _ = m.handle(.leader)
        return m
    }

    @Test func stickyActionKeepsTheMenuOpen() {
        var m = opened()
        #expect(m.handle(.key("v")) == .runAndStay(volume))
        #expect(m.isOpen)
        #expect(m.path.isEmpty)
    }

    @Test func optionInvertsSticky() {
        var m = opened()
        #expect(m.handle(.key("v", option: true)) == .run(volume))
        #expect(!m.isOpen)
        m = opened()
        #expect(m.handle(.key("m", option: true)) == .runAndStay(mail))
        #expect(m.isOpen)
    }

    @Test func stickyNotAllowedAlwaysCloses() {
        var m = opened(stickyAllowed: false)
        #expect(m.handle(.key("v")) == .run(volume))
        #expect(!m.isOpen)
        m = opened(stickyAllowed: false)
        #expect(m.handle(.key("m", option: true)) == .run(mail))
    }

    @Test func batchGroupRunsItsActionsAndCloses() {
        var m = opened()
        #expect(m.handle(.key("b")) == .runBatch(group: batchDay, actions: [mail, notes]))
        #expect(!m.isOpen)
    }

    @Test func optionOnAGroupRunsABatchWithoutGroupsOrDynamicItems() {
        var m = opened()
        #expect(m.handle(.key("s", option: true)) == .runBatch(group: startDay, actions: [mail, notes]))
        #expect(!m.isOpen)
    }

    @Test func dynamicItemAsksForItsChildrenThenEntersThem() {
        var m = opened()
        #expect(m.handle(.key("p")) == .loadDynamic(processes))
        #expect(m.isOpen)
        #expect(m.path.isEmpty)
        let loaded: [Item] = [.shell("1", "kill 1", "kill 1")]
        #expect(m.enterLoaded(loaded, forKey: "p") == .show(path: ["p"]))
        #expect(m.currentItems == loaded)
        #expect(m.handle(.key("1")) == .run(loaded[0]))
    }

    @Test func backFromALoadedLevelForgetsIt() {
        var m = opened()
        _ = m.handle(.key("p"))
        _ = m.enterLoaded([notes], forKey: "p")
        #expect(m.handle(.back) == .show(path: []))
        #expect(m.currentItems == fixture)
        #expect(m.handle(.key("p")) == .loadDynamic(processes))
    }

    @Test func enterLoadedNeedsADynamicItemOfTheCurrentLevel() {
        var m = opened()
        #expect(m.enterLoaded([notes], forKey: "m") == .none)
        #expect(m.enterLoaded([notes], forKey: "z") == .none)
        var closed = LeaderMachine(items: fixture)
        #expect(closed.enterLoaded([notes], forKey: "p") == .none)
    }

    @Test func upPopsButNeverCloses() {
        var m = opened()
        #expect(m.handle(.up) == .none)
        #expect(m.isOpen)
        _ = m.handle(.key("s"))
        _ = m.handle(.key("x"))
        #expect(m.handle(.up) == .show(path: ["s"]))
        #expect(m.handle(.up) == .show(path: []))
        #expect(m.handle(.up) == .none)
        #expect(m.isOpen)
    }

    @Test func openAtAGroupPath() {
        var m = LeaderMachine(items: fixture)
        #expect(m.open(at: ["s", "x"]) == .show(path: ["s", "x"]))
        #expect(m.isOpen)
        #expect(m.currentItems == [notes])
        #expect(m.handle(.key("n")) == .run(notes))
    }

    @Test func openAtAnActionRunsItAndStaysClosed() {
        var m = LeaderMachine(items: fixture)
        #expect(m.open(at: ["s", "m"]) == .run(mail))
        #expect(!m.isOpen)
        #expect(m.open(at: ["m"]) == .run(mail))
    }

    @Test func openAtAMissingPathDoesNothing() {
        var m = LeaderMachine(items: fixture)
        #expect(m.open(at: []) == .none)
        #expect(m.open(at: ["s", "q"]) == .none)
        #expect(m.open(at: ["m", "x"]) == .none)
        #expect(!m.isOpen)
    }

    @Test func resumingAtLevelsAnswersLikeTheMachineThatGotThere() {
        let loaded: [Item] = [.shell("1", "kill 1", "kill 1")]
        var resumed = LeaderMachine(items: fixture, openAt: ["p"], levels: [loaded])
        #expect(resumed.isOpen)
        #expect(resumed.currentItems == loaded)
        #expect(resumed.handle(.key("1")) == .run(loaded[0]))

        var nested = LeaderMachine(items: fixture, openAt: ["s", "x"], levels: [startDay.children!, [notes]])
        #expect(nested.handle(.back) == .show(path: ["s"]))
        #expect(nested.handle(.key("m")) == .run(mail))
    }

    @Test func replacingItemsForgetsLoadedLevels() {
        var m = opened()
        _ = m.handle(.key("p"))
        _ = m.enterLoaded([notes], forKey: "p")
        m.items = [mail]
        #expect(m.handle(.key("m")) == .run(mail))
    }
}
