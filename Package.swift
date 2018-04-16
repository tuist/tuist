// swift-tools-version:4.0

import PackageDescription

let package = Package(
    name: "xcbuddy",
    dependencies: [
        .package(url: "git@github.com:xcodeswift/xcproj.git", .upToNextMinor(from: "4.2.0")),
        .package(url: "git@github.com:jakeheis/SwiftCLI.git", .upToNextMinor(from: "4.0.0")),
        .package(url: "git@github.com:httpswift/swifter.git", .upToNextMinor(from: "1.4.0")),
        .package(url: "git@github.com:kareman/SwiftShell.git", .upToNextMinor(from: "4.0.0")),
        .package(url: "git@github.com:mtynior/ColorizeSwift.git", .upToNextMinor(from: "1.2.0")),
        .package(url: "git@github.com:JohnSundell/Unbox.git", .upToNextMinor(from: "2.5.0")),
    ],
    targets: [
        .target(
            name: "ProjectDescription",
            dependencies: []),
        .testTarget(
            name: "ProjectDescriptionTests",
            dependencies: ["ProjectDescription"]
        ),
        .target(
            name: "Dependencies",
            dependencies: ["xcproj", "SwiftCLI", "Swifter", "SwiftShell", "ColorizeSwift", "Unbox"]
        ),
    ]
)
