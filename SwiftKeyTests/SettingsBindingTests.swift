import Combine
import SwiftUI
import XCTest
@testable import SwiftKey

/// Settings controls must write through `SettingsStore`'s properties: their `didSet` publishes
/// `settingsChanged`, which re-registers hotkeys and switches the overlay style. The `@AppStorage`
/// projected binding (`settings.$overlayStyle`) writes the stored value directly and skips `didSet`.
final class SettingsBindingTests: XCTestCase {
    private var changes: AnyCancellable?

    /// A binding the way a view gets it from `$settings.property`: through the key path.
    private func binding<Value>(_ settings: SettingsStore, _ keyPath: ReferenceWritableKeyPath<SettingsStore, Value>) -> Binding<Value> {
        Binding(get: { settings[keyPath: keyPath] }, set: { settings[keyPath: keyPath] = $0 })
    }

    private func assertPublishes(_ settings: SettingsStore, file: StaticString = #filePath, line: UInt = #line,
                                 _ change: () -> Void) {
        var count = 0
        changes = settings.settingsChanged.sink { count += 1 }
        change()
        XCTAssertGreaterThan(count, 0, "settingsChanged was not published", file: file, line: line)
        changes = nil
    }

    func testKeyPathBindingsPublishEveryWatchedSetting() {
        let settings = SettingsStore()
        let style = settings.overlayStyle
        let screen = settings.overlayScreenOption
        let hotkey = settings.mainHotkey
        let launchaHotkey = settings.launchaHotkey
        defer {
            settings.overlayStyle = style
            settings.overlayScreenOption = screen
            settings.mainHotkey = hotkey
            settings.launchaHotkey = launchaHotkey
        }

        for target in SettingsStore.OverlayStyle.allCases where target != settings.overlayStyle {
            assertPublishes(settings) { binding(settings, \.overlayStyle).wrappedValue = target }
            XCTAssertEqual(settings.overlayStyle, target)
        }
        assertPublishes(settings) {
            binding(settings, \.overlayScreenOption).wrappedValue = screen == .primary ? .mouse : .primary
        }
        assertPublishes(settings) { binding(settings, \.mainHotkey).wrappedValue = "ctrl+option+shift+cmd+f14" }
        assertPublishes(settings) { binding(settings, \.launchaHotkey).wrappedValue = "ctrl+option+shift+cmd+f13" }
        assertPublishes(settings) { binding(settings, \.triggerKeyHoldMode).wrappedValue.toggle() }
        assertPublishes(settings) { binding(settings, \.useHorizontalOverlayLayout).wrappedValue.toggle() }
        assertPublishes(settings) { binding(settings, \.launchaDoubleTap).wrappedValue.toggle() }
        assertPublishes(settings) { binding(settings, \.launchaCalculator).wrappedValue.toggle() }
    }

    /// No settings view binds to the `@AppStorage` projection, which bypasses `didSet`.
    func testSettingsViewsDoNotBindToTheStorageProjection() throws {
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("SwiftKey/UI/Settings")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty)
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(text.contains("settings.$"), "\(file.lastPathComponent) binds to settings.$…; use $settings.… so didSet runs")
        }
    }
}
