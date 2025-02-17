import Foundation

class Environment {
    static let shared = Environment()

    enum Variables: String {
        case swiftKey = "SWIFTKEY"
        case swiftKeyVersion = "SWIFTKEY_VERSION"
        case swiftKeyBuild = "SWIFTKEY_BUILD"
        case swiftKeyConfigPath = "SWIFTKEY_PLUGINS_PATH"
        case osVersionMajor = "OS_VERSION_MAJOR"
        case osVersionMinor = "OS_VERSION_MINOR"
        case osVersionPatch = "OS_VERSION_PATCH"
    }

    private var dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    var userLoginShell = "/bin/zsh"

    private var systemEnv: [Variables: String] = [
        .swiftKey: "1",
        .swiftKeyVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
        .swiftKeyBuild: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "",
        .swiftKeyConfigPath: SettingsStore.shared.configFilePath,
        .osVersionMajor: String(ProcessInfo.processInfo.operatingSystemVersion.majorVersion),
        .osVersionMinor: String(ProcessInfo.processInfo.operatingSystemVersion.minorVersion),
        .osVersionPatch: String(ProcessInfo.processInfo.operatingSystemVersion.patchVersion),
    ]

    var systemEnvStr: [String: String] {
        Dictionary(uniqueKeysWithValues:
            systemEnv.map { key, value in (key.rawValue, value) })
    }
}
