// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "SwifterPM",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(name: "SwifterPMCore", targets: ["SwifterPMCore"]),
        .executable(name: "swifterpm", targets: ["swifterpm"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", exact: "1.7.1"),
        .package(url: "https://github.com/apple/swift-crypto.git", exact: "3.15.1"),
        .package(url: "https://github.com/swiftlang/swift-subprocess.git", exact: "0.4.0"),
        .package(url: "https://github.com/tuist/FileSystem.git", exact: "0.18.0"),
        .package(url: "https://github.com/tuist/Path.git", exact: "0.3.8"),
    ],
    targets: [
        .target(
            name: "SwifterPMCore",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.linux])),
                .product(name: "Subprocess", package: "swift-subprocess"),
                .product(name: "FileSystem", package: "FileSystem"),
                .product(name: "Path", package: "Path"),
            ],
            path: "Sources/swifterpm"
        ),
        .executableTarget(
            name: "swifterpm",
            dependencies: ["SwifterPMCore"],
            path: "Sources/swifterpmCLI"
        ),
        .testTarget(
            name: "SwifterPMCoreTests",
            dependencies: ["SwifterPMCore"],
            path: "Tests/swifterpmTests",
            exclude: ["main.swift"],
            resources: [
                .copy("Fixtures"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
