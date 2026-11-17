import Foundation
import SwiftKeyCore

/// Validates menu configuration for errors and warnings
final class ConfigValidator {

    /// The message for a key that is neither one character nor a named key.
    static let invalidKeyMessage = "Key must be one character, space, return or f1…f20"

    /// The loaded micro-apps, so a `micro://` item can be checked; nil checks only the id's form.
    private let microApps: MicroAppCatalog?
    /// The micro-apps folder as the person sees it, for the messages.
    private let microFolder: String

    init(microApps: MicroAppCatalog? = nil, microFolder: String = "the micro-apps folder") {
        self.microApps = microApps
        self.microFolder = microFolder
    }

    /// Validates a single menu item
    func validate(_ item: MenuItem, path: [String] = []) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        let currentPath = path + [item.title]

        // Key validation
        if item.key.isEmpty {
            issues.append(ValidationIssue(
                type: .emptyKey,
                severity: .error,
                message: "Key is required",
                itemId: item.id,
                path: currentPath
            ))
        } else if SequenceKey.normalize(item.key) == nil {
            issues.append(ValidationIssue(
                type: .invalidKey,
                severity: .error,
                message: "\(Self.invalidKeyMessage), found '\(item.key)'",
                itemId: item.id,
                path: currentPath
            ))
        }

        // Title validation
        if item.title.trimmingCharacters(in: .whitespaces).isEmpty {
            issues.append(ValidationIssue(
                type: .emptyTitle,
                severity: .error,
                message: "Title cannot be empty",
                itemId: item.id,
                path: currentPath
            ))
        }

        // Action validation
        if let action = item.action {
            issues.append(contentsOf: validateAction(action, itemId: item.id, path: currentPath))
        } else if item.submenu == nil {
            issues.append(ValidationIssue(
                type: .missingAction,
                severity: .warning,
                message: "Item has no action and no submenu",
                itemId: item.id,
                path: currentPath
            ))
        }

        // Hotkey validation
        if let hotkey = item.hotkey {
            issues.append(contentsOf: validateHotkey(hotkey, itemId: item.id, path: currentPath))
        }

        // Recursively validate submenu
        if let submenu = item.submenu {
            for subitem in submenu {
                issues.append(contentsOf: validate(subitem, path: currentPath))
            }
        }

