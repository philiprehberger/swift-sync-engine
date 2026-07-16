// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "swift-sync-engine",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
        .watchOS(.v9)
    ],
    products: [
        .library(name: "SyncEngine", targets: ["SyncEngine"])
    ],
    targets: [
        .target(
            name: "SyncEngine",
            path: "Sources/SyncEngine"
        ),
        .testTarget(
            name: "SyncEngineTests",
            dependencies: ["SyncEngine"],
            path: "Tests/SyncEngineTests"
        )
    ]
)
