import XCTest
@testable import SwiftKeyCore

final class MicroAppRunTests: XCTestCase {
    private func param(_ name: String, required: Bool = true, defaultValue: String? = nil) -> MicroApp.Param {
        MicroApp.Param(name: name, kind: .text, required: required, defaultValue: defaultValue)
    }

    func testEnvironmentSetsPATHAndParamVariables() {
        let base = ["HOME": "/Users/x", "PATH": "/usr/bin", "TING_OLD": "stray", "LANG": "en_US.UTF-8",
                    "LC_ALL": "C", "LC_CTYPE": "UTF-8", "TERM": "xterm"]
        let env = MicroAppRunRules.environment(
            base: base, path: "/opt/bin:/usr/bin",
            params: [param("domain"), param("record_type", required: false, defaultValue: "A"), param("note")],
            values: ["domain": "example.com", "unknown": "x"])
        XCTAssertEqual(env, ["HOME": "/Users/x", "PATH": "/opt/bin:/usr/bin", "TERM": "xterm",
                             "TING_DOMAIN": "example.com", "TING_RECORD_TYPE": "A", "TING_NOTE": ""])
    }

    func testAppendCutsAtTheLimit() {
        var buffer = Data()
        XCTAssertFalse(MicroAppRunRules.append(Data(repeating: 1, count: 6), to: &buffer, limit: 10))
        XCTAssertFalse(MicroAppRunRules.append(Data(repeating: 2, count: 4), to: &buffer, limit: 10))
        XCTAssertEqual(buffer.count, 10)
        XCTAssertTrue(MicroAppRunRules.append(Data(repeating: 3, count: 1), to: &buffer, limit: 10))
        XCTAssertEqual(buffer.count, 10)

        var other = Data()
        XCTAssertTrue(MicroAppRunRules.append(Data(repeating: 1, count: 15), to: &other, limit: 10))
        XCTAssertEqual(other, Data(repeating: 1, count: 10))
        XCTAssertEqual(MicroAppRunRules.outputLimit, 1_048_576)
    }

    func testCutTextDropsASplitCharacter() {
        let full = Data("aé€😀".utf8) // 1 + 2 + 3 + 4 bytes
        XCTAssertEqual(MicroAppRunRules.text(full, cut: true), "aé€😀")
        XCTAssertEqual(MicroAppRunRules.text(full.prefix(9), cut: true), "aé€")
        XCTAssertEqual(MicroAppRunRules.text(full.prefix(7), cut: true), "aé€")
        XCTAssertEqual(MicroAppRunRules.text(full.prefix(5), cut: true), "aé")
        XCTAssertEqual(MicroAppRunRules.text(full.prefix(2), cut: true), "a")
        XCTAssertEqual(MicroAppRunRules.text(full.prefix(5), cut: false), "aé\u{FFFD}")
    }

    func testRemovingEndNewlines() {
        XCTAssertEqual(MicroAppRunRules.removingEndNewlines("a\nb\n\n"), "a\nb")
        XCTAssertEqual(MicroAppRunRules.removingEndNewlines("line\r\n"), "line")
        XCTAssertEqual(MicroAppRunRules.removingEndNewlines("  text  \n"), "  text  ")
        XCTAssertEqual(MicroAppRunRules.removingEndNewlines("\n\n"), "")
        XCTAssertEqual(MicroAppRunRules.removingEndNewlines("\nkeep"), "\nkeep")
    }

    func testPATHDirectoriesAndFallback() {
        XCTAssertEqual(MicroAppRunRules.directories(ofPATH: "/a::/b:/a:"), ["/a", "/b"])
        XCTAssertEqual(MicroAppRunRules.fallbackPATH(tingPATH: "/usr/bin:/usr/local/bin"),
                       "/usr/bin:/usr/local/bin:/opt/homebrew/bin")
        XCTAssertEqual(MicroAppRunRules.fallbackPATH(tingPATH: nil),
                       "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin")
        XCTAssertEqual(MicroAppRunRules.fallbackPATH(tingPATH: ""), MicroAppRunRules.fallbackPATH(tingPATH: nil))
    }

    func testPATHFromShellOutput() {
        let b = MicroAppRunRules.pathBeginMarker, e = MicroAppRunRules.pathEndMarker
        XCTAssertEqual(MicroAppRunRules.pathFromShellOutput("Welcome!\n\(b)\n/x/bin:/usr/bin\n\(e)\nbye\n"), "/x/bin:/usr/bin")
        XCTAssertNil(MicroAppRunRules.pathFromShellOutput("/x/bin:/usr/bin\n"))
        XCTAssertNil(MicroAppRunRules.pathFromShellOutput("\(b)\n\(e)\n"))
        XCTAssertNil(MicroAppRunRules.pathFromShellOutput("\(b)\n/x/bin\n"))
        XCTAssertEqual(MicroAppRunRules.pathShellArguments.prefix(3), ["-l", "-i", "-c"])
    }
}
