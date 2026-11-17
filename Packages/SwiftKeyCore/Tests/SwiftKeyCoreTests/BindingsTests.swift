import Testing
@testable import SwiftKeyCore

@Suite struct BindingTreeTests {
    private var terminal: Item { .app("t", "Terminal", "com.apple.Terminal") }
    private var fixture: [Item] { [.group("a", "Apps", [.group("b", "Nested", [.app("s", "Safari", "com.apple.Safari")]), terminal]), .url("w", "Web", "https://example.com")] }

    @Test func lookupAndFlatten() {
        #expect(BindingTree.item(at: [], in: fixture) == nil)
        #expect(BindingTree.item(at: ["missing"], in: fixture) == nil)
        #expect(BindingTree.item(at: ["w", "x"], in: fixture) == nil)
        #expect(BindingTree.item(at: ["a", "t"], in: fixture) == terminal)
        let rows = BindingTree.flatten(fixture)
        #expect(rows.map(\.sequence) == [["a"], ["a", "b"], ["a", "b", "s"], ["a", "t"], ["w"]])
        for row in rows { #expect(BindingTree.item(at: row.sequence, in: fixture) == row.item) }
        #expect(BindingTree.flatten([]).isEmpty)
    }
    @Test func problemsAndCheckOrder() {
        #expect(BindingTree.problem(placing: [], moving: ["a"], in: fixture) == .empty)
        #expect(BindingTree.problem(placing: ["a", "tab"], moving: ["a"], in: fixture) == .invalidKey("tab"))
        #expect(BindingTree.problem(placing: ["a", "t", "x"], moving: ["a"], in: fixture) == .insideItself)
        #expect(BindingTree.problem(placing: ["a", "t", "x"], moving: nil, in: fixture) == .prefixIsAction(prefix: ["a", "t"], label: "Terminal"))
        #expect(BindingTree.problem(placing: ["a", "t", "x", "tab"], moving: nil, in: fixture) == .invalidKey("tab"))
        #expect(BindingTree.problem(placing: ["w", "x", "y"], moving: nil, in: fixture) == .prefixIsAction(prefix: ["w"], label: "Web"))
        #expect(BindingTree.problem(placing: ["a", "t"], moving: nil, in: fixture) == .taken(label: "Terminal"))
        #expect(BindingTree.problem(placing: ["a"], moving: nil, in: fixture) == .taken(label: "Apps"))
        #expect(BindingTree.problem(placing: ["a", "t"], moving: ["a", "t"], in: fixture) == nil)
        #expect(BindingTree.problem(placing: ["z", "x"], moving: nil, in: fixture) == nil)
    }
    @Test func insertCreatesGroupsAndAppends() throws {
        var items = fixture
        try BindingTree.insert(terminal, at: ["space", "f2", "x"], in: &items)
        let expected = Item.group("space", "Group ␣", [.group("f2", "Group F2", [.app("x", "Terminal", "com.apple.Terminal")])])
        #expect(items == fixture + [expected])
        try BindingTree.insert(.url("z", "Link", "https://example.com"), at: ["a", "x"], in: &items)
        #expect(BindingTree.item(at: ["a"], in: items)?.children?.map(\.key) == ["b", "t", "x"])
    }
    @Test func insertErrors() {
        let cases: [([String], SequenceProblem)] = [([], .empty), (["tab"], .invalidKey("tab")), (["w", "x"], .prefixIsAction(prefix: ["w"], label: "Web")), (["a"], .taken(label: "Apps"))]
        for (path, error) in cases {
            var items = fixture
            #expect(throws: error) { try BindingTree.insert(terminal, at: path, in: &items) }
        }
    }
    @Test func moveBetweenGroupsAndPrune() throws {
        var items = fixture
        try BindingTree.move(from: ["a", "b", "s"], to: ["c", "x"], in: &items)
        #expect(BindingTree.item(at: ["a", "b"], in: items) == nil)
        #expect(BindingTree.item(at: ["a"], in: items)?.children == [terminal])
        #expect(items.map(\.key) == ["a", "w", "c"])
        #expect(BindingTree.item(at: ["c", "x"], in: items) == .app("x", "Safari", "com.apple.Safari"))
        try BindingTree.move(from: ["a", "t"], to: ["c", "t"], in: &items)
        #expect(items.map(\.key) == ["w", "c"])
        #expect(BindingTree.item(at: ["c"], in: items)?.children?.map(\.key) == ["x", "t"])
    }
    @Test func moveGroupAndSameSequence() throws {
        var items = fixture
        try BindingTree.move(from: ["a"], to: ["a"], in: &items)
        try BindingTree.move(from: ["a", "t"], to: ["a", "t"], in: &items)
        #expect(items == fixture)
        try BindingTree.move(from: ["a", "b"], to: ["z"], in: &items)
        #expect(items.last == .group("z", "Nested", [.app("s", "Safari", "com.apple.Safari")]))
        #expect(BindingTree.item(at: ["a"], in: items)?.children == [terminal])
    }
    @Test func failedMovesAreAtomic() {
        let cases: [([String], [String], SequenceProblem)] = [
            (["z"], ["x"], .notFound), (["a"], [], .empty),
            (["a"], ["tab"], .invalidKey("tab")),
            (["a"], ["a", "x"], .insideItself),
            (["a"], ["a", "b"], .insideItself),
            (["a", "t"], ["w"], .taken(label: "Web")),
            (["a", "t"], ["w", "x"], .prefixIsAction(prefix: ["w"], label: "Web"))]
        for (from, to, error) in cases {
            var items = fixture
            #expect(throws: error) { try BindingTree.move(from: from, to: to, in: &items) }
            #expect(items == fixture)
        }
    }
    @Test func removePrunesAllEmptyAncestors() throws {
        var items: [Item] = [.group("a", "A", [.group("b", "B", [terminal])]), .url("w", "Web", "https://example.com")]
        try BindingTree.remove(at: ["a", "b", "t"], in: &items)
        #expect(items == [.url("w", "Web", "https://example.com")])
        try BindingTree.remove(at: ["w"], in: &items)
        #expect(items.isEmpty)
        items = fixture
        try BindingTree.remove(at: ["a", "b"], in: &items)
        #expect(BindingTree.item(at: ["a"], in: items)?.children == [terminal])
    }
    @Test func terminalPrefixConversionQ2c() throws {
        var items = [terminal]
        #expect(BindingTree.problem(placing: ["t", "x"], moving: nil, in: items) == .prefixIsAction(prefix: ["t"], label: "Terminal"))
        try BindingTree.convertToGroup(at: ["t"], in: &items)
        #expect(items == [.group("t", "Terminal", [terminal])])
        #expect(BindingTree.item(at: ["t", "t"], in: items) == terminal)
        #expect(BindingTree.problem(placing: ["t", "x"], moving: nil, in: items) == nil)
        let before = items
        try BindingTree.convertToGroup(at: ["t"], in: &items)
        #expect(items == before)
        try BindingTree.insert(.url("x", "Example", "https://example.com"), at: ["t", "x"], in: &items)
        #expect(BindingTree.item(at: ["t"], in: items)?.children?.map(\.key) == ["t", "x"])
    }
    @Test func updatePreservesKey() throws {
        var items = fixture
        try BindingTree.update(at: ["a", "t"], in: &items) { item in
            item.key = "x"
            item.label = "Changed"
            item.action = .url("https://example.com")
        }
        #expect(BindingTree.item(at: ["a", "t"], in: items) == .url("t", "Changed", "https://example.com"))
        #expect(BindingTree.item(at: ["a", "x"], in: items) == nil)
    }
    @Test(arguments: [[], ["z"], ["a", "z"], ["w", "x"]] as [[String]])
    func notFound(_ path: [String]) {
        var items = fixture
        #expect(throws: SequenceProblem.notFound) { try BindingTree.remove(at: path, in: &items) }
        #expect(throws: SequenceProblem.notFound) { try BindingTree.convertToGroup(at: path, in: &items) }
        #expect(throws: SequenceProblem.notFound) { try BindingTree.update(at: path, in: &items) { $0.label = "Changed" } }
        #expect(items == fixture)
    }
}
