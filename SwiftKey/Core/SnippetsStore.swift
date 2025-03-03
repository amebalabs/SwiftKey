import Foundation
import Combine
import Yams

// MARK: - ConfigSnippet

/// Represents a shareable snippet of configuration that can be imported into the main config
struct ConfigSnippet: Identifiable, Codable, Equatable {
    let id: String // Unique identifier for the snippet (usually author/name format)
    let name: String // Display name of the snippet
    let description: String // Description of what the snippet does
    let author: String // Creator of the snippet
    let tags: [String] // Categories/tags for searching
    let created: Date // Creation date
    let updated: Date? // Last update date (optional)
    let content: String // The actual YAML content
    let previewImageURL: String? // URL to a preview image (optional)
    
    /// The parsed MenuItem array from the YAML content
    var menuItems: [MenuItem]? {
        do {
            let decoder = YAMLDecoder()
            return try decoder.decode([MenuItem].self, from: content)
        } catch {
            print("Error parsing snippet YAML: \(error)")
            return nil
        }
    }
}

// MARK: - SnippetsStore

/// Manages downloading, caching and providing access to config snippets
class SnippetsStore: ObservableObject, DependencyInjectable {
    // Published properties for reactive updates
    @Published private(set) var snippets: [ConfigSnippet] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var lastError: Error?
    
    // Dependencies
    var settingsStore: SettingsStore!
    var configManager: ConfigManager!
    
    func injectDependencies(_ container: DependencyContainer) {
        self.settingsStore = container.settingsStore
        self.configManager = container.configManager
        print("SnippetsStore: Dependencies injected successfully")
    }
    
    private let baseURL = URL(string: "https://swiftkey.app/snippets")!
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
        
        URLSession.shared.dataTaskPublisher(for: indexURL)
            .map(\.data)
            .decode(type: [ConfigSnippet].self, decoder: JSONDecoder())
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    
                    if case let .failure(error) = completion {
                        print("SnippetsStore: Failed to fetch snippets: \(error)")
                        self?.lastError = error
                    }
                },
                receiveValue: { [weak self] fetchedSnippets in
                    print("SnippetsStore: Successfully fetched \(fetchedSnippets.count) snippets")
                    self?.snippets = fetchedSnippets
                    self?.cacheSnippets(fetchedSnippets)
                }
            )
            .store(in: &cancellables)
    }
    
    /// Searches snippets based on a query string
    func searchSnippets(query: String) -> [ConfigSnippet] {
        guard !query.isEmpty else { return snippets }
        
        let lowercasedQuery = query.lowercased()
        
        return snippets.filter { snippet in
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
        case .failure(let error):
            return .failure(error)
        }
    }
    
    /// Creates a snippet from a subset of current config
    func createSnippet(from menuItems: [MenuItem], name: String, description: String, author: String, tags: [String]) -> Result<ConfigSnippet, Error> {
        do {
            let encoder = YAMLEncoder()
            let yamlContent = try encoder.encode(menuItems)
            
            let snippet = ConfigSnippet(
                id: "\(author.lowercased())/\(name.lowercased().replacingOccurrences(of: " ", with: "-"))",
                name: name,
                description: description,
                author: author,
                tags: tags,
                created: Date(),
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
            }
            print("SnippetsStore: Loaded \(cachedSnippets.count) snippets from cache")
        } catch {
            print("SnippetsStore: Failed to load snippets from cache: \(error)")
            // If we can't load from cache, fetch fresh data
            fetchSnippets()
        }
    }
    
    /// Caches snippets locally
    private func cacheSnippets(_ snippetsToCache: [ConfigSnippet]) {
        guard let cacheURL = getCacheFileURL() else { return }
        
        do {
            let data = try JSONEncoder().encode(snippetsToCache)
            try data.write(to: cacheURL)
            print("SnippetsStore: Successfully cached \(snippetsToCache.count) snippets")
        } catch {
            print("SnippetsStore: Failed to cache snippets: \(error)")
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
            print("SnippetsStore: Failed to get cache directory: \(error)")
            return nil
        }
    }
}

// MARK: - MergeStrategy

/// Strategy for merging imported snippets with existing config
enum MergeStrategy {
    case append      // Add snippets at the end of the existing config
    case prepend     // Add snippets at the beginning of the existing config
    case replace     // Replace the entire config with the snippets
    case smart       // Try to merge intelligently based on item key and title
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