// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

#if TUIST
    import struct ProjectDescription.PackageSettings

    let packageSettings = PackageSettings(
        baseSettings: .settings(base: ["GENERATE_MASTER_OBJECT_FILE": "YES"])
    )
#endif

let package = Package(
    name: "Tuist",
    dependencies: [
        .package(path: "../"),
        .package(url: "https://github.com/tuist/FileSystem.git", .upToNextMajor(from: "0.2.0")),
        .package(url: "https://github.com/Kolos65/Mockable.git", from: "0.0.9"),
        .package(url: "https://github.com/tuist/XcodeGraph.git", from: "0.8.1"),
        .package(url: "https://github.com/tuist/command", from: "0.8.0"),
    ]
)
