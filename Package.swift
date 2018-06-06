// swift-tools-version:4.0

import PackageDescription

let package = Package(
    name: "xpm",
    dependencies: [
        .package(url: "git@github.com:xcode-project-manager/xcodeproj.git", .revision("089d26ec37d741593512c6876062b726d3923229")),
        .package(url: "https://github.com/apple/swift-package-manager", from: "0.2.0"),
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
            dependencies: ["xcodeproj", "Utility"]
        ),
    ]
)
