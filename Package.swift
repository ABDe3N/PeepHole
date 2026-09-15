// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NetHog",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "NetHog",
            path: "Sources/NetHog"
        )
    ]
)
