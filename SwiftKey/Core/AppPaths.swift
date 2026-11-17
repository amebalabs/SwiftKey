import Foundation

/// Where SwiftKey keeps its files.
///
/// `SWIFTKEY_CONFIG=/path/config.yaml` makes that file the config, puts every data file next to it
/// with the config file name in front (`/path/config.yaml.approvals.json`), puts micro-apps in
/// `/path/config.yaml.micro/`, and keeps settings in their own defaults suite. Tests and agents
/// then never touch the person's config, data or preferences.
///
/// Only debug builds and test runs follow `SWIFTKEY_CONFIG`: in a release build, a config named
/// from outside could bring its own approvals. Unit tests without the variable get a config of
/// their own in a new temporary folder, so they never reach the person's files or preferences.
struct AppPaths {
    static let environmentKey = "SWIFTKEY_CONFIG"
    /// Set by XCTest in the process that hosts unit tests.
    static let testEnvironmentKey = "XCTestConfigurationFilePath"

    /// True in debug builds; release builds ignore `SWIFTKEY_CONFIG` outside test runs.
    #if DEBUG
    static let isDebugBuild = true
    #else
    static let isDebugBuild = false
    #endif

    /// The paths of this process.
    static let current: AppPaths = {
        let paths = AppPaths()
        if paths.ignoredOverride {
            AppLogger.config.notice("SWIFTKEY_CONFIG is ignored: only debug builds and tests follow it")
        }
        return paths
    }()

    /// The settings store of this process: the standard defaults, or a suite of the override.
    static let defaults: UserDefaults = current.defaultsSuiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard

    /// The config file named by `SWIFTKEY_CONFIG` (or made for a test run), or nil without the override.
    let configOverride: URL?
    let home: URL
    /// `SWIFTKEY_CONFIG` was set but this build does not follow it.
    let ignoredOverride: Bool

    init(environment: [String: String] = ProcessInfo.processInfo.environment,
         home: URL = FileManager.default.homeDirectoryForCurrentUser,
         isDebugBuild: Bool = AppPaths.isDebugBuild) {
        let isTestRun = environment[Self.testEnvironmentKey] != nil
        let value = environment[Self.environmentKey].flatMap { $0.isEmpty ? nil : $0 }
        if let value, isDebugBuild || isTestRun {
            configOverride = URL(fileURLWithPath: (value as NSString).expandingTildeInPath)
        } else if isTestRun {
            configOverride = FileManager.default.temporaryDirectory
                .appendingPathComponent("swiftkey-tests-\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString)",
                                        isDirectory: true)
                .appendingPathComponent("config.yaml")
        } else {
            configOverride = nil
        }
        ignoredOverride = value != nil && !(isDebugBuild || isTestRun)
        self.home = home
    }

    /// A data file: `<config>.<name>` with the override, else
    /// `~/Library/Application Support/SwiftKey/<name>`.
    func url(for name: String) -> URL {
        if let configOverride {
            return URL(fileURLWithPath: configOverride.path + "." + name)
        }
        return home.appendingPathComponent("Library/Application Support/SwiftKey", isDirectory: true)
            .appendingPathComponent(name)
    }

    /// The micro-apps folder of `config`: `<config>.micro/` with the override, else `micro/` next to it.
    func microFolder(config: URL) -> URL {
        if let configOverride, configOverride.standardizedFileURL == config.standardizedFileURL {
            return URL(fileURLWithPath: config.path + ".micro", isDirectory: true)
        }
        return config.deletingLastPathComponent().appendingPathComponent("micro", isDirectory: true)
    }

    /// The defaults suite for the override: an absolute path, so the settings are the file
    /// `<config>.settings.plist` next to the config and nothing is left in ~/Library/Preferences;
    /// nil without the override.
    var defaultsSuiteName: String? {
        guard let configOverride else { return nil }
        return configOverride.path + ".settings"
    }
}
