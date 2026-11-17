import AppKit
import SwiftUI
import XCTest
@testable import SwiftKey

/// The Accessibility window with an injected permission check. The window is built but never
/// shown, and System Settings is never opened.
@MainActor
final class AccessibilityWindowTests: XCTestCase {
    private final class Permission {
        var trusted = false
    }

    private func controller(_ permission: Permission, opened: @escaping (URL) -> Void = { _ in }) -> AccessibilityWindowController {
        _ = NSApplication.shared
        return AccessibilityWindowController(access: AccessibilityAccess(check: { permission.trusted }),
                                             appURL: URL(fileURLWithPath: "/System/Applications/Calculator.app"),
                                             openURL: opened, presentsWindow: false)
    }

    func testAccessReportsOnlyTheChangeToTrusted() {
        let permission = Permission()
        let access = AccessibilityAccess(check: { permission.trusted })
        XCTAssertFalse(access.isTrusted)
        XCTAssertFalse(access.refresh())
        permission.trusted = true
        XCTAssertTrue(access.refresh())
        XCTAssertTrue(access.isTrusted)
        XCTAssertFalse(access.refresh(), "a second refresh is no change")
        permission.trusted = false
        XCTAssertFalse(access.refresh())
        XCTAssertFalse(access.isTrusted)
    }

    func testTheWindowOpensOnlyWithoutAccessAndClosesWhenAccessComes() async throws {
        let permission = Permission()
        var opened: [URL] = []
        let window = controller(permission) { opened.append($0) }
        var granted = 0
        window.onGranted = { granted += 1 }

        permission.trusted = true
        window.show()
        XCTAssertFalse(window.isOpen, "SwiftKey has access: nothing to show")

        permission.trusted = false
        window.show()
        XCTAssertTrue(window.isOpen)
        window.openSettings()
        XCTAssertEqual(opened, [URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!])

        window.poll()
        XCTAssertEqual(granted, 0)
        permission.trusted = true
        window.poll()
        window.poll()
        XCTAssertEqual(granted, 1)
        XCTAssertTrue(window.access.isTrusted)
        try await Task.sleep(nanoseconds: 1_500_000_000)
        XCTAssertFalse(window.isOpen, "the window closes by itself a moment after access came")
    }

    func testTheGuideFitsItsWidthAndTheIconIsADragSource() throws {
        let permission = Permission()
        let view = AccessibilityGuideView(access: AccessibilityAccess(check: { permission.trusted }),
                                          appURL: URL(fileURLWithPath: "/System/Applications/Calculator.app"), onOpenSettings: {})
        let hosting = NSHostingView(rootView: view)
        let size = hosting.fittingSize
        XCTAssertEqual(size.width, AccessibilityGuideView.width)
        XCTAssertTrue((280...560).contains(size.height), "\(size)")

        let icon = AppIconDragView(url: URL(fileURLWithPath: "/System/Applications/Calculator.app"))
        XCTAssertFalse(icon.mouseDownCanMoveWindow)
        XCTAssertEqual(icon.toolTip, "Drag SwiftKey into the Accessibility list")
    }

    func testTheAppUsageTextForAppleEventsIsInTheBundle() {
        let text = Bundle.main.object(forInfoDictionaryKey: "NSAppleEventsUsageDescription") as? String
        XCTAssertTrue(text?.contains("Finder") == true, text ?? "missing")
    }
}
