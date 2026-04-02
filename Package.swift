// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "swift-sync-engine",
    products: [
        .library(
            name: "SyncEngine",
            targets: ["SyncEngine"]
        ),
    ],
    targets: [
        .target(
            name: "SyncEngine"
        ),
        .testTarget(
            name: "SyncEngineTests",
            dependencies: ["SyncEngine"]
        ),
    ]
)
