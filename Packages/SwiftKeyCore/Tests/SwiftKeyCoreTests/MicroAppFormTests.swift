import Foundation
import Testing
@testable import SwiftKeyCore

private let dns = MicroApp(
    id: "dns-lookup", name: "DNS lookup", description: "Look up.", tools: [],
    params: [
        .init(name: "domain", kind: .text, required: true, prompt: "Domain"),
        .init(name: "tool", kind: .choice(["dig", "whois"]), required: false, defaultValue: "dig", prompt: "Tool"),
        .init(name: "record", kind: .choice(["A", "AAAA", "MX", "TXT"]), required: false, defaultValue: "A", prompt: "Record"),
    ],
    input: .none, command: "dig \"$TING_DOMAIN\" \"$TING_RECORD\" $TING_TOOL", output: .init(targets: [.panel]))

private let changeCase = MicroApp(
    id: "change-case", description: "Case.",
    params: [.init(name: "mode", kind: .choice(["upper", "lower", "title"]), required: false, defaultValue: "upper", prompt: "Case")],
    input: .clipboard, command: "echo $TING_MODE", output: .init(targets: [.clipboard]))

@Suite struct MicroAppFormStartTests {
    @Test func noMemoryGivesDefaultsAndHidesOptionalFields() {
        let form = MicroAppForm.start(dns, remembered: MicroAppRememberedValues())
        #expect(form.fields.map(\.value) == ["", "dig", "A"])
        #expect(form.fields.map(\.isRemembered) == [false, false, false])
        #expect(!form.optionalOpen)
        #expect(form.hasOptionalToggle)
        #expect(form.visibleIndexes == [0])
        #expect(form.fields.map { $0.param.shownPrompt } == ["Domain", "Tool", "Record"])
    }

    @Test func memoryFillsTheFieldsAndAChangedOptionalOpensThePart() {
        let memory = MicroAppRememberedValues(values: ["dns-lookup": ["domain": "example.com", "tool": "dig", "record": "MX"]])
        let form = MicroAppForm.start(dns, remembered: memory)
        #expect(form.fields.map(\.value) == ["example.com", "dig", "MX"])
        #expect(form.fields.map(\.isRemembered) == [true, true, true])
        #expect(form.optionalOpen)
        #expect(form.visibleIndexes == [0, 1, 2])
    }

    @Test func rememberedDefaultsKeepTheOptionalPartClosed() {
        let memory = MicroAppRememberedValues(values: ["dns-lookup": ["domain": "example.com", "tool": "dig", "record": "A"]])
        let form = MicroAppForm.start(dns, remembered: memory)
        #expect(form.fields[0].value == "example.com")
        #expect(!form.optionalOpen)
    }

    @Test func staleChoiceIsDroppedForTheDefault() {
        let memory = MicroAppRememberedValues(values: ["dns-lookup": ["domain": "a.org", "record": "SRV"]])
        let form = MicroAppForm.start(dns, remembered: memory)
        #expect(form.fields[2].value == "A")
        #expect(!form.fields[2].isRemembered)
        #expect(!form.optionalOpen)
    }

    @Test func staleRequiredChoiceFallsBackToTheFirstOption() {
        let param = MicroApp.Param(name: "mode", kind: .choice(["one", "two"]), required: true)
        #expect(MicroAppForm.startValue(of: param, remembered: "three") == ("one", false))
        #expect(MicroAppForm.startValue(of: param, remembered: nil) == ("one", false))
        #expect(MicroAppForm.startValue(of: param, remembered: "two") == ("two", true))
    }

    @Test func removedParameterIsIgnoredAndDroppedWhenSaved() {
        var memory = MicroAppRememberedValues(values: ["dns-lookup": ["domain": "a.org", "port": "53"]])
        let form = MicroAppForm.start(dns, remembered: memory)
        #expect(form.fields.map(\.param.name) == ["domain", "tool", "record"])
        #expect(form.values == ["domain": "a.org", "tool": "dig", "record": "A"])
        memory.remember(form.values.merging(["port": "53"]) { a, _ in a }, for: dns)
        #expect(memory.values["dns-lookup"] == ["domain": "a.org", "tool": "dig", "record": "A"])
    }

