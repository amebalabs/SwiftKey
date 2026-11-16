import Foundation
import Yams

/// Parses YAML configuration into MenuItem structures
final class ConfigParser {

    init() {}

    /// Parses YAML string into menu items
    func parse(_ yamlString: String) throws -> [MenuItem] {
        // Check for empty content
        if yamlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ConfigError.emptyFile
        }

        let decoder = YAMLDecoder()

        do {
            // First validate that root is an array
            if let yamlObject = try Yams.load(yaml: yamlString) {
                guard yamlObject is [Any] else {
                    throw ConfigError.invalidYamlFormat(
                        message: "Root element must be an array of menu items",
                        line: 1,
                        column: 1
                    )
                }
            }

            // Decode to actual model
            let items = try decoder.decode([MenuItem].self, from: yamlString)

            if items.isEmpty {
                throw ConfigError.emptyConfiguration
            }

            return items

        } catch let error as ConfigError {
            throw error
        } catch let yamlError as YamlError {
            let lineInfo = extractLineInfo(from: yamlError)
            throw ConfigError.invalidYamlFormat(
                message: yamlError.localizedDescription,
                line: lineInfo.line,
                column: lineInfo.column
            )
        } catch let decodingError as DecodingError {
            throw mapDecodingError(decodingError)
        } catch {
            throw ConfigError.parsingFailed(underlying: error)
        }
    }

    /// Serializes menu items back to YAML
    func serialize(_ items: [MenuItem]) throws -> String {
        let encoder = YAMLEncoder()
        do {
            return try encoder.encode(items)
        } catch {
            throw ConfigError.parsingFailed(underlying: error)
        }
    }

    // MARK: - Private Helpers

    private func extractLineInfo(from error: YamlError) -> (line: Int, column: Int) {
        var line = 0
        var column = 0

        let errorDescription = error.localizedDescription
        let lineColumnPattern = #"line (\d+), column (\d+)"#

        if let regex = try? NSRegularExpression(pattern: lineColumnPattern),
           let match = regex.firstMatch(
               in: errorDescription,
               range: NSRange(errorDescription.startIndex..., in: errorDescription)
           ) {
            if let lineRange = Range(match.range(at: 1), in: errorDescription),
               let columnRange = Range(match.range(at: 2), in: errorDescription) {
                line = Int(errorDescription[lineRange]) ?? 0
                column = Int(errorDescription[columnRange]) ?? 0
            }
        }

        return (line, column)
    }

    private func mapDecodingError(_ error: DecodingError) -> ConfigError {
        switch error {
        case let .keyNotFound(key, context):
            return ConfigError.missingRequiredField(
                field: key.stringValue,
                context: context.debugDescription
            )
        case let .typeMismatch(_, context):
            let fieldName = context.codingPath.last?.stringValue ?? "unknown"
            return ConfigError.typeMismatch(
                field: fieldName,
                context: context.debugDescription
            )
        case let .valueNotFound(_, context):
            let fieldName = context.codingPath.last?.stringValue ?? "unknown"
            return ConfigError.missingRequiredField(
                field: fieldName,
                context: context.debugDescription
            )
        case let .dataCorrupted(context):
            return ConfigError.invalidYamlFormat(
                message: context.debugDescription,
                line: 0,
                column: 0
            )
        @unknown default:
            return ConfigError.parsingFailed(underlying: error)
        }
    }
}
