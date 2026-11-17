import XCTest

/// End-to-end tests of the running app: real key presses, real windows and real files.
///
/// Every test starts SwiftKey with `SWIFTKEY_CONFIG` pointing to a config it writes in a new
/// temporary folder, so the person's config, micro-apps, approvals and settings are never read
/// or changed. Settings come from launch arguments, which every defaults suite of the app reads.
///
/// These tests press keys and take focus: run them only when nobody is typing on this Mac
/// (`mise run test-ui`).
final class SwiftKeyUITests: XCTestCase {
    /// ⌃⌥⇧⌘F19 opens the menu; ⌃⌥⇧⌘F18 opens launcha. Nobody uses these by hand.
    private let menuModifiers: XCUIElement.KeyModifierFlags = [.control, .option, .shift, .command]

    private var folder: URL!
    private var config: URL!
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("swiftkey-ui-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        config = folder.appendingPathComponent("config.yaml")
        try writeConfig()
        try writeMicroApp()

        app = XCUIApplication()
        app.launchEnvironment["SWIFTKEY_CONFIG"] = config.path
        app.launchArguments += [
            "-NeedsOnboarding", "NO",
            "-MainHotkey", "ctrl+option+shift+cmd+f19",
            "-LaunchaHotkey", "ctrl+option+shift+cmd+f18",
            "-ShowMenuDelay", "0.25",
            "-OverlayStyle", "Default",
        ]
        app.launch()
    }

    override func tearDownWithError() throws {
        app?.terminate()
        if let folder { try? FileManager.default.removeItem(at: folder) }
    }

    // MARK: - Fixtures

    /// A file in the temporary folder that a menu item creates with `touch`.
    private func marker(_ name: String) -> URL { folder.appendingPathComponent(name) }

    private func writeConfig() throws {
        let yaml = """
        - key: "g"
          title: "Group"
          submenu:
            - key: "t"
              title: "Touch file"
              action: "shell://'touch \(marker("touched").path)'"
            - key: "m"
              title: "Greet"
              action: "micro://greet"
        """
        try yaml.write(to: config, atomically: true, encoding: .utf8)
    }

    private func writeMicroApp() throws {
        let micro = URL(fileURLWithPath: config.path + ".micro", isDirectory: true)
        try FileManager.default.createDirectory(at: micro, withIntermediateDirectories: true)
        let yaml = """
        format: ting.microapp/2
        id: greet
        name: Greet
        description: Greet someone.
        params:
          - name: who
            type: text
            required: true
            prompt: Who
        input: none
        command: echo "Hello, $TING_WHO"
        output:
          to: [panel]
          as: text

        """
        try yaml.write(to: micro.appendingPathComponent("greet.yaml"), atomically: true, encoding: .utf8)
    }

    private func openMenu() {
        app.typeKey(.F19, modifierFlags: menuModifiers)
    }

    private func waitForFile(_ url: URL, timeout: TimeInterval = 10) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: url.path) { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return false
    }

    private var approveButton: XCUIElement { app.buttons["Approve and Run"] }

    // MARK: - Tests

    /// The menu opens with the main key; a sequence runs a command after its approval.
    func testMenuSequenceRunsACommandAfterApproval() {
        openMenu()
        XCTAssertTrue(app.staticTexts["Group"].waitForExistence(timeout: 5), "the menu did not open")
        app.typeKey("g", modifierFlags: [])
        XCTAssertTrue(app.staticTexts["Touch file"].waitForExistence(timeout: 5))
        app.typeKey("t", modifierFlags: [])
        XCTAssertTrue(approveButton.waitForExistence(timeout: 5), "no approval window")
        approveButton.click()
        XCTAssertTrue(waitForFile(marker("touched")), "the command did not run")
    }

    /// Keys typed faster than the delay run the item without the menu ever showing.
    func testFastTypingNeverShowsTheMenu() {
        openMenu()
        app.typeKey("g", modifierFlags: [])
        app.typeKey("t", modifierFlags: [])
        XCTAssertTrue(approveButton.waitForExistence(timeout: 5), "no approval window")
        XCTAssertFalse(app.staticTexts["Group"].exists, "the menu showed")
        XCTAssertFalse(app.staticTexts["Touch file"].exists, "the submenu showed")
        approveButton.click()
        XCTAssertTrue(waitForFile(marker("touched")))
    }

    /// Delete goes back one level; at the top level it closes the menu.
    func testDeleteGoesBack() {
        openMenu()
        app.typeKey("g", modifierFlags: [])
        XCTAssertTrue(app.staticTexts["Touch file"].waitForExistence(timeout: 5))
        app.typeKey(.delete, modifierFlags: [])
        XCTAssertTrue(app.staticTexts["Group"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Touch file"].exists)
        app.typeKey(.delete, modifierFlags: [])
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.staticTexts["Group"])
        wait(for: [gone], timeout: 5)
    }

    /// The approval window's default button is Cancel: Return declines, nothing runs.
    func testReturnInTheApprovalWindowCancels() {
        openMenu()
        app.typeKey("g", modifierFlags: [])
        app.typeKey("t", modifierFlags: [])
        XCTAssertTrue(approveButton.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Cancel"].exists)
        app.typeKey(.return, modifierFlags: [])
        let closed = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: approveButton)
        wait(for: [closed], timeout: 5)
        XCTAssertFalse(waitForFile(marker("touched"), timeout: 2), "Return approved the command")
    }

    /// launcha finds a menu item by its title and runs it like its keys.
    func testLaunchaSearchesAndRunsAMenuItem() {
        app.typeKey(.F18, modifierFlags: menuModifiers)
        let field = app.textFields.matching(NSPredicate(format: "placeholderValue == %@", "Search menu, apps and files")).firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "launcha did not open")
        field.typeText("Touch file")
        XCTAssertTrue(app.staticTexts["Touch file"].waitForExistence(timeout: 5), "no match")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(approveButton.waitForExistence(timeout: 5), "no approval window")
        approveButton.click()
        XCTAssertTrue(waitForFile(marker("touched")))
    }

    /// A micro-app asks for its parameter after approval and shows its result in the panel.
    func testMicroAppAsksForAParamAndShowsTheResult() {
        openMenu()
        app.typeKey("g", modifierFlags: [])
        app.typeKey("m", modifierFlags: [])
        XCTAssertTrue(approveButton.waitForExistence(timeout: 5), "no approval window")
        approveButton.click()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "no parameter form")
        field.typeText("World")
        app.typeKey(.return, modifierFlags: [])
        let result = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Hello, World")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 10), "no result in the panel")
    }
}
