// Reads the context of a micro-app start: the active app, the Finder selection, the browser tab,
// the selected text and the front window. SwiftKey reads only what the file lists in `context:`.
import AppKit
import ApplicationServices
import CoreServices
import SwiftKeyCore
import SwiftKeyRuntime

/// The app that was in front when a micro-app started. SwiftKey's own panels never activate SwiftKey, so
/// this is the app the person worked in.
struct MicroAppTarget: Equatable, Sendable {
    var pid: pid_t
    var bundleID: String?
    var name: String
    var path: String?

    @MainActor static func frontmost() -> MicroAppTarget? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return MicroAppTarget(pid: app.processIdentifier, bundleID: app.bundleIdentifier,
                              name: app.localizedName ?? app.bundleIdentifier ?? "the app", path: app.bundleURL?.path)
    }
}

/// A context or keyboard problem, with the message the person sees.
struct MicroAppInputError: LocalizedError, Equatable {
    var message: String
    /// SwiftKey does not have the Accessibility permission: the flow shows the Accessibility window.
    var needsAccessibility = false
    var errorDescription: String? { message }

    static let accessibility = MicroAppInputError(message: MicroAppContextScripts.accessibilityMessage, needsAccessibility: true)
}

extension Error {
    /// `true` for the error of a missing Accessibility permission.
    var needsAccessibility: Bool { (self as? MicroAppInputError)?.needsAccessibility == true }
}

@MainActor
protocol MicroAppContextReading: AnyObject {
    /// The values of `sources` for a start in front of `target`.
    func read(_ sources: [MicroAppContextSource], target: MicroAppTarget?) async throws -> MicroAppContext
}

