import Combine
import Foundation
import os
import Yams

// MARK: - ConfigSnippet

/// Represents a shareable snippet of configuration that can be imported into the main config
struct ConfigSnippet: Identifiable, Codable, Equatable {
    let id: String // Unique identifier for the snippet (usually author/name format)
    let name: String // Display name of the snippet
    let description: String // Description of what the snippet does
    let author: String // Creator of the snippet
    let tags: [String] // Categories/tags for searching
    let created: String // Creation date (ISO string format)
    let updated: String? // Last update date (optional, ISO string format)
    let content: String // The actual YAML content
    let previewImageURL: String? // URL to a preview image (optional)

    /// The parsed MenuItem array from the YAML content
    var menuItems: [MenuItem]? {
        do {
            let decoder = YAMLDecoder()
            return try decoder.decode([MenuItem].self, from: content)
        } catch {
            AppLogger.snippets.error("Error parsing snippet YAML: \(error.localizedDescription)")
            return nil
        }
    }

    var creationDate: Date? {
        return dateFromString(created)
    }

    var updateDate: Date? {
        guard let updated = updated else { return nil }
        return dateFromString(updated)
    }

    private func dateFromString(_ dateString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: dateString)
    }
}

// MARK: - SnippetsStore

/// Manages downloading, caching and providing access to config snippets
class SnippetsStore: ObservableObject, DependencyInjectable {
    private let logger = AppLogger.snippets

    // Published properties for reactive updates
    @Published private(set) var snippets: [ConfigSnippet] = []
    @Published private(set) var filteredSnippets: [ConfigSnippet] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var lastError: Error?

    // Dependencies
    var settingsStore: SettingsStore!
    var configManager: ConfigManager!

    func injectDependencies(_ container: DependencyContainer) {
        self.settingsStore = container.settingsStore
        self.configManager = container.configManager
        logger.debug("Dependencies injected successfully")
    }

    private let baseURL = URL(string: "https://swiftkey.app/snippets")!
    private let cacheFileName = "snippets-cache.json"
    private var cancellables = Set<AnyCancellable>()

    // Track if we've already loaded data
    private var didInitialLoad = false

    /// Ensures snippets are loaded when needed
    private func ensureSnippetsLoaded() {
        if !didInitialLoad {
            logger.debug("Performing deferred snippet load")
            Task {
                await loadCachedSnippets()
            }
            didInitialLoad = true
        }
    }

    // MARK: - Public Methods

    /// Fetches snippets from the remote repository using async/await
    func fetchSnippets() async {
        // Set loading state on main thread
        await MainActor.run {
            isLoading = true
            didInitialLoad = true // Mark as loaded since we're explicitly fetching now
        }

        // URL for the snippets index file
        let indexURL = baseURL.appendingPathComponent("index.json")
        logger.info("Fetching snippets from URL: \(indexURL.absoluteString, privacy: .public)")

        do {
            let (data, _) = try await URLSession.shared.data(from: indexURL)

            let fetchedSnippets = try JSONDecoder().decode([ConfigSnippet].self, from: data)

            // Update UI state on main thread
            await MainActor.run {
                logger.info("Successfully fetched \(fetchedSnippets.count) snippets")
                snippets = fetchedSnippets
                filteredSnippets = fetchedSnippets
                isLoading = false
                lastError = nil
            }

            try await cacheSnippets(fetchedSnippets)

        } catch {
            logger.error("Failed to fetch snippets: \(error.localizedDescription)")

            await MainActor.run {
                isLoading = false
                lastError = error

                if snippets.isEmpty {
                    Task {
                        await loadCachedSnippets()
                    }
                }
            }
        }
    }

    /// Searches snippets based on a query string
    func searchSnippets(query: String) {
        ensureSnippetsLoaded()

        guard !query.isEmpty else {
            filteredSnippets = snippets
            return
        }

        let lowercasedQuery = query.lowercased()

        filteredSnippets = snippets.filter { snippet in
            snippet.name.lowercased().contains(lowercasedQuery) ||
                snippet.description.lowercased().contains(lowercasedQuery) ||
                snippet.author.lowercased().contains(lowercasedQuery) ||
                snippet.tags.contains { $0.lowercased().contains(lowercasedQuery) }
        }
    }

    func importSnippet(_ snippet: ConfigSnippet, mergeStrategy: MergeStrategy = .append) async throws {
        guard let menuItems = snippet.menuItems else {
            throw SnippetError.invalidYamlFormat
        }

        try await configManager.importSnippet(menuItems: menuItems, strategy: mergeStrategy)
    }

    func createSnippet(
        from menuItems: [MenuItem],
        name: String,
        description: String,
        author: String,
        tags: [String]
    ) async throws -> ConfigSnippet {
        return try await Task {
            let encoder = YAMLEncoder()
            let yamlContent = try encoder.encode(menuItems)

            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let createdString = dateFormatter.string(from: Date())

            return ConfigSnippet(
                id: "\(author.lowercased())/\(name.lowercased().replacingOccurrences(of: " ", with: "-"))",
                name: name,
                description: description,
                author: author,
                tags: tags,
                created: createdString,
                updated: nil,
                content: yamlContent,
                previewImageURL: nil
            )
        }.value
    }

    // MARK: - Private Methods

    private func loadCachedSnippets() async {
        guard let cacheURL = getCacheFileURL() else { return }

        do {
            let data = try Data(contentsOf: cacheURL)
            let cachedSnippets = try JSONDecoder().decode([ConfigSnippet].self, from: data)

            await MainActor.run {
                snippets = cachedSnippets
                filteredSnippets = cachedSnippets
                logger.info("Loaded \(cachedSnippets.count) snippets from cache")
            }
        } catch {
            logger.error("Failed to load snippets from cache: \(error.localizedDescription)")

            await fetchSnippets()
        }
    }

    private func cacheSnippets(_ snippetsToCache: [ConfigSnippet]) async throws {
        guard let cacheURL = getCacheFileURL() else {
            logger.error("Failed to get cache URL")
            throw NSError(
                domain: "com.swiftkey.snippets",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to get cache URL"]
            )
        }

        do {
            let data = try JSONEncoder().encode(snippetsToCache)

            try data.write(to: cacheURL)
            logger.debug("Successfully cached \(snippetsToCache.count) snippets")
        } catch {
            logger.error("Failed to cache snippets: \(error.localizedDescription)")
            throw error
        }
    }

    private func getCacheFileURL() -> URL? {
        do {
            let cacheDirectory = try FileManager.default.url(
                for: .cachesDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            return cacheDirectory.appendingPathComponent(cacheFileName)
        } catch {
            logger.error("Failed to get cache directory: \(error.localizedDescription)")
            return nil
        }
    }
}

// MARK: - MergeStrategy

/// Strategy for merging imported snippets with existing config
enum MergeStrategy {
    case append // Add snippets at the end of the existing config
    case prepend // Add snippets at the beginning of the existing config
    case replace // Replace the entire config with the snippets
    case smart // Try to merge intelligently based on item key and title
}

// MARK: - Error Types

enum SnippetError: Error {
    case fetchFailed
    case invalidYamlFormat
    case mergeConflict
    case invalidSnippet
}

extension SnippetError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .fetchFailed:
            return "Failed to fetch snippets from the repository."
        case .invalidYamlFormat:
            return "The snippet contains invalid YAML format."
        case .mergeConflict:
            return "There were conflicts when merging the snippet with your configuration."
        case .invalidSnippet:
            return "The snippet is invalid or corrupted."
        }
    }
}
