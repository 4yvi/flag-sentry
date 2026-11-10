// swift-tools-version:5.7
// Used only to run the unit tests with `swift test`. The app itself is built by build.sh.
import PackageDescription

let package = Package(
    name: "FlagSentry",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "FlagSentryCore",
            path: "Sources/FlagSentryCore"
        ),
        .testTarget(
            name: "FlagSentryTests",
            dependencies: ["FlagSentryCore"],
            path: "Tests/FlagSentryTests"
        ),
    ]
)
