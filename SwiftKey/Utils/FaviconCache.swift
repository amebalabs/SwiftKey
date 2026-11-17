import AppKit
import Foundation

/// Thread-safe cache for favicons using Swift actor
actor FaviconCache {
    private var cache = [String: NSImage]()
    private var pendingRequests = [String: Task<NSImage?, Error>]()

    /// Gets a cached favicon if available
    func getCached(_ key: String) -> NSImage? {
        cache[key]
    }

    /// Stores a favicon in the cache
    func setCached(_ key: String, image: NSImage) {
        cache[key] = image
    }

    /// Gets a pending request task if one exists
    func getPending(_ key: String) -> Task<NSImage?, Error>? {
        pendingRequests[key]
    }

    /// Stores a pending request task
    func setPending(_ key: String, task: Task<NSImage?, Error>) {
        pendingRequests[key] = task
    }

    /// Removes a completed pending request
    func removePending(_ key: String) {
        pendingRequests.removeValue(forKey: key)
    }

    /// Clears all cached images
    func clearMemoryCache() {
        cache.removeAll()
    }

    /// Returns the number of cached items
    var cacheCount: Int {
        cache.count
    }

    /// Preload multiple items into the cache
    func preload(_ items: [(String, NSImage)]) {
        for (key, image) in items {
            cache[key] = image
        }
    }
}
