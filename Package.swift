// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PeepHole",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "PeepHole",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/PeepHole",
            // build.sh places Sparkle.framework in PeepHole.app/Contents/Frameworks.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(
            name: "PeepHoleTests",
            dependencies: ["PeepHole"],
            path: "Tests/PeepHoleTests"
        ),
    ]
)
