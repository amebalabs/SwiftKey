import Foundation

/// The agent prompt: a ready English text for a coding agent (Claude Code, Codex, pi, …) that
/// says how to change SwiftKey: menu items, micro-apps and libraries. The person adds their own
/// task after its last line.
///
/// Pure logic: the Settings button gives these values and gets the text.
public enum AgentPrompt {
    public static let toast = "Agent prompt copied"

    /// The raw GitHub file of the format document at the tag of `version`, or on `main` when the
    /// version is unknown, e.g.
    /// `https://raw.githubusercontent.com/amebalabs/SwiftKey/v1.5.0/Packages/SwiftKeyCore/docs/micro-apps/FORMAT.md`.
    public static func formatLink(version: String?) -> String {
        let ref = version.map { "v" + $0 } ?? "main"
        return "https://raw.githubusercontent.com/amebalabs/SwiftKey/\(ref)/Packages/SwiftKeyCore/docs/micro-apps/FORMAT.md"
    }

    /// The guide for configuring SwiftKey, next to FORMAT.md in the app.
    public static func guide(forFormat path: String) -> String {
        (path as NSString).deletingLastPathComponent + "/CONFIGURING.md"
    }

    /// The link of the guide: `docs/CONFIGURING.md` at the same tag as the format link.
    public static func guideLink(forFormatLink link: String) -> String {
        link.replacingOccurrences(of: "docs/micro-apps/FORMAT.md", with: "docs/CONFIGURING.md")
    }

    /// The text of the prompt.
    /// - Parameters:
    ///   - formatDocument: the absolute path of FORMAT.md inside SwiftKey.app, or nil when it is not there.
    ///     The guide CONFIGURING.md is next to it.
    ///   - link: the fallback link of the format document, see `formatLink(version:)`.
    ///   - configFile: the absolute path of the YAML config file.
    ///   - microAppsFolder: the absolute path of the micro-apps folder.
    ///   - executable: the absolute path of the SwiftKey executable; `swiftkey-micro` is next to it.
    public static func text(formatDocument: String?, link: String, configFile: String, microAppsFolder: String,
                            executable: String) -> String {
        let guideLink = guideLink(forFormatLink: link)
        let read: String
        if let formatDocument {
            read = "1. Read the guide `\(guide(forFormat: formatDocument))` and follow it; if it cannot be read, use \(guideLink) instead. " +
                "For micro-apps it points to the format document `\(formatDocument)` (or \(link))."
        } else {
            read = "1. Read the guide \(guideLink) and follow it. For micro-apps it points to the format document \(link)."
        }
        let folder = shellQuoted(microAppsFolder)
        let micro = shellQuoted((executable as NSString).deletingLastPathComponent + "/swiftkey-micro")
        let libs = shellQuoted(microAppsFolder + "/libs")
        return [
            "Change my SwiftKey setup. SwiftKey is a keyboard launcher for macOS: its menus live in a YAML config file, and small tools (micro-apps) are YAML files.",
            "",
            read,
            "2. Write each micro-app as one file named `<id>.yaml`, where `<id>` is its kebab-case id, in a temporary folder (not in the micro-apps folder).",
            "3. Check it with `\(micro) check --libs \(libs) <file>` and fix the file until the check reports no problem (`<file>: ok`, exit code 0).",
            "4. Move the good file into the micro-apps folder `\(microAppsFolder)`, for example `mkdir -p \(folder) && mv <file> \(folder)/`.",
            "5. Change the config file `\(configFile)` only for the menu items I ask for; a menu item starts a micro-app with `action: \"micro://<id>\"`.",
            "6. Never put API keys into files and never change ~/Library/Application Support/SwiftKey/. I approve each new command and micro-app at its first start.",
            "",
            "My task: ",
        ].joined(separator: "\n")
    }

    /// A path for the shell, in single quotes; a single quote inside becomes `'\''`.
    public static func shellQuoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