@MainActor
final class MicroAppContextReader: MicroAppContextReading {
    /// Runs an AppleScript (osascript).
    var runScript: @Sendable (String) async -> MicroAppScriptResult = { await MicroAppScript.run($0) }
    /// Asks macOS whether SwiftKey may send Apple Events to the app; shows the Automation prompt once.
    var automationPermission: @Sendable (String) async -> OSStatus = { await MicroAppContextReader.askAutomation(bundleID: $0) }
    /// The running apps' bundle ids.
    var runningApps: @MainActor () -> [String] = { NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier) }
    /// The selected text by ⌘C, when Accessibility gives none.
    private let copySelection: @MainActor (MicroAppTarget) async -> String?
    /// The browser that was active last, while SwiftKey runs.
    private(set) var lastBrowser: String?
    private nonisolated let center = NSWorkspace.shared.notificationCenter
    private nonisolated(unsafe) var observer: NSObjectProtocol?

    init(copySelection: @escaping @MainActor (MicroAppTarget) async -> String?) {
        self.copySelection = copySelection
        observer = center.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                                     object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard let id = app?.bundleIdentifier, MicroAppContextScripts.dialect(of: id) != nil else { return }
            MainActor.assumeIsolated { self?.lastBrowser = id }
        }
    }

    deinit {
        if let observer { center.removeObserver(observer) }
    }

    func read(_ sources: [MicroAppContextSource], target: MicroAppTarget?) async throws -> MicroAppContext {
        var context = MicroAppContext()
        guard !sources.isEmpty else { return context }
        if sources.contains(.app), let target {
            context.set(.app, "name", target.name)
            context.set(.app, "bundle", target.bundleID ?? "")
            context.set(.app, "path", target.path ?? "")
            context.set(.app, "pid", String(target.pid))
        }
        if sources.contains(where: \.needsAccessibility) { try MicroAppAccessibility.require() }
        // The selection first: it is what the person looked at, and ⌘C needs the app in front.
        if sources.contains(.selection), let target {
            var text = MicroAppAccessibility.selectedText(pid: target.pid)
            if text?.isEmpty ?? true, let copied = await copySelection(target) { text = copied }
            context.set(.selection, "text", text ?? "")
        }
        if sources.contains(.window), let target {
            let window = MicroAppAccessibility.window(pid: target.pid)
            context.set(.window, "title", window.title)
            context.set(.window, "document", window.document)
        }
        if sources.contains(.finder) {
            let output = try await script(MicroAppContextScripts.finder, bundleID: MicroAppContextScripts.finderBundleID,
                                          appName: "Finder", reading: "the Finder selection")
            let finder = MicroAppContextScripts.parseFinder(output)
            context.set(.finder, "folder", finder.folder)
            context.set(.finder, "selection", finder.selection.joined(separator: "\n"))
        }
        if sources.contains(.browser), let id = MicroAppContextScripts.chooseBrowser(active: target?.bundleID, lastUsed: lastBrowser,
                                                                                       running: runningApps()),
           let dialect = MicroAppContextScripts.dialect(of: id) {
            let name = NSRunningApplication.runningApplications(withBundleIdentifier: id).first?.localizedName ?? id
            let output = try await script(MicroAppContextScripts.browser(bundleID: id, dialect: dialect), bundleID: id,
                                          appName: name, reading: "the browser tab")
            let tab = MicroAppContextScripts.parseBrowser(output)
            context.set(.browser, "url", tab.url)
            context.set(.browser, "title", tab.title)
            context.set(.browser, "name", name)
        }
        return context
    }

    /// The output of `text`, an AppleScript for the app `bundleID`; empty when the app is gone.
    private func script(_ text: String, bundleID: String, appName: String, reading what: String) async throws -> String {
        guard runningApps().contains(bundleID) else { return "" }
        switch await automationPermission(bundleID) {
        case noErr: break
        case OSStatus(procNotFound): return ""
        case OSStatus(errAEEventNotPermitted):
            throw MicroAppInputError(message: MicroAppContextScripts.message(.notAllowed, appName: appName, reading: what)!)
        default: break // Let the script report anything else.
        }
        let result = await runScript(text)
        switch result.end {
        case .success: return result.stdout
        case .cancelled: throw CancellationError()
        case .timedOut: throw MicroAppInputError(message: MicroAppContextScripts.message(.timedOut, appName: appName, reading: what)!)
        case .failure:
            guard let message = MicroAppContextScripts.message(MicroAppContextScripts.failure(stderr: result.stderr), appName: appName,
                                                               reading: what) else { return "" }
            throw MicroAppInputError(message: message)
        }
    }

    /// Blocks while the Automation prompt is up, so it runs off the main thread.
    nonisolated static func askAutomation(bundleID: String) async -> OSStatus {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
                guard let desc = target.aeDesc else { return continuation.resume(returning: OSStatus(procNotFound)) }
                continuation.resume(returning: AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, true))
            }
        }
    }
}

/// The Accessibility parts: the permission, the selected text and the front window of an app.
enum MicroAppAccessibility {
    /// Throws `MicroAppInputError.accessibility` when SwiftKey may not use Accessibility. SwiftKey's own
    /// Accessibility window explains how to allow it, so the prompt of macOS is not shown.
    static func require() throws {
        guard AXIsProcessTrusted() else { throw MicroAppInputError.accessibility }
    }

    private static func application(_ pid: pid_t) -> AXUIElement {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1)
        return app
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func element(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(element, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    /// The selected text of the focused element; `nil` when the app does not tell.
    static func selectedText(pid: pid_t) -> String? {
        guard let focused = element(application(pid), kAXFocusedUIElementAttribute) else { return nil }
        return attribute(focused, kAXSelectedTextAttribute) as? String
    }

    /// The title of the front window and the path (or URL) of its document; empty when unknown.
    static func window(pid: pid_t) -> (title: String, document: String) {
        guard let window = element(application(pid), kAXFocusedWindowAttribute) ?? element(application(pid), kAXMainWindowAttribute)
        else { return ("", "") }
        let title = attribute(window, kAXTitleAttribute) as? String ?? ""
        var document = attribute(window, kAXDocumentAttribute) as? String ?? ""
        if let url = URL(string: document), url.isFileURL { document = url.path }
        return (title, document)
    }
}
