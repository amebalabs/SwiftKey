import Foundation
import os

/// Centralized logging system for SwiftKey
enum AppLogger {
    // Define subsystems by major functional areas
    static let ui = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.swiftkey", category: "UI")
    static let config = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.swiftkey", category: "Config")
    static let keyboard = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.swiftkey", category: "Keyboard")
    static let core = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.swiftkey", category: "Core")
    static let utils = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.swiftkey", category: "Utils")
    static let snippets = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.swiftkey", category: "Snippets")

    // General app-wide logger
    static let app = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.swiftkey", category: "App")
}
