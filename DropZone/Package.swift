// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "DropZone",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .target(
            name: "DropZoneLib",
            dependencies: [],
            path: "Sources/DropZoneLib"
        ),
        .executableTarget(
            name: "DropZone",
            dependencies: ["DropZoneLib"],
            path: "Sources/DropZone"
        ),
        .testTarget(
            name: "DropZoneTests",
            dependencies: ["DropZoneLib"],
            path: "Tests/DropZoneTests"
        ),
    ]
)
