import AppKit
import Foundation
import os

@MainActor
class FaviconManager {
    static let shared = FaviconManager()
    
    private var cache = [String: NSImage]()
    private var pendingRequests = [String: Task<NSImage?, Error>]()
    
    private let session: URLSession
    private let cacheDirectory: URL
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: config)
        
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleID = Bundle.main.bundleIdentifier ?? "com.swiftkey"
        let appCacheURL = appSupportURL.appendingPathComponent(bundleID).appendingPathComponent("IconCache")
        
        self.cacheDirectory = appCacheURL
        
        if !fileManager.fileExists(atPath: appCacheURL.path) {
            do {
                try fileManager.createDirectory(at: appCacheURL, withIntermediateDirectories: true)
            } catch {
                AppLogger.app.error("Failed to create icon cache directory: \(error.localizedDescription)")
            }
        }
        
        Task {
            await loadCachedIcons()
        }
    }
    
    func getFavicon(for urlString: String) async -> NSImage? {
        // Generate a unique key for the URL
        let cacheKey = cacheKey(for: urlString)
        
        // Check if we have this favicon cached in memory
        if let cachedImage = cache[cacheKey] {
            return cachedImage
        }
        
        // Check if we're already fetching this favicon
        if let pendingTask = pendingRequests[cacheKey] {
            do {
                return try await pendingTask.value
            } catch {
                AppLogger.app.error("Error retrieving pending favicon: \(error.localizedDescription)")
                return nil
            }
        }
        
        // Start a new request
        let task = Task<NSImage?, Error> {
            guard let image = await fetchFaviconForURL(urlString) else {
                return nil
            }
            return image
        }
        
        pendingRequests[cacheKey] = task
        
        do {
            let image = try await task.value
            // Cache the result before returning
            if let image = image {
                cache[cacheKey] = image
                // Save to persistent cache
                saveIconToCache(cacheKey: cacheKey, image: image)
            }
            pendingRequests.removeValue(forKey: cacheKey)
            return image
        } catch {
            AppLogger.app.error("Error fetching favicon: \(error.localizedDescription)")
            pendingRequests.removeValue(forKey: cacheKey)
            return nil
        }
    }
    
    private func fetchFaviconForURL(_ urlString: String) async -> NSImage? {
        guard let url = URL(string: urlString) else {
            return nil
        }
        
        guard let host = url.host else {
            return nil
        }
        
        if let googleFaviconURL = URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=128") {
            return await fetchImage(from: googleFaviconURL)
        }
        
        return nil
    }
    
    private func fetchImage(from url: URL) async -> NSImage? {
        do {
            let (data, response) = try await session.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let image = NSImage(data: data) else {
                return nil
            }
            
            let standardSize = NSSize(width: 16, height: 16)
            return resizeImage(image, to: standardSize)
            
        } catch {
            AppLogger.app.debug("Error fetching image from \(url.absoluteString): \(error.localizedDescription)")
            return nil
        }
    }
    
    private func resizeImage(_ image: NSImage, to size: NSSize) -> NSImage {
        let canvasSize = NSSize(width: 32, height: 32)
        let resizedImage = NSImage(size: canvasSize)
        
        resizedImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        
        NSColor.clear.set()
        NSRect(origin: .zero, size: canvasSize).fill()
        
        let xOffset = (canvasSize.width - size.width) / 2
        let yOffset = (canvasSize.height - size.height) / 2
        
        image.draw(in: NSRect(x: xOffset, y: yOffset, width: size.width, height: size.height),
                  from: NSRect(origin: .zero, size: image.size),
                  operation: .copy, 
                  fraction: 1.0)
        
        resizedImage.unlockFocus()
        
        return resizedImage
    }
    
    private func cacheKey(for urlString: String) -> String {
        guard let url = URL(string: urlString),
              let host = url.host else {
            return "favicon:\(urlString)"
        }
        
        return "favicon:\(host)"
    }
    
    private func loadCachedIcons() async {
        do {
            let fileManager = FileManager.default
            let cacheFiles = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
            
            for fileURL in cacheFiles {
                if fileURL.pathExtension == "png" {
                    let cacheKey = fileURL.deletingPathExtension().lastPathComponent
                    if let image = NSImage(contentsOf: fileURL) {
                        cache[cacheKey] = image
                        AppLogger.app.debug("Loaded cached icon: \(cacheKey)")
                    }
                }
            }
            
            AppLogger.app
                .debug("Loaded \(self.cache.count) icons from persistent cache")
        } catch {
            AppLogger.app.error("Error loading cached icons: \(error.localizedDescription)")
        }
    }
    
    private func saveIconToCache(cacheKey: String, image: NSImage) {
        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
            AppLogger.app.error("Failed to convert icon to PNG for caching")
            return
        }
        
        let fileURL = cacheDirectory.appendingPathComponent("\(cacheKey).png")
        
        do {
            try pngData.write(to: fileURL)
            AppLogger.app.debug("Saved icon to cache: \(cacheKey)")
        } catch {
            AppLogger.app.error("Failed to save icon to cache: \(error.localizedDescription)")
        }
    }
}
