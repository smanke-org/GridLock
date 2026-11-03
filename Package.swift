// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "GridLock",
    platforms: [.macOS(.v26)],
    targets: [
        // Pure logic — display keys, desks, grid math, layouts — kept free of AppKit and
        // Accessibility so it can be tested with synthetic displays.
        .target(name: "GridLockKit"),
        .executableTarget(name: "GridLock", dependencies: ["GridLockKit"]),
        .testTarget(name: "GridLockKitTests", dependencies: ["GridLockKit"]),
    ]
)