        return issues
    }

    /// Validates hierarchy-level rules (duplicates, etc.)
    func validateHierarchy(_ items: [MenuItem], path: [String] = []) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []

        // Check for duplicate keys at this level
        var seenKeys: [String: UUID] = [:]
        for item in items {
            if let existingId = seenKeys[item.key] {
                issues.append(ValidationIssue(
                    type: .duplicateKey,
                    severity: .error,
                    message: "Duplicate key '\(item.key)' in menu level",
                    itemId: item.id,
                    path: path
                ))
                // Also mark the first occurrence
                if !issues.contains(where: { $0.itemId == existingId && $0.type == .duplicateKey }) {
                    issues.append(ValidationIssue(
                        type: .duplicateKey,
                        severity: .error,
                        message: "Duplicate key '\(item.key)' in menu level",
                        itemId: existingId,
                        path: path
                    ))
                }
            } else {
                seenKeys[item.key] = item.id
            }

            // Validate individual items
            issues.append(contentsOf: validate(item, path: path))

            // Recurse into submenus
            if let submenu = item.submenu {
                issues.append(contentsOf: validateHierarchy(submenu, path: path + [item.title]))
            }
        }

        return issues
    }

    /// Hotkeys used by more than one item, or equal to the main SwiftKey hotkey: global hotkeys
    /// must be unique across the whole menu.
    func validateHotkeyConflicts(_ items: [MenuItem], mainHotkey: Hotkey?) -> [ValidationIssue] {
        HotkeyRules.conflicts(in: items, mainHotkey: mainHotkey)
            .sorted { $0.key.uuidString < $1.key.uuidString }
            .map { ValidationIssue(type: .invalidHotkey, severity: .error, message: $0.value, itemId: $0.key) }
    }

    /// Returns only errors (issues that must be fixed)
    func errors(from issues: [ValidationIssue]) -> [ValidationIssue] {
        issues.filter { $0.severity == .error }
    }

    /// Returns only warnings (issues that should be reviewed)
    func warnings(from issues: [ValidationIssue]) -> [ValidationIssue] {
        issues.filter { $0.severity == .warning }
    }

    /// Checks if the configuration is valid (no errors)
    func isValid(_ items: [MenuItem]) -> Bool {
        errors(from: validateHierarchy(items)).isEmpty
    }

    // MARK: - Private Validation Methods

    private func validateAction(_ action: String, itemId: UUID, path: [String]) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []

        if action.hasPrefix("open://") {
            let urlString = String(action.dropFirst("open://".count))
            if urlString.isEmpty {
                issues.append(ValidationIssue(
                    type: .invalidURL,
                    severity: .error,
                    message: "URL cannot be empty",
                    itemId: itemId,
                    path: path
                ))
            } else if urlString.contains(" ") && URL(string: urlString) == nil {
                issues.append(ValidationIssue(
                    type: .invalidURL,
                    severity: .warning,
                    message: "URL may be invalid: \(urlString)",
                    itemId: itemId,
                    path: path
                ))
            }
        } else if action.hasPrefix("launch://") {
            let appPath = String(action.dropFirst("launch://".count))
            if appPath.isEmpty {
                issues.append(ValidationIssue(
                    type: .invalidPath,
                    severity: .error,
                    message: "Application path or bundle identifier cannot be empty",
                    itemId: itemId,
                    path: path
                ))
            } else if LaunchTarget(appPath).resolve() == nil {
                let message: String
                if case .bundleID = LaunchTarget(appPath) {
                    message = "No installed application has the bundle identifier \(appPath)"
                } else {
                    message = "Application may not exist: \(appPath)"
                }
                issues.append(ValidationIssue(
                    type: .invalidPath,
                    severity: .warning,
                    message: message,
                    itemId: itemId,
                    path: path
                ))
            }
        } else if action.hasPrefix("shell://") {
            let command = String(action.dropFirst("shell://".count))
            if command.trimmingCharacters(in: .whitespaces).isEmpty {
                issues.append(ValidationIssue(
                    type: .dangerousCommand,
                    severity: .error,
                    message: "Shell command cannot be empty",
                    itemId: itemId,
                    path: path
                ))
            } else {
                // Every command needs approval of its exact text before it runs, so no list of
                // dangerous patterns is checked here.

                // Check for unbalanced quotes
                let quoteCount = command.filter { $0 == "\"" || $0 == "'" }.count
                if quoteCount % 2 != 0 {
                    issues.append(ValidationIssue(
                        type: .dangerousCommand,
                        severity: .warning,
                        message: "Shell command has unbalanced quotes",
                        itemId: itemId,
                        path: path
                    ))
                }

                // Check command length
                if command.count > 1000 {
                    issues.append(ValidationIssue(
                        type: .dangerousCommand,
                        severity: .warning,
                        message: "Shell command exceeds 1000 characters",
                        itemId: itemId,
                        path: path
                    ))
                }
            }
        } else if action.hasPrefix("shortcut://") {
            let shortcutName = String(action.dropFirst("shortcut://".count))
            if shortcutName.trimmingCharacters(in: .whitespaces).isEmpty {
                issues.append(ValidationIssue(
                    type: .missingAction,
                    severity: .error,
                    message: "Shortcut name cannot be empty",
                    itemId: itemId,
                    path: path
                ))
            }
        } else if action.hasPrefix("dynamic://") {
            // Dynamic menus are valid
        } else if action.hasPrefix("micro://") {
            issues.append(contentsOf: validateMicroApp(String(action.dropFirst("micro://".count)), itemId: itemId, path: path))
        } else if !action.isEmpty {
            // Unknown action type
            let knownPrefixes = ["launch://", "open://", "shortcut://", "shell://", "dynamic://", "micro://"]
            if !knownPrefixes.contains(where: { action.hasPrefix($0) }) {
                issues.append(ValidationIssue(
                    type: .missingAction,
                    severity: .warning,
                    message: "Unknown action type: \(action.prefix(20))...",
                    itemId: itemId,
                    path: path
                ))
            }
        }

        return issues
    }

    /// An empty id is an error. A micro-app that is not in the folder, or whose file has errors, is a
    /// warning: the item shows as not working until the file is fixed.
    private func validateMicroApp(_ rawID: String, itemId: UUID, path: [String]) -> [ValidationIssue] {
        let id = rawID.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty else {
            return [ValidationIssue(type: .missingAction, severity: .error, message: "Micro-app id cannot be empty",
                                    itemId: itemId, path: path)]
        }
        guard let microApps else { return [] }
        let resolution = microApps.resolve(id)
        guard let problem = resolution.problem(id: id, folder: microFolder) else { return [] }
        return [ValidationIssue(type: .missingAction, severity: .warning, message: problem, itemId: itemId, path: path)]
    }

    private func validateHotkey(_ hotkey: String, itemId: UUID, path: [String]) -> [ValidationIssue] {
        guard let problem = HotkeyRules.problem(hotkey) else { return [] }
        return [ValidationIssue(
            type: .invalidHotkey,
            severity: .error,
            message: problem,
            itemId: itemId,
            path: path
        )]
    }
}
