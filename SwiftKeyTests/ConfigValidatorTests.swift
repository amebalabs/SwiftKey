import Testing
import Foundation
import SwiftKeyCore
@testable import SwiftKey

@Suite("Configuration Validation")
struct ConfigValidatorTests {

    let validator = ConfigValidator()

    // MARK: - Key Validation

    @Test("Empty key produces validation error")
    func emptyKeyValidation() {
        let item = MenuItem(
            id: UUID(),
            key: "",
            icon: nil,
            title: "Test",
            action: "open://https://example.com",
            sticky: false,
            notify: false,
            batch: false,
            hidden: false,
            submenu: nil,
            hotkey: nil
        )
        let issues = validator.validate(item)

        #expect(issues.contains { $0.type == .emptyKey })
        #expect(issues.contains { $0.severity == .error })
    }

    @Test("Multi-character key produces validation error")
    func multiCharacterKeyValidation() {
        let item = MenuItem(
            id: UUID(),
            key: "abc",
            icon: nil,
            title: "Test",
            action: "open://https://example.com",
            sticky: false,
            notify: false,
            batch: false,
            hidden: false,
            submenu: nil,
            hotkey: nil
        )
        let issues = validator.validate(item)

        #expect(issues.contains { $0.type == .invalidKey })
    }

    @Test("Valid single character key produces no key errors")
    func validKeyNoErrors() {
        let item = MenuItem(
            id: UUID(),
            key: "a",
            icon: nil,
            title: "Test",
            action: "open://https://example.com",
            sticky: false,
            notify: false,
            batch: false,
            hidden: false,
            submenu: nil,
            hotkey: nil
        )
        let issues = validator.validate(item)

        #expect(!issues.contains { $0.type == .emptyKey || $0.type == .invalidKey })
    }

    // MARK: - Title Validation

    @Test("Empty title produces validation error")
    func emptyTitleValidation() {
        let item = MenuItem(
            id: UUID(),
            key: "a",
            icon: nil,
            title: "   ",
            action: "open://https://example.com",
            sticky: false,
            notify: false,
            batch: false,
            hidden: false,
            submenu: nil,
            hotkey: nil
        )
        let issues = validator.validate(item)

        #expect(issues.contains { $0.type == .emptyTitle })
    }

    // MARK: - Action Validation

    @Test("Missing action without submenu produces warning")
    func missingActionWarning() {
        let item = MenuItem(
            id: UUID(),
            key: "a",
            icon: nil,
            title: "Test",
            action: nil,
            sticky: false,
            notify: false,
            batch: false,
            hidden: false,
            submenu: nil,
            hotkey: nil
        )
        let issues = validator.validate(item)

        #expect(issues.contains { $0.type == .missingAction && $0.severity == .warning })
    }

    @Test("Item with submenu but no action is valid")
    func submenuWithoutActionIsValid() {
        let submenuItem = MenuItem(
            id: UUID(),
            key: "x",
            icon: nil,
            title: "Sub Item",
            action: "open://https://example.com",
            sticky: false,
            notify: false,
            batch: false,
            hidden: false,
            submenu: nil,
            hotkey: nil
        )
        let item = MenuItem(
            id: UUID(),
            key: "a",
            icon: nil,
            title: "Parent",
            action: nil,
            sticky: false,
            notify: false,
            batch: false,
            hidden: false,
            submenu: [submenuItem],
            hotkey: nil
        )
        let issues = validator.validate(item)

        #expect(!issues.contains { $0.type == .missingAction && $0.itemId == item.id })
    }

    @Test("Empty open URL produces error")
    func emptyOpenURLError() {
        let item = MenuItem(
            id: UUID(),
            key: "a",
            icon: nil,
            title: "Test",
            action: "open://",
            sticky: false,
            notify: false,
            batch: false,
            hidden: false,
            submenu: nil,
            hotkey: nil
        )
        let issues = validator.validate(item)

        #expect(issues.contains { $0.type == .invalidURL && $0.severity == .error })
    }

    @Test("Empty shell command produces error")
    func emptyShellCommandError() {
        let item = MenuItem(
            id: UUID(),
            key: "a",
            icon: nil,
            title: "Test",
            action: "shell://   ",
            sticky: false,
            notify: false,
            batch: false,
            hidden: false,
            submenu: nil,
            hotkey: nil
        )
        let issues = validator.validate(item)

        #expect(issues.contains { $0.type == .dangerousCommand && $0.severity == .error })
    }

    @Test("Shell commands are not judged by patterns: approval guards them")
    func shellCommandsHaveNoPatternWarnings() {
        let commands = [
            "shell://rm -rf ~/Downloads/old",
            "shell://sudo reboot",
            "shell://dd if=/dev/zero of=/tmp/zeros bs=1k count=1"
        ]

        for command in commands {
            let issues = validator.validate(MenuItem(key: "a", title: "Test", action: command))
            #expect(!issues.contains { $0.type == .dangerousCommand }, "Unexpected issue for: \(command)")
        }
    }

    @Test("Unbalanced quotes in a shell command produce a warning")
    func unbalancedQuotesWarning() {
        let issues = validator.validate(MenuItem(key: "a", title: "Test", action: "shell://echo 'hi"))

        #expect(issues.contains { $0.type == .dangerousCommand && $0.severity == .warning })
        #expect(!issues.contains { $0.severity == .error })
    }

