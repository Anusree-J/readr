// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ReadrKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "ReadrKit", targets: ["ReadrKit"]),
    ],
    dependencies: [
        // Rendering, RAG storage, and provider SDKs are added as the
        // corresponding milestones land. Kept dependency-free for now so the
        // core contracts build on any platform (including Linux CI).
    ],
    targets: [
        .target(
            name: "ReadrKit",
            path: "Sources/ReadrKit"
        ),
        .testTarget(
            name: "ReadrKitTests",
            dependencies: ["ReadrKit"],
            path: "Tests/ReadrKitTests"
        ),
    ]
)
