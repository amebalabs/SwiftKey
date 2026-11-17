import Foundation

/// Validation issue severity levels
enum ValidationSeverity: Comparable {
    case info       // Informational
    case warning    // Should be reviewed
    case error      // Must be fixed
}

/// Types of validation issues
enum ValidationType {
    case emptyKey
    case duplicateKey
    case invalidKey
    case emptyTitle
    case invalidURL
    case invalidPath
    case dangerousCommand
    case missingAction
    case circularReference
    case invalidIcon
    case invalidHotkey
}

/// Represents a validation issue found in configuration
struct ValidationIssue: Identifiable, Equatable {
    let id: UUID
    let type: ValidationType
    let severity: ValidationSeverity
    let message: String
    let itemId: UUID?
    let path: [String]

    init(
        id: UUID = UUID(),
        type: ValidationType,
        severity: ValidationSeverity,
        message: String,
        itemId: UUID? = nil,
        path: [String] = []
    ) {
        self.id = id
        self.type = type
        self.severity = severity
        self.message = message
        self.itemId = itemId
        self.path = path
    }

    static func == (lhs: ValidationIssue, rhs: ValidationIssue) -> Bool {
        lhs.id == rhs.id
    }
}