    @Test func rememberFalseGivesACleanFormAndSavesNothing() {
        var app = dns
        app.remember = false
        var memory = MicroAppRememberedValues(values: ["dns-lookup": ["domain": "a.org", "record": "MX"]])
        let form = MicroAppForm.start(app, remembered: memory)
        #expect(form.fields.map(\.value) == ["", "dig", "A"])
        #expect(!form.optionalOpen)
        memory.remember(["domain": "b.org"], for: app)
        #expect(memory.values["dns-lookup"] == nil)
    }

    @Test func allOptionalOpensAtOnceWithoutAToggle() {
        let form = MicroAppForm.start(changeCase, remembered: MicroAppRememberedValues())
        #expect(form.optionalOpen)
        #expect(!form.hasOptionalToggle)
        #expect(form.visibleIndexes == [0])
        #expect(form.isSingleChoiceList)
        #expect(form.values == ["mode": "upper"])
    }

    @Test func noParametersGiveNoPanel() {
        let app = MicroApp(id: "x", description: "X", input: .none, command: "true", output: .init(targets: [.panel]))
        let form = MicroAppForm.start(app, remembered: MicroAppRememberedValues())
        #expect(form.isEmpty)
        #expect(!form.optionalOpen)
        #expect(!form.isSingleChoiceList)
    }

    @Test func dnsIsNotASingleChoiceList() {
        #expect(!MicroAppForm.start(dns, remembered: MicroAppRememberedValues()).isSingleChoiceList)
    }
}

@Suite struct MicroAppFormEditTests {
    @Test func emptyRequiredTextIsMissing() {
        var form = MicroAppForm.start(dns, remembered: MicroAppRememberedValues())
        #expect(form.firstMissingRequired == 0)
        form.fields[0].value = "  "
        #expect(form.firstMissingRequired == 0)
        form.fields[0].value = "example.com"
        #expect(form.firstMissingRequired == nil)
    }

    @Test func optionalTextMadeEmptyGivesTheEmptyValue() {
        let app = MicroApp(id: "t", description: "T",
                           params: [.init(name: "sep", kind: .text, required: false, defaultValue: ",")],
                           input: .none, command: "echo $TING_SEP", output: .init(targets: [.panel]))
        var form = MicroAppForm.start(app, remembered: MicroAppRememberedValues())
        form.fields[0].value = ""
        #expect(form.firstMissingRequired == nil)
        #expect(form.values == ["sep": ""])
    }

    @Test func tabMovesBetweenVisibleFieldsOnly() {
        var form = MicroAppForm.start(dns, remembered: MicroAppRememberedValues())
        #expect(form.nextVisible(after: 0) == 0)
        form.optionalOpen = true
        #expect(form.nextVisible(after: 0) == 1)
        #expect(form.nextVisible(after: 2) == 0)
        #expect(form.nextVisible(after: 0, by: -1) == 2)
        form.optionalOpen = false
        #expect(form.nextVisible(after: 2) == 0)
    }
}

@Suite struct MicroAppRememberedValuesTests {
    @Test func roundTripsAsPlainText() throws {
        var memory = MicroAppRememberedValues()
        memory.remember(["domain": "example.com", "tool": "dig", "record": "MX"], for: dns)
        let data = memory.encoded()
        #expect(MicroAppRememberedValues.decode(data) == memory)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\"record\" : \"MX\""))
        #expect(text.hasSuffix("\n"))
    }

    @Test func unreadableFileGivesNoValues() {
        #expect(MicroAppRememberedValues.decode(Data("nope".utf8)) == MicroAppRememberedValues())
        #expect(MicroAppRememberedValues.decode(Data(#"{"version":99,"values":{}}"#.utf8)) == MicroAppRememberedValues())
    }
}

@Suite struct MicroAppChoiceFilterTests {
    let records = ["A", "AAAA", "MX", "TXT", "NS", "CNAME"]

