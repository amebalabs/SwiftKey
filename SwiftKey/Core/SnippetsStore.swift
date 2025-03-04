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
            print("Error parsing snippet YAML: \(error)")
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
        print("SnippetsStore: Dependencies injected successfully")
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
        print("SnippetsStore: Fetching snippets from URL: \(indexURL.absoluteString)")
        
        // Configure JSON decoder with date decoding strategy
        let decoder = JSONDecoder()
        
        // First try the network request to get snippets from the website
        URLSession.shared.dataTaskPublisher(for: indexURL)
            .map { data, response -> Data in
                if let httpResponse = response as? HTTPURLResponse {
                    print("SnippetsStore: HTTP response status: \(httpResponse.statusCode)")
                }
                return data
            }
            .decode(type: [ConfigSnippet].self, decoder: decoder)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    
                    if case let .failure(error) = completion {
                        print("SnippetsStore: Failed to fetch snippets: \(error)")
                        self?.lastError = error
                        
                        // Fall back to mock data if network request fails
                        self?.loadMockData()
                    }
                },
                receiveValue: { [weak self] fetchedSnippets in
                    print("SnippetsStore: Successfully fetched \(fetchedSnippets.count) snippets")
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
        case .failure(let error):
            return .failure(error)
        }
    }
    
    /// Creates a snippet from a subset of current config
    func createSnippet(from menuItems: [MenuItem], name: String, description: String, author: String, tags: [String]) -> Result<ConfigSnippet, Error> {
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
    
    /// Loads mock data for demonstration purposes
    @discardableResult
    private func loadMockData() -> Bool {
        print("SnippetsStore: Loading mock data")
        
        // Create sample snippet data 
        let mockSnippets = createMockSnippets()
        
        DispatchQueue.main.async { [weak self] in
            self?.snippets = mockSnippets
            self?.filteredSnippets = mockSnippets
            self?.isLoading = false
            print("SnippetsStore: Successfully loaded \(mockSnippets.count) mock snippets")
        }
        
        return true
    }
    
    /// Creates mock snippets for testing
    private func createMockSnippets() -> [ConfigSnippet] {
        let developerSnippet = ConfigSnippet(
            id: "developer/devtools-toolkit",
            name: "Developer Tools Toolkit",
            description: "A collection of essential developer tools and shortcuts for macOS, including IDE launchers, git commands, and Docker controls.",
            author: "Alex Johnson",
            tags: ["development", "git", "docker", "ide"],
            created: "2024-06-10",
            updated: nil,
            content: "# Developer tools and IDE shortcuts\n- key: \"d\"\n  icon: \"terminal.fill\"\n  title: \"Developer Tools\"\n  submenu:\n    - key: \"x\"\n      title: \"Xcode\"\n      action: \"launch:///Applications/Xcode.app\"\n    - key: \"v\"\n      title: \"Visual Studio Code\"\n      action: \"launch:///Applications/Visual Studio Code.app\"\n    - key: \"i\"\n      title: \"IntelliJ IDEA\"\n      action: \"launch:///Applications/IntelliJ IDEA.app\"\n    - key: \"g\"\n      title: \"Git Commands\"\n      submenu:\n        - key: \"p\"\n          title: \"Pull\"\n          action: \"shell://git pull\"\n          notify: true\n        - key: \"s\"\n          title: \"Status\"\n          action: \"shell://git status\"\n          notify: true",
            previewImageURL: nil
        )
        
        let quickAppSnippet = ConfigSnippet(
            id: "productivity/quick-apps",
            name: "Quick App Launcher",
            description: "A simple app launcher for your most frequently used applications, organized by category with custom icons.",
            author: "Sarah Miller",
            tags: ["productivity", "launcher", "apps"],
            created: "2024-05-15",
            updated: nil,
            content: "# Quick app launcher by category\n- key: \"a\"\n  icon: \"app.fill\"\n  title: \"Applications\"\n  submenu:\n    - key: \"b\"\n      icon: \"safari\"\n      title: \"Browsers\"\n      submenu:\n        - key: \"s\"\n          title: \"Safari\"\n          action: \"launch:///Applications/Safari.app\"\n        - key: \"c\"\n          title: \"Chrome\"\n          action: \"launch:///Applications/Google Chrome.app\"\n        - key: \"f\"\n          title: \"Firefox\"\n          action: \"launch:///Applications/Firefox.app\"\n    - key: \"p\"\n      icon: \"doc.text\"\n      title: \"Productivity\"\n      submenu:\n        - key: \"p\"\n          title: \"Preview\"\n          action: \"launch:///System/Applications/Preview.app\"\n        - key: \"n\"\n          title: \"Notes\"\n          action: \"launch:///System/Applications/Notes.app\"\n        - key: \"c\"\n          title: \"Calculator\"\n          action: \"launch:///System/Applications/Calculator.app\"",
            previewImageURL: nil
        )
        
        let systemSnippet = ConfigSnippet(
            id: "system/mac-utils",
            name: "macOS System Utilities",
            description: "Essential macOS system controls and utilities, including display settings, sound controls, and power management options.",
            author: "Michael Chen",
            tags: ["system", "macos", "utilities"],
            created: "2024-04-22",
            updated: "2024-05-30",
            content: "# macOS system utilities and controls\n- key: \"s\"\n  icon: \"gearshape.fill\"\n  title: \"System\"\n  submenu:\n    - key: \"d\"\n      icon: \"display\"\n      title: \"Display\"\n      submenu:\n        - key: \"n\"\n          title: \"Night Shift Toggle\"\n          action: \"shell://osascript -e 'tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode'\"\n          notify: true\n        - key: \"b\"\n          title: \"Brightness Up\"\n          action: \"shell://brightness up\"\n        - key: \"d\"\n          title: \"Brightness Down\"\n          action: \"shell://brightness down\"\n    - key: \"a\"\n      icon: \"speaker.wave.3.fill\"\n      title: \"Audio\"\n      submenu:\n        - key: \"u\"\n          title: \"Volume Up\"\n          action: \"shell://volume up\"\n        - key: \"d\"\n          title: \"Volume Down\"\n          action: \"shell://volume down\"\n        - key: \"m\"\n          title: \"Mute Toggle\"\n          action: \"shell://volume mute\"\n    - key: \"p\"\n      icon: \"bolt.fill\"\n      title: \"Power\"\n      submenu:\n        - key: \"s\"\n          title: \"Sleep\"\n          action: \"shell://pmset sleepnow\"\n        - key: \"r\"\n          title: \"Restart\"\n          action: \"shell://osascript -e 'tell app \"System Events\" to restart'\"\n        - key: \"o\"\n          title: \"Shut Down\"\n          action: \"shell://osascript -e 'tell app \"System Events\" to shut down'\"",
            previewImageURL: nil
        )
        
        return [developerSnippet, quickAppSnippet, systemSnippet]
    }
    
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
