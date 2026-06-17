// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DevCommand",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "DevCommand",
            path: "Sources/DevCommand"
        ),
        .testTarget(
            name: "DevCommandTests",
            dependencies: ["DevCommand"],
            path: "Tests/DevCommandTests"
        )
    ],
    // Stay in Swift 5 language mode: the app is a thin GUI over CLI tools and
    // doesn't need Swift 6 strict-concurrency ceremony for its Process plumbing.
    swiftLanguageModes: [.v5]
)