    @Test func lettersFilterWithPrefixFirst() {
        #expect(MicroAppChoiceFilter.options(records, matching: "") == records)
        #expect(MicroAppChoiceFilter.options(records, matching: "m") == ["MX", "CNAME"])
        #expect(MicroAppChoiceFilter.options(records, matching: "x") == ["MX", "TXT"])
        #expect(MicroAppChoiceFilter.options(records, matching: "q").isEmpty)
    }

    @Test func markStaysWhileItMatches() {
        #expect(MicroAppChoiceFilter.mark("A", in: ["A", "AAAA", "CNAME"]) == "A")
        #expect(MicroAppChoiceFilter.mark("A", in: ["MX", "CNAME"]) == "MX")
        #expect(MicroAppChoiceFilter.mark("A", in: []) == nil)
    }

    @Test func arrowsMoveAndStopAtTheEnds() {
        #expect(MicroAppChoiceFilter.move("A", by: 1, in: records) == "AAAA")
        #expect(MicroAppChoiceFilter.move("A", by: -1, in: records) == "A")
        #expect(MicroAppChoiceFilter.move("CNAME", by: 1, in: records) == "CNAME")
        #expect(MicroAppChoiceFilter.move("A", by: 1, in: ["MX", "TXT"]) == "MX")
    }
}

private let interleaved = MicroApp(
    id: "mixed", description: "Mixed.",
    params: [
        .init(name: "a", kind: .text, required: true, prompt: "A"),
        .init(name: "b", kind: .choice(["x", "y"]), required: false, defaultValue: "x", prompt: "B"),
        .init(name: "c", kind: .text, required: true, prompt: "C"),
    ],
    input: .none, command: "echo $TING_A $TING_B $TING_C", output: .init(targets: [.panel]))

@Suite struct MicroAppFormReviewTests {
    @Test func interleavedFieldsStayInFileOrder() {
        var form = MicroAppForm.start(interleaved, remembered: MicroAppRememberedValues())
        #expect(form.visibleIndexes.map { form.fields[$0].param.shownPrompt } == ["A", "C"])
        form.optionalOpen = true
        #expect(form.visibleIndexes.map { form.fields[$0].param.shownPrompt } == ["A", "B", "C"])
        #expect(form.nextVisible(after: 0) == 1)
        #expect(form.nextVisible(after: 1) == 2)
    }

    @Test func choiceFilterWithNoMatchBlocksEnter() {
        let form = MicroAppForm.start(changeCase, remembered: MicroAppRememberedValues())
        #expect(form.firstBlocked() == nil)
        #expect(form.firstBlocked(queries: [0: "lo"]) == nil)
        let blocked = form.firstBlocked(queries: [0: "zzz"])
        #expect(blocked?.index == 0)
        #expect(blocked?.block == .noOption)
    }

    @Test func firstBlockedFollowsFileOrder() {
        var form = MicroAppForm.start(interleaved, remembered: MicroAppRememberedValues())
        form.fields[0].value = "ok"
        let blocked = form.firstBlocked(queries: [1: "q"])
        #expect(blocked?.index == 1)
        #expect(blocked?.block == .noOption)
        let empty = form.firstBlocked()
        #expect(empty?.index == 2)
        #expect(empty?.block == .emptyRequired)
    }

    @Test func tallFormScrollsInsideTheCap() {
        #expect(MicroAppFormLayout.maxFormHeight(panelHeight: 680) == 530)
        #expect(MicroAppFormLayout.maxFormHeight(panelHeight: 2000) == 530)
        #expect(MicroAppFormLayout.maxFormHeight(panelHeight: 200) == 80)
        #expect(MicroAppFormLayout.formHeight(content: 300, panelHeight: 680) == 300)
        #expect(!MicroAppFormLayout.scrolls(content: 300, panelHeight: 680))
        #expect(MicroAppFormLayout.formHeight(content: 2400, panelHeight: 680) == 530)
        #expect(MicroAppFormLayout.scrolls(content: 2400, panelHeight: 680))
    }
}
