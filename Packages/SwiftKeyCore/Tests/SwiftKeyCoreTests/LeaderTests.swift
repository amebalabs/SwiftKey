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
