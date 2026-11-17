import Foundation

/// The `swiftkey-micro` that this test run built: next to the test bundle in the build products
/// folder, whatever the configuration or build path.
enum BuiltTool {
    private final class Anchor {}

    static var swiftkeyMicro: URL {
        Bundle(for: Anchor.self).bundleURL.deletingLastPathComponent().appendingPathComponent("swiftkey-micro")
    }
}
