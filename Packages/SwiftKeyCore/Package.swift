// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftKeyCore",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(name: "SwiftKeyCore", targets: ["SwiftKeyCore"]),
        .library(name: "SwiftKeyRuntime", targets: ["SwiftKeyRuntime"]),
        .executable(name: "swiftkey-micro", targets: ["swiftkey-micro"]),
    ],
    targets: [
        // Pure logic: keys, leader state machine, launcha search, calculator, approvals, micro-apps. No AppKit.
        .target(
            name: "SwiftKeyCore",
            swiftSettings: [.swiftLanguageMode(.v5)]),
        // Runs micro-apps: child processes, HTTP, keychain. Shared by the app and the console tool.
        .target(
            name: "SwiftKeyRuntime",
            dependencies: ["SwiftKeyCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(
            name: "swiftkey-micro",
            dependencies: ["SwiftKeyRuntime"],
            swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(
            name: "SwiftKeyCoreTests",
            dependencies: ["SwiftKeyCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(
            name: "SwiftKeyRuntimeTests",
            dependencies: ["SwiftKeyCore", "SwiftKeyRuntime"],
            swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
