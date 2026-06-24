// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ReaderKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "ReaderKit", targets: ["ReaderKit"]),
    ],
    dependencies: [
        // Rendering, RAG storage, and provider SDKs are added as the
        // corresponding milestones land. Kept dependency-free for now so the
        // core contracts build on any platform (including Linux CI).
    ],
    targets: [
        .target(
            name: "ReaderKit",
            path: "Sources/ReaderKit"
        ),
        .testTarget(
            name: "ReaderKitTests",
            dependencies: ["ReaderKit"],
            path: "Tests/ReaderKitTests"
        ),
    ]
)
