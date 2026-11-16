import Foundation

/// Validates menu configuration for errors and warnings
final class ConfigValidator {

    private let dangerousPatterns = [
        "rm -rf /",
        "rm -rf ~",
        "sudo ",
        "> /dev/",
        ">> /",
        "mkfs",
        "dd if=",
        ":(){ :|:& };:"
    ]

    private let validModifiers = ["cmd", "ctrl", "alt", "shift", "option", "command", "control"]

    init() {}

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
        } else if item.key.count > 1 {
            issues.append(ValidationIssue(
                type: .invalidKey,
                severity: .error,
                message: "Key must be a single character, found '\(item.key)'",
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
                for pattern in dangerousPatterns {
                    if command.contains(pattern) {
                        issues.append(ValidationIssue(
                            type: .dangerousCommand,
                            severity: .warning,
                            message: "Potentially dangerous command pattern: \(pattern)",
                            itemId: itemId,
                            path: path
                        ))
                        break
                    }
                }

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
        } else if !action.isEmpty {
            // Unknown action type
            let knownPrefixes = ["launch://", "open://", "shortcut://", "shell://", "dynamic://"]
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

    private func validateHotkey(_ hotkey: String, itemId: UUID, path: [String]) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []

        let components = hotkey.components(separatedBy: "+").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }

        guard !components.isEmpty else {
            issues.append(ValidationIssue(
                type: .invalidHotkey,
                severity: .error,
                message: "Hotkey cannot be empty",
                itemId: itemId,
                path: path
            ))
            return issues
        }

        // All but the last component should be valid modifiers
        for i in 0 ..< (components.count - 1) {
            if !validModifiers.contains(components[i]) {
                issues.append(ValidationIssue(
                    type: .invalidHotkey,
                    severity: .error,
                    message: "Invalid modifier '\(components[i])' in hotkey",
                    itemId: itemId,
                    path: path
                ))
            }
        }

        // Last component should be a single character or known key name
        if let lastComponent = components.last {
            let validKeyNames = ["space", "return", "enter", "tab", "escape", "delete", "backspace",
                                "up", "down", "left", "right", "home", "end", "pageup", "pagedown"]
            if lastComponent.count > 1 && !validKeyNames.contains(lastComponent) {
                issues.append(ValidationIssue(
                    type: .invalidHotkey,
                    severity: .warning,
                    message: "Hotkey '\(lastComponent)' may not be recognized",
                    itemId: itemId,
                    path: path
                ))
            }
        }

        return issues
    }
}
