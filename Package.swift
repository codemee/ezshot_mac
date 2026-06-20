// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ezshot",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "EzshotCore", targets: ["EzshotCore"]),
        .executable(name: "ezshot", targets: ["EzshotApp"]),
        .executable(name: "ezshot-core-tests", targets: ["EzshotCoreTests"])
    ],
    targets: [
        .target(
            name: "EzshotCore",
            path: "src/EzshotCore"
        ),
        .executableTarget(
            name: "EzshotApp",
            dependencies: ["EzshotCore"],
            path: "src/EzshotApp"
        ),
        .executableTarget(
            name: "EzshotCoreTests",
            dependencies: ["EzshotCore"],
            path: "tests/EzshotCoreTests"
        )
    ]
)
