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
            // Using static logger since this is called in a struct
            AppLogger.snippets.error("Error parsing snippet YAML: \(error.localizedDescription)")
            return nil
        }
    }

    /// Parsed creation date
    var creationDate: Date? {
        return dateFromString(created)
    }

    /// Parsed update date
    var updateDate: Date? {
        guard let updated = updated else { return nil }
        return dateFromString(updated)
    }

    /// Converts a date string to a Date object
    private func dateFromString(_ dateString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: dateString)
    }
}

// MARK: - SnippetsStore

/// Manages downloading, caching and providing access to config snippets
class SnippetsStore: ObservableObject, DependencyInjectable {
    // Logger for this class
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

    private let baseURL = URL(string: "http://localhost:3000")!
    private let cacheFileName = "snippets-cache.json"
    private var cancellables = Set<AnyCancellable>()

    init() {
        // Load cached snippets immediately
        loadCachedSnippets()
    }

    // MARK: - Public Methods

    /// Fetches snippets from the remote repository
    func fetchSnippets() {
        isLoading = true

        // URL for the snippets index file
        let indexURL = baseURL.appendingPathComponent("index.json")
        logger.info("Fetching snippets from URL: \(indexURL.absoluteString, privacy: .public)")

        // Configure JSON decoder
        let decoder = JSONDecoder()

        // Perform the network request
        URLSession.shared.dataTaskPublisher(for: indexURL)
            .map { $0.data }
            .decode(type: [ConfigSnippet].self, decoder: decoder)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false

                    if case let .failure(error) = completion {
                        self?.logger.error("Failed to fetch snippets: \(error.localizedDescription)")
                        self?.lastError = error

                        // Load cached snippets if available
                        if self?.snippets.isEmpty == true {
                            self?.loadCachedSnippets()
                        }
                    }
                },
                receiveValue: { [weak self] fetchedSnippets in
                    self?.logger.info("Successfully fetched \(fetchedSnippets.count) snippets")
                    self?.snippets = fetchedSnippets
                    self?.filteredSnippets = fetchedSnippets
                    self?.cacheSnippets(fetchedSnippets)
                }
            )
            .store(in: &cancellables)
    }

    /// Searches snippets based on a query string
    func searchSnippets(query: String) {
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

    /// Imports a snippet and merges it with the existing config
    func importSnippet(_ snippet: ConfigSnippet, mergeStrategy: MergeStrategy = .append) -> Result<Void, Error> {
        guard let menuItems = snippet.menuItems else {
            return .failure(SnippetError.invalidYamlFormat)
        }

        // Use ConfigManager to merge and save the snippet
        let result = configManager.importSnippet(menuItems: menuItems, strategy: mergeStrategy)
        switch result {
        case .success:
            return .success(())
        case let .failure(error):
            return .failure(error)
        }
    }

    /// Creates a snippet from a subset of current config
    func createSnippet(
        from menuItems: [MenuItem],
        name: String,
        description: String,
        author: String,
        tags: [String]
    ) -> Result<ConfigSnippet, Error> {
        do {
            let encoder = YAMLEncoder()
            let yamlContent = try encoder.encode(menuItems)

            // Format today's date as ISO string
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let createdString = dateFormatter.string(from: Date())

            let snippet = ConfigSnippet(
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

            return .success(snippet)
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Private Methods

    /// Loads snippets from local cache
    private func loadCachedSnippets() {
        guard let cacheURL = getCacheFileURL() else { return }

        do {
            let data = try Data(contentsOf: cacheURL)
            let cachedSnippets = try JSONDecoder().decode([ConfigSnippet].self, from: data)
            DispatchQueue.main.async { [weak self] in
                self?.snippets = cachedSnippets
                self?.filteredSnippets = cachedSnippets
            }
            logger.info("Loaded \(cachedSnippets.count) snippets from cache")
        } catch {
            logger.error("Failed to load snippets from cache: \(error.localizedDescription)")
            // If we can't load from cache, fetch fresh data
            fetchSnippets()
        }
    }

    /// Caches snippets locally
    private func cacheSnippets(_ snippetsToCache: [ConfigSnippet]) {
        guard let cacheURL = getCacheFileURL() else {
            logger.error("Failed to get cache URL")
            return
        }

        do {
            let data = try JSONEncoder().encode(snippetsToCache)
            try data.write(to: cacheURL)
            logger.debug("Successfully cached \(snippetsToCache.count) snippets")
        } catch {
            logger.error("Failed to cache snippets: \(error.localizedDescription)")
        }
    }

    /// Gets the URL for the cache file
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
