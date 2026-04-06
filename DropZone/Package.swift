// swift-tools-version: 6.0

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
            path: "Tests/DropZoneTests",
            swiftSettings: [
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                ]),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-rpath", "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker", "-rpath", "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/usr/lib",
                    "-Xlinker", "-F", "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker", "-L", "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/usr/lib",
                ]),
            ]
        ),
    ]
)
