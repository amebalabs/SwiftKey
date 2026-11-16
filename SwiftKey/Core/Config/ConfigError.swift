import Foundation

/// Errors that can occur during configuration operations
enum ConfigError: LocalizedError, Equatable {
    // File operations
    case fileNotFound
    case accessDenied
    case readFailed(underlying: Error)

    // Parsing
    case emptyFile
    case emptyConfiguration
    case invalidYamlFormat(message: String, line: Int, column: Int)
    case parsingFailed(underlying: Error)

    // Validation
    case missingRequiredField(field: String, context: String)
    case typeMismatch(field: String, context: String)
    case validationFailed(issues: [ValidationIssue])

    // Shell/Command
    case invalidShellCommand(message: String, command: String)

    // Operations
    case saveFailed(underlying: Error)
    case backupFailed(underlying: Error)
    case dependencyNotReady
    case unknown(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "Configuration file not found"
        case .accessDenied:
            return "Access denied to configuration file"
        case .readFailed(let error):
            return "Failed to read configuration: \(error.localizedDescription)"
        case .emptyFile:
            return "Configuration file is empty"
        case .emptyConfiguration:
            return "Configuration contains no menu items"
        case .invalidYamlFormat(let message, let line, let column):
            if line > 0 {
                return "Invalid YAML at line \(line), column \(column): \(message)"
            }
            return "Invalid YAML format: \(message)"
        case .parsingFailed(let error):
            return "Failed to parse configuration: \(error.localizedDescription)"
        case .missingRequiredField(let field, let context):
            return "Missing required field '\(field)': \(context)"
        case .typeMismatch(let field, let context):
            return "Type mismatch for field '\(field)': \(context)"
        case .validationFailed(let issues):
            let errorCount = issues.filter { $0.severity == .error }.count
            return "Configuration has \(errorCount) validation error(s)"
        case .invalidShellCommand(let message, let command):
            return "Invalid shell command: \(message) in '\(command)'"
        case .saveFailed(let error):
            return "Failed to save configuration: \(error.localizedDescription)"
        case .backupFailed(let error):
            return "Failed to create backup: \(error.localizedDescription)"
        case .dependencyNotReady:
            return "Configuration manager dependencies are not ready"
        case .unknown(let error):
            return "Unknown error: \(error.localizedDescription)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .fileNotFound:
            return "Create a new configuration file or check the file path in settings."
        case .accessDenied:
            return "Check file permissions or choose a different location."
        case .readFailed:
            return "Check if the file is corrupted or in use by another application."
        case .emptyFile, .emptyConfiguration:
            return "Add at least one menu item to your configuration."
        case .invalidYamlFormat:
            return "Check your YAML syntax. Common issues include incorrect indentation or missing quotes."
        case .parsingFailed:
            return "Verify the configuration structure matches the expected format."
        case .missingRequiredField(let field, _):
            return "Add the '\(field)' field to your configuration."
        case .typeMismatch(let field, _):
            return "Check the value type for '\(field)' in your configuration."
        case .validationFailed:
            return "Fix the validation errors shown in the configuration editor."
        case .invalidShellCommand:
            return "Review the command for potentially dangerous operations."
        case .saveFailed:
            return "Check if you have write permissions and the disk is not full."
        case .backupFailed:
            return "Check available disk space and permissions for the backup directory."
        case .dependencyNotReady:
            return "Wait for the application to fully initialize."
        case .unknown:
            return "Try restarting the application."
        }
    }

    static func == (lhs: ConfigError, rhs: ConfigError) -> Bool {
        switch (lhs, rhs) {
        case (.fileNotFound, .fileNotFound),
             (.accessDenied, .accessDenied),
             (.emptyFile, .emptyFile),
             (.emptyConfiguration, .emptyConfiguration),
             (.dependencyNotReady, .dependencyNotReady):
            return true
        case let (.invalidYamlFormat(m1, l1, c1), .invalidYamlFormat(m2, l2, c2)):
            return m1 == m2 && l1 == l2 && c1 == c2
        case let (.missingRequiredField(f1, c1), .missingRequiredField(f2, c2)):
            return f1 == f2 && c1 == c2
        case let (.typeMismatch(f1, c1), .typeMismatch(f2, c2)):
            return f1 == f2 && c1 == c2
        case let (.invalidShellCommand(m1, c1), .invalidShellCommand(m2, c2)):
            return m1 == m2 && c1 == c2
        default:
            return false
        }
    }
}
