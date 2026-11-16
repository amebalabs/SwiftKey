import Foundation

/// Where SwiftKey keeps its files.
///
/// `SWIFTKEY_CONFIG=/path/config.yaml` makes that file the config, puts every data file next to it
/// with the config file name in front (`/path/config.yaml.approvals.json`), puts micro-apps in
/// `/path/config.yaml.micro/`, and keeps settings in their own defaults suite. Tests and agents
/// then never touch the person's config, data or preferences.
struct AppPaths {
    static let environmentKey = "SWIFTKEY_CONFIG"

    /// The paths of this process.
    static let current = AppPaths()

    /// The settings store of this process: the standard defaults, or a suite of the override.
    static let defaults: UserDefaults = current.defaultsSuiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard

    /// The config file named by `SWIFTKEY_CONFIG`, or nil without the override.
    let configOverride: URL?
    let home: URL

    init(environment: [String: String] = ProcessInfo.processInfo.environment,
         home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        if let value = environment[Self.environmentKey], !value.isEmpty {
            configOverride = URL(fileURLWithPath: (value as NSString).expandingTildeInPath)
        } else {
            configOverride = nil
        }
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

    /// The defaults suite for the override, derived from its path; nil without the override.
    var defaultsSuiteName: String? {
        guard let configOverride else { return nil }
        let safe = configOverride.path.map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
        return "com.ameba.SwiftKey.config" + safe
    }
}
