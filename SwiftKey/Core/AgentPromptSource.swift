import AppKit
import SwiftKeyCore

/// The real values of the agent prompt on this Mac: the format document inside SwiftKey.app, the
/// link of the running version, the config file, its micro-apps folder and the SwiftKey executable.
enum AgentPromptSource {
    /// The prompt for `configURL`. Reads nothing but the bundle and the paths.
    static func text(bundle: Bundle = .main, configURL: URL, paths: AppPaths = .current) -> String {
        AgentPrompt.text(formatDocument: formatDocument(bundle: bundle),
                         link: AgentPrompt.formatLink(version: version(bundle: bundle)),
                         configFile: configURL.standardizedFileURL.path,
                         microAppsFolder: paths.microFolder(config: configURL).standardizedFileURL.path,
                         executable: executable(bundle: bundle))
    }

    /// `Contents/Resources/FORMAT.md` when it is there and readable; nil for a bundle without it.
    static func formatDocument(bundle: Bundle) -> String? {
        guard let url = bundle.url(forResource: "FORMAT", withExtension: "md") else { return nil }
        let path = url.resolvingSymlinksInPath().path
        return FileManager.default.isReadableFile(atPath: path) ? path : nil
    }

    /// The marketing version of the bundle; nil without one, so the links point to `main`.
    static func version(bundle: Bundle) -> String? {
        guard let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String,
              !version.isEmpty else { return nil }
        return version
    }

    /// The absolute path of the SwiftKey executable; `swiftkey-micro` is next to it.
    static func executable(bundle: Bundle) -> String {
        let url = bundle.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        return url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    /// Puts the text on `pasteboard`. Tests pass a private pasteboard, never the person's clipboard.
    static func copy(_ text: String, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
