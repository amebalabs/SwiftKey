import Foundation

/// The version of the running SwiftKey. Releases set it from the git tag, so the source tree has none.
public enum AppVersion {
    /// `CFBundleShortVersionString` of the enclosing app bundle; nil for runs without one
    /// (`swift run`, tests). `swiftkey-micro` inside SwiftKey.app reads the app's version.
    public static var marketing: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }
}
