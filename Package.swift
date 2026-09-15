// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NetHog",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "NetHog",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/NetHog",
            // build.sh places Sparkle.framework in NetHog.app/Contents/Frameworks.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(
            name: "NetHogTests",
            dependencies: ["NetHog"],
            path: "Tests/NetHogTests"
        ),
    ]
)
