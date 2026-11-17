import Carbon
import SwiftKeyCore
import XCTest
@testable import SwiftKey

final class LegacyHotkeyMigrationTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "com.ameba.SwiftKey.tests.migration-" + UUID().uuidString
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    /// The JSON the KeyboardShortcuts library wrote: ⇧⌘F is key code 3 with cmdKey | shiftKey.
    func testMovesTheOldHotkeyIntoTheSetting() {
        defaults.set(#"{"carbonKeyCode":3,"carbonModifiers":768}"#, forKey: LegacyHotkeyMigration.legacyKey)
        LegacyHotkeyMigration.migrate(defaults)
        XCTAssertEqual(defaults.string(forKey: SettingsStore.mainHotkeyKey), "shift+cmd+f")
        // The old value stays for a downgrade.
        XCTAssertNotNil(defaults.object(forKey: LegacyHotkeyMigration.legacyKey))
    }

    func testAllFourModifiers() {
        let modifiers = cmdKey | shiftKey | optionKey | controlKey
        defaults.set(#"{"carbonKeyCode":105,"carbonModifiers":\#(modifiers)}"#, forKey: LegacyHotkeyMigration.legacyKey)
        LegacyHotkeyMigration.migrate(defaults)
        XCTAssertEqual(defaults.string(forKey: SettingsStore.mainHotkeyKey), "ctrl+option+shift+cmd+f13")
    }

    func testRunsOnceAndKeepsAClearedHotkeyCleared() {
        defaults.set(#"{"carbonKeyCode":3,"carbonModifiers":768}"#, forKey: LegacyHotkeyMigration.legacyKey)
        LegacyHotkeyMigration.migrate(defaults)
        defaults.set("", forKey: SettingsStore.mainHotkeyKey)
        LegacyHotkeyMigration.migrate(defaults)
        XCTAssertEqual(defaults.string(forKey: SettingsStore.mainHotkeyKey), "")
    }

    func testDoesNotReplaceAHotkeyThatIsAlreadySet() {
        defaults.set("home", forKey: SettingsStore.mainHotkeyKey)
        defaults.set(#"{"carbonKeyCode":3,"carbonModifiers":768}"#, forKey: LegacyHotkeyMigration.legacyKey)
        LegacyHotkeyMigration.migrate(defaults)
        XCTAssertEqual(defaults.string(forKey: SettingsStore.mainHotkeyKey), "home")
    }

    func testTurnedOffMissingOrBrokenValuesSetNothing() {
        for value: Any? in [false, nil, "not json", #"{"carbonKeyCode":58,"carbonModifiers":0}"#] {
            XCTAssertNil(LegacyHotkeyMigration.hotkey(fromLegacy: value), String(describing: value))
        }
        defaults.set(false, forKey: LegacyHotkeyMigration.legacyKey)
        LegacyHotkeyMigration.migrate(defaults)
        XCTAssertNil(defaults.string(forKey: SettingsStore.mainHotkeyKey))
        XCTAssertTrue(defaults.bool(forKey: LegacyHotkeyMigration.doneKey))
    }

    func testABareKeyIsKept() {
        XCTAssertEqual(LegacyHotkeyMigration.hotkey(fromLegacy: #"{"carbonKeyCode":115,"carbonModifiers":0}"#)?.string, "home")
    }
}

final class HotkeyRulesTests: XCTestCase {
    func testValidHotkeys() {
        for text in ["cmd+shift+a", "ctrl+alt+p", "cmd+f12", "shift+space", "f13", "home", "option+command+k"] {
            XCTAssertNil(HotkeyRules.problem(text), text)
        }
    }

    func testInvalidHotkeys() {
        XCTAssertNotNil(HotkeyRules.problem("hyper+a"))
        XCTAssertNotNil(HotkeyRules.problem("cmd+a+b"))
        XCTAssertNotNil(HotkeyRules.problem(""))
        XCTAssertTrue(HotkeyRules.problem("right-option")?.contains("modifier alone") == true)
    }

    func testConflictsWithEachOtherAndTheMainHotkey() {
        let a = MenuItem(key: "a", title: "A", action: "shell://true", hotkey: "cmd+shift+a")
        let b = MenuItem(key: "b", title: "B", action: "shell://true", hotkey: "shift+cmd+a")
        let c = MenuItem(key: "c", title: "C", action: "shell://true", hotkey: "f13")
        let d = MenuItem(key: "d", title: "D", action: "shell://true", hotkey: "f14")
        let group = MenuItem(key: "g", title: "G", submenu: [b, c])
        let conflicts = HotkeyRules.conflicts(in: [a, group, d], mainHotkey: Hotkey(string: "f13"))
        XCTAssertEqual(Set(conflicts.keys), [a.id, b.id, c.id])
        XCTAssertTrue(conflicts[a.id]?.contains("'B'") == true)
        XCTAssertTrue(conflicts[c.id]?.contains("SwiftKey hotkey") == true)
    }

    func testValidatorReportsHotkeyProblemsAndConflicts() {
        let validator = ConfigValidator()
        let bad = MenuItem(key: "a", title: "A", action: "shell://true", hotkey: "hyper+a")
        XCTAssertTrue(validator.validate(bad).contains { $0.type == .invalidHotkey && $0.severity == .error })
        let one = MenuItem(key: "a", title: "A", action: "shell://true", hotkey: "f15")
        let two = MenuItem(key: "b", title: "B", action: "shell://true", hotkey: "f15")
        let issues = validator.validateHotkeyConflicts([one, two], mainHotkey: nil)
        XCTAssertEqual(Set(issues.compactMap(\.itemId)), [one.id, two.id])
    }
}

@MainActor
final class HotkeyServiceTests: XCTestCase {
    /// Unusual combinations, held only for the moment of a test, so the tests never take a key the
    /// person uses; not ⌃⌥⇧⌘F18 or F19, which the UI tests press.
    private let unusual = Hotkey(string: "ctrl+option+shift+cmd+f17")!
    private let otherUnusual = Hotkey(string: "ctrl+option+shift+cmd+f16")!

    func testRegistersRefusesDuplicatesPausesAndResumes() {
        let service = HotkeyService()
        var released: [HotkeyService.Slot] = []
        service.onRelease = { released.append($0) }
        defer {
            service.activate(nil, for: .main)
            service.activate(nil, for: .launcha)
        }

        service.activate(unusual, for: .main)
        XCTAssertEqual(service.status(.main), .active)

        service.activate(unusual, for: .launcha)
        XCTAssertEqual(service.status(.launcha), .failed("⌃⌥⇧⌘F17 is already used for the SwiftKey hotkey."))

        service.pause()
        XCTAssertEqual(service.status(.main), .inactive)
        XCTAssertEqual(released, [.main])
        service.resume()
        XCTAssertEqual(service.status(.main), .active)

        service.activate(nil, for: .main)
        XCTAssertEqual(service.status(.main), .inactive)
        XCTAssertNil(service.hotkey(.main))
    }

    func testAModifierAloneFails() {
        let service = HotkeyService()
        defer { service.activate(nil, for: .main) }
        service.activate(.modifierTap(.rightOption), for: .main)
        guard case .failed(let reason) = service.status(.main) else { return XCTFail("expected a failure") }
        XCTAssertTrue(reason.contains("not a modifier"))
    }

    func testItemSlotsAreRemovedWhenTheirItemIsGone() {
        let service = HotkeyService()
        defer { service.deactivateItems(except: []) }
        let kept = UUID(), gone = UUID()
        service.activate(unusual, for: .item(kept))
        service.activate(otherUnusual, for: .item(gone))
        service.deactivateItems(except: [kept])
        XCTAssertEqual(service.status(.item(kept)), .active)
        XCTAssertNil(service.hotkey(.item(gone)))
        service.deactivateItems(except: [])
        XCTAssertTrue(service.slots.isEmpty)
    }
}

@MainActor
final class HotkeyRecordingGateTests: XCTestCase {
    private final class Owner: HotkeyRecordingOwner {
        var cancelled = 0
        func cancel() { cancelled += 1 }
    }

    func testOneRecordingAtATime() {
        var changes: [Bool] = []
        let gate = HotkeyRecordingGate { changes.append($0) }
        let first = Owner(), second = Owner()
        gate.begin(first)
        XCTAssertEqual(changes, [true])
        gate.begin(second)
        XCTAssertEqual(first.cancelled, 1)
        XCTAssertEqual(changes, [true])
        // A late end from the cancelled owner keeps the hotkeys off.
        gate.end(first)
        XCTAssertTrue(gate.isActive)
        gate.end(second)
        XCTAssertEqual(changes, [true, false])
        XCTAssertFalse(gate.isActive)
    }
}

@MainActor
final class DelayedRevealTests: XCTestCase {
    func testNoDelayRevealsAtOnce() {
        let reveal = DelayedReveal()
        var shown = false
        reveal.start(after: 0) { shown = true }
        XCTAssertTrue(shown)
        XCTAssertFalse(reveal.isPending)
    }

    func testRevealsAfterTheDelay() {
        let reveal = DelayedReveal()
        let shown = expectation(description: "revealed")
        reveal.start(after: 0.05) { shown.fulfill() }
        XCTAssertTrue(reveal.isPending)
        wait(for: [shown], timeout: 2)
        XCTAssertFalse(reveal.isPending)
    }

    func testAMenuThatClosesFirstIsNeverShown() {
        let reveal = DelayedReveal()
        var shown = false
        reveal.start(after: 0.05) { shown = true }
        reveal.cancel()
        let waited = expectation(description: "waited past the delay")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { waited.fulfill() }
        wait(for: [waited], timeout: 2)
        XCTAssertFalse(shown)
        XCTAssertFalse(reveal.isPending)
    }
}