    @Test("Named keys and single characters are valid", arguments: ["space", "return", "f1", "f13", "f20", "Space", "F5", " ", "ф", "§"])
    func namedKeysAreValid(_ key: String) {
        let issues = validator.validate(MenuItem(key: key, title: "Test", action: "open://https://example.com"))

        #expect(!issues.contains { $0.type == .invalidKey })
    }

    @Test("Unknown multi-character keys are invalid", arguments: ["ab", "f21", "tab"])
    func unknownKeysAreInvalid(_ key: String) {
        let issues = validator.validate(MenuItem(key: key, title: "Test", action: "open://https://example.com"))

        #expect(issues.contains { $0.type == .invalidKey })
    }

    // MARK: - Hierarchy Validation

    @Test("Duplicate keys at same level produce errors")
    func duplicateKeyValidation() {
        let items = [
            MenuItem(
                id: UUID(),
                key: "a",
                icon: nil,
                title: "First",
                action: "open://https://example.com",
                sticky: false,
                notify: false,
                batch: false,
                hidden: false,
                submenu: nil,
                hotkey: nil
            ),
            MenuItem(
                id: UUID(),
                key: "a",
                icon: nil,
                title: "Second",
                action: "open://https://example.com",
                sticky: false,
                notify: false,
                batch: false,
                hidden: false,
                submenu: nil,
                hotkey: nil
            )
        ]
        let issues = validator.validateHierarchy(items)

        #expect(issues.contains { $0.type == .duplicateKey })
    }

    @Test("Same keys at different levels are allowed")
    func sameKeysAtDifferentLevelsAllowed() {
        let submenuItem = MenuItem(
            id: UUID(),
            key: "a",
            icon: nil,
            title: "Sub Item",
            action: "open://https://example.com",
            sticky: false,
            notify: false,
            batch: false,
            hidden: false,
            submenu: nil,
            hotkey: nil
        )
        let items = [
            MenuItem(
                id: UUID(),
                key: "a",
                icon: nil,
                title: "Parent",
                action: nil,
                sticky: false,
                notify: false,
                batch: false,
                hidden: false,
                submenu: [submenuItem],
                hotkey: nil
            )
        ]
        let issues = validator.validateHierarchy(items)

        #expect(!issues.contains { $0.type == .duplicateKey })
    }

    // MARK: - Valid Configuration

    @Test("Valid menu item produces no errors")
    func validItemNoErrors() {
        let item = MenuItem(
            id: UUID(),
            key: "a",
            icon: "safari",
            title: "Open Browser",
            action: "open://https://example.com",
            sticky: false,
            notify: false,
            batch: false,
            hidden: false,
            submenu: nil,
            hotkey: nil
        )
        let issues = validator.validate(item)

        #expect(validator.errors(from: issues).isEmpty)
    }

    @Test("isValid returns true for valid configuration")
    func isValidForValidConfig() {
        let items = [
            MenuItem(
                id: UUID(),
                key: "a",
                icon: nil,
                title: "First",
                action: "open://https://example.com",
                sticky: false,
                notify: false,
                batch: false,
                hidden: false,
                submenu: nil,
                hotkey: nil
            ),
            MenuItem(
                id: UUID(),
                key: "b",
                icon: nil,
                title: "Second",
                action: "shell://echo hello",
                sticky: false,
                notify: false,
                batch: false,
                hidden: false,
                submenu: nil,
                hotkey: nil
            )
        ]

        #expect(validator.isValid(items))
    }

    @Test("isValid returns false for invalid configuration")
    func isValidForInvalidConfig() {
        let items = [
            MenuItem(
                id: UUID(),
                key: "",
                icon: nil,
                title: "Missing Key",
                action: "open://https://example.com",
                sticky: false,
                notify: false,
                batch: false,
                hidden: false,
                submenu: nil,
                hotkey: nil
            )
        ]

        #expect(!validator.isValid(items))
    }
}

@Suite("Micro-app action validation")
struct MicroAppActionValidationTests {
    private let catalog = MicroAppCatalog.load([
        ("upper.yaml", "format: ting.microapp/2\ndescription: Upper.\ninput: clipboard\ncommand: tr a-z A-Z\n"),
        ("bad.yaml", "format: nope\n"),
    ])

    private func issues(_ action: String) -> [ValidationIssue] {
        ConfigValidator(microApps: catalog, microFolder: "~/micro")
            .validate(MenuItem(key: "m", title: "Micro", action: action))
    }

    @Test("A loaded micro-app is valid")
    func working() {
        #expect(issues("micro://upper").isEmpty)
    }

    @Test("An empty id is an error")
    func emptyID() {
        #expect(issues("micro:// ").map(\.severity) == [.error])
    }

    @Test("A micro-app that is not in the folder is a warning naming the id and the folder")
    func missing() {
        let found = issues("micro://nothing")
        #expect(found.map(\.severity) == [.warning])
        #expect(found.first?.message == "Micro-app `nothing` not found in ~/micro")
    }

    @Test("A broken file is a warning with its first error")
    func broken() {
        let found = issues("micro://bad")
        #expect(found.map(\.severity) == [.warning])
        #expect(found.first?.message.hasPrefix("Micro-app bad.yaml, line 1:") == true)
    }

    @Test("Without a catalog only the id's form is checked")
    func withoutCatalog() {
        #expect(ConfigValidator().validate(MenuItem(key: "m", title: "Micro", action: "micro://nothing")).isEmpty)
    }
}
